# Credit Card Statement Import — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Statements page where users can store credit card PDF passwords in Keychain, upload encrypted PDF statements, auto-decrypt and extract transactions via the existing LLM pipeline, and track import history.

**Architecture:** New sidebar item "Statements" with a dedicated view. Passwords stored in Keychain as a JSON array under a new key. PDF decryption via PDFKit's `unlock(withPassword:)`. Extracted text flows through existing `PDFExtractor` → `AutoCategorizer` → `TransferDetector`. Import history tracked in a new `statement_imports` GRDB table.

**Tech Stack:** SwiftUI, PDFKit (macOS SDK), GRDB, KeychainService, OpenRouter LLM (via existing PDFExtractor)

---

### Task 1: Add StatementPassword Model + Keychain Storage

**Files:**
- Create: `LedgeIt/LedgeIt/Models/StatementPassword.swift`
- Modify: `LedgeIt/LedgeIt/Services/KeychainService.swift`

**Step 1: Create the StatementPassword model**

Create `LedgeIt/LedgeIt/Models/StatementPassword.swift`:

```swift
import Foundation

struct StatementPassword: Codable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var bankName: String
    var cardLabel: String
    var password: String

    static let keychainAccount = "statement_passwords"

    static func loadAll() -> [StatementPassword] {
        guard let json = KeychainService.loadRaw(account: StatementPassword.keychainAccount),
              let data = json.data(using: .utf8),
              let passwords = try? JSONDecoder().decode([StatementPassword].self, from: data) else {
            return []
        }
        return passwords
    }

    static func saveAll(_ passwords: [StatementPassword]) throws {
        let data = try JSONEncoder().encode(passwords)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "StatementPassword", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode passwords"])
        }
        try KeychainService.saveRaw(account: StatementPassword.keychainAccount, value: json)
    }
}
```

**Step 2: Add raw Keychain accessors to KeychainService**

In `LedgeIt/LedgeIt/Services/KeychainService.swift`, add these two methods (after the existing `deleteAll()` method). These allow storing arbitrary JSON under a custom account name, separate from the API credentials:

```swift
// MARK: - Raw Account Storage (for non-Key data like statement passwords)

static func loadRaw(account: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data,
          let str = String(data: data, encoding: .utf8) else {
        return nil
    }
    return str
}

static func saveRaw(account: String, value: String) throws {
    guard let data = value.data(using: .utf8) else { return }

    // Delete existing
    let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: account
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    // Add new
    let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: account,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
    ]
    let status = SecItemAdd(addQuery as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw NSError(domain: "KeychainService", code: Int(status),
                      userInfo: [NSLocalizedDescriptionKey: "Keychain save failed: \(status)"])
    }
}
```

**Step 3: Build to verify**

Run: `swift build`
Expected: Build complete with no errors.

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Models/StatementPassword.swift LedgeIt/LedgeIt/Services/KeychainService.swift
git commit -m "feat: add StatementPassword model with Keychain storage"
```

---

### Task 2: Add StatementImport Model + Database Migration

**Files:**
- Create: `LedgeIt/LedgeIt/Models/StatementImport.swift`
- Modify: `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift`

**Step 1: Create the StatementImport GRDB model**

Create `LedgeIt/LedgeIt/Models/StatementImport.swift`:

```swift
import Foundation
import GRDB

struct StatementImport: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var filename: String
    var bankName: String?
    var statementPeriod: String?
    var transactionCount: Int = 0
    var importedAt: String?
    var status: String = "pending"  // pending, processing, done, failed
    var errorMessage: String?

    static let databaseTableName = "statement_imports"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let filename = Column(CodingKeys.filename)
        static let bankName = Column(CodingKeys.bankName)
        static let statementPeriod = Column(CodingKeys.statementPeriod)
        static let transactionCount = Column(CodingKeys.transactionCount)
        static let importedAt = Column(CodingKeys.importedAt)
        static let status = Column(CodingKeys.status)
        static let errorMessage = Column(CodingKeys.errorMessage)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case bankName = "bank_name"
        case statementPeriod = "statement_period"
        case transactionCount = "transaction_count"
        case importedAt = "imported_at"
        case status
        case errorMessage = "error_message"
    }
}
```

**Step 2: Add database migration**

In `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift`, add a new migration after the last existing one. Find the last `migrator.registerMigration("vN")` block and add:

```swift
migrator.registerMigration("v9") { db in
    try db.create(table: "statement_imports") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("filename", .text).notNull()
        t.column("bank_name", .text)
        t.column("statement_period", .text)
        t.column("transaction_count", .integer).notNull().defaults(to: 0)
        t.column("imported_at", .text)
        t.column("status", .text).notNull().defaults(to: "pending")
        t.column("error_message", .text)
    }
}
```

> **Note:** Check the last migration version number. If the last is `v8`, use `v9`. If it's different, increment accordingly.

**Step 3: Build to verify**

Run: `swift build`
Expected: Build complete with no errors.

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Models/StatementImport.swift LedgeIt/LedgeIt/Database/DatabaseMigrations.swift
git commit -m "feat: add StatementImport model and database migration"
```

