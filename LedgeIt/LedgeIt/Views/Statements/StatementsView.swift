import SwiftUI
import PDFKit
import GRDB

struct StatementsView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var passwords: [StatementPassword] = []
    @State private var imports: [StatementImport] = []
    @State private var showAddPassword = false
    @State private var editingPassword: StatementPassword?

    // PDF attachments from Gmail
    @State private var pdfAttachments: [AttachmentWithEmail] = []
    @State private var isLoadingAttachments = false

    // Processing state
    @State private var processingAttachmentId: Int64?
    @State private var processStatus = ""
    @State private var processingStep = 0
    @State private var extractedTransactions: [StatementService.ExtractedTransaction] = []
    @State private var extractedBankName: String?
    @State private var extractedFilename: String?
    @State private var extractionError: String?
    @State private var isImporting = false
    @State private var paymentSummary: PDFExtractor.PaymentSummary?
    @State private var isCreatingReminder = false
    @State private var reminderCreated = false

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

                // Password Vault
                PasswordVaultSection(
                    l10n: l10n,
                    passwords: $passwords,
                    showAddPassword: $showAddPassword,
                    editingPassword: $editingPassword
                )

                Divider()

                // Gmail PDF Attachments
                GmailPDFSection(
                    l10n: l10n,
                    attachments: pdfAttachments,
                    isLoading: isLoadingAttachments,
                    processingId: processingAttachmentId,
                    processStatus: processStatus,
                    processingStep: processingStep,
                    extractedTransactions: extractedTransactions,
                    extractedBankName: extractedBankName,
                    extractionError: extractionError,
                    isImporting: isImporting,
                    importedFilenames: Set(imports.map(\.filename)),
                    paymentSummary: paymentSummary,
                    isCreatingReminder: isCreatingReminder,
                    reminderCreated: reminderCreated,
                    onRefresh: { loadAttachments() },
                    onProcess: { att in processAttachment(att) },
                    onImportAll: { importAll() },
                    onCancel: { clearExtraction() },
                    onCreateReminder: { createPaymentReminder() }
                )

                Divider()

                // Import History
                ImportHistorySection(l10n: l10n, imports: imports)
            }
            .padding(20)
        }
        .navigationTitle(l10n.statements)
        .onAppear {
            loadData()
            loadAttachments()
        }
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

    // MARK: - Data Loading

    private func loadData() {
        passwords = StatementPassword.loadAll()
        imports = (try? AppDatabase.shared.db.read { db in
            try StatementImport
                .order(StatementImport.Columns.id.desc)
                .fetchAll(db)
        }) ?? []
    }

    private func loadAttachments() {
        isLoadingAttachments = true
        Task {
            do {
                let allPDFs = try AppDatabase.shared.db.read { db in
                    let sql = """
                        SELECT a.*, e.subject AS email_subject, e.sender AS email_sender, e.date AS email_date
                        FROM attachments a
                        JOIN emails e ON a.email_id = e.id
                        WHERE LOWER(a.mime_type) LIKE '%pdf%'
                           OR LOWER(a.filename) LIKE '%.pdf'
                        ORDER BY e.date DESC
                    """
                    return try AttachmentWithEmail.fetchAll(db, sql: sql)
                }
                pdfAttachments = allPDFs.filter { isFinancialPDF($0) }
            } catch {
                print("Failed to load PDF attachments: \(error)")
            }
            isLoadingAttachments = false
        }
    }

    private func isFinancialPDF(_ att: AttachmentWithEmail) -> Bool {
        let filename = (att.filename ?? "").lowercased()
        let subject = (att.emailSubject ?? "").lowercased()
        let sender = (att.emailSender ?? "").lowercased()
        let combined = "\(filename) \(subject) \(sender)"

        // Reject non-financial PDFs first
        let rejectKeywords = [
            // Career / recruitment
            "career", "recruit", "hiring", "job", "interview", "resume", "cv",
            "vacancy", "position", "talent", "onboarding", "orientation",
            "apac career", "linkedin", "glassdoor", "indeed",
            // Education / courses
            "course", "syllabus", "lecture", "tutorial", "training material",
            "certificate of completion",
            // Marketing / events
            "newsletter", "webinar", "conference", "invitation", "rsvp",
            "brochure", "catalog", "flyer", "promo",
            // Legal / contracts (non-financial)
            "nda", "terms of service", "privacy policy",
            // Technical / manuals
            "user guide", "manual", "datasheet", "whitepaper", "spec sheet",
        ]

        for keyword in rejectKeywords {
            if combined.contains(keyword) { return false }
        }

        let financialKeywords = [
            // English
            "statement", "estatement", "e-statement", "credit card",
            "invoice", "receipt", "billing", "payment", "transaction",
            "account summary", "balance", "instalment", "installment",
            // Chinese
            "帳單", "對帳單", "消費明細", "信用卡", "銀行", "存摺", "繳款",
            "交易明細", "月結單", "帳戶", "繳費", "收據", "發票",
            // Bank-specific filename prefixes
            "dailystmt", "ebma", "ubot", "esun", "cbgcc",
        ]

        for keyword in financialKeywords {
            if combined.contains(keyword) { return true }
        }

        let senderDomains = [
            "richart.tw", "taishinbank", "esunbank", "cathaybk", "ubot.com",
            "hncb.com", "dbs.com", "megabank", "firstbank", "sinopac",
            "ctbcbank", "tcb-bank", "scsb.com", "feib.com",
        ]

        for domain in senderDomains {
            if sender.contains(domain) { return true }
        }

        return false
    }

    // MARK: - Processing

    private func processAttachment(_ att: AttachmentWithEmail) {
        guard let emailId = att.emailId,
              let gmailAttachmentId = att.gmailAttachmentId else { return }

        processingAttachmentId = att.id
        extractionError = nil
        extractedTransactions = []
        processingStep = 0

        Task {
            do {
                // 1. Download + decrypt PDF
                processingStep = 0
                let authService = GoogleAuthService()
                let gmail = GmailService(accessTokenProvider: {
                    try await authService.getValidAccessToken()
                })
                let pdfData = try await gmail.getAttachment(messageId: emailId, attachmentId: gmailAttachmentId)

                // 2. Classify document
                processingStep = 1

                // 3. Extract transactions (handled inside processStatement)
                processingStep = 2
                let result = try await service.processStatement(data: pdfData, filename: att.filename ?? "statement.pdf")

                // 4. Categorizing
                processingStep = 3
                extractedTransactions = result.transactions
                extractedBankName = result.bankName
                extractedFilename = att.filename ?? "statement.pdf"
                paymentSummary = result.paymentSummary
            } catch {
                extractionError = error.localizedDescription
            }
            processingAttachmentId = nil
            processStatus = ""
            processingStep = 0
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
        paymentSummary = nil
        reminderCreated = false
    }

    private func createPaymentReminder() {
        guard let summary = paymentSummary,
              let dueDate = summary.dueDate,
              let totalDue = summary.totalDue else { return }

        isCreatingReminder = true
        Task {
            do {
                let authService = GoogleAuthService()
                let calendarService = CalendarService(accessTokenProvider: {
                    try await authService.getValidAccessToken()
                })
                let bank = extractedBankName ?? "Credit Card"
                let currency = summary.currency ?? "TWD"
                _ = try await calendarService.createPaymentEvent(
                    merchant: bank,
                    amount: totalDue,
                    currency: currency,
                    date: dueDate,
                    description: "Payment due: \(bank) \(currency) \(String(format: "%.0f", totalDue))"
                )
                reminderCreated = true
            } catch {
                extractionError = error.localizedDescription
            }
            isCreatingReminder = false
        }
    }
}

