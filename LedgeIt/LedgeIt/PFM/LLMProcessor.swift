import Foundation

struct LLMProcessor: Sendable {

    // MARK: - Result Types

    struct ClassificationLLMResult: Codable, Sendable {
        let isFinancial: Bool
        let transactionIntent: Int
        let marketingProbability: Int
        let riskScore: Int
        let documentType: String
        let reasoning: String

        enum CodingKeys: String, CodingKey {
            case isFinancial = "is_financial"
            case transactionIntent = "transaction_intent"
            case marketingProbability = "marketing_probability"
            case riskScore = "risk_score"
            case documentType = "document_type"
            case reasoning
        }
    }

    struct ExtractionResult: Codable, Sendable {
        let transactions: [ExtractedTransaction]
        let bankInfo: BankInfo?
        let documentType: String?

        enum CodingKeys: String, CodingKey {
            case transactions
            case bankInfo = "bank_info"
            case documentType = "document_type"
        }
    }

    struct ExtractedTransaction: Codable, Sendable {
        let amount: Double?
        let currency: String?
        let merchant: String?
        let description: String?
        let date: String?
        let type: String?       // debit / credit / transfer
        let categoryHint: String?

        enum CodingKeys: String, CodingKey {
            case amount, currency, merchant, description, date, type
            case categoryHint = "category_hint"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            amount = Self.decodeFlexibleDouble(from: container, key: .amount)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
            merchant = try container.decodeIfPresent(String.self, forKey: .merchant)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            date = try container.decodeIfPresent(String.self, forKey: .date)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            categoryHint = try container.decodeIfPresent(String.self, forKey: .categoryHint)
        }

        private static func decodeFlexibleDouble(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
            if let val = try? container.decode(Double.self, forKey: key) { return val }
            if let str = try? container.decode(String.self, forKey: key) { return Double(str) }
            if let val = try? container.decode(Int.self, forKey: key) { return Double(val) }
            return nil
        }
    }

    struct BankInfo: Codable, Sendable {
        let name: String?
        let accountLast4: String?

        enum CodingKeys: String, CodingKey {
            case name
            case accountLast4 = "account_last4"
        }
    }

    struct BillExtractionResult: Codable, Sendable {
        let bankName: String?
        let dueDate: String?
        let amountDue: Double?
        let currency: String?
        let statementPeriod: String?

        enum CodingKeys: String, CodingKey {
            case bankName = "bank_name"
            case dueDate = "due_date"
            case amountDue = "amount_due"
            case currency
            case statementPeriod = "statement_period"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bankName = try container.decodeIfPresent(String.self, forKey: .bankName)
            dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
            statementPeriod = try container.decodeIfPresent(String.self, forKey: .statementPeriod)
            if let val = try? container.decode(Double.self, forKey: .amountDue) { amountDue = val }
            else if let str = try? container.decode(String.self, forKey: .amountDue) { amountDue = Double(str) }
            else if let val = try? container.decode(Int.self, forKey: .amountDue) { amountDue = Double(val) }
            else { amountDue = nil }
        }
    }

    // MARK: - Properties

    let openRouter: OpenRouterService

    // MARK: - Classification

    func classifyEmail(
        subject: String,
        body: String,
        sender: String
    ) async throws -> ClassificationLLMResult {
        let truncatedBody = String(body.prefix(3000))

        let systemPrompt = """
        You are an expert email classifier for financial transactions. \
        Classify the given email and return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Classify this email for financial transaction content.

        Subject: \(subject)
        From: \(sender)
        Body (truncated): \(truncatedBody)

        Return JSON with these fields:
        {
          "is_financial": true/false,
          "transaction_intent": 0-10,
          "marketing_probability": 0-10,
          "risk_score": 0-10,
          "document_type": "statement|receipt|order|payment|transaction|other",
          "reasoning": "brief explanation"
        }
        """

        let response = try await openRouter.complete(
            model: PFMConfig.classificationModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: PFMConfig.llmTemperature,
        )

        return try parseJSON(response, as: ClassificationLLMResult.self)
    }

