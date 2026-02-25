import Foundation

struct IntentClassifier: Sendable {

    // MARK: - Types

    enum Decision: String, Sendable {
        case accept = "ACCEPT"
        case reject = "REJECT"
        case uncertain = "UNCERTAIN"
    }

    enum Method: String, Sendable {
        case ruleBased = "rule_based"
        case aiFallback = "ai_fallback"
    }

    struct ClassificationResult: Sendable {
        let decision: Decision
        let transactionIntent: Int
        let marketingProbability: Int
        let senderReputation: Int
        let riskScore: Int
        let reasoning: String
        let confidence: Double
        let method: Method
    }

    // MARK: - Public API

    func classify(
        subject: String,
        body: String,
        sender: String,
        senderEmail: String
    ) -> ClassificationResult {
        let (ruleDecision, reason) = ruleBasedFilter(
            subject: subject,
            body: body,
            sender: sender,
            senderEmail: senderEmail
        )

        switch ruleDecision {
        case .certainAccept:
            return ClassificationResult(
                decision: .accept,
                transactionIntent: 10,
                marketingProbability: 0,
                senderReputation: 10,
                riskScore: 0,
                reasoning: reason,
                confidence: 0.95,
                method: .ruleBased
            )
        case .certainReject:
            return ClassificationResult(
                decision: .reject,
                transactionIntent: 0,
                marketingProbability: 10,
                senderReputation: 5,
                riskScore: 3,
                reasoning: reason,
                confidence: 0.95,
                method: .ruleBased
            )
        case .uncertain:
            return ClassificationResult(
                decision: .uncertain,
                transactionIntent: 5,
                marketingProbability: 5,
                senderReputation: 5,
                riskScore: 5,
                reasoning: reason,
                confidence: 0.5,
                method: .ruleBased
            )
        }
    }

    // MARK: - Rule-Based Filter

    private enum RuleDecision {
        case certainAccept
        case certainReject
        case uncertain
    }

