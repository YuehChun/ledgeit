import Foundation

struct PDFExtractor: Sendable {
    let llmProcessor: LLMProcessor

    struct PDFFinancialData: Codable, Sendable {
        let transactions: [LLMProcessor.ExtractedTransaction]
        let documentType: String?
        let issuer: String?
        let paymentSummary: PaymentSummary?

        enum CodingKeys: String, CodingKey {
            case transactions
            case documentType = "document_type"
            case issuer
            case paymentSummary = "payment_summary"
        }
    }

    struct PaymentSummary: Codable, Sendable {
        let totalDue: Double?
        let minimumDue: Double?
        let dueDate: String?
        let currency: String?
        let statementPeriod: String?
        let amountType: String?  // LLM classification: "total_due", "minimum_due", "new_charges", etc.

        enum CodingKeys: String, CodingKey {
            case totalDue = "total_due"
            case minimumDue = "minimum_due"
            case dueDate = "due_date"
            case currency
            case statementPeriod = "statement_period"
            case amountType = "amount_type"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalDue = Self.flexDouble(from: container, key: .totalDue)
            minimumDue = Self.flexDouble(from: container, key: .minimumDue)
            dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
            statementPeriod = try container.decodeIfPresent(String.self, forKey: .statementPeriod)
            amountType = try container.decodeIfPresent(String.self, forKey: .amountType)
        }

        private static func flexDouble(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
            if let val = try? container.decode(Double.self, forKey: key) { return val }
            if let str = try? container.decode(String.self, forKey: key) { return Double(str) }
            if let val = try? container.decode(Int.self, forKey: key) { return Double(val) }
            return nil
        }
    }

    /// Analyze PDF text content for structured financial data.
    /// Returns nil if the text does not contain extractable financial information.
    func extractFinancialData(
        pdfText: String,
        emailSubject: String,
        emailSender: String
    ) async throws -> PDFFinancialData? {
        let truncated = String(pdfText.prefix(8000))
        guard !truncated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let systemPrompt = """
        You are a financial document parser specialized in extracting transactions from PDF attachments \
        such as bank statements, credit card statements, invoices, and receipts. \
        Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Extract all financial transactions from this PDF document content.

        Email subject: \(emailSubject)
        Email sender: \(emailSender)

        PDF content:
        \(truncated)

        Return JSON:
        {
          "transactions": [
            {
              "amount": 123.45,
              "currency": "TWD",
              "merchant": "Store Name",
              "description": "Brief description",
              "date": "YYYY-MM-DD",
              "type": "debit|credit|transfer",
              "category_hint": "optional category hint"
            }
          ],
          "document_type": "statement|invoice|receipt|report",
          "issuer": "Bank or company name"
        }

        Rules:
        - Extract individual line-item transactions, NOT summary totals
        - For bank/credit card statements, extract each transaction row
        - Use exact amounts and dates as shown in the document
        - Skip balance entries, opening/closing balances, and subtotals
        - If no transactions found, return empty transactions array
        """

        let session = try SessionFactory.makeLegacySession(
            assignment: llmProcessor.providerConfig.extraction,
            config: llmProcessor.providerConfig
        )
        let response = try await session.complete(
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: PFMConfig.llmTemperature
        )

        return try parseJSON(response)
    }

