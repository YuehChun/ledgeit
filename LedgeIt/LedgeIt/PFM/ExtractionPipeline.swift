import Foundation
import GRDB
import Observation

@Observable
@MainActor
final class ExtractionPipeline {

    // MARK: - Properties

    let database: AppDatabase
    let llmProcessor: LLMProcessor
    private let intentClassifier = IntentClassifier()

    var isProcessing = false
    var processedCount = 0
    var totalCount = 0

    // MARK: - Init

    init(database: AppDatabase, llmProcessor: LLMProcessor) {
        self.database = database
        self.llmProcessor = llmProcessor
    }

    // MARK: - Process All Unprocessed Emails

    func processUnprocessedEmails() async throws {
        guard !isProcessing else { return }
        isProcessing = true
        processedCount = 0

        defer { isProcessing = false }

        // 1. Query unprocessed emails
        let emails: [Email] = try await database.db.read { db in
            try Email
                .filter(Email.Columns.isProcessed == false)
                .fetchAll(db)
        }

        totalCount = emails.count

        // Supabase service (optional, best-effort)
        let supabase = try? SupabaseService()
        var financialEmails: [Email] = []

        // 2. Process each email
        for email in emails {
            do {
                let (transactions, isFinancial) = try await processEmail(email)

                // Dedup: filter out transactions that already exist in DB (same amount + currency + date)
                let deduped = try await deduplicateTransactions(transactions)

                // Save transactions
                try await database.db.write { [deduped] db in
                    for txn in deduped {
                        try txn.insert(db)
                    }
                }

                // Mark email as processed
                let emailIsFinancial = isFinancial || !deduped.isEmpty
                try await database.db.write { db in
                    var updated = email
                    updated.isProcessed = true
                    updated.isFinancial = emailIsFinancial
                    try updated.update(db)
                }

                // Collect financial emails for Supabase
                if emailIsFinancial {
                    var finEmail = email
                    finEmail.isProcessed = true
                    finEmail.isFinancial = true
                    financialEmails.append(finEmail)
                }

                processedCount += 1

            } catch {
                // Mark as processed even on failure to avoid reprocessing
                try? await database.db.write { db in
                    var updated = email
                    updated.isProcessed = true
                    updated.classificationResult = "error: \(error.localizedDescription)"
                    try updated.update(db)
                }
                processedCount += 1
            }
        }

        // 3. Upsert financial emails to Supabase (best-effort, batch)
        if let supabase, !financialEmails.isEmpty {
            let batchSize = 50
            for start in stride(from: 0, to: financialEmails.count, by: batchSize) {
                let end = min(start + batchSize, financialEmails.count)
                try? await supabase.upsertEmails(Array(financialEmails[start..<end]))
            }
        }

        // 4. Update SyncState
        try await database.db.write { [processedCount] db in
            if var syncState = try SyncState.fetchOne(db, key: 1) {
                syncState.totalEmailsProcessed += processedCount
                try syncState.update(db)
            }
        }
    }

    // MARK: - Process Single Email

    func processEmail(_ email: Email) async throws -> (transactions: [Transaction], isFinancial: Bool) {
        let subject = email.subject ?? ""
        let sender = email.sender ?? ""

        // Get clean body text: prefer plain text, fall back to stripped HTML
        let body: String
        if let text = email.bodyText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = text
        } else if let html = email.bodyHtml, !html.isEmpty {
            body = Self.stripHTML(html)
        } else {
            body = ""
        }

        // Fetch attachment text (PDFs) for this email
        let attachmentText: String? = try await database.db.read { db in
            let texts = try Attachment
                .filter(Attachment.Columns.emailId == email.id)
                .filter(Attachment.Columns.extractedText != nil)
                .fetchAll(db)
                .compactMap(\.extractedText)
            return texts.isEmpty ? nil : texts.joined(separator: "\n---\n")
        }

        // Extract sender email from "Name <email>" format
        let senderEmail = extractEmail(from: sender)

        // Combine body + attachment text for classification
        let fullText = [body, attachmentText].compactMap { $0 }.joined(separator: "\n\n[Attachment]\n")

        // Step A: Rule-based intent classification
        let classification = intentClassifier.classify(
            subject: subject,
            body: fullText,
            sender: sender,
            senderEmail: senderEmail
        )

        // Step B: For uncertain cases, use LLM classification
        var finalDecision = classification.decision
        var classificationJSON: String?