---

### Task 3: Create StatementService (PDF Decrypt + Extract)

**Files:**
- Create: `LedgeIt/LedgeIt/Services/StatementService.swift`

**Step 1: Create the service**

This service orchestrates: load passwords → try decrypt → extract text → LLM extraction → categorization.

Create `LedgeIt/LedgeIt/Services/StatementService.swift`:

```swift
import Foundation
import PDFKit

@MainActor
final class StatementService {
    let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    struct ExtractionResult: Sendable {
        let transactions: [ExtractedTransaction]
        let bankName: String?
        let matchedPassword: StatementPassword?
    }

    struct ExtractedTransaction: Identifiable, Sendable {
        let id = UUID()
        var amount: Double
        var currency: String
        var merchant: String?
        var description: String?
        var transactionDate: String?
        var type: String?
        var category: String?
        var subcategory: String?
        var transferType: String?
        var transferMetadata: String?
        var isTransfer: Bool = false
    }

    // MARK: - Decrypt PDF

    func decryptPDF(data: Data) throws -> (PDFDocument, StatementPassword?) {
        guard let document = PDFDocument(data: data) else {
            throw StatementError.invalidPDF
        }

        // If not encrypted, return directly
        if !document.isLocked {
            return (document, nil)
        }

        // Try all stored passwords
        let passwords = StatementPassword.loadAll()
        for pw in passwords {
            if document.unlock(withPassword: pw.password) {
                return (document, pw)
            }
        }

        throw StatementError.noMatchingPassword
    }

    // MARK: - Extract Text

    func extractText(from document: PDFDocument) throws -> String {
        var fullText = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i),
                  let text = page.string else { continue }
            fullText += text + "\n"
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StatementError.noTextContent
        }

        if PDFParserService.isGarbageText(trimmed) {
            throw StatementError.garbageText
        }

        return trimmed
    }

    // MARK: - Full Pipeline

    func processStatement(data: Data, filename: String) async throws -> ExtractionResult {
        // 1. Decrypt
        let (document, matchedPw) = try decryptPDF(data: data)

        // 2. Extract text
        let pdfText = try extractText(from: document)

        // 3. LLM extraction
        let openRouter = try OpenRouterService()
        let extractor = PDFExtractor(openRouter: openRouter)
        guard let financialData = try await extractor.extractFinancialData(
            pdfText: pdfText,
            emailSubject: filename,
            emailSender: matchedPw?.bankName ?? "Credit Card Statement"
        ) else {
            throw StatementError.extractionFailed
        }

        // 4. Categorize + detect transfers
        let transactions = financialData.transactions.map { raw -> ExtractedTransaction in
            let cat = AutoCategorizer.categorize(
                merchant: raw.merchant,
                description: raw.description,
                docType: financialData.documentType,
                amount: raw.amount
            )
            let transferResult = TransferDetector.detectTransfer(
                in: "\(raw.merchant ?? "") \(raw.description ?? "")",
                amount: raw.amount
            )
            var metadataJSON: String? = nil
            if transferResult.isTransfer, !transferResult.metadata.isEmpty {
                metadataJSON = (try? String(data: JSONEncoder().encode(transferResult.metadata), encoding: .utf8))
            }
            return ExtractedTransaction(
                amount: raw.amount,
                currency: raw.currency ?? "TWD",
                merchant: raw.merchant,
                description: raw.description,
                transactionDate: raw.date,
                type: transferResult.isTransfer ? "transfer" : (raw.type ?? "debit"),
                category: cat.rawValue,
                subcategory: cat.dimension,
                transferType: transferResult.transferType,
                transferMetadata: metadataJSON,
                isTransfer: transferResult.isTransfer
            )
        }

        return ExtractionResult(
            transactions: transactions,
            bankName: financialData.issuer ?? matchedPw?.bankName,
            matchedPassword: matchedPw
        )
    }

    // MARK: - Save to DB

    func saveTransactions(_ extracted: [ExtractedTransaction], filename: String, bankName: String?) async throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try await database.db.write { db in
            for tx in extracted {
                var transaction = Transaction(
                    amount: tx.amount,
                    currency: tx.currency,
                    merchant: tx.merchant,
                    category: tx.category,
                    subcategory: tx.subcategory,
                    transactionDate: tx.transactionDate,
                    description: tx.description,
                    type: tx.type,
                    transferType: tx.transferType,
                    transferMetadata: tx.transferMetadata,
                    createdAt: now
                )
                try transaction.insert(db)
            }

            // Record import
            var record = StatementImport(
                filename: filename,
                bankName: bankName,
                transactionCount: extracted.count,
                importedAt: now,
                status: "done"
            )
            try record.insert(db)
        }
    }

    // MARK: - Errors

    enum StatementError: LocalizedError {
        case invalidPDF
        case noMatchingPassword
        case noTextContent
        case garbageText
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "Invalid or corrupted PDF file"
            case .noMatchingPassword: return "No stored password could decrypt this PDF"
            case .noTextContent: return "PDF contains no extractable text"
            case .garbageText: return "PDF text is unreadable (scanned image?)"
            case .extractionFailed: return "Failed to extract financial data from PDF"
            }
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build complete. May need minor adjustments if `LeanCategory.dimension` or `LLMProcessor.ExtractedTransaction` fields differ — check compiler output.

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/StatementService.swift
git commit -m "feat: add StatementService for PDF decrypt and extraction pipeline"
```

