# Credit Card Statement Import — Design Document

**Date:** 2026-03-01
**Status:** Approved

## Problem

Credit card statements are password-encrypted PDFs. Users need a way to:
1. Store bank-specific PDF passwords securely
2. Upload statement PDFs
3. Auto-decrypt using stored passwords
4. Extract transaction data via LLM pipeline
5. Import into the existing transaction system

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Password matching | Auto-try all stored passwords | Simple, no filename convention needed |
| Navigation | New "Statements" sidebar item | Dedicated page for monthly recurring use |
| Password storage | macOS Keychain | Most secure — OS-level encryption, existing KeychainService |
| Extraction pipeline | Full LLM pipeline | Reuse PDFExtractor → AutoCategorizer → TransferDetector |

## Architecture

### Data Model

**StatementPassword** — Keychain-backed (JSON array under key `statement_passwords`)

```json
[
  { "id": "uuid", "bankName": "國泰世華", "cardLabel": "CUBE卡", "password": "A123456789" },
  { "id": "uuid", "bankName": "玉山銀行", "cardLabel": "Pi卡", "password": "B987654321" }
]
```

**StatementImport** — New GRDB table `statement_imports`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| filename | TEXT | Original PDF filename |
| bankName | TEXT | Matched bank (nullable) |
| statementPeriod | TEXT | e.g., "2026-02" |
| transactionCount | INTEGER | Number of extracted transactions |
| importedAt | TEXT | ISO 8601 timestamp |
| status | TEXT | pending / processing / done / failed |
| errorMessage | TEXT | Error details if failed |

**Transaction** — No changes. Imported transactions use `emailId = nil` and `description` notes the source statement.

### UI Layout

Statements page with 3 sections:

1. **Password Vault** — List of bank/card entries with masked passwords. Add/edit/delete. Stored in Keychain.
2. **Upload & Extract** — Drag & drop zone or file picker. Shows processing progress, then extracted transaction preview table with approve/cancel.
3. **Import History** — List of previously imported statements (filename, bank, transaction count, date).

### Processing Flow

```
User drops PDF
  → Load all passwords from Keychain
  → For each password: try PDFDocument.unlock(withPassword:)
  → On success: PDFParserService.extractText()
  → PDFExtractor.extractFinancialData() (LLM call)
  → AutoCategorizer.categorize() + TransferDetector.detectTransfer()
  → Show preview table to user
  → User clicks "Import All"
  → Save transactions to DB + record StatementImport
  → On all passwords fail: Show "No matching password" error
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| StatementPassword | Models/StatementPassword.swift | Codable struct for Keychain storage |
| StatementImport | Models/StatementImport.swift | GRDB model for import history |
| StatementService | Services/StatementService.swift | Decrypt PDF, orchestrate extraction |
| StatementsView | Views/Statements/StatementsView.swift | Main page with 3 sections |
| PasswordVaultSection | Views/Statements/StatementsView.swift | Manage passwords |
| UploadSection | Views/Statements/StatementsView.swift | Drop zone + preview |
| ImportHistorySection | Views/Statements/StatementsView.swift | History list |
| DB Migration | Database/AppDatabase.swift | Add statement_imports table |

### Security

- Passwords never leave Keychain except temporarily in memory during decryption
- No passwords stored in SQLite or UserDefaults
- Keychain access requires device unlock (kSecAttrAccessibleWhenUnlocked)