        if classification.decision == .uncertain {
            let llmResult = try await llmProcessor.classifyEmail(
                subject: subject,
                body: fullText,
                sender: sender
            )

            // Encode classification result for storage
            if let data = try? JSONEncoder().encode(llmResult) {
                classificationJSON = String(data: data, encoding: .utf8)
            }

            // Determine decision from LLM result
            let thresholds = PFMConfig.intentThresholds
            if llmResult.isFinancial &&
               llmResult.transactionIntent >= thresholds.acceptTransactionIntent &&
               llmResult.marketingProbability < thresholds.acceptMaxMarketing {
                finalDecision = .accept
            } else if llmResult.transactionIntent < thresholds.rejectTransactionIntent ||
                      llmResult.marketingProbability >= thresholds.rejectMinMarketing {
                finalDecision = .reject
            } else if llmResult.transactionIntent >= thresholds.reviewMinTransactionIntent {
                finalDecision = .accept  // Accept with caution for review zone
            } else {
                finalDecision = .reject
            }
        } else {
            // Store rule-based reasoning
            classificationJSON = "{\"method\":\"\(classification.method.rawValue)\",\"reasoning\":\"\(classification.reasoning)\"}"
        }

        // Save classification result on email
        let finalClassificationJSON = classificationJSON
        try await database.db.write { [finalClassificationJSON] db in
            var updated = email
            updated.classificationResult = finalClassificationJSON
            try updated.update(db)
        }

        // Step C: If rejected, return empty
        guard finalDecision == .accept else {
            return ([], false)
        }

        // Step D-1: Route credit card statements to bill extraction
        if classification.isCreditCardStatement {
            if let billResult = try await llmProcessor.extractCreditCardBill(
                subject: subject,
                body: fullText,
                sender: sender
            ), let dueDate = billResult.dueDate, let amountDue = billResult.amountDue {
                let bill = CreditCardBill(
                    emailId: email.id,
                    bankName: billResult.bankName ?? sender,
                    dueDate: dueDate,
                    amountDue: amountDue,
                    currency: billResult.currency ?? "TWD",
                    statementPeriod: billResult.statementPeriod
                )
                try await database.db.write { [bill] db in
                    // Deduplicate: skip if same bank + same due date already exists
                    let existing = try CreditCardBill
                        .filter(CreditCardBill.Columns.bankName == bill.bankName)
                        .filter(CreditCardBill.Columns.dueDate == bill.dueDate)
                        .fetchOne(db)
                    if existing == nil {
                        try bill.insert(db)
                    }
                }
            }
            return ([], true)  // Financial but no individual transactions
        }

        // Step D-2: Extract transactions via LLM
        let extractionResult = try await llmProcessor.extractTransactions(
            subject: subject,
            body: fullText,
            sender: sender,
            attachmentText: attachmentText
        )

        // Step E: Build Transaction records with categorization and transfer detection
        let now = ISO8601DateFormatter().string(from: Date())
        var transactions: [Transaction] = []

        for extracted in extractionResult.transactions {
            guard let amount = extracted.amount else { continue }

            // Auto-categorize
            let category = AutoCategorizer.categorize(
                merchant: extracted.merchant,
                description: extracted.description,
                docType: extractionResult.documentType,
                amount: amount
            )

            // Transfer detection if type is "transfer"
            var transferType: String?
            var transferMetadataJSON: String?

            if extracted.type?.lowercased() == "transfer" {
                let combinedText = "\(subject) \(body)"
                let result = TransferDetector.detectTransfer(in: combinedText, amount: amount)
                if result.isTransfer {
                    transferType = result.transferType
                    let metadataDict: [String: String] = [
                        "subtype": result.transferSubtype ?? "",
                        "direction": result.direction,
                        "scope": result.scope,
                        "is_own": result.isOwn ? "true" : "false",
                        "payment_system": result.paymentSystem ?? ""
                    ].merging(result.metadata) { current, _ in current }

                    if let data = try? JSONSerialization.data(withJSONObject: metadataDict),
                       let json = String(data: data, encoding: .utf8) {
                        transferMetadataJSON = json
                    }
                }
            }

            // Encode raw extraction for debugging
            var rawJSON: String?
            if let data = try? JSONEncoder().encode(extracted) {
                rawJSON = String(data: data, encoding: .utf8)
            }

            let transaction = Transaction(
                id: nil,
                emailId: email.id,
                attachmentId: nil,
                amount: amount,
                currency: extracted.currency ?? "USD",
                merchant: extracted.merchant,
                category: category.rawValue,
                subcategory: category.dimension,
                transactionDate: extracted.date,
                description: extracted.description,
                type: extracted.type,
                transferType: transferType,
                transferMetadata: transferMetadataJSON,
                confidence: Double(classification.confidence),
                rawExtraction: rawJSON,
                createdAt: now
            )

            transactions.append(transaction)
        }