---

### Task 4: Add Localization Strings

**Files:**
- Modify: `LedgeIt/LedgeIt/Utilities/Localization.swift`

**Step 1: Add all statement-related L10n strings**

Add these computed properties to the `L10n` struct (find the last string definition and add after it):

```swift
// MARK: - Statements
var statements: String { s("Statements", "帳單") }
var statementsSubtitle: String { s("Import credit card statements", "匯入信用卡帳單") }
var passwordVault: String { s("Password Vault", "密碼保管庫") }
var addPassword: String { s("Add Password", "新增密碼") }
var editPassword: String { s("Edit Password", "編輯密碼") }
var bankName: String { s("Bank Name", "銀行名稱") }
var cardLabel: String { s("Card Label", "卡片名稱") }
var pdfPassword: String { s("PDF Password", "PDF 密碼") }
var deletePassword: String { s("Delete", "刪除") }
var savePassword: String { s("Save", "儲存") }
var cancelAction: String { s("Cancel", "取消") }
var uploadStatement: String { s("Upload Statement", "上傳帳單") }
var dropPDFHere: String { s("Drop PDF here or click to browse", "拖放 PDF 檔案或點擊瀏覽") }
var processing: String { s("Processing...", "處理中...") }
var decrypting: String { s("Decrypting PDF...", "解密 PDF 中...") }
var extractingText: String { s("Extracting text...", "擷取文字中...") }
var analyzingTransactions: String { s("Analyzing transactions...", "分析交易中...") }
var extractedTransactions: String { s("Extracted Transactions", "擷取的交易") }
var importAll: String { s("Import All", "全部匯入") }
var noTransactionsFound: String { s("No transactions found", "未找到交易") }
var noTransactionsDesc: String { s("Could not extract transactions from this statement", "無法從此帳單中擷取交易") }
var importHistory: String { s("Import History", "匯入記錄") }
var noImportHistory: String { s("No imports yet", "尚無匯入記錄") }
var noImportHistoryDesc: String { s("Upload a credit card statement to get started", "上傳信用卡帳單以開始") }
var transactionCount: String { s("transactions", "筆交易") }
var importSuccess: String { s("Successfully imported", "匯入成功") }
var noPasswordsYet: String { s("No passwords saved", "尚無儲存的密碼") }
var noPasswordsDesc: String { s("Add your credit card statement passwords to enable auto-decrypt", "新增信用卡帳單密碼以啟用自動解密") }
var statementsSidebar: String { s("Statements", "帳單") }
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build complete with no errors.

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Utilities/Localization.swift
git commit -m "feat: add localization strings for statement import feature"
```

---

