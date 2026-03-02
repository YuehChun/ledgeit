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
        let paymentSummary: PDFExtractor.PaymentSummary?
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
        if !document.isLocked {
            return (document, nil)
        }
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
        let (document, matchedPw) = try decryptPDF(data: data)
        let pdfText = try extractText(from: document)

        let openRouter = try OpenRouterService()
        let llmProcessor = LLMProcessor(openRouter: openRouter)
        let extractor = PDFExtractor(llmProcessor: llmProcessor)
        // Use multi-layer statement extraction (classify → extract with powerful model)
        guard let financialData = try await extractor.extractStatementData(
            pdfText: pdfText,
            filename: filename,
            bankHint: matchedPw?.bankName
        ) else {
            throw StatementError.extractionFailed
        }

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
                amount: raw.amount ?? 0,
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
            matchedPassword: matchedPw,
            paymentSummary: financialData.paymentSummary
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
