# PFM (Personal Financial Management) Extraction - Complete Code Reference

This document catalogs the entire PFM extraction system found across `old-ai/`.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Package Structure](#package-structure)
3. [Main Processor (email_processor.py)](#main-processor)
4. [Intent Classification (3-stage)](#intent-classification)
5. [Document Type Classification](#document-type-classification)
6. [LLM Transaction Extraction](#llm-transaction-extraction)
7. [Unified LLM Processor (Phase 3)](#unified-llm-processor-phase-3)
8. [Sequential Task Processor](#sequential-task-processor)
9. [Attachment Handling](#attachment-handling)
10. [Transaction Categorization](#transaction-categorization)
11. [Transfer Detection](#transfer-detection)
12. [Deduplication](#deduplication)
13. [Transaction Validation](#transaction-validation)
14. [Database Layer](#database-layer)
15. [Metadata & Profile Extraction](#metadata--profile-extraction)
16. [Multi-Layer Extraction (Research Pipeline)](#multi-layer-extraction-research-pipeline)
17. [Configuration Reference](#configuration-reference)
18. [PFM Data Schema](#pfm-data-schema)
19. [CLI Interface](#cli-interface)

---

## Architecture Overview

The PFM system extracts financial transaction data from Gmail emails. Two parallel implementations exist:

### Production Pipeline (`services/pfm_email_processor/`)

```
Gmail API (PFMGmailClient)
    |
    v
[HybridIntentClassifier]  ---- Rule-based pre-filter (fast, <1ms)
    |                          |
    |  UNCERTAIN               | CERTAIN_ACCEPT / CERTAIN_REJECT
    v                          |
[EmailIntentClassifier]  <-----+  (LLM call only for uncertain cases)
    |
    v
[DocumentTypeClassifier]  ---- TRANSACTION / INVOICE / ORDER / MARKETING / STATEMENT
    |
    v  [if should_extract=true]
[AttachmentManager]  ---- Download PDF/Excel/CSV + HTML image extraction
    |
    v
[EnhancedLLMTransactionExtractor]  or  [UnifiedLLMProcessor (Phase 3)]
    |
    v
[auto_categorizer + GoldenSetMapper]  ---- Category standardization
    |
    v
[TransactionValidator]  ---- Zero-amount, marketing keyword, confidence checks
    |
    v
[Deduplicator]  ---- MultiSourceFingerprint + DB historical check
    |
    v
[SupabaseManager]  ---- Write to emails, transactions, attachments tables
```

### Research Pipeline (`services/transaction_extraction/`)

```
Supabase (golden_email_samples / toxic_email_samples / chaos_email_samples)
    |
    v
[EmailExtractionPipeline]
    |
    v
[MultiLayerExtractor]  ---- 5-layer extraction engine
    Layer 1: Rule-based (regex for currency, date, card, direction)
    Layer 2: LLM coarse extraction (MerchantName, Amount, Currency)
    Layer 2.5: SubCategory-specific extraction
    Layer 3: LLM fine-grained (category-specific prompts)
    Layer 4: Validation + cross-field consistency
    Layer 5: Iterative refinement (multiple LLM passes)
    |
    v
[transactions table]  via  map_extraction_to_transaction()
```

---

## Package Structure

### `services/pfm_email_processor/` (50 files)

| File | Class/Function | Purpose |
|---|---|---|
| `__init__.py` | Exports `PFMEmailProcessor`, `get_processor` | Package entry |
| `email_processor.py` | `PFMEmailProcessor` | Main orchestrator (~3000 lines) |
| `gmail_client.py` | `PFMGmailClient` | Thread-safe Gmail client |
| `config.py` | Constants | All configuration values |
| `hybrid_intent_classifier.py` | `HybridIntentClassifier` | Two-stage rule+AI classifier |
| `email_intent_classifier.py` | `EmailIntentClassifier` | LLM-based intent scoring |
| `financial_classifier.py` | `FinancialClassifier` | Legacy keyword-based classifier |
| `document_type_classifier.py` | `DocumentTypeClassifier` | Pre-classification before extraction |
| `llm_transaction_extractor.py` | `LLMTransactionExtractor` | Base LLM extractor |
| `llm_transaction_extractor_enhanced.py` | `EnhancedLLMTransactionExtractor` | Production extractor (70%->90% accuracy) |
| `unified_llm_processor.py` | `UnifiedLLMProcessor` | Phase 3 single-call replacement |
| `sequential_task_processor.py` | `SequentialTaskProcessor` | 7-task modular extraction |
| `attachment_manager.py` | `AttachmentManager` | Gmail attachment download |
| `attachment_manager_supabase.py` | — | Supabase Storage variant |
| `pdf_parser_inline.py` | `SimplePDFParser` | Inline PDF text extraction |
| `html_image_extractor.py` | — | HTML email image extraction |
| `auto_categorizer.py` | `smart_categorize_transaction()` | Category classification |
| `golden_set_mapper.py` | `GoldenSetMapper` | Maps to golden-set categories |
| `transfer_detector.py` | `TransferDetector` | 15+ transfer type detection |
| `enhanced_transfer_detector.py` | `EnhancedTransferDetector` | Enhanced transfer enrichment |
| `transfer_classifier.py` | — | Transfer subtype classification |
| `deduplicator.py` | `Deduplicator` | Fingerprint-based dedup |
| `intelligent_deduplicator.py` | — | Extended dedup logic |
| `dedup_integration.py` | — | Dedup integration helpers |
| `multi_source_fingerprint.py` | `MultiSourceFingerprint` | Transaction fingerprinting |
| `transaction_validator.py` | `TransactionValidator`, `ExtractionMetrics` | Post-processing validation |
| `database_factory.py` | `get_db_manager()` | DB backend factory |
| `database_manager.py` | `databaseManager` | Legacy SQLite (deprecated) |
| `supabase_manager.py` | `SupabaseManager` | Supabase backend |
| `enhanced_extraction_processor.py` | `EnhancedExtractionProcessor` | Integration of enhanced modules |
| `enhanced_merchant_recognizer.py` | — | Merchant name normalization |
| `merchant_extractor_enhanced.py` | — | Enhanced merchant extraction |
| `merchant_alias_db.py` | — | Merchant alias database |
| `amount_extractor_enhanced.py` | — | Amount parsing |
| `amount_validator_enhanced.py` | — | Amount validation |
| `rejection_rules_optimized.py` | — | Optimized email rejection rules |
| `confidence_scoring.py` | — | Extraction confidence scoring |
| `metadata_manager.py` | `MetadataManager` | Bank info, address extraction |
| `metadata_storage.py` | `MetadataStorage` | Metadata persistence |
| `profile_manager.py` | — | User profile data management |
| `gender_inference.py` | — | Gender inference from name |
| `vision_integration.py` | `@integrate_vision_processor` | Vision API decorator |
| `enhanced_vision_processor.py` | — | Enhanced Vision processing |
| `email_cache_manager.py` | — | Email caching |
| `data_quality_monitor.py` | — | Extraction quality monitoring |
| `batch_write_queue.py` | — | Async batch DB writes (+30-50% perf) |
| `ab_test_processor.py` | — | A/B test framework |
| `email_processor_enhanced.py` | — | Enhanced processor variant |
| `config_validator.py` | — | Configuration validation |
| `cli.py` | CLI entry point | `python -m services.pfm_email_processor.cli` |

### `services/transaction_extraction/` (26 files)

| File | Purpose |
|---|---|
| `transactions_extraction.py` | ECS task runner for extraction |
| `email_extraction_pipeline.py` | Pipeline for golden/toxic/chaos datasets |
| `layers/base.py` | `MultiLayerExtractor` (5-layer engine) |
| `layers/extraction_layer1.py` | Rule-based regex extraction |
| `layers/extraction_layer2.py` | LLM coarse extraction |
| `layers/extraction_layer2_5.py` | SubCategory-specific extraction |
| `layers/extraction_layer3.py` | LLM fine-grained extraction |
| `layers/extraction_layer4.py` | Validation + consistency |
| `layers/extraction_layer5.py` | Iterative refinement |
| `layers/helpers.py` | Field definitions (`GOLDEN_EXTRACTION_FIELDS`) |
| `evaluation_system.py` | Extraction quality evaluation |
| `run_evaluation*.py` | Evaluation runners |
| `chaos_regression_report.py` | Regression testing |
| `weak_signal_detector.py` | Poor-quality extraction alerting |
| `optimize_extraction.py` | Prompt optimization |
| `generate_chaos_emails.py` | Test email generation |
| `generate_email_variations.py` | Email variation generation |

---

## Main Processor

**File:** `services/pfm_email_processor/email_processor.py`

### Class: `PFMEmailProcessor`

```python
class PFMEmailProcessor:
    def __init__(self, user_id='user-default'):
        self.gmail_client = PFMGmailClient(user_id=user_id)
        self.attachment_manager = AttachmentManager(self.gmail_client)
        self.classifier = FinancialClassifier()
        self.intent_classifier = HybridIntentClassifier()
        self.llm_extractor = LLMTransactionExtractor()      # EnhancedLLMTransactionExtractor
        self.deduplicator = Deduplicator(self.db)
        self.document_classifier = DocumentTypeClassifier()
        self.transaction_validator = TransactionValidator()
```

### Main Processing Flow (`process_emails`)

1. Build Gmail query: `"after:{start_date} before:{end_date}"`
2. `_fetch_emails()` — paginated Gmail API list (max 500/page)
3. Dedup check against already-processed email IDs
4. `_process_emails_parallel()` — ThreadPoolExecutor (10 workers)
5. `batch_write_context()` for async DB writes (+30-50% perf)

### Single Email Processing (`_process_single_email`)

1. **Extract email info** — subject, sender, body_full, body_preview, received_date
2. **AI Intent Classification** — `HybridIntentClassifier.classify_email_intent()`
   - Returns: decision (ACCEPT/REVIEW/REJECT), transaction_intent 0-10, marketing_probability 0-10, risk_score 0-10
3. **Legacy fallback** — `FinancialClassifier.is_financial_email()` for comparison
4. **Save email record** to DB (or batch queue)
5. **Download attachments** — PDF, Excel, CSV + HTML image extraction
6. **Transaction extraction:**
   - With attachments: `_extract_from_attachments_parallel()`, fallback to body
   - Without: `_extract_from_email_body()`
7. **Deduplication + merge** (e.g., Carrefour marketplace multi-item)
8. **Save transactions** to DB

---

## Intent Classification

### Stage 1: `HybridIntentClassifier`

**File:** `services/pfm_email_processor/hybrid_intent_classifier.py`

Two-stage classifier that reduces LLM calls by 40-60%:

```
Email → Rule-based pre-filter → CERTAIN_ACCEPT → Process
                              → CERTAIN_REJECT → Skip
                              → UNCERTAIN → Stage 2 (LLM)
```

**CERTAIN_ACCEPT triggers:**
- Sender domain matches `TRUSTED_FINANCIAL_INSTITUTIONS` (banks, payment processors)
- Strong financial keywords in subject/body

**CERTAIN_REJECT triggers:**
- Strong marketing/promotional keywords
- Newsletter patterns without financial content

### Stage 2: `EmailIntentClassifier`

**File:** `services/pfm_email_processor/email_intent_classifier.py`

LLM-based multi-dimensional scoring (GPT-4o-mini via OpenRouter):

**Output:**
```json
{
    "decision": "ACCEPT" | "REVIEW" | "REJECT",
    "transaction_intent": 0-10,
    "marketing_probability": 0-10,
    "sender_reputation": 0-10,
    "risk_score": 0-10
}
```

**Pre-filters (skip LLM call):** quote/estimate, payment_failed, free_trial, cart_reminder, shipment_notice, OTP/verification codes, chargeback/refund, scheduled transactions, booking confirmations without payment, exchange rate alerts, security alerts, GitHub/CI notifications

### Stage 3: `FinancialClassifier` (Legacy)

**File:** `services/pfm_email_processor/financial_classifier.py`

Keyword-based classification. Returns `(is_financial, document_type, confidence)`.

---

## Document Type Classification

**File:** `services/pfm_email_processor/document_type_classifier.py`

Pre-classifies emails before LLM extraction:

| Document Type | `should_extract` | Keywords |
|---|---|---|
| `TRANSACTION` | Yes | payment successful, charged, debited, transaction confirmed |
| `INVOICE_UNPAID` | Yes | invoice, amount due, payable by, billing period |
| `ORDER_CONFIRMATION` | Yes | order confirmed, order placed |
| `MARKETING` | No | unsubscribe, promotional, flash sale |
| `STATEMENT` | No | statement available, monthly statement |
| `BOARDING_PASS` | No | boarding pass, check-in |
| `COMMUNITY_NOTICE` | No | community update, construction notice |

Priority hierarchy: `TRANSACTION > INVOICE_UNPAID > ORDER_CONFIRMATION > MARKETING > STATEMENT > BOARDING_PASS > COMMUNITY_NOTICE`

---

## LLM Transaction Extraction

### Base: `LLMTransactionExtractor`

**File:** `services/pfm_email_processor/llm_transaction_extractor.py`

- Model: `openai/gpt-4o-mini` via OpenRouter
- LRU cache (1000 entries) to avoid re-extracting identical content
- Async batch extraction supported
- Extracts: amount, currency, merchant, date, description, document_type

### Enhanced: `EnhancedLLMTransactionExtractor`

**File:** `services/pfm_email_processor/llm_transaction_extractor_enhanced.py`

Production extractor (imported as `LLMTransactionExtractor` in `email_processor.py`):

```python
class EnhancedLLMTransactionExtractor(LLMTransactionExtractor):
    """Enhanced with merchant name extraction, amount recognition, rejection rule optimization
    Expected accuracy: 70% -> 90%
    """
    def extract_transactions(self, email_content, attachment_preview,
                             document_type, sender_email, subject, doc_classification):
        # Step 1: Pre-check - optimized rejection rules
        # Step 2: Rule-based merchant/amount extraction
        # Step 3: LLM extraction
        # Step 4: Post-processing validation
```

---

## Unified LLM Processor (Phase 3)

**File:** `services/pfm_email_processor/unified_llm_processor.py`

Replaces the multi-stage pipeline with a single optimized 3-layer LLM call:

```
Email Content → Layer 1 (Classification) → Layer 2 (Extraction) → JSON Output
```

**Performance Metrics:**
- 88% code reduction (2430 -> 300 lines)
- 70-80% cost reduction (optimized prompts)
- 40-60% faster (smart caching, 5min TTL)
- 90% -> 95%+ accuracy
- 98%+ success rate (retry mechanism)

**Optimizations:**
- Layered prompts (70-80% token reduction)
- Smart context caching (5min TTL)
- Exponential backoff retry (3 attempts)
- Dynamic max_tokens allocation
- Uses `TransferDetector` + `EnhancedTransferDetector` for transfer field enrichment

---

## Sequential Task Processor

**File:** `services/pfm_email_processor/sequential_task_processor.py`

7-task modular extraction (used when `USE_SEQUENTIAL_TASKS=true`):

```python
TASK_EXECUTION_ORDER = [
    'transaction_extraction',      # Core transaction data
    'transfer_detection',          # Transfer type classification
    'bank_fee_categorization',     # Bank fee identification
    'bank_info_extraction',        # IBAN, account numbers
    'metadata_extraction',         # Address, relationships
    'profile_extraction',          # User name, DOB, gender
    'email_classification_flags'   # is_financial, is_medical, etc.
]
```

---

## Attachment Handling

### `AttachmentManager`

**File:** `services/pfm_email_processor/attachment_manager.py`

```python
SUPPORTED_MIME_TYPES = [
    'application/pdf',
    'application/octet-stream',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv'
]
```

**Features:**
- Downloads attachments via Gmail Attachments API
- Password-protected PDF handling (user password cache from Supabase `users.pdf_passwords`)
- HTML image extraction for OCR (`extract_html_images`)
- PDF text extraction via `SimplePDFParser` (inline, uses pdfplumber/PyMuPDF)

### Vision API Integration

**File:** `services/pfm_email_processor/vision_integration.py`

```python
@integrate_vision_processor
def process_email_with_attachments(email_data, attachments):
    # Strategies: Vision API -> OCR -> Text extraction -> Table extraction
```

---

## Transaction Categorization

### `auto_categorizer.py`

**File:** `services/pfm_email_processor/auto_categorizer.py`

```python
LEAN_CATEGORIES = [
    'FOOD_AND_DRINK', 'GROCERIES', 'ENTERTAINMENT', 'TRAVEL',
    'HEALTHCARE', 'PERSONAL_CARE', 'EDUCATION', 'CHARITY',
    'BANK_FEES_AND_CHARGES', 'UTILITIES', 'INSURANCE',
    'INVESTMENTS', 'SHOPPING', 'TRANSPORT', 'GENERAL',
]

# Pattern matching for common merchants:
MERCHANT_PATTERNS = {
    'Starbucks': 'FOOD_AND_DRINK',
    'Carrefour': 'GROCERIES',
    'Emirates': 'TRAVEL',
    'DEWA': 'UTILITIES',
    ...
}
```

### `GoldenSetMapper`

**File:** `services/pfm_email_processor/golden_set_mapper.py`

Maps lean categories to golden-set categories:

```python
LEAN_TO_GOLDEN_MAPPING = {
    'UTILITIES': 'Household',
    'TRAVEL': 'Travel',
    'GROCERIES': 'Groceries',
    'FOOD_AND_DRINK': 'Dining',
    'SHOPPING': 'Shopping',
    'ENTERTAINMENT': 'Entertainment',
    'BANK_FEES_AND_CHARGES': 'Financial services',
    ...
}
```

Uses `golden_set_truth.json` for merchant-to-category lookups.

---

## Transfer Detection

### `TransferDetector`

**File:** `services/pfm_email_processor/transfer_detector.py`

Detects 15+ transfer types with >95% precision, >90% recall:

| Transfer Type | Example |
|---|---|
| `wire_transfer` | International bank wire |
| `ach_transfer` | ACH electronic transfer |
| `P2P_DOMESTIC` | Person-to-person domestic |
| `INTERNAL_SAME_BANK` | Same bank different accounts |
| `INTERNAL_SAME_USER` | Same user own accounts |
| `INTERNATIONAL_EXTERNAL_BANK` | Cross-border transfer |

### `EnhancedTransferDetector`

**File:** `services/pfm_email_processor/enhanced_transfer_detector.py`

Adds IBAN extraction, account number recognition, transfer scope enrichment.

---

## Deduplication

### `Deduplicator`

**File:** `services/pfm_email_processor/deduplicator.py`

```python
class Deduplicator:
    """Strategy: fingerprint hash -> DB historical check -> batch dedup"""
```

Uses `MultiSourceFingerprint` for transaction fingerprinting based on: amount, merchant, date, description, currency.

---

## Transaction Validation

### `TransactionValidator`

**File:** `services/pfm_email_processor/transaction_validator.py`

Post-processing checks:
- Zero-amount filtering
- Marketing keyword detection
- Confidence score thresholds
- Amount reasonableness checks
- Currency validation

### `ExtractionMetrics`

Tracks per-session extraction performance metrics.

---

## Database Layer

### `database_factory.py`

```python
def get_db_manager(backend=None):
    """Factory: auto-detects from PFM_DATABASE_BACKEND env var
    Exclusively uses Supabase (SQLite deprecated)
    """
```

### `SupabaseManager`

**File:** `services/pfm_email_processor/supabase_manager.py`

Manages all CRUD for:
- `emails` table — raw email records
- `transactions` table — extracted transactions
- `attachments` table — downloaded attachments
- `processing_logs` table — processing audit trail
- `email_sync_jobs` table — sync job tracking

### `databaseManager` (Legacy)

**File:** `services/pfm_email_processor/database_manager.py`

Deprecated SQLite manager. Schema reference only:

```sql
CREATE TABLE emails (
    id, gmail_message_id, subject, sender, body_preview,
    is_financial, document_type, confidence_score, ...
);

CREATE TABLE transactions (
    id, email_id, amount, currency, merchant, date,
    description, document_type, confidence_score, ...
);

CREATE TABLE attachments (
    id, email_id, filename, mime_type, file_path, ...
);
```

---

## Metadata & Profile Extraction

### `MetadataManager`

**File:** `services/pfm_email_processor/metadata_manager.py`

Extracts from financial emails:
- Bank information (IBAN, account numbers, bank names)
- Addresses
- Relationships (employers, business contacts)
- Travel preferences

### `MetadataStorage`

**File:** `services/pfm_email_processor/metadata_storage.py`

Persists metadata to Supabase.

### `profile_manager.py`

Manages user profile data extracted from emails (name, DOB, gender).

### `gender_inference.py`

Infers gender from first name.

---

## Multi-Layer Extraction (Research Pipeline)

### `MultiLayerExtractor`

**File:** `services/transaction_extraction/layers/base.py`

5-layer extraction engine for evaluation against labeled datasets:

**Layer 1** (`extraction_layer1.py`): Rule-based regex
- Currency patterns: AED, USD, SAR, EUR, GBP, INR, JPY, CNY
- Date patterns: YYYY-MM-DD, DD/MM/YYYY, etc.
- Card last-4 digits extraction
- Direction keywords (incoming/outgoing)
- TransferScope, IncomeSubType detection

**Layer 2** (`extraction_layer2.py`): LLM coarse extraction
- MerchantName, Amount, BaseCurrency, Direction, EmailType, SubCategory

**Layer 2.5** (`extraction_layer2_5.py`): SubCategory-specific extraction

**Layer 3** (`extraction_layer3.py`): LLM fine-grained extraction
- Category-specific prompts
- order_id, transaction_date, card_last_4

**Layer 4** (`extraction_layer4.py`): Validation + refinement
- PFMEffect / ExpenseSubType rules:
  - Transfer category + outgoing direction -> ExpenseSubType = "transfer_out"
  - If PFMEffect is "expense" -> ExpenseSubType = "transfer_out"

**Layer 5** (`extraction_layer5.py`): Iterative refinement
- Multiple LLM passes
- Critical rule: "ExpenseSubType: ONLY set if PFMEffect is 'expense', otherwise MUST be null"

### Evaluation Tools

- `evaluation_system.py` — evaluation framework
- `run_evaluation.py` / `run_evaluation_for_golden.py` / `run_evaluation_for_mix.py` — runners
- `chaos_regression_report.py` — regression testing with field-level metrics
- `weak_signal_detector.py` — detects poor-quality extractions and alerts

---

## Configuration Reference

**File:** `services/pfm_email_processor/config.py`

### Gmail Settings
| Setting | Value |
|---|---|
| `GMAIL_QUERY_TEMPLATE` | `"after:{start_date}"` |
| `DEFAULT_LOOKBACK_DAYS` | 30 |
| `MAX_EMAILS_PER_BATCH` | 100 |

### LLM Settings
| Setting | Value |
|---|---|
| `OPENROUTER_MODEL` | `"openai/gpt-4o-mini"` |
| `OPENROUTER_BASE_URL` | `"https://openrouter.ai/api/v1"` |
| `LLM_TEMPERATURE` | 0.1 |
| `LLM_MAX_TOKENS` | 2000 |
| `LLM_TIMEOUT` | 30s |

### Vision API Settings
| Setting | Value |
|---|---|
| `ENABLE_HTML_IMAGE_OCR` | True |
| `VISION_API_ENABLED` | True |
| `VISION_API_TIMEOUT` | 120s |

### Intent Classification Thresholds (0-10 scale)
| Threshold | Value | Description |
|---|---|---|
| `accept_transaction_intent` | 7 | Minimum to accept |
| `accept_max_marketing` | 4 | Maximum marketing score to accept |
| `reject_transaction_intent` | 4 | Below this = reject |
| `reject_min_marketing` | 8 | Above this = reject |
| `reject_min_risk` | 7 | Above this = reject |

### Feature Flags
| Flag | Default | Description |
|---|---|---|
| `USE_AI_INTENT_CLASSIFIER` | True | Enable LLM intent classification |
| `USE_HYBRID_CLASSIFIER` | True | Enable two-stage classification |

---

## PFM Data Schema

### Core Fields (from `GOLDEN_EXTRACTION_FIELDS`)

| Field | Description | Example Values |
|---|---|---|
| `MerchantName` | Transaction counterparty | "Carrefour", "Emirates" |
| `Category` | High-level category | "Groceries", "Travel", "Shopping" |
| `SubCategory` | Detailed sub-category | "FOOD_AND_DRINK", "UTILITIES" |
| `EmailType` | Source document type | "transaction", "invoice", "receipt" |
| `BaseCurrency` | Currency code | "AED", "USD", "SAR" |
| `Amount` | Transaction amount | 150.00 |
| `Direction` | Money flow direction | "incoming", "outgoing" |
| `PFMEffect` | **Core PFM field** | "expense", "income", "neutral" |
| `FlowType` | Transaction flow | "transfer", "payment", "purchase" |
| `IncomeSubType` | Income classification | "salary", "refund", "other_income" |
| `TransferScope` | Transfer geography | "domestic_external_bank", "international_external_bank" |
| `AccountRelationship` | Account type | "user_own_current", "third_party_individual" |
| `ExpenseSubType` | Expense classification | "transfer_out", "transfer_out_unknown_category" |
| `Label` | Free-text label | — |

### Classification Fields (Regression Testing)

```python
CLASSIFICATION_FIELDS = {
    'golden': ['EmailType', 'Category', 'SubCategory', 'Direction', 'PFMEffect',
               'FlowType', 'IncomeSubType', 'ExpenseSubType', 'TransferScope',
               'AccountRelationship'],
    'chaos': ['direction'],
}
```

---

## CLI Interface

**File:** `services/pfm_email_processor/cli.py`

```bash
# Process last 30 days of emails for default user
python -m services.pfm_email_processor.cli --days 30

# Process for specific user
python -m services.pfm_email_processor.cli --days 30 --user-id <user_uuid>
```