// MARK: - Attachment + Email Join Model

struct AttachmentWithEmail: Codable, FetchableRecord, Identifiable, Sendable {
    var id: Int64?
    var emailId: String?
    var filename: String?
    var mimeType: String?
    var size: Int?
    var gmailAttachmentId: String?
    var extractedText: String?
    var isProcessed: Bool = false
    var emailSubject: String?
    var emailSender: String?
    var emailDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case emailId = "email_id"
        case filename
        case mimeType = "mime_type"
        case size
        case gmailAttachmentId = "gmail_attachment_id"
        case extractedText = "extracted_text"
        case isProcessed = "is_processed"
        case emailSubject = "email_subject"
        case emailSender = "email_sender"
        case emailDate = "email_date"
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
                            Text(String(repeating: "\u{2022}", count: 8))
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

// MARK: - Gmail PDF Section

private struct GmailPDFSection: View {
    let l10n: L10n
    let attachments: [AttachmentWithEmail]
    let isLoading: Bool
    let processingId: Int64?
    let processStatus: String
    let processingStep: Int
    let extractedTransactions: [StatementService.ExtractedTransaction]
    let extractedBankName: String?
    let extractionError: String?
    let isImporting: Bool
    let importedFilenames: Set<String>
    let paymentSummary: PDFExtractor.PaymentSummary?
    let isCreatingReminder: Bool
    let reminderCreated: Bool
    let onRefresh: () -> Void
    let onProcess: (AttachmentWithEmail) -> Void
    let onImportAll: () -> Void
    let onCancel: () -> Void
    let onCreateReminder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(l10n.gmailPDFs, systemImage: "envelope.badge.fill")
                    .font(.headline)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(isLoading)
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

            // Payment summary card
            if let summary = paymentSummary, summary.dueDate != nil || summary.totalDue != nil {
                PaymentSummaryCard(
                    l10n: l10n,
                    summary: summary,
                    bankName: extractedBankName,
                    isCreatingReminder: isCreatingReminder,
                    reminderCreated: reminderCreated,
                    onCreateReminder: onCreateReminder
                )
            }