    private func ruleBasedFilter(
        subject: String,
        body: String,
        sender: String,
        senderEmail: String
    ) -> (RuleDecision, String) {

        let senderDomain = senderEmail.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
        let senderEmailLower = senderEmail.lowercased()
        let subjectLower = subject.lowercased()
        let bodyPrefix = String(body.prefix(2000)).lowercased()
        let combinedText = subjectLower + " " + bodyPrefix

        // ============================================================
        // CERTAIN_ACCEPT Rules
        // ============================================================

        // Rule 1: Trusted financial institution + transaction keywords
        let isTrustedBank = PFMConfig.trustedFinancialInstitutions.contains { domain in
            senderEmailLower.contains(domain)
        }

        if isTrustedBank {
            let transactionKeywords = [
                "transaction", "payment", "charged", "debited", "paid",
                "receipt", "invoice", "statement", "balance"
            ]
            if transactionKeywords.contains(where: { combinedText.contains($0) }) {
                return (.certainAccept, "Trusted bank (\(senderDomain)) + transaction keywords")
            }
        }

        // Rule 2: Payment confirmation with transaction ID
        let paymentConfirmationKeywords = [
            "payment received", "payment successful", "payment confirmed",
            "order confirmed", "order placed", "purchase confirmed",
            "transaction complete", "successfully charged"
        ]
        let hasPaymentConfirmation = paymentConfirmationKeywords.contains { combinedText.contains($0) }

        let transactionIdPattern = try? NSRegularExpression(
            pattern: #"(order|transaction|receipt|invoice|reference)\s*(#|number|id|no\.?)[\s:]*[\w\d-]+"#,
            options: .caseInsensitive
        )
        let hasTransactionId = transactionIdPattern?.firstMatch(
            in: combinedText,
            range: NSRange(combinedText.startIndex..., in: combinedText)
        ) != nil

        if hasPaymentConfirmation && hasTransactionId {
            return (.certainAccept, "Payment confirmation + transaction ID")
        }

        // Rule 3: Bank statement or account summary (excluding notifications)
        let statementNotificationKeywords = [
            "statement available", "statement is available",
            "statement ready", "new statement", "latest statement"
        ]
        let isStatementNotification = statementNotificationKeywords.contains { combinedText.contains($0) }

        if !isStatementNotification {
            let statementKeywords = [
                "account statement", "bank statement", "monthly statement",
                "account summary", "transaction history", "account activity"
            ]
            if statementKeywords.contains(where: { combinedText.contains($0) }) {
                return (.certainAccept, "Bank statement/account summary")
            }
        }

        // Rule 4: Specific amount with payment verb (excluding third-party news)
        let amountWithPaymentPattern = try? NSRegularExpression(
            pattern: #"(paid|charged|debited|transferred)\s+(?:aed|sar|usd|zar|eur|gbp)?\s*[\d,]+\.?\d*"#,
            options: .caseInsensitive
        )
        let hasAmountWithPayment = amountWithPaymentPattern?.firstMatch(
            in: combinedText,
            range: NSRange(combinedText.startIndex..., in: combinedText)
        ) != nil

        if hasAmountWithPayment {
            let thirdPartyIndicators = [
                "court ordered", "must pay", "ordered to pay", "legal costs",
                "government", "executives", "fraud case", "lawsuit"
            ]
            if !thirdPartyIndicators.contains(where: { combinedText.contains($0) }) {
                return (.certainAccept, "Specific amount with payment verb")
            }
        }

        // ============================================================
        // CERTAIN_REJECT Rules
        // ============================================================

        // Rule 5: News sender domains
        let newsDomains = [
            "newsletter", "dailynews", "newsoftheday", "mybroadband",
            "breaking", "headlines", "digest"
        ]
        if newsDomains.contains(where: { senderEmailLower.contains($0) }) {
            return (.certainReject, "News/newsletter sender (\(senderDomain))")
        }

        // Rule 6: Strong exclude keywords (skip for trusted utilities)
        let trustedUtilityDomains = [
            "dewa.gov.ae", "dewa.ae",
            "addc.ae",
            "etisalat.ae", "du.ae",
            "virginmobile.ae",
            "abudhabigas.ae"
        ]
        let isTrustedUtility = trustedUtilityDomains.contains { senderEmailLower.contains($0) }

        let utilityBillKeywords = ["dewa", "addc", "etisalat", "du bill", "virgin mobile bill", "gas bill"]
        let hasUtilitySubject = utilityBillKeywords.contains { subjectLower.contains($0) }

        if !isTrustedUtility && !hasUtilitySubject {
            for keyword in PFMConfig.strongExcludeKeywords {
                if combinedText.contains(keyword) {
                    return (.certainReject, "Strong marketing keyword: \(keyword)")
                }
            }
        }

        // Rule 7: Third-party transaction patterns (news articles)
        let thirdPartyPatterns = [
            #"court ordered .+ to pay"#,
            #".+ must pay .+ million"#,
            #"legal costs .+ ordered"#,
            #"government .+ announces .+ spending"#,
            #"fraud .+ (executives|officials)"#
        ]
        for pattern in thirdPartyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: combinedText, range: NSRange(combinedText.startIndex..., in: combinedText)) != nil {
                return (.certainReject, "Third-party transaction (news article)")
            }
        }

        // Rule 8: Community notices
        let communityIndicators = [
            "community announcement", "construction notice", "building project",
            "paid up capital", "special notice", "construction project notice"
        ]
        if communityIndicators.contains(where: { combinedText.contains($0) }) {
            let communityDomains = ["anacity.com", "gov.", "municipality"]
            if communityDomains.contains(where: { senderEmailLower.contains($0) }) {
                return (.certainReject, "Community announcement (not personal transaction)")
            }
        }

        // Rule 9: 3+ promotional keywords without payment confirmation
        let promotionalKeywords = [
            "flash sale", "limited time offer", "shop now", "buy now",
            "discount code", "promo code", "exclusive deal", "save now"
        ]
        let promotionalCount = promotionalKeywords.filter { combinedText.contains($0) }.count
        if promotionalCount >= 3 && !hasPaymentConfirmation {
            return (.certainReject, "High promotional content (\(promotionalCount) keywords)")
        }

        // Rule 10: Very long emails (typical promotional/newsletter)
        if body.count > 10000 {
            let legitimateLongKeywords = [
                "statement", "summary", "report",
                "booking confirmed", "booking confirmation",
                "flight confirmation", "itinerary",
                "reservation confirmed", "reservation details",
                "travel details", "booking details",
                "electronic ticket", "payment receipt", "ticket receipt",
                "event ticket", "admission ticket", "entry ticket",
                "ticket confirmation", "ticket order", "your ticket"
            ]

            let airlineDomains = [
                "emirates.com", "etihad.com", "flydubai.com", "qatarairways.com",
                "booking.com", "airbnb.com"
            ]
            let isAirlineOrTravel = airlineDomains.contains { senderEmailLower.contains($0) }
            let hasLegitimateKeywords = legitimateLongKeywords.contains { combinedText.contains($0) }

            if !(isAirlineOrTravel || hasLegitimateKeywords) {
                return (.certainReject, "Very long email (likely promotional)")
            }
        }

        // ============================================================
        // UNCERTAIN
        // ============================================================
        return (.uncertain, "Ambiguous content (requires AI analysis)")
    }
}