    // MARK: - Extraction

    func extractTransactions(
        subject: String,
        body: String,
        sender: String,
        attachmentText: String? = nil
    ) async throws -> ExtractionResult {
        let truncatedBody = String(body.prefix(6000))

        let attachmentSection: String
        if let text = attachmentText, !text.isEmpty {
            attachmentSection = "\nAttachment content:\n\(String(text.prefix(3000)))"
        } else {
            attachmentSection = ""
        }

        let systemPrompt = """
        You are a financial transaction extraction expert. \
        Extract ALL transaction details from the email. \
        Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Extract all financial transactions from this email.

        Subject: \(subject)
        From: \(sender)
        Body: \(truncatedBody)\(attachmentSection)

        Return JSON:
        {
          "transactions": [
            {
              "amount": 123.45,
              "currency": "AED",
              "merchant": "Store Name",
              "description": "Brief description",
              "date": "YYYY-MM-DD",
              "type": "debit|credit|transfer",
              "category_hint": "optional category hint"
            }
          ],
          "bank_info": {
            "name": "Bank Name or null",
            "account_last4": "1234 or null"
          },
          "document_type": "statement|receipt|order|payment|transaction"
        }

        Rules:
        - Extract exact amounts and currencies (AED, USD, SAR, EUR, GBP, TWD, JPY)
        - Use email date if transaction date not specified
        - Only extract actual transaction amounts, NOT balances or credit limits
        - For transfers with exchange rates, extract the original currency amount
        - "type" must be debit, credit, or transfer

        DEDUPLICATION RULES (critical):
        - If the email contains BOTH individual line items AND a grand total, extract ONLY the line items, NOT the total (e.g., hotel bill with room + tax + service charge — extract those, skip the total)
        - Credit card statement totals (本期應繳總金額, total amount due) should NOT be extracted — they double-count individual card transactions that were already extracted from other emails
        - Bank auto-pay notifications (自動扣繳, automatic debit) and payment failure notices (扣款失敗) are NOT new transactions — return empty transactions array for these
        - If multiple flight segments appear in one e-ticket receipt with the same booking, extract ONE transaction for the total fare, not per-segment
        - Shipping/delivery notifications for an order are NOT new transactions — the purchase was already recorded from the order confirmation email
        """

        let response = try await openRouter.complete(
            model: PFMConfig.extractionModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: PFMConfig.llmTemperature
        )

        return try parseJSON(response, as: ExtractionResult.self)
    }

    // MARK: - Credit Card Bill Extraction

    func extractCreditCardBill(
        subject: String,
        body: String,
        sender: String
    ) async throws -> BillExtractionResult? {
        let systemPrompt = """
        You are a credit card statement parser. Extract the payment due date and amount from credit card statement emails. \
        Return ONLY valid JSON, no markdown or explanation.
        """

        let truncatedBody = String(body.prefix(4000))

        let userPrompt = """
        Extract the credit card bill information from this email:

        Subject: \(subject)
        Sender: \(sender)

        Body:
        \(truncatedBody)

        Return JSON in this exact format:
        {
          "bank_name": "The bank or credit card issuer name",
          "due_date": "YYYY-MM-DD format payment deadline",
          "amount_due": 12345.00,
          "currency": "TWD or USD or other ISO currency code",
          "statement_period": "YYYY-MM-DD to YYYY-MM-DD or null"
        }

        Rules:
        - due_date is the PAYMENT DEADLINE, not the statement date
        - amount_due is the TOTAL amount due (本期應繳總金額 / total amount due / statement balance)
        - For Taiwan banks: look for 繳款截止日, 繳款期限, 最後繳款日
        - For English statements: look for "payment due date", "due by", "pay by"
        - currency: use TWD for Taiwan dollar (NT$), USD for US dollar, etc.
        - If you cannot find a due date, return null for due_date
        """

        let response = try await openRouter.complete(
            model: PFMConfig.extractionModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: PFMConfig.llmTemperature
        )

        return try parseJSON(response, as: BillExtractionResult.self)
    }

