# PFM & Gmail Pipeline - End-to-End Data Flow

This document describes the complete pipeline that connects Gmail email reading with PFM (Personal Financial Management) data extraction.

---

## Table of Contents

1. [Pipeline Overview](#pipeline-overview)
2. [Pipeline 1: Production (AWS Fargate)](#pipeline-1-production-aws-fargate)
3. [Pipeline 2: Research/Evaluation](#pipeline-2-researchevaluation)
4. [Trigger Mechanisms](#trigger-mechanisms)
5. [Data Flow Diagrams](#data-flow-diagrams)
6. [Database Schema](#database-schema)
7. [File Inventory](#file-inventory)
8. [Environment Variables](#environment-variables)
9. [AWS Infrastructure](#aws-infrastructure)
10. [PFM-Adjacent Services](#pfm-adjacent-services)

---

## Pipeline Overview

There are **two parallel pipeline implementations**:

| Pipeline | Location | Purpose | Trigger | Gmail Client |
|---|---|---|---|---|
| Production | `services/pfm_email_processor/` + `pfm_email_processor_aws/` | Real user email processing | Supabase Edge Function -> ECS Fargate | `PFMGmailClient` |
| Research | `services/transaction_extraction/` | Evaluation on labeled datasets | Manual / ECS task | `GmailScanner` (for ingestion only) |

**Key Distinction:** The PFM pipeline runs as a **standalone AWS ECS task**, NOT through the main LangGraph agent (`graph.py`) or gRPC API (`app-grpc.py`). It is completely decoupled from the conversational AI.

---

## Pipeline 1: Production (AWS Fargate)

### Entry Points

**`services/pfm_email_processor_aws/entrypoint.py`**

```python
# Dynamic entry point: selects pipeline based on env var
use_phase3 = os.getenv('USE_PHASE3_PIPELINE', 'true').lower() == 'true'
# Default: main_phase3.py (100% Unified LLM)
# Fallback: main.py (Standard multi-stage pipeline)
```

**`services/pfm_email_processor_aws/main_phase3.py`** (Phase 3 - Current Production)

### Complete Data Flow

```
1. TRIGGER
   Supabase Edge Function "email-sync-runner"
   -> runFargateTask() on cluster "pfm-email-cluster"
   -> ECS Task Definition "pfm-email-processor:67"
   -> entrypoint.py -> main_phase3.py

2. GMAIL AUTHENTICATION
   PFMGmailClient(user_id=user_id)
   Credential loading cascade:
     a. GOOGLE_ACCESS_TOKEN env var (Fargate mode)
     b. Supabase users table (google_access_token, google_refresh_token)
     c. gmail_token_{user_id}.json file
     d. /tmp/gmail_token_{user_id}.json (Fargate fallback)

3. EMAIL FETCHING
   service = gmail_client.get_service()
   results = service.users().messages().list(
       userId='me', q="after:{start_date}", maxResults=batch_size
   ).execute()

   # Paginated fetch (max 500 per page)
   # Dedup check: skip already-processed gmail_message_ids

4. EMAIL BODY EXTRACTION
   msg_data = gmail_client.get_message_with_retry(email_id)
   body = gmail_client.extract_email_body(msg_data)

   # Extraction includes:
   #   - Plain text from MIME parts
   #   - HTML to text conversion (with img alt attributes)
   #   - Embedded image OCR via Vision API (CID + data URI images)
   #   - Forwarded message header filtering

5. INTENT CLASSIFICATION (HybridIntentClassifier)
   Stage 1: Rule-based pre-filter (<1ms)
     -> CERTAIN_ACCEPT: trusted financial institution sender
     -> CERTAIN_REJECT: strong marketing/news signals
     -> UNCERTAIN: pass to Stage 2

   Stage 2: LLM classification (GPT-4o-mini, only for uncertain)
     -> Multi-dimensional scoring: transaction_intent (0-10),
        marketing_probability (0-10), risk_score (0-10)
     -> Decision: ACCEPT / REVIEW / REJECT

   Result: 40-60% reduction in LLM calls

6. ATTACHMENT DOWNLOAD (AttachmentManager)
   # Downloads PDF, Excel, CSV from Gmail Attachments API
   # Handles password-protected PDFs (user password cache from DB)
   # Extracts HTML embedded images for OCR

   SUPPORTED_MIME_TYPES = [
       'application/pdf',
       'application/octet-stream',
       'application/vnd.ms-excel',
       'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
       'text/csv'
   ]

7. TRANSACTION EXTRACTION
   Phase 3 (current): UnifiedLLMProcessor
     Layer 1: Fast classification (is_financial? document_type?)
     Layer 2: Full extraction (transactions, metadata)
     Layer 3: Optional metadata enrichment

   Standard (fallback): EnhancedLLMTransactionExtractor
     Step 1: Pre-check - optimized rejection rules
     Step 2: Rule-based merchant/amount extraction
     Step 3: LLM extraction (GPT-4o-mini)
     Step 4: Post-processing validation

8. TRANSFER ENRICHMENT (TransferDetector)
   # Enriches transfer-related fields:
   #   FlowType, TransferScope, AccountRelationship,
   #   IncomeSubType, ExpenseSubType, IBAN, PaymentMethod

9. AUTO-CATEGORIZATION
   smart_categorize_transaction()  ->  LEAN_CATEGORIES
   GoldenSetMapper                 ->  Golden-set categories

   Mapping: 'UTILITIES' -> 'Household', 'TRAVEL' -> 'Travel', etc.

10. VALIDATION (TransactionValidator)
    # Checks: zero-amount, marketing keywords,
    #         confidence threshold, amount reasonableness

11. DEDUPLICATION (Deduplicator)
    # MultiSourceFingerprint -> DB historical check -> batch dedup
    # Fingerprint based on: amount, merchant, date, description, currency

12. METADATA EXTRACTION (MetadataManager + MetadataStorage)
    # Bank info, addresses, relationships, travel preferences
    # Profile data: name, DOB, gender

13. DATABASE WRITE (SupabaseManager / BatchWriteQueue)
    # Tables: emails, transactions, attachments, processing_logs
    # Batch writes for +30-50% performance
    # ThreadPoolExecutor with 10 workers for parallel processing
```

### Token Provisioning on Fargate

**`services/pfm_email_processor_aws/fetch_token_from_db.py`**

```python
# Queries Supabase users table for OAuth tokens
# Writes gmail_token_{user_id}.json to /app/ or /tmp/
# Token data: {
#     "token": google_access_token,
#     "refresh_token": google_refresh_token,
#     "scopes": ["https://www.googleapis.com/auth/gmail.readonly"]
# }
```

---

## Pipeline 2: Research/Evaluation

### Step 1: Email Ingestion (Gmail -> Supabase)

**`scripts/scan_gmail_to_supabase.py`**

```
GmailScanner (services/gmail_scanner.py)
    |
    | OAuth2 + Gmail API (gmail.readonly)
    |
    v
EmailStorage (services/email_storage.py)
    |
    | Supabase API (credentials from AWS SSM)
    |
    v
Supabase Tables:
    golden.hugo.backup@gmail.com -> public.golden_email_samples
    malbank.test.toxic@gmail.com -> public.toxic_email_samples
```

- Batch size: 20 emails, 0.5s delay between batches
- Deduplication by `gmail_message_id`
- Recipient safety check: prevents cross-account data mixing

### Step 2: Transaction Extraction (Supabase -> Supabase)

**`services/transaction_extraction/transactions_extraction.py`**

```
Supabase (golden_email_samples / toxic_email_samples / chaos_email_samples)
    |
    | Filter by email_account_id + classification flags
    |
    v
EmailExtractionPipeline (email_extraction_pipeline.py)
    |
    v
MultiLayerExtractor (layers/base.py)
    |
    | Layer 1: Regex (currency, date, card, direction)
    | Layer 2: LLM coarse (MerchantName, Amount, Currency, Direction, EmailType)
    | Layer 2.5: SubCategory-specific
    | Layer 3: LLM fine-grained (category-specific prompts)
    | Layer 4: Validation + cross-field consistency
    | Layer 5: Iterative refinement
    |
    v
map_extraction_to_transaction()
    |
    | Mapping: MerchantName->merchant, Amount->amount,
    |          BaseCurrency->currency, Category->category,
    |          Direction->direction (INCOME/EXPENSE/NEUTRAL)
    |
    v
Supabase transactions table (upsert)
    extraction_method = 'EmailExtractionPipeline'
    source = 'email'
```

### Step 3: Evaluation

```
run_evaluation.py / run_evaluation_for_golden.py
    |
    v
evaluation_system.py
    |
    | Compare extracted vs. ground truth
    | Field-level accuracy metrics
    |
    v
chaos_regression_report.py
    |
    | CLASSIFICATION_FIELDS:
    |   golden: EmailType, Category, SubCategory, Direction, PFMEffect,
    |           FlowType, IncomeSubType, ExpenseSubType, TransferScope
    |   chaos: direction
    |
    v
weak_signal_detector.py -> alerts for poor extractions
```

---

## Trigger Mechanisms

### Production Pipeline Trigger

```
User connects Gmail account in frontend
    -> Supabase saves google_access_token / google_refresh_token to users table
    -> Supabase Edge Function "email-sync-runner" triggers
    -> runFargateTask() on AWS ECS
        Cluster: pfm-email-cluster
        Task Definition: pfm-email-processor:67
        ECR Image: pfm-email-processor
    -> entrypoint.py -> main_phase3.py
    -> PFMGmailClient reads emails
    -> UnifiedLLMProcessor extracts transactions
    -> SupabaseManager writes results
```

### Research Pipeline Trigger

```
Manual execution:
    python scripts/scan_gmail_to_supabase.py       # Step 1: Ingest emails
    python services/transaction_extraction/transactions_extraction.py  # Step 2: Extract
    python services/transaction_extraction/run_evaluation.py           # Step 3: Evaluate
```

---

## Data Flow Diagrams

### Production Pipeline (Phase 3)

```
                    ┌──────────────────────┐
                    │  Supabase Edge Func   │
                    │  "email-sync-runner"  │
                    └──────────┬───────────┘
                               │ runFargateTask()
                               v
                    ┌──────────────────────┐
                    │   AWS ECS Fargate     │
                    │   entrypoint.py       │
                    └──────────┬───────────┘
                               │
                               v
┌──────────┐     ┌──────────────────────┐     ┌──────────────┐
│  Gmail   │────>│  PFMGmailClient      │────>│ Email Body   │
│  API     │     │  (gmail.readonly)    │     │ + Attachments│
└──────────┘     └──────────────────────┘     └──────┬───────┘
                                                      │
                               ┌──────────────────────┘
                               v
                    ┌──────────────────────┐
                    │ HybridIntentClassifier│
                    │ (Rule + GPT-4o-mini) │
                    └──────────┬───────────┘
                               │ ACCEPT
                               v
                    ┌──────────────────────┐
                    │ UnifiedLLMProcessor   │
                    │ Layer 1: Classify     │
                    │ Layer 2: Extract      │
                    │ Layer 3: Enrich       │
                    └──────────┬───────────┘
                               │
                    ┌──────────┴───────────┐
                    v                      v
          ┌─────────────┐      ┌─────────────────┐
          │TransferDetect│      │auto_categorizer  │
          │TransferScope │      │GoldenSetMapper   │
          │IBAN, FlowType│      │Category mapping  │
          └──────┬──────┘      └────────┬────────┘
                 │                      │
                 └──────────┬───────────┘
                            v
                 ┌──────────────────────┐
                 │ TransactionValidator  │
                 │ Deduplicator          │
                 └──────────┬───────────┘
                            │
                            v
                 ┌──────────────────────┐
                 │     Supabase         │
                 │  emails              │
                 │  transactions        │
                 │  attachments         │
                 │  processing_logs     │
                 └──────────────────────┘
```

### Research Pipeline

```
┌──────────┐     ┌──────────────┐     ┌──────────────────┐
│  Gmail   │────>│ GmailScanner │────>│  EmailStorage    │
│  API     │     │              │     │  (Supabase)      │
└──────────┘     └──────────────┘     └────────┬─────────┘
                                               │
                   golden_email_samples ────────┤
                   toxic_email_samples  ────────┤
                   chaos_email_samples  ────────┘
                                               │
                                               v
                              ┌─────────────────────────┐
                              │ EmailExtractionPipeline  │
                              │ -> MultiLayerExtractor   │
                              │    (5 layers)            │
                              └────────────┬────────────┘
                                           │
                                           v
                              ┌─────────────────────────┐
                              │ transactions table       │
                              │ (extraction_method =     │
                              │  'EmailExtractionPipeline')│
                              └────────────┬────────────┘
                                           │
                                           v
                              ┌─────────────────────────┐
                              │ evaluation_system.py     │
                              │ chaos_regression_report  │
                              │ weak_signal_detector     │
                              └─────────────────────────┘
```

---

## Database Schema

### Supabase Tables (Production)

#### `emails`
| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `gmail_message_id` | TEXT | Gmail message ID (dedup key) |
| `user_id` | UUID | User reference |
| `subject` | TEXT | Email subject |
| `sender` | TEXT | Sender email |
| `body_preview` | TEXT | Body snippet |
| `is_financial` | BOOLEAN | Financial classification result |
| `document_type` | TEXT | TRANSACTION, INVOICE, etc. |
| `confidence_score` | FLOAT | Classification confidence |
| `received_date` | TIMESTAMP | Email date |
| `processed_at` | TIMESTAMP | Processing timestamp |

#### `transactions`
| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `email_id` | UUID | FK to emails |
| `email_account_id` | UUID | FK to email_account |
| `profile_id` | UUID | FK to profile |
| `amount` | NUMERIC | Transaction amount |
| `currency` | TEXT | Currency code |
| `merchant` | TEXT | Merchant name |
| `category` | TEXT | Golden-set category |
| `subcategory` | TEXT | Sub-category |
| `direction` | TEXT | INCOME / EXPENSE / NEUTRAL |
| `document_type` | TEXT | Source document type |
| `transaction_type` | TEXT | 'merchant' or 'transfer' |
| `transaction_date_time` | TIMESTAMP | Transaction date |
| `iban` | TEXT | IBAN if detected |
| `payment_method` | TEXT | Payment method |
| `extraction_method` | TEXT | 'EmailExtractionPipeline' / 'UnifiedLLM' |
| `source` | TEXT | 'email' |
| `confidence_score` | FLOAT | Extraction confidence |

#### `attachments`
| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `email_id` | UUID | FK to emails |
| `filename` | TEXT | Original filename |
| `mime_type` | TEXT | MIME type |
| `file_path` | TEXT | Storage path |
| `extracted_text` | TEXT | OCR/parsed text |

#### `golden_email_samples` / `toxic_email_samples`
| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `gmail_message_id` | TEXT | Dedup key |
| `email_content` | TEXT | Full body text |
| `subject` | TEXT | Subject |
| `sender` | TEXT | Sender |
| `recipient` | TEXT | Recipient (always = scanned account email) |
| `date` | TIMESTAMP | Email date |
| `headers` | JSONB | All email headers |
| `metadata` | JSONB | Labels, attachments, snippet, thread_id |

#### `email_sync_jobs`
Tracks Fargate task executions for the PFM pipeline.

#### `users` (relevant columns)
| Column | Type | Description |
|---|---|---|
| `google_access_token` | TEXT | Gmail OAuth access token |
| `google_refresh_token` | TEXT | Gmail OAuth refresh token |
| `pdf_passwords` | JSONB | Password cache for protected PDFs |

---

## File Inventory

### Production Pipeline Files

| File | Role |
|---|---|
| `services/pfm_email_processor/__init__.py` | Package entry (exports PFMEmailProcessor, get_processor) |
| `services/pfm_email_processor/email_processor.py` | Main orchestrator (~3000 lines) |
| `services/pfm_email_processor/gmail_client.py` | Thread-safe multi-user Gmail client |
| `services/pfm_email_processor/config.py` | All configuration constants |
| `services/pfm_email_processor/hybrid_intent_classifier.py` | Two-stage rule+AI classifier |
| `services/pfm_email_processor/email_intent_classifier.py` | LLM intent scoring |
| `services/pfm_email_processor/financial_classifier.py` | Legacy keyword classifier |
| `services/pfm_email_processor/document_type_classifier.py` | Document type pre-classification |
| `services/pfm_email_processor/llm_transaction_extractor.py` | Base LLM extractor |
| `services/pfm_email_processor/llm_transaction_extractor_enhanced.py` | Production extractor |
| `services/pfm_email_processor/unified_llm_processor.py` | Phase 3 single-call processor |
| `services/pfm_email_processor/sequential_task_processor.py` | 7-task modular extraction |
| `services/pfm_email_processor/attachment_manager.py` | Gmail attachment download |
| `services/pfm_email_processor/pdf_parser_inline.py` | PDF text extraction |
| `services/pfm_email_processor/html_image_extractor.py` | HTML image extraction |
| `services/pfm_email_processor/auto_categorizer.py` | Category classification |
| `services/pfm_email_processor/golden_set_mapper.py` | Golden-set category mapping |
| `services/pfm_email_processor/transfer_detector.py` | Transfer type detection |
| `services/pfm_email_processor/enhanced_transfer_detector.py` | Enhanced transfer enrichment |
| `services/pfm_email_processor/deduplicator.py` | Transaction deduplication |
| `services/pfm_email_processor/multi_source_fingerprint.py` | Transaction fingerprinting |
| `services/pfm_email_processor/transaction_validator.py` | Post-processing validation |
| `services/pfm_email_processor/database_factory.py` | DB backend factory |
| `services/pfm_email_processor/supabase_manager.py` | Supabase CRUD operations |
| `services/pfm_email_processor/metadata_manager.py` | Bank info extraction |
| `services/pfm_email_processor/metadata_storage.py` | Metadata persistence |
| `services/pfm_email_processor/profile_manager.py` | User profile management |
| `services/pfm_email_processor/batch_write_queue.py` | Async batch DB writes |
| `services/pfm_email_processor/vision_integration.py` | Vision API decorator |
| `services/pfm_email_processor/enhanced_vision_processor.py` | Enhanced Vision processing |
| `services/pfm_email_processor/confidence_scoring.py` | Extraction confidence scoring |
| `services/pfm_email_processor/data_quality_monitor.py` | Quality monitoring |
| `services/pfm_email_processor/cli.py` | CLI interface |
| `services/pfm_email_processor_aws/entrypoint.py` | AWS Fargate entry point |
| `services/pfm_email_processor_aws/main_phase3.py` | Phase 3 Fargate main (~2600 lines) |
| `services/pfm_email_processor_aws/fetch_token_from_db.py` | Token provisioning for Fargate |

### Email Ingestion Files

| File | Role |
|---|---|
| `services/gmail_scanner.py` | Bulk Gmail scanner |
| `services/email_storage.py` | Supabase email storage |
| `scripts/scan_gmail_to_supabase.py` | Batch scanning script |
| `scripts/setup-gmail-oauth-ssm.sh` | AWS SSM credential upload |

### Research Pipeline Files

| File | Role |
|---|---|
| `services/transaction_extraction/transactions_extraction.py` | ECS task runner |
| `services/transaction_extraction/email_extraction_pipeline.py` | Pipeline for labeled datasets |
| `services/transaction_extraction/layers/base.py` | MultiLayerExtractor |
| `services/transaction_extraction/layers/extraction_layer1.py` | Rule-based extraction |
| `services/transaction_extraction/layers/extraction_layer2.py` | LLM coarse extraction |
| `services/transaction_extraction/layers/extraction_layer2_5.py` | SubCategory-specific |
| `services/transaction_extraction/layers/extraction_layer3.py` | LLM fine-grained |
| `services/transaction_extraction/layers/extraction_layer4.py` | Validation |
| `services/transaction_extraction/layers/extraction_layer5.py` | Iterative refinement |
| `services/transaction_extraction/layers/helpers.py` | Field definitions |
| `services/transaction_extraction/evaluation_system.py` | Quality evaluation |
| `services/transaction_extraction/weak_signal_detector.py` | Alert system |

---

## Environment Variables

### Required for Production Pipeline

| Variable | Description | Source |
|---|---|---|
| `GOOGLE_ACCESS_TOKEN` | Gmail OAuth access token | Supabase / env |
| `GOOGLE_REFRESH_TOKEN` | Gmail OAuth refresh token | Supabase / env |
| `GOOGLE_CLIENT_ID` | OAuth client ID | env |
| `GOOGLE_CLIENT_SECRET` | OAuth client secret | env |
| `OPENROUTER_API_KEY` | LLM API key for GPT-4o-mini | env |
| `OPENAI_API_KEY` | Vision API key (for image OCR) | env |
| `SUPABASE_URL` | Supabase project URL | env / AWS SSM |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase admin key | env / AWS SSM |
| `PFM_DATABASE_BACKEND` | DB backend (always `supabase`) | env (set in code) |

### Optional

| Variable | Default | Description |
|---|---|---|
| `USE_PHASE3_PIPELINE` | `true` | Use Unified LLM (Phase 3) |
| `PFM_VERBOSE` | `1` | Enable verbose logging |
| `PFM_LOG_LEVEL` | `INFO` | Log level |
| `PFM_DEBUG` | `False` | Debug mode |
| `SUPPRESS_IMAGE_WARNINGS` | `true` | Suppress image processing warnings |
| `GMAIL_AUTH_METHOD` | `auto` | OAuth flow type (auto/manual/console) |

---

## AWS Infrastructure

### ECS Cluster

```
Cluster: pfm-email-cluster
Task Definition: pfm-email-processor:67
ECR Repository: pfm-email-processor
```

### AWS SSM Parameter Store

```
/malbank-ai/staging/supabase-url              -> SUPABASE_URL
/malbank-ai/staging/supabase-service-role-key  -> SUPABASE_SERVICE_ROLE_KEY
/malbank-ai/staging/supabase-anon-key          -> SUPABASE_ANON_KEY
/malbank/${ENVIRONMENT}/gmail-oauth-client     -> oauth_client.json content
/malbank/${ENVIRONMENT}/gmail-oauth-token      -> token.json content
```

---

## PFM-Adjacent Services

### `OpenFinanceService`

**File:** `services/open_finance_service.py`

Mock integration with external financial institutions. Not Gmail-based — provides consent-based transaction data:

```python
class OpenFinanceService:
    def fetch_transactions(self, user_id, connection_id, account_id) -> List[Dict]:
        # Returns mock transactions: SPINNEYS DUBAI, SALARY DEPOSIT, NOON.COM
```

### Clarity Score / EKID

**File:** `services/clarity_score/run_ekid_from_emails.py`

Uses PFM pipeline output to build identity knowledge claims:

```python
from services.pfm_email_processor.supabase_manager import get_manager
from services.pfm_email_processor.unified_llm_processor import UnifiedLLMProcessor

# Queries emails WHERE is_financial=true OR is_medical=true
#   OR is_education=true OR is_travel=true
```

### Bank Statement gRPC

**File:** `app-grpc.py`

Bank statement data (from user-uploaded PDFs in chat) flows through gRPC:

```python
if isinstance(result, dict) and 'bank_statement' in result:
    response.extracted_data.bank_statement.account_number = stmt.get('account_number', '')
    response.extracted_data.bank_statement.bank_name = stmt.get('bank_name', '')
    # ... transactions with category_totals
```

This is for **user-uploaded PDFs** via chat, NOT for the Gmail-based PFM pipeline.

### Existing Documentation

| File | Content |
|---|---|
| `docs/pfm_email_processor_architecture.md` | Architecture with Mermaid diagrams |
| `docs/pfm_email_processor_deployment.md` | AWS deployment guide |
| `docs/pfm_email_processor_modification.md` | How to modify the pipeline |
| `GMAIL_INTEGRATION_ISSUE.md` | Gmail integration planning doc |