    /// Multi-layer extraction for credit card statements.
    /// Layer 1: Classify document type (payment notice vs. transaction detail)
    /// Layer 2: Extract transactions using the model configured for the 'statement' use case.
    func extractStatementData(
        pdfText: String,
        filename: String,
        bankHint: String?
    ) async throws -> PDFFinancialData? {
        let truncated = String(pdfText.prefix(12000))
        guard !truncated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Layer 1: Classify — is this a payment notice or transaction detail?
        // NOTE: Do not pass bankHint as a strong signal — it may be wrong due to PDFKit false positives.
        // Let the LLM detect the issuer from actual document content.
        let classifyPrompt = """
        Analyze this credit card PDF document and classify it.
        Detect the bank/issuer name from the document content itself — do NOT rely on external hints.
        Return ONLY valid JSON, no markdown.

        Filename: \(filename)

        Document text (first 2000 chars):
        \(String(truncated.prefix(2000)))

        Return JSON:
        {
          "document_type": "transaction_detail" | "payment_notice" | "annual_summary" | "other",
          "issuer": "bank name (detected from document content)",
          "currency": "TWD or USD etc",
          "statement_period": "YYYY-MM if detectable",
          "confidence": 0.0-1.0
        }
        """

        let classifySession = try SessionFactory.makeLegacySession(
            assignment: llmProcessor.providerConfig.classification,
            config: llmProcessor.providerConfig
        )
        let classifyResponse = try await classifySession.complete(
            messages: [
                .system("You are a financial document classifier. Return ONLY valid JSON."),
                .user(classifyPrompt)
            ],
            temperature: 0.0
        )

        // Parse classification — prefer LLM-detected issuer over password hint
        var detectedCurrency = "TWD"
        var detectedIssuer: String? = nil
        if let data = cleanJSON(classifyResponse).data(using: .utf8),
           let info = try? JSONDecoder().decode(StatementClassification.self, from: data) {
            detectedCurrency = info.currency ?? "TWD"
            detectedIssuer = info.issuer
        }
        // Only fall back to bankHint if LLM couldn't detect the issuer
        if detectedIssuer == nil || detectedIssuer?.isEmpty == true {
            detectedIssuer = bankHint
        }

        // Layer 2: Full extraction with powerful model
        let systemPrompt = """
        You are an expert financial document parser for credit card statements from Taiwanese and international banks.
        You must extract EVERY individual transaction line item.
        Pay careful attention to:
        - Amount formats: "1,234" means 1234, "NT$1,234" means TWD 1234
        - Date formats vary by bank: MM/DD, YYYY/MM/DD, DD/MM, etc.
        - Distinguish between: transaction date (消費日) vs posting date (入帳日) — prefer transaction date
        - Payment entries (繳款/Payment) should be type "credit", purchases should be type "debit"
        - Foreign currency transactions may show both original currency and TWD equivalent — use TWD amount
        - Skip: statement totals, previous balance, new balance, minimum payment, credit limit
        Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Extract ALL individual transactions AND payment summary from this credit card statement.

        Bank: \(detectedIssuer ?? "Unknown")
        Currency: \(detectedCurrency)
        Filename: \(filename)

        Full document text:
        \(truncated)

        Return JSON:
        {
          "transactions": [
            {
              "amount": 1234.0,
              "currency": "\(detectedCurrency)",
              "merchant": "Merchant name",
              "description": "Transaction description",
              "date": "YYYY-MM-DD",
              "type": "debit|credit|transfer",
              "category_hint": "food|transport|shopping|entertainment|utilities|other"
            }
          ],
          "payment_summary": {
            "total_due": 12345.0,
            "minimum_due": 1234.0,
            "due_date": "YYYY-MM-DD",
            "currency": "\(detectedCurrency)",
            "statement_period": "YYYY-MM-DD to YYYY-MM-DD",
            "amount_type": "total_due"
          },
          "document_type": "statement",
          "issuer": "\(detectedIssuer ?? "Unknown")"
        }

        Important rules:
        - Extract EVERY transaction row — do not skip or summarize
        - Amounts must be positive numbers (e.g., 1234 not -1234)
        - For payments/credits, set type to "credit"; for purchases, set type to "debit"
        - Dates must be YYYY-MM-DD format
        - If a transaction has both foreign and local currency, use the local (\(detectedCurrency)) amount

        Payment summary rules:
        - total_due: 本期應繳總金額 / Total Amount Due / Statement Balance
        - minimum_due: 最低應繳金額 / Minimum Payment Due
        - due_date: 繳款截止日 / 繳款期限 / 最後繳款日 / Payment Due Date — MUST be YYYY-MM-DD
        - amount_type: classify the total_due as one of: "total_due", "minimum_due", "new_charges", "previous_balance", "other"
        - If payment info is not found, set payment_summary to null
        """

        let statementSession = try SessionFactory.makeLegacySession(
            assignment: llmProcessor.providerConfig.statement,
            config: llmProcessor.providerConfig
        )
        let response = try await statementSession.complete(
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: 0.05
        )

        return try parseJSON(response)
    }

    // Classification helper
    private struct StatementClassification: Codable {
        let documentType: String?
        let issuer: String?
        let currency: String?
        let statementPeriod: String?
        let confidence: Double?

        enum CodingKeys: String, CodingKey {
            case documentType = "document_type"
            case issuer
            case currency
            case statementPeriod = "statement_period"
            case confidence
        }
    }

    private func cleanJSON(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseJSON(_ raw: String) throws -> PDFFinancialData {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fix trailing commas
        cleaned = cleaned.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)

        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(PDFFinancialData.self, from: data)
            } catch {
                print("[PDFExtractor] Direct decode failed")
            }
        }

        // Extract JSON from first { to last }
        if let startRange = cleaned.range(of: "{"),
           let endRange = cleaned.range(of: "}", options: .backwards) {
            let jsonStr = String(cleaned[startRange.lowerBound...endRange.upperBound])
            if let data = jsonStr.data(using: .utf8) {
                do {
                    return try JSONDecoder().decode(PDFFinancialData.self, from: data)
                } catch {
                    print("[PDFExtractor] Extract-braces decode failed")
                }
            }
        }

        // Recovery for truncated JSON: find last complete transaction object, close brackets
        if let startIdx = cleaned.firstIndex(of: "{") {
            var truncated = String(cleaned[startIdx...])
            // Find the last complete "}" that could end a transaction object
            // Try progressively shorter substrings ending at each "}"
            let braceIndices = truncated.indices.filter { truncated[$0] == "}" }
            for braceIdx in braceIndices.reversed() {
                var attempt = String(truncated[...braceIdx])
                // Count unclosed brackets
                var openBraces = 0
                var openBrackets = 0
                for ch in attempt {
                    switch ch {
                    case "{": openBraces += 1
                    case "}": openBraces -= 1
                    case "[": openBrackets += 1
                    case "]": openBrackets -= 1
                    default: break
                    }
                }
                // Close any remaining open brackets
                attempt += String(repeating: "]", count: max(0, openBrackets))
                attempt += String(repeating: "}", count: max(0, openBraces))
                attempt = attempt.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
                attempt = attempt.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)

                if let data = attempt.data(using: .utf8),
                   let result = try? JSONDecoder().decode(PDFFinancialData.self, from: data) {
                    print("[PDFExtractor] Recovered truncated JSON")
                    return result
                }
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}