    // MARK: - Spending Analysis

    struct SpendingAnalysis: Codable, Sendable {
        let summary: String
        let anomalies: [String]
        let budgetRecommendations: [String]
        let patterns: SpendingPatterns
        let topInsight: String

        enum CodingKeys: String, CodingKey {
            case summary, anomalies, patterns
            case budgetRecommendations = "budget_recommendations"
            case topInsight = "top_insight"
        }
    }

    struct SpendingPatterns: Codable, Sendable {
        let subscriptions: [String]
        let unusualSpending: [String]
        let savingOpportunities: [String]

        enum CodingKeys: String, CodingKey {
            case subscriptions
            case unusualSpending = "unusual_spending"
            case savingOpportunities = "saving_opportunities"
        }
    }

    func analyzeSpending(
        summary: String,
        trends: String,
        recentTransactions: String
    ) async throws -> SpendingAnalysis {
        let systemPrompt = """
        You are a personal finance advisor. Analyze the user's spending data and \
        return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Analyze this spending data and provide actionable insights.

        Category Breakdown & Top Merchants:
        \(summary)

        Monthly Trends:
        \(trends)

        Recent Transactions:
        \(recentTransactions)

        Return JSON:
        {
          "summary": "2-3 sentence natural language spending summary",
          "anomalies": ["any unusual charges or spikes"],
          "budget_recommendations": ["specific, actionable budget tips"],
          "patterns": {
            "subscriptions": ["detected recurring subscriptions"],
            "unusual_spending": ["spending that deviates from patterns"],
            "saving_opportunities": ["ways to reduce spending"]
          },
          "top_insight": "single most important financial insight"
        }
        """

        let response = try await openRouter.complete(
            model: PFMConfig.classificationModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: 0.3
        )

        return try parseJSON(response, as: SpendingAnalysis.self)
    }

    // MARK: - Vision / OCR

    func extractFromImage(imageData: Data) async throws -> String {
        let base64 = imageData.base64EncodedString()

        let message = OpenRouterService.Message.userWithImage(
            text: """
            Extract all financial transaction information from this image. \
            Include amounts, currencies, merchant names, dates, and transaction types. \
            Return the extracted text in a structured format.
            """,
            imageBase64: base64
        )

        return try await openRouter.complete(
            model: PFMConfig.visionModel,
            messages: [message],
            temperature: PFMConfig.llmTemperature
        )
    }

    // MARK: - JSON Parsing (robust)

    private func parseJSON<T: Decodable>(_ raw: String, as type: T.Type) throws -> T {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks
        if cleaned.contains("```json") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        }
        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try direct parse
        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                // Fall through to recovery
            }
        }

        // Extract JSON object from text
        if let startRange = cleaned.range(of: "{"),
           let endRange = cleaned.range(of: "}", options: .backwards) {
            let jsonSubstring = String(cleaned[startRange.lowerBound...endRange.upperBound])

            // Fix trailing commas
            var fixed = jsonSubstring
            fixed = fixed.replacingOccurrences(
                of: #",\s*\}"#,
                with: "}",
                options: .regularExpression
            )
            fixed = fixed.replacingOccurrences(
                of: #",\s*\]"#,
                with: "]",
                options: .regularExpression
            )

            if let data = fixed.data(using: .utf8) {
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    print("[LLMProcessor] JSON decode failed: \(error)")
                }
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}

enum LLMProcessorError: LocalizedError {
    case jsonParsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .jsonParsingFailed(let preview):
            return "Failed to parse LLM JSON response: \(preview)"
        }
    }
}
