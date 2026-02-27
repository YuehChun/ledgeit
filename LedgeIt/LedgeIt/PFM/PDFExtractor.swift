import Foundation

struct PDFExtractor: Sendable {
    let llmProcessor: LLMProcessor

    struct PDFFinancialData: Codable, Sendable {
        let transactions: [LLMProcessor.ExtractedTransaction]
        let documentType: String?
        let issuer: String?

        enum CodingKeys: String, CodingKey {
            case transactions
            case documentType = "document_type"
            case issuer
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

        let response = try await llmProcessor.openRouter.complete(
            model: PFMConfig.extractionModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: PFMConfig.llmTemperature,
            maxTokens: PFMConfig.llmMaxTokens
        )

        return try parseJSON(response)
    }

    private func parseJSON(_ raw: String) throws -> PDFFinancialData {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(PDFFinancialData.self, from: data)
            } catch {
                // Fall through to recovery
            }
        }

        if let startRange = cleaned.range(of: "{"),
           let endRange = cleaned.range(of: "}", options: .backwards) {
            var jsonStr = String(cleaned[startRange.lowerBound...endRange.upperBound])
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)
            if let data = jsonStr.data(using: .utf8) {
                return try JSONDecoder().decode(PDFFinancialData.self, from: data)
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}