### Task 5: Add Sidebar Item + Create StatementsView

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift`
- Create: `LedgeIt/LedgeIt/Views/Statements/StatementsView.swift`

**Step 1: Add sidebar item to ContentView**

In `LedgeIt/LedgeIt/Views/ContentView.swift`:

1. Add `case statements = "Statements"` to the `SidebarItem` enum (after `calendar`, before `analysis`)
2. Add icon in the `icon` computed property: `case .statements: return "doc.text.fill"`
3. Add sidebar row in the "Data" section (after calendar row):
   ```swift
   sidebarRow(l10n.statementsSidebar, icon: SidebarItem.statements.icon)
       .tag(SidebarItem.statements)
   ```
4. Add case in the detail switch:
   ```swift
   case .statements:
       StatementsView()
   ```

**Step 2: Create StatementsView with all 3 sections**

Create directory first, then create `LedgeIt/LedgeIt/Views/Statements/StatementsView.swift`:

```swift
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct StatementsView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var passwords: [StatementPassword] = []
    @State private var imports: [StatementImport] = []
    @State private var showAddPassword = false
    @State private var editingPassword: StatementPassword?

    // Upload state
    @State private var isProcessing = false
    @State private var processStatus = ""
    @State private var extractedTransactions: [StatementService.ExtractedTransaction] = []
    @State private var extractedBankName: String?
    @State private var extractedFilename: String?
    @State private var extractionError: String?
    @State private var isImporting = false
    @State private var isDragOver = false

    private let service = StatementService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.statements)
                        .font(.title2).fontWeight(.bold)
                    Text(l10n.statementsSubtitle)
                        .font(.callout).foregroundStyle(.secondary)
                }

                // MARK: - Password Vault
                PasswordVaultSection(
                    l10n: l10n,
                    passwords: $passwords,
                    showAddPassword: $showAddPassword,
                    editingPassword: $editingPassword
                )

                Divider()

                // MARK: - Upload
                UploadSection(
                    l10n: l10n,
                    isProcessing: isProcessing,
                    processStatus: processStatus,
                    extractedTransactions: extractedTransactions,
                    extractedBankName: extractedBankName,
                    extractionError: extractionError,
                    isImporting: isImporting,
                    isDragOver: $isDragOver,
                    onFilePicked: { url in handleFile(url) },
                    onImportAll: { importAll() },
                    onCancel: { clearExtraction() }
                )

                Divider()

                // MARK: - Import History
                ImportHistorySection(l10n: l10n, imports: imports)
            }
            .padding(20)
        }
        .navigationTitle(l10n.statements)
        .onAppear { loadData() }
        .sheet(isPresented: $showAddPassword) {
            PasswordFormSheet(l10n: l10n, password: nil) { newPw in
                passwords.append(newPw)
                try? StatementPassword.saveAll(passwords)
            }
        }
        .sheet(item: $editingPassword) { pw in
            PasswordFormSheet(l10n: l10n, password: pw) { updated in
                if let idx = passwords.firstIndex(where: { $0.id == updated.id }) {
                    passwords[idx] = updated
                    try? StatementPassword.saveAll(passwords)
                }
            }
        }
    }

    private func loadData() {
        passwords = StatementPassword.loadAll()
        imports = (try? AppDatabase.shared.db.read { db in
            try StatementImport
                .order(StatementImport.Columns.id.desc)
                .fetchAll(db)
        }) ?? []
    }

    private func handleFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            extractionError = "Failed to read file"
            return
        }
        let filename = url.lastPathComponent
        isProcessing = true
        extractionError = nil
        extractedTransactions = []

        Task {
            do {
                processStatus = l10n.decrypting
                let (document, matchedPw) = try service.decryptPDF(data: data)

                processStatus = l10n.extractingText
                let pdfText = try service.extractText(from: document)

                processStatus = l10n.analyzingTransactions
                let openRouter = try OpenRouterService()
                let extractor = PDFExtractor(openRouter: openRouter)
                guard let financialData = try await extractor.extractFinancialData(
                    pdfText: pdfText,
                    emailSubject: filename,
                    emailSender: matchedPw?.bankName ?? "Credit Card Statement"
                ) else {
                    throw StatementService.StatementError.extractionFailed
                }

                let transactions = financialData.transactions.map { raw -> StatementService.ExtractedTransaction in
                    let cat = AutoCategorizer.categorize(
                        merchant: raw.merchant,
                        description: raw.description,
                        docType: financialData.documentType,
                        amount: raw.amount
                    )
                    let transferResult = TransferDetector.detectTransfer(
                        in: "\(raw.merchant ?? "") \(raw.description ?? "")",
                        amount: raw.amount
                    )
                    var metadataJSON: String? = nil
                    if transferResult.isTransfer, !transferResult.metadata.isEmpty {
                        metadataJSON = (try? String(data: JSONEncoder().encode(transferResult.metadata), encoding: .utf8))
                    }
                    return StatementService.ExtractedTransaction(
                        amount: raw.amount,
                        currency: raw.currency ?? "TWD",
                        merchant: raw.merchant,
                        description: raw.description,
                        transactionDate: raw.date,
                        type: transferResult.isTransfer ? "transfer" : (raw.type ?? "debit"),
                        category: cat.rawValue,
                        subcategory: cat.dimension,
                        transferType: transferResult.transferType,
                        transferMetadata: metadataJSON,
                        isTransfer: transferResult.isTransfer
                    )
                }

                extractedTransactions = transactions
                extractedBankName = financialData.issuer ?? matchedPw?.bankName
                extractedFilename = filename
            } catch {
                extractionError = error.localizedDescription
            }
            isProcessing = false
            processStatus = ""
        }
    }

    private func importAll() {
        guard !extractedTransactions.isEmpty, let filename = extractedFilename else { return }
        isImporting = true
        Task {
            do {
                try await service.saveTransactions(extractedTransactions, filename: filename, bankName: extractedBankName)
                clearExtraction()
                loadData()
            } catch {
                extractionError = error.localizedDescription
            }
            isImporting = false
        }
    }

    private func clearExtraction() {
        extractedTransactions = []
        extractedBankName = nil
        extractedFilename = nil
        extractionError = nil
    }
}

