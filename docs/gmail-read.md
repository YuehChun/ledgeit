# Gmail Read - Complete Code Reference

This document catalogs every Gmail reading implementation found across `old-ai/`.

All Gmail reading uses the **Gmail REST API** (`googleapiclient`) exclusively. No IMAP usage exists in the codebase.

---

## Table of Contents

1. [Gmail Implementations Overview](#gmail-implementations-overview)
2. [GmailScanner (Bulk Scanner)](#1-gmailscanner---bulk-email-scanner)
3. [PFMGmailClient (PFM Pipeline)](#2-pfmgmailclient---pfm-pipeline-gmail-client)
4. [EmailAgent (Hotel Reservation)](#3-emailagent---hotel-reservation-service)
5. [Email Monitor (LangGraph)](#4-email-monitor---langgraph-based)
6. [EmailAgentTool (Shopping)](#5-emailagenttool---shopping-agent)
7. [Gmail Scan Script](#6-scan-gmail-to-supabase-script)
8. [AWS Fargate Entry Point](#7-aws-fargate-entry-point)
9. [Email Storage](#8-email-storage---supabase-persistence)
10. [OAuth Setup & Tokens](#9-oauth-setup--tokens)

---

## Gmail Implementations Overview

| Implementation | File | Purpose | Scope | Read/Write |
|---|---|---|---|---|
| `GmailScanner` | `services/gmail_scanner.py` | Bulk email scanning to Supabase | `gmail.readonly` | Read only |
| `PFMGmailClient` | `services/pfm_email_processor/gmail_client.py` | PFM pipeline email reading | `gmail.readonly` | Read only |
| `EmailAgent` | `services/hotel_reservation_service.py` | Hotel negotiation emails | `gmail.send`, `gmail.readonly`, `gmail.modify`, `gmail.labels`, `gmail.compose` | Read + Write |
| Email Monitor | `services/email_monitor.py` | Poll unread hotel replies | Uses `EmailAgent` | Read + Write |
| `EmailAgentTool` | `tools/shopping/email_agent_tool.py` | Shopping verification emails | `gmail.readonly`, `gmail.send` | Read + Write |
| `quickstart.py` | `quickstart.py` | Demo / testing | Full scopes | Read + Write |

---

## 1. GmailScanner - Bulk Email Scanner

**File:** `old-ai/services/gmail_scanner.py`

Standalone class for scanning entire Gmail accounts and yielding structured email dicts. Used by `scan_gmail_to_supabase.py` to populate golden/toxic email sample tables.

### Class: `GmailScanner`

```python
class GmailScanner:
    SCOPES = ['https://www.googleapis.com/auth/gmail.readonly']

    def __init__(self, email_address, token_file, oauth_client_file='oauth_client.json')
```

**Constructor Parameters:**
- `email_address` — e.g. `'golden.hugo.backup@gmail.com'`
- `token_file` — e.g. `'token.golden.json'`
- `oauth_client_file` — defaults to `'oauth_client.json'`

### Authentication (`_authenticate`)

Supports three OAuth flows:
1. **Local server** (default) — opens browser automatically
2. **Console** — for Docker/non-interactive environments (auto-detected via `/.dockerenv` or `DOCKER_CONTAINER` env)
3. **Manual** — set `GMAIL_AUTH_METHOD=manual` or `GMAIL_FORCE_MANUAL_AUTH`

After auth, **verifies token matches expected email** via `users().getProfile(userId='me')`. Rejects token mismatches to prevent cross-account data mixing.

### Key Methods

| Method | Description |
|---|---|
| `_authenticate()` | Full OAuth2 flow with token load/refresh/create |
| `is_authenticated()` | Returns `True` if service is initialized |
| `list_all_messages(query, max_results_per_page=500)` | Paginated message listing, yields `{id, threadId}` |
| `get_message(message_id)` | Gets full message details (`format='full'`) |
| `extract_email_body(msg_data)` | Extracts plain text from MIME parts (recursive) |
| `extract_email_metadata(msg_data)` | Returns subject, sender, recipient, date, headers, labels, attachments |
| `scan_all_emails(query)` | High-level iterator yielding complete email dicts |

### Output Format (`scan_all_emails` yields)

```python
{
    'gmail_message_id': str,    # Gmail message ID
    'email_content': str,       # Plain text body
    'subject': str,
    'sender': str,
    'recipient': str,           # Always set to self.email_address
    'date': datetime,
    'headers': dict,            # All headers as key-value
    'metadata': {
        'labels': list,
        'snippet': str,
        'thread_id': str,
        'attachments': [{
            'filename': str,
            'mime_type': str,
            'size': int,
            'attachment_id': str
        }]
    }
}
```

---

## 2. PFMGmailClient - PFM Pipeline Gmail Client

**File:** `old-ai/services/pfm_email_processor/gmail_client.py`

The central Gmail client for the PFM extraction pipeline. Thread-safe, multi-user, with 5 credential loading strategies.

### Class: `PFMGmailClient`

```python
class PFMGmailClient:
    SCOPES = ['https://www.googleapis.com/auth/gmail.readonly']

    def __init__(self, user_id='user-default', token_file_path=None)
```

### Credential Loading Priority

1. **Environment variables** — `GOOGLE_ACCESS_TOKEN` + `GOOGLE_REFRESH_TOKEN` (stateless/Fargate mode)
   - Requires `GOOGLE_CLIENT_ID` + `GOOGLE_CLIENT_SECRET` for refresh
2. **Supabase database** — queries `users` table for `google_access_token` / `google_refresh_token`
   - Falls back to hardcoded Supabase Dashboard OAuth client_id if env vars not set
3. **Explicit token file** — path passed via `token_file_path` constructor arg
4. **Default token file** — `gmail_token_{user_id}.json` in project root
5. **Temp file** — `/tmp/gmail_token_{user_id}.json` (Fargate fallback)

### Thread Safety

- Uses `threading.local()` for per-thread Gmail service instances
- `threading.Lock()` for token refresh coordination
- `get_service()` creates thread-local service instances to avoid SSL issues in ThreadPoolExecutor

### Key Methods

| Method | Description |
|---|---|
| `_initialize_service()` | Loads creds and creates main service instance |
| `_load_credentials()` | 5-method credential loading cascade |
| `_load_credentials_from_supabase()` | Queries Supabase `users` table |
| `get_service()` | Returns thread-local Gmail service (creates if needed) |
| `get_message_with_retry(message_id, format='full', max_retries=3)` | SSL-safe fetch with exponential backoff |
| `extract_email_body(msg_data, skip_image_extraction=False)` | Extracts text + HTML + embedded image OCR |
| `_extract_text_from_embedded_images(html_content, msg_data)` | CID and data URI image extraction |
| `_extract_text_from_image_data(image_data)` | Vision API OCR (GPT-4o via OpenRouter/OpenAI) |
| `_build_cid_map(payload, message_id)` | Maps Content-ID to image data or attachment IDs |
| `_filter_forwarded_message_headers(body)` | Strips forwarded message headers from body text |
| `_clean_html_content(html_content)` | HTML to text with img alt attribute preservation |

### Vision API OCR

When `skip_image_extraction=False` (default), embedded images in HTML emails are processed via Vision API:

- **Supported image sources:** CID references (email attachments), data URI inline images
- **External URLs are skipped** (http/https)
- **Image validation:** PIL check, minimum 10x10 pixels, max 4096 dimension resize, convert to PNG
- **API:** OpenRouter (`openai/gpt-4o`) or OpenAI (`gpt-4o`) depending on API key prefix
- **Prompt focus:** Transaction amounts, merchant names, dates, currency symbols
- **Timeout:** 120 seconds, temperature 0.1, max_tokens 1500

---

## 3. EmailAgent - Hotel Reservation Service

**File:** `old-ai/services/hotel_reservation_service.py` (very large, ~8000+ lines)

Full Gmail OAuth2 setup embedded in hotel reservation service. Handles both reading and sending/replying to emails for hotel negotiation workflow.

### Scopes (broader than PFM)

```python
SCOPES = [
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.modify',
    'https://www.googleapis.com/auth/gmail.labels',
    'https://www.googleapis.com/auth/gmail.compose'
]
```

### Key Functions

```python
def _get_gmail_service():
    """Initialize Gmail service using OAuth2 user authentication"""
    # Loads token.json / oauth_client.json

class EmailAgent:
    def __init__(self):
        self.service = _get_gmail_service()

    def extract_email_body(self, msg_data): ...
    def send_email(self, to_email, subject, body, is_html=False): ...

# Global singleton
email_agent = EmailAgent()
```

### Gmail API Operations Used

| Operation | API Call |
|---|---|
| List messages | `service.users().messages().list(userId='me', q=query, maxResults=10)` |
| Get message | `service.users().messages().get(userId='me', id=message_id)` |
| Mark as read | `service.users().messages().modify(userId='me', id=id, body={'removeLabelIds': ['UNREAD']})` |
| Send email | `service.users().messages().send(userId='me', body={'raw': raw_message})` |
| Get profile | `service.users().getProfile(userId='me')` |

### Utility Functions

```python
def force_gmail_reauth(): ...     # Force re-authentication
def test_gmail_permissions(): ... # Test Gmail API permissions
```

---

## 4. Email Monitor - LangGraph-based

**File:** `old-ai/services/email_monitor.py`

Continuously polls Gmail every 60 seconds for unread hotel replies. Built as a LangGraph state machine.

### How It Works

1. Imports `email_agent` singleton from `hotel_reservation_service`
2. Polls `is:unread` messages
3. For each unread message:
   - Extracts sender, subject, body
   - Extracts `session_id` from email content (links to hotel session)
   - Marks as read via `messages().modify()`
   - Classifies email via LLM (`CLASSIFY_EMAIL_SENDER_AND_CONTENT` prompt)
   - Routes to handler node based on classification

### LangGraph Nodes

| Node | Trigger | Action |
|---|---|---|
| `hotel_agent_mail_monitor` | Entry point (every 60s) | Fetch unread, classify, route |
| `hotel_request_info` | `content_type: info_request` | Fetch user info, generate & send response |
| `hotel_new_offer` | `content_type: new_offer` | Compare prices, notify frontend |
| `hotel_payment_link` | `content_type: payment_pdf/payment_link` | Detect payment type, notify |
| `get_user_signed_pdf` | `content_type: signed_pdf` | Forward signed doc to hotel |
| `user_confirm_hotel_offer` | `content_type: confirm_offer` | Send booking confirmation |

### State Schema

```python
class EmailMonitorState(TypedDict):
    session_id: Optional[str]
    email_id: Optional[str]
    email_content: Optional[str]
    email_subject: Optional[str]
    sender: Optional[str]
    sender_type: Optional[str]        # "hotel" | "user" | "unknown"
    content_classification: Optional[str]
    session_data: Optional[Dict]
    extracted_info: Optional[Dict]
    next_action: Optional[str]
    user_info: Optional[Dict]
    response_email: Optional[Dict]
    session_updates: Optional[Dict]
```

---

## 5. EmailAgentTool - Shopping Agent

**File:** `old-ai/tools/shopping/email_agent_tool.py`

Shopping domain tool for reading verification emails and sending order-related emails.

```python
class EmailAgentTool:
    SCOPES = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.send"
    ]

    def _get_gmail_service(self): ...
    def check_for_verification_email(self, subject_filter): ...
    def send_email(self, to_email, subject, body, is_html=False): ...
```

Uses `token.json` / `oauth_client.json` from project root.

---

## 6. Scan Gmail to Supabase Script

**File:** `old-ai/scripts/scan_gmail_to_supabase.py`

Batch script that uses `GmailScanner` + `EmailStorage` to populate Supabase research tables.

### Email Accounts

| Account | Email | Token File | Supabase Table |
|---|---|---|---|
| golden | `golden.hugo.backup@gmail.com` | `token.golden.json` | `public.golden_email_samples` |
| toxic | `malbank.test.toxic@gmail.com` | `token.toxic.json` | `public.toxic_email_samples` |

### Usage

```bash
# Scan all emails from both accounts
python scripts/scan_gmail_to_supabase.py

# Scan only unread emails
python scripts/scan_gmail_to_supabase.py --query "is:unread"

# Scan with limit (for testing)
python scripts/scan_gmail_to_supabase.py --limit 10

# Dry run (don't store, just scan)
python scripts/scan_gmail_to_supabase.py --dry-run

# Scan specific account only
python scripts/scan_gmail_to_supabase.py --account golden
```

### Batch Processing

- Batch size: 20 emails
- 0.5s delay between batches (rate limit avoidance)
- Deduplication via `gmail_message_id` check before insert
- Recipient safety check: ensures recipient matches expected account email

---

## 7. AWS Fargate Entry Point

**File:** `old-ai/services/pfm_email_processor_aws/main_phase3.py`

Production entry point for the PFM pipeline running on AWS ECS/Fargate. Imports and uses `PFMGmailClient`.

```python
from ai.services.pfm_email_processor.gmail_client import PFMGmailClient

gmail_client = PFMGmailClient(user_id=user_id)
service = gmail_client.get_service()

# Email fetching:
results = service.users().messages().list(userId='me', q=query, maxResults=batch_size).execute()
msg_data = gmail_client.get_message_with_retry(email_id)
body = gmail_client.extract_email_body(msg_data)
```

**Token provisioning on Fargate:**
- `fetch_token_from_db.py` writes `gmail_token_{user_id}.json` from Supabase `users` table
- Alternatively uses `GOOGLE_ACCESS_TOKEN` env var for stateless mode

---

## 8. Email Storage - Supabase Persistence

**File:** `old-ai/services/email_storage.py`

Stores scanned emails into Supabase tables. Used by `scan_gmail_to_supabase.py`.

### Class: `EmailStorage`

```python
class EmailStorage:
    def __init__(self, max_retries=5, base_delay=1.0, max_delay=60.0)
```

**Credential source:** AWS SSM Parameter Store via `utils/env_loader.py`
- `SUPABASE_URL` from `/malbank-ai/staging/supabase-url`
- `SUPABASE_SERVICE_ROLE_KEY` from `/malbank-ai/staging/supabase-service-role-key`

### Key Methods

| Method | Description |
|---|---|
| `email_exists(table_name, gmail_message_id)` | Check if email already stored |
| `emails_exist_batch(table_name, gmail_message_ids)` | Batch dedup check |
| `store_golden_email(email_data)` | Insert to `golden_email_samples` |
| `store_toxic_email(email_data)` | Insert to `toxic_email_samples` |
| `store_golden_emails_batch(emails_data)` | Batch insert to golden |
| `store_toxic_emails_batch(emails_data)` | Batch insert to toxic |

### Rate Limit Handling

Exponential backoff with jitter on 429 errors:
- Max retries: 5
- Base delay: 1.0s
- Max delay: 60.0s
- Formula: `min(base_delay * 2^attempt + random(0,1), max_delay)`

### Record Schema

```python
{
    'gmail_message_id': str,   # Dedup key
    'email_content': str,
    'subject': str,
    'sender': str,
    'recipient': str,
    'date': str,               # ISO format
    'headers': dict,           # JSONB
    'metadata': dict           # JSONB (labels, attachments, snippet, thread_id)
}
```

---

## 9. OAuth Setup & Tokens

### Token Files

| File | Account | Used By |
|---|---|---|
| `oauth_client.json` | Google OAuth app credentials | All Gmail implementations |
| `token.json` | Default token | EmailAgent, EmailAgentTool, quickstart.py |
| `token.golden.json` | `golden.hugo.backup@gmail.com` | GmailScanner |
| `token.toxic.json` | `malbank.test.toxic@gmail.com` | GmailScanner |
| `gmail_token_{user_id}.json` | Per-user tokens | PFMGmailClient |

### AWS SSM Setup Script

**File:** `old-ai/scripts/setup-gmail-oauth-ssm.sh`

Uploads OAuth credentials to AWS SSM Parameter Store:

```bash
aws ssm put-parameter \
  --name "/malbank/${ENVIRONMENT}/gmail-oauth-client" \
  --type "SecureString" \
  --value "$OAUTH_CLIENT_CONTENT"

aws ssm put-parameter \
  --name "/malbank/${ENVIRONMENT}/gmail-oauth-token" \
  --type "SecureString" \
  --value "$TOKEN_CONTENT"
```

### Quickstart / Demo

**File:** `old-ai/quickstart.py`

Basic Gmail API demo script for authentication testing:

```python
def get_gmail_service(): ...  # Full OAuth2 flow

# Operations:
service.users().labels().list(userId='me').execute()
service.users().messages().list(userId='me', maxResults=5).execute()
```
