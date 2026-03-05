# Import My Credit Card PDF

> **As a user**, I want to import password-protected credit card PDF statements and automatically extract all transactions, so I don't have to manually enter dozens of line items.

![Statement Parser](../../screenshots/statements_parser.png)

## The Problem

Credit card statements arrive as password-protected PDFs with dozens of transactions. Manually entering each transaction into a finance app is tedious and error-prone. Some banks don't even send email notifications for individual transactions — only the monthly statement PDF.

## How LedgeIt Solves It

The **Statements** view handles the entire PDF import pipeline:

### Password Vault

Store PDF passwords securely in macOS Keychain. Add passwords for each bank once, and LedgeIt remembers them for future imports. In the screenshot, passwords are stored for two banks (聯邦 and 星展).

### Gmail PDF Attachments

LedgeIt automatically finds PDF attachments from your Gmail. Each attachment shows:
- Filename, sender, date, file size
- **Parse** button to extract transactions with AI

### AI-Powered Extraction

When you click Parse, the AI:
1. Decrypts the PDF using your stored password
2. Extracts the text content
3. Identifies the bank and statement period
4. Extracts every transaction (date, merchant, category, amount)

The screenshot shows a parsed 玉山銀行 (E.SUN Bank) statement with:
- **Payment Summary** — Total due (TWD 27,314), minimum due, due date, period
- **22 Extracted Transactions** — Each with date, merchant name, category, and amount
- Merchants like IKEA, 悠遊卡自動加值, CLAUDE.AI SUBSCRIPTION, 放心初蔬果網

### One-Click Import

Review the extracted transactions, then click **Import All** to add them to your database. Smart deduplication ensures transactions already imported from email notifications won't be duplicated.