        return (transactions, !transactions.isEmpty)
    }

    // MARK: - Deduplication

    /// Filter out transactions that already exist in the DB (same amount + currency + date)
    private func deduplicateTransactions(_ transactions: [Transaction]) async throws -> [Transaction] {
        var result: [Transaction] = []
        for txn in transactions {
            guard let date = txn.transactionDate else {
                result.append(txn)
                continue
            }
            let exists = try await database.db.read { db in
                try Transaction
                    .filter(Transaction.Columns.amount == txn.amount)
                    .filter(Transaction.Columns.currency == txn.currency)
                    .filter(Transaction.Columns.transactionDate == date)
                    .fetchCount(db) > 0
            }
            if !exists {
                result.append(txn)
            }
        }
        return result
    }

    // MARK: - Calendar Sync

    func syncTransactionsToCalendar(calendarService: CalendarService) async throws -> Int {
        // Find transactions not yet in calendar_events
        let unsyncedTransactions: [Transaction] = try await database.db.read { db in
            try Transaction.fetchAll(db, sql: """
                SELECT t.* FROM transactions t
                WHERE t.id NOT IN (SELECT transaction_id FROM calendar_events WHERE transaction_id IS NOT NULL)
                AND t.transaction_date IS NOT NULL
                AND t.merchant IS NOT NULL
                ORDER BY t.transaction_date DESC
                """)
        }

        var syncedCount = 0

        for txn in unsyncedTransactions {
            guard let txnId = txn.id,
                  let merchant = txn.merchant,
                  let date = txn.transactionDate else { continue }

            let title = "\u{1F4B0} \(merchant) - \(String(format: "%.2f", abs(txn.amount))) \(txn.currency)"

            do {
                let response = try await calendarService.createPaymentEvent(
                    merchant: merchant,
                    amount: abs(txn.amount),
                    currency: txn.currency,
                    date: date,
                    description: txn.description
                )

                let event = CalendarEvent(
                    transactionId: txnId,
                    googleEventId: response.id,
                    title: title,
                    date: date,
                    amount: abs(txn.amount),
                    currency: txn.currency,
                    isSynced: true
                )

                try await database.db.write { [event] db in
                    try event.insert(db)
                }

                syncedCount += 1
            } catch {
                // Save with isSynced=false for retry
                let event = CalendarEvent(
                    transactionId: txnId,
                    title: title,
                    date: date,
                    amount: abs(txn.amount),
                    currency: txn.currency,
                    isSynced: false
                )

                try? await database.db.write { [event] db in
                    try event.insert(db)
                }
            }
        }

        return syncedCount
    }

    // MARK: - Helpers

    /// Strip HTML tags and decode common entities to produce clean text.
    static func stripHTML(_ html: String) -> String {
        var result = html

        // Remove <style>...</style> and <script>...</script> blocks
        result = result.replacingOccurrences(
            of: #"<style[^>]*>[\s\S]*?</style>"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<script[^>]*>[\s\S]*?</script>"#,
            with: "",
            options: .regularExpression
        )

        // Replace <br>, <p>, <div>, <tr>, <li> with newlines
        result = result.replacingOccurrences(
            of: #"<\s*(?:br|p|div|tr|li)[^>]*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove all remaining HTML tags
        result = result.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&#160;", " "),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Decode numeric entities like &#123;
        result = result.replacingOccurrences(
            of: #"&#(\d+);"#,
            with: "",
            options: .regularExpression
        )

        // Collapse multiple whitespace/newlines
        result = result.replacingOccurrences(
            of: #"[ \t]+"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractEmail(from senderString: String) -> String {
        // Parse "Display Name <email@domain.com>" format
        if let startIdx = senderString.firstIndex(of: "<"),
           let endIdx = senderString.firstIndex(of: ">") {
            let emailStart = senderString.index(after: startIdx)
            return String(senderString[emailStart..<endIdx])
        }
        // If no angle brackets, the whole string might be an email
        if senderString.contains("@") {
            return senderString.trimmingCharacters(in: .whitespaces)
        }
        return senderString
    }
}