// MARK: - Password Vault Section

private struct PasswordVaultSection: View {
    let l10n: L10n
    @Binding var passwords: [StatementPassword]
    @Binding var showAddPassword: Bool
    @Binding var editingPassword: StatementPassword?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(l10n.passwordVault, systemImage: "lock.shield.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showAddPassword = true
                } label: {
                    Label(l10n.addPassword, systemImage: "plus")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            if passwords.isEmpty {
                ContentUnavailableView(
                    l10n.noPasswordsYet,
                    systemImage: "key.fill",
                    description: Text(l10n.noPasswordsDesc)
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(passwords) { pw in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pw.bankName)
                                    .font(.callout).fontWeight(.medium)
                                Text(pw.cardLabel)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(repeating: "•", count: 8))
                                .font(.callout).foregroundStyle(.tertiary)
                            Button {
                                editingPassword = pw
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                passwords.removeAll { $0.id == pw.id }
                                try? StatementPassword.saveAll(passwords)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Upload Section

private struct UploadSection: View {
    let l10n: L10n
    let isProcessing: Bool
    let processStatus: String
    let extractedTransactions: [StatementService.ExtractedTransaction]
    let extractedBankName: String?
    let extractionError: String?
    let isImporting: Bool
    @Binding var isDragOver: Bool
    let onFilePicked: (URL) -> Void
    let onImportAll: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.uploadStatement, systemImage: "arrow.up.doc.fill")
                .font(.headline)

            // Drop zone
            if !isProcessing && extractedTransactions.isEmpty && extractionError == nil {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isDragOver ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isDragOver ? Color.accentColor.opacity(0.05) : Color.clear)
                        )
                        .frame(height: 100)

                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(l10n.dropPDFHere)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .onDrop(of: [.pdf], isTargeted: $isDragOver) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadFileRepresentation(for: .pdf) { url, _, _ in
                        guard let url else { return }
                        // Copy to temp because the provided URL is temporary
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.removeItem(at: tempURL)
                        try? FileManager.default.copyItem(at: url, to: tempURL)
                        DispatchQueue.main.async {
                            onFilePicked(tempURL)
                        }
                    }
                    return true
                }
                .onTapGesture {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        onFilePicked(url)
                    }
                }
            }

            // Processing indicator
            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(processStatus)
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            }

            // Error
            if let error = extractionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.callout).foregroundStyle(.red)
                    Spacer()
                    Button(l10n.cancelAction) { onCancel() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(12)
                .background(.red.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Extracted transactions preview
            if !extractedTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(l10n.extractedTransactions)
                            .font(.subheadline).fontWeight(.semibold)
                        if let bank = extractedBankName {
                            Text("— \(bank)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(extractedTransactions.count) \(l10n.transactionCount)")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    // Table header
                    HStack(spacing: 0) {
                        Text("Date").frame(width: 90, alignment: .leading)
                        Text("Merchant").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Category").frame(width: 100, alignment: .leading)
                        Text("Amount").frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption).foregroundStyle(.tertiary).fontWeight(.medium)
                    .padding(.horizontal, 8)

                    // Transaction rows
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(extractedTransactions) { tx in
                                HStack(spacing: 0) {
                                    Text(tx.transactionDate?.prefix(10) ?? "—")
                                        .frame(width: 90, alignment: .leading)
                                    Text(tx.merchant ?? tx.description ?? "—")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                    Text(tx.category ?? "—")
                                        .frame(width: 100, alignment: .leading)
                                        .font(.caption)
                                    Text(String(format: "%.0f %@", tx.amount, tx.currency))
                                        .frame(width: 100, alignment: .trailing)
                                        .fontWeight(.medium)
                                        .foregroundStyle(tx.type == "credit" ? .green : .primary)
                                }
                                .font(.callout)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.background.tertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(maxHeight: 300)

                    // Action buttons
                    HStack {
                        Spacer()
                        Button(l10n.cancelAction) { onCancel() }
                            .buttonStyle(.bordered)
                        Button {
                            onImportAll()
                        } label: {
                            if isImporting {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(l10n.processing)
                                }
                            } else {
                                Label(l10n.importAll, systemImage: "square.and.arrow.down.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting)
                    }
                }
                .padding(12)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Import History Section

private struct ImportHistorySection: View {
    let l10n: L10n
    let imports: [StatementImport]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(l10n.importHistory, systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if imports.isEmpty {
                ContentUnavailableView(
                    l10n.noImportHistory,
                    systemImage: "tray",
                    description: Text(l10n.noImportHistoryDesc)
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(imports) { record in
                        HStack {
                            Image(systemName: record.status == "done" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(record.status == "done" ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.filename)
                                    .font(.callout).fontWeight(.medium)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    if let bank = record.bankName {
                                        Text(bank).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text("\(record.transactionCount) \(l10n.transactionCount)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let date = record.importedAt {
                                Text(date.prefix(10))
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(10)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Password Form Sheet

private struct PasswordFormSheet: View {
    let l10n: L10n
    let password: StatementPassword?
    let onSave: (StatementPassword) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var bankName = ""
    @State private var cardLabel = ""
    @State private var pdfPassword = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(password == nil ? l10n.addPassword : l10n.editPassword)
                .font(.headline)

            Form {
                TextField(l10n.bankName, text: $bankName)
                TextField(l10n.cardLabel, text: $cardLabel)
                SecureField(l10n.pdfPassword, text: $pdfPassword)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(l10n.cancelAction) { dismiss() }
                    .buttonStyle(.bordered)
                Button(l10n.savePassword) {
                    let pw = StatementPassword(
                        id: password?.id ?? UUID().uuidString,
                        bankName: bankName,
                        cardLabel: cardLabel,
                        password: pdfPassword
                    )
                    onSave(pw)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(bankName.isEmpty || pdfPassword.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let pw = password {
                bankName = pw.bankName
                cardLabel = pw.cardLabel
                pdfPassword = pw.password
            }
        }
    }
}
```

**Step 3: Build to verify**

Run: `swift build`
Expected: Build complete. Check for any missing imports or type mismatches.

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift LedgeIt/LedgeIt/Views/Statements/StatementsView.swift
git commit -m "feat: add Statements page with password vault, upload, and import history"
```

---

### Task 6: Integration Testing & Polish

**Step 1: Build and launch the app**

```bash
swift build && cp .build/debug/LedgeIt /Applications/LedgeIt.app/Contents/MacOS/LedgeIt && open /Applications/LedgeIt.app
```

**Step 2: Manual verification checklist**

1. Click "Statements" in sidebar — page loads with 3 sections
2. Add a password entry — form sheet opens, save works, appears in vault
3. Edit a password — form pre-populates, save updates entry
4. Delete a password — entry removed
5. Drag & drop a PDF — processing states show, transactions appear
6. Click "Import All" — transactions saved, import history updated
7. Restart app — passwords persist (Keychain), import history persists (DB)

**Step 3: Fix any issues found during testing**

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete credit card statement import feature"
```