            // Extracted transactions preview
            if !extractedTransactions.isEmpty {
                TransactionPreviewCard(
                    l10n: l10n,
                    transactions: extractedTransactions,
                    bankName: extractedBankName,
                    isImporting: isImporting,
                    onImportAll: onImportAll,
                    onCancel: onCancel
                )
            }

            // Attachment list
            if attachments.isEmpty && !isLoading {
                ContentUnavailableView(
                    l10n.noGmailPDFs,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(l10n.noGmailPDFsDesc)
                )
            } else {
                VStack(spacing: 4) {
                    ForEach(attachments) { att in
                        let isImported = importedFilenames.contains(att.filename ?? "")
                        let isProcessingThis = processingId == att.id

                        HStack(spacing: 10) {
                            Image(systemName: isImported ? "checkmark.circle.fill" : "doc.fill")
                                .foregroundStyle(isImported ? .green : .blue)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(att.filename ?? "attachment.pdf")
                                    .font(.callout).fontWeight(.medium)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let sender = att.emailSender {
                                        Text(sender.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespaces) ?? sender)
                                            .font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    if let date = att.emailDate {
                                        Text(date.prefix(10))
                                            .font(.caption2).foregroundStyle(.tertiary)
                                            .monospacedDigit()
                                    }
                                }
                            }

                            Spacer()

                            if let size = att.size {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }

                            if isProcessingThis {
                                AIProgressView(
                                    title: l10n.parse,
                                    steps: [
                                        l10n.decrypting,
                                        "Classifying document",
                                        "Extracting transactions",
                                        "Categorizing"
                                    ],
                                    currentStep: processingStep
                                )
                                .frame(width: 220)
                            } else if isImported {
                                Text(l10n.imported)
                                    .font(.caption2).foregroundStyle(.green)
                            } else {
                                Button(l10n.parse) {
                                    onProcess(att)
                                }
                                .buttonStyle(.bordered).controlSize(.regular)
                                .disabled(processingId != nil)
                            }
                        }
                        .padding(10)
                        .background(isProcessingThis ? Color.accentColor.opacity(0.05) : Color.clear)
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

// MARK: - Payment Summary Card

private struct PaymentSummaryCard: View {
    let l10n: L10n
    let summary: PDFExtractor.PaymentSummary
    let bankName: String?
    let isCreatingReminder: Bool
    let reminderCreated: Bool
    let onCreateReminder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(.orange)
                Text(l10n.paymentSummaryTitle)
                    .font(.subheadline).fontWeight(.semibold)
                if let bank = bankName {
                    Text("— \(bank)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let type = summary.amountType {
                    Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 20) {
                // Total due
                if let total = summary.totalDue {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.totalDue)
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(summary.currency ?? "TWD") \(String(format: "%,.0f", total))")
                            .font(.title3).fontWeight(.bold).foregroundStyle(.red)
                    }
                }

                // Minimum due
                if let minimum = summary.minimumDue {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.minimumDue)
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(summary.currency ?? "TWD") \(String(format: "%,.0f", minimum))")
                            .font(.callout).fontWeight(.semibold)
                    }
                }

                // Due date
                if let dueDate = summary.dueDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.paymentDueDate)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(dueDate)
                            .font(.callout).fontWeight(.semibold).monospacedDigit()
                    }
                }

                // Statement period
                if let period = summary.statementPeriod {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.statementPeriod)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(period)
                            .font(.caption).monospacedDigit()
                    }
                }
            }

            // Calendar reminder button
            if summary.dueDate != nil && summary.totalDue != nil {
                Divider()
                HStack {
                    Spacer()
                    if reminderCreated {
                        Label(l10n.reminderCreated, systemImage: "checkmark.circle.fill")
                            .font(.callout).foregroundStyle(.green)
                    } else {
                        Button {
                            onCreateReminder()
                        } label: {
                            if isCreatingReminder {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(l10n.creatingReminder)
                                }
                            } else {
                                Label(l10n.createCalendarReminder, systemImage: "calendar.badge.plus")
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .controlSize(.small)
                        .disabled(isCreatingReminder)
                    }
                }
            }
        }
        .padding(12)
        .background(.orange.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Transaction Preview Card

private struct TransactionPreviewCard: View {
    let l10n: L10n
    let transactions: [StatementService.ExtractedTransaction]
    let bankName: String?
    let isImporting: Bool
    let onImportAll: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.extractedTransactions)
                    .font(.subheadline).fontWeight(.semibold)
                if let bank = bankName {
                    Text("— \(bank)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(transactions.count) \(l10n.transactionCount)")
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

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(transactions) { tx in
                        HStack(spacing: 0) {
                            Text(tx.transactionDate?.prefix(10).description ?? "—")
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
        .background(.green.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
