import Foundation

struct TransferDetector: Sendable {

    // MARK: - Types

    struct TransferPattern: Sendable {
        let type: String
        let subtype: String
        let patterns: [String]   // regex strings
        let keywords: [String]
        let confidenceWeight: Double
        let paymentSystem: String?
    }

    struct TransferResult: Sendable {
        let isTransfer: Bool
        let transferType: String?
        let transferSubtype: String?
        let direction: String        // inflow / outflow / neutral / unknown
        let scope: String            // domestic / international
        let isOwn: Bool
        let paymentSystem: String?
        let confidence: Double
        let metadata: [String: String]
    }

    // MARK: - All Transfer Patterns

    static let patterns: [TransferPattern] = [
        // 1. Wire Transfers
        TransferPattern(
            type: "wire_transfer", subtype: "international",
            patterns: [
                #"WIRE\s+TRANSFER"#,
                #"INTERNATIONAL\s+TRANSFER"#,
                #"SWIFT\s*:?\s*([A-Z]{8,11})"#,
                #"FED\s*WIRE"#,
                #"WIRE\s+REF\s*:?\s*(\w+)"#,
                #"AMOUNT\s+CREDITED.*INTERNATIONAL"#,
                #"TRANSFER.*CREDITED"#
            ],
            keywords: ["wire transfer", "swift", "fedwire", "wire to", "wire from", "correspondent bank", "international transfer"],
            confidenceWeight: 0.95,
            paymentSystem: "SWIFT"
        ),
        // 2. ACH Transfers
        TransferPattern(
            type: "ach_transfer", subtype: "standard",
            patterns: [
                #"ACH\s+(DEBIT|CREDIT)"#,
                #"ACH\s+TRANSFER"#,
                #"AUTOMATED\s+CLEARING\s+HOUSE"#,
                #"ACH\s+TRACE\s*:?\s*(\d+)"#
            ],
            keywords: ["ach", "automated clearing", "direct deposit", "ach credit", "ach debit"],
            confidenceWeight: 0.90,
            paymentSystem: "ACH"
        ),
        // 3. Remittances
        TransferPattern(
            type: "remittance", subtype: "bank_remittance",
            patterns: [
                #"INWARD\s+REMITTANCE"#,
                #"OUTWARD\s+REMITTANCE"#,
                #"REMITTANCE\s+RECEIVED"#,
                #"REMITTANCE\s+SENT"#,
                #"CREDITED.*REMITTANCE"#,
                #"DEBITED.*REMITTANCE"#
            ],
            keywords: ["inward remittance", "outward remittance", "remittance", "international remittance"],
            confidenceWeight: 0.95,
            paymentSystem: "BANK_REMITTANCE"
        ),
        TransferPattern(
            type: "remittance", subtype: "western_union",
            patterns: [
                #"WESTERN\s+UNION"#,
                #"MTCN\s*:?\s*(\d{10})"#,
                #"WU\s+TRANSFER"#
            ],
            keywords: ["western union", "mtcn", "money transfer control", "wu"],
            confidenceWeight: 0.92,
            paymentSystem: "WESTERN_UNION"
        ),
        TransferPattern(
            type: "remittance", subtype: "moneygram",
            patterns: [
                #"MONEYGRAM"#,
                #"MGI\s+TRANSFER"#,
                #"REFERENCE\s*:?\s*(\d{8})"#
            ],
            keywords: ["moneygram", "mgi", "money transfer"],
            confidenceWeight: 0.92,
            paymentSystem: "MONEYGRAM"
        ),
        TransferPattern(
            type: "remittance", subtype: "wise",
            patterns: [
                #"WISE\s+TRANSFER"#,
                #"TRANSFERWISE"#,
                #"WISE\s+REF\s*:?\s*(\w+)"#
            ],
            keywords: ["wise", "transferwise", "multi-currency"],
            confidenceWeight: 0.90,
            paymentSystem: "WISE"
        ),
        TransferPattern(
            type: "remittance", subtype: "remitly",
            patterns: [
                #"REMITLY"#,
                #"REMIT\s+TRANSFER"#
            ],
            keywords: ["remitly", "remittance", "family support"],
            confidenceWeight: 0.88,
            paymentSystem: "REMITLY"
        ),
        // 4. Refunds
        TransferPattern(
            type: "refund", subtype: "merchant",
            patterns: [
                #"REFUND.*ORDER\s*#?\s*(\w+)"#,
                #"REFUND\s+CONFIRMATION"#,
                #"REFUND.*PROCESSED"#,
                #"YOUR\s+REFUND"#,
                #"RETURN\s+CREDIT"#,
                #"MERCHANT\s+REFUND"#,
                #"CANCELLED\s+ORDER"#,
                #"REFUND\s+AMOUNT"#
            ],
            keywords: ["refund", "return", "credit", "reversal", "cancelled order", "item returned", "refund confirmation"],
            confidenceWeight: 0.88,
            paymentSystem: "MERCHANT"
        ),
        TransferPattern(
            type: "refund", subtype: "bank_fee",
            patterns: [
                #"FEE\s+REVERSAL"#,
                #"CHARGE\s+REVERSAL"#,
                #"BANK\s+FEE\s+REFUND"#
            ],
            keywords: ["fee reversal", "charge reversal", "bank refund", "fee waived"],
            confidenceWeight: 0.90,
            paymentSystem: "BANK"
        ),
        TransferPattern(
            type: "refund", subtype: "tax",
            patterns: [
                #"TAX\s+REFUND"#,
                #"IRS\s+REFUND"#,
                #"STATE\s+TAX\s+REFUND"#
            ],
            keywords: ["tax refund", "irs refund", "state refund", "tax return"],
            confidenceWeight: 0.95,
            paymentSystem: "GOVERNMENT"
        ),
        TransferPattern(
            type: "refund", subtype: "insurance",
            patterns: [
                #"INSURANCE\s+REFUND"#,
                #"CLAIM\s+REFUND"#,
                #"PREMIUM\s+REFUND"#
            ],
            keywords: ["insurance refund", "claim refund", "premium refund", "policy refund"],
            confidenceWeight: 0.88,
            paymentSystem: "INSURANCE"
        ),
        TransferPattern(
            type: "refund", subtype: "utility",
            patterns: [
                #"UTILITY\s+REFUND"#,
                #"OVERPAYMENT\s+REFUND"#,
                #"DEPOSIT\s+REFUND"#
            ],
            keywords: ["utility refund", "overpayment", "deposit return", "credit balance"],
            confidenceWeight: 0.85,
            paymentSystem: "UTILITY"
        ),
        // 5. P2P Payments
        TransferPattern(
            type: "p2p_payment", subtype: "venmo",
            patterns: [
                #"VENMO\s+(FROM|TO)"#,
                #"VENMO\s*:?\s*@([\w]+)"#
            ],
            keywords: ["venmo", "venmo payment", "sent via venmo"],
            confidenceWeight: 0.85,
            paymentSystem: "VENMO"
        ),
        TransferPattern(
            type: "p2p_payment", subtype: "zelle",
            patterns: [
                #"ZELLE\s+(PAYMENT|TRANSFER)"#,
                #"SENT\s+WITH\s+ZELLE"#
            ],
            keywords: ["zelle", "zelle payment", "zelle transfer"],
            confidenceWeight: 0.85,
            paymentSystem: "ZELLE"
        ),
        TransferPattern(
            type: "p2p_payment", subtype: "cashapp",
            patterns: [
                #"CASH\s+APP"#,
                #"CASHAPP\s+(PAYMENT|TRANSFER)"#,
                #"\$CASHTAG"#
            ],
            keywords: ["cash app", "cashapp", "square cash", "cashtag"],
            confidenceWeight: 0.85,
            paymentSystem: "CASHAPP"
        ),
        TransferPattern(
            type: "p2p_payment", subtype: "paypal",
            patterns: [
                #"PAYPAL\s+(TRANSFER|PAYMENT)"#,
                #"PP\s+TRANSFER"#,
                #"PAYPAL\s+ID\s*:?\s*([\w@\.]+)"#
            ],
            keywords: ["paypal", "pp transfer", "paypal payment"],
            confidenceWeight: 0.85,
            paymentSystem: "PAYPAL"
        ),
        // 6. NEFT
        TransferPattern(
            type: "neft", subtype: "standard",
            patterns: [
                #"NEFT\s*/?\s*(\w+)"#,
                #"UTR\s*:?\s*(\w+)"#,
                #"NATIONAL\s+ELECTRONIC\s+FUNDS"#
            ],
            keywords: ["neft", "national electronic", "utr", "neft transfer"],
            confidenceWeight: 0.90,
            paymentSystem: "NEFT"
        ),
        // 7. RTGS
        TransferPattern(
            type: "rtgs", subtype: "high_value",
            patterns: [
                #"RTGS\s*/?\s*(\w+)"#,
                #"REAL\s+TIME\s+GROSS"#,
                #"RTGS\s+UTR\s*:?\s*(\w+)"#
            ],
            keywords: ["rtgs", "real time gross settlement", "high value transfer"],
            confidenceWeight: 0.92,
            paymentSystem: "RTGS"
        ),
        // 8. IMPS
        TransferPattern(
            type: "imps", subtype: "instant",
            patterns: [
                #"IMPS\s*/?\s*(\w+)"#,
                #"IMMEDIATE\s+PAYMENT"#,
                #"IMPS\s+REF\s*:?\s*(\w+)"#
            ],
            keywords: ["imps", "immediate payment", "instant transfer"],
            confidenceWeight: 0.88,
            paymentSystem: "IMPS"
        ),
        // 9. UPI
        TransferPattern(
            type: "upi", subtype: "instant",
            patterns: [
                #"UPI\s*/?\s*(\w+)"#,
                #"UPI\s+ID\s*:?\s*([\w@\.]+)"#,
                #"UPI\s+TXN\s*:?\s*(\d+)"#
            ],
            keywords: ["upi", "unified payment", "phonepe", "gpay", "paytm", "bhim"],
            confidenceWeight: 0.85,
            paymentSystem: "UPI"
        ),
        // 10. SEPA
        TransferPattern(
            type: "sepa", subtype: "credit_transfer",
            patterns: [
                #"SEPA\s+TRANSFER"#,
                #"SEPA\s+CREDIT"#,
                #"SINGLE\s+EURO\s+PAYMENT"#,
                #"IBAN\s*:?\s*(AT|BE|BG|HR|CY|CZ|DK|EE|FI|FR|DE|GR|HU|IE|IT|LV|LT|LU|MT|NL|PL|PT|RO|SK|SI|ES|SE)\d{2}[A-Z0-9]+"#
            ],
            keywords: ["sepa", "single euro payment", "euro transfer"],
            confidenceWeight: 0.90,
            paymentSystem: "SEPA"
        ),
        // 11. Internal Transfers
        TransferPattern(
            type: "internal_transfer", subtype: "between_accounts",
            patterns: [
                #"TRANSFER\s+BETWEEN\s+ACCOUNTS"#,
                #"INTERNAL\s+TRANSFER"#,
                #"OWN\s+ACCOUNT\s+TRANSFER"#,
                #"INTER\s*-?\s*ACCOUNT"#
            ],
            keywords: ["between accounts", "internal transfer", "own account", "account to account", "inter account"],
            confidenceWeight: 0.95,
            paymentSystem: "INTERNAL"
        ),
        // 11b. General Bank Transfers
        TransferPattern(
            type: "bank_transfer", subtype: "domestic",
            patterns: [
                #"BANK\s+TRANSFER"#,
                #"LOCAL\s+TRANSFER"#,
                #"AMOUNT.*DEBITED"#,
                #"DEBITED\s+FROM"#,
                #"TRANSFER\s+TO"#,
                #"DOMESTIC\s+TRANSFER"#,
                #"\d+\.?\d*\s+DR"#,
                #"TRANSACTION\s+ALERT"#,
                #"DEBIT\s+ALERT"#
            ],
            keywords: ["bank transfer", "local transfer", "debited", "transfer to", "domestic transfer", "transaction alert"],
            confidenceWeight: 0.85,
            paymentSystem: "LOCAL"
        ),
        // 12. Bill Payment
        TransferPattern(
            type: "bill_payment", subtype: "utility",
            patterns: [
                #"BILL\s+PAY"#,
                #"UTILITY\s+PAYMENT"#,
                #"ONLINE\s+BILL\s+PAYMENT"#
            ],
            keywords: ["bill pay", "bill payment", "utility payment", "online payment"],
            confidenceWeight: 0.82,
            paymentSystem: "BILLPAY"
        ),
        // 13. Crypto Transfers
        TransferPattern(
            type: "crypto_transfer", subtype: "on_chain",
            patterns: [
                #"CRYPTO\s+TRANSFER"#,
                #"(BTC|ETH|USDT|USDC)\s+TRANSFER"#,
                #"0x[a-fA-F0-9]{40}"#,
                #"BLOCKCHAIN\s+TRANSFER"#
            ],
            keywords: ["crypto", "bitcoin", "ethereum", "blockchain", "wallet", "coinbase", "binance"],
            confidenceWeight: 0.80,
            paymentSystem: "CRYPTO"
        ),
        // 14. Direct Debit
        TransferPattern(
            type: "direct_debit", subtype: "recurring",
            patterns: [
                #"DIRECT\s+DEBIT"#,
                #"DD\s+MANDATE"#,
                #"RECURRING\s+PAYMENT"#,
                #"AUTO\s+DEBIT"#
            ],
            keywords: ["direct debit", "recurring", "mandate", "auto debit", "subscription"],
            confidenceWeight: 0.85,
            paymentSystem: "DIRECT_DEBIT"
        ),
        // 15. Salary
        TransferPattern(
            type: "salary", subtype: "salary",
            patterns: [
                #"SALARY\s+DEPOSIT"#,
                #"SALARY.*CREDITED"#,
                #"PAYROLL"#,
                #"DIRECT\s+DEPOSIT.*EMPLOYER"#,
                #"WAGES\s+DEPOSIT"#,
                #"YOUR\s+SALARY"#,
                #"SALARY\s+HAS\s+BEEN"#,
                #"AMOUNT.*CR.*SALARY"#
            ],
            keywords: ["salary", "payroll", "wages", "employer deposit", "monthly salary", "salary credited"],
            confidenceWeight: 0.93,
            paymentSystem: "PAYROLL"
        ),
        // 16. Government Transfers
        TransferPattern(
            type: "government_transfer", subtype: "benefit",
            patterns: [
                #"SSA\s+TREAS"#,
                #"IRS\s+TREAS"#,
                #"GOVT\s+PAYMENT"#,
                #"STIMULUS\s+PAYMENT"#
            ],
            keywords: ["ssa", "irs", "treasury", "unemployment", "stimulus", "government payment"],
            confidenceWeight: 0.95,
            paymentSystem: "GOVERNMENT"
        ),
        // 17. Loan Transfers
        TransferPattern(
            type: "loan_transfer", subtype: "disbursement",
            patterns: [
                #"LOAN\s+DISBURSEMENT"#,
                #"LOAN\s+CREDIT"#,
                #"MORTGAGE\s+DISBURSEMENT"#
            ],
            keywords: ["loan disbursement", "loan credit", "mortgage advance"],
            confidenceWeight: 0.88,
            paymentSystem: "LOAN"
        ),
        TransferPattern(
            type: "loan_transfer", subtype: "repayment",
            patterns: [
                #"LOAN\s+REPAYMENT"#,
                #"LOAN\s+PAYMENT"#,
                #"MORTGAGE\s+PAYMENT"#,
                #"EMI\s+PAYMENT"#
            ],
            keywords: ["loan repayment", "loan payment", "mortgage payment", "emi"],
            confidenceWeight: 0.88,
            paymentSystem: "LOAN"
        ),
    ]

    // MARK: - Detect Transfer

    static func detectTransfer(in text: String, amount: Double?) -> TransferResult {
        guard !text.isEmpty else {
            return TransferResult(
                isTransfer: false, transferType: nil, transferSubtype: nil,
                direction: "unknown", scope: "domestic", isOwn: false,
                paymentSystem: nil, confidence: 0, metadata: [:]
            )
        }

        let textUpper = text.uppercased()
        let textLower = text.lowercased()

        // --- Pattern matching ---
        struct Match {
            let type: String
            let subtype: String
            let paymentSystem: String?
            var confidence: Double
        }

        var matches: [Match] = []

        for pattern in patterns {
            var score = 0.0

            // Check regex patterns
            for regexStr in pattern.patterns {
                if let regex = try? NSRegularExpression(pattern: regexStr, options: []),
                   regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)) != nil {
                    score += pattern.confidenceWeight * 0.7
                    break
                }
            }

            // Check keywords
            var keywordMatches = 0
            for keyword in pattern.keywords {
                if textLower.contains(keyword.lowercased()) {
                    keywordMatches += 1
                }
            }
            if keywordMatches > 0 {
                let keywordScore = min(Double(keywordMatches) * 0.1, 0.3)
                score += keywordScore
            }

            if score > 0 {
                matches.append(Match(
                    type: pattern.type,
                    subtype: pattern.subtype,
                    paymentSystem: pattern.paymentSystem,
                    confidence: min(score, 1.0)
                ))
            }
        }

        // Best match with threshold 0.3
        guard let best = matches.max(by: { $0.confidence < $1.confidence }),
              best.confidence >= 0.3 else {
            return TransferResult(
                isTransfer: false, transferType: nil, transferSubtype: nil,
                direction: "unknown", scope: "domestic", isOwn: false,
                paymentSystem: nil, confidence: 0, metadata: [:]
            )
        }

        // --- Extract metadata ---
        var metadata: [String: String] = [:]

        // IBAN
        let ibanPatterns = [
            #"IBAN\s*:?\s*([A-Z]{2}\d{2}[A-Z0-9]{12,30})"#,
            #"ACCOUNT\s*:?\s*([A-Z]{2}\d{2}[A-Z0-9]{12,30})"#
        ]
        for p in ibanPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []),
               let m = regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)),
               let range = Range(m.range(at: 1), in: textUpper) {
                metadata["iban"] = String(textUpper[range])
                break
            }
        }

        // SWIFT/BIC
        let swiftPatterns = [
            #"SWIFT\s*:?\s*([A-Z]{8,11})"#,
            #"BIC\s*:?\s*([A-Z]{8,11})"#,
            #"SWIFT\s+CODE\s*:?\s*([A-Z]{8,11})"#
        ]
        for p in swiftPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []),
               let m = regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)),
               let range = Range(m.range(at: 1), in: textUpper) {
                metadata["swift"] = String(textUpper[range])
                break
            }
        }

        // Reference numbers
        let genericRefPatterns = [
            #"REFERENCE\s+NUMBER\s*([A-Z0-9\-]+)"#,
            #"REFERENCE\s*:?\s*([A-Z0-9\-]+)"#,
            #"REF\s*:?\s*([A-Z0-9\-]+)"#,
            #"TRANSACTION\s+ID\s*:?\s*([A-Z0-9\-]+)"#,
            #"TXN\s+ID\s*:?\s*([A-Z0-9\-]+)"#
        ]
        for p in genericRefPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []),
               let m = regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)),
               let range = Range(m.range(at: 1), in: textUpper) {
                let ref = String(textUpper[range])
                if ref.count > 3 {
                    metadata["reference_number"] = ref
                    break
                }
            }
        }

        // Beneficiary
        let beneficiaryPatterns = [
            #"TO\s+ACCOUNT\s+([A-Z][A-Z\s\.]+?)(?:\s*\*+|\s*\d+|\n|$)"#,
            #"(?:TO|BENEFICIARY|RECIPIENT|PAYEE)\s*:?\s*([A-Z][A-Z\s\.]+?)(?:\n|$|ACCOUNT|BANK|\*)"#,
            #"TRANSFER\s+TO\s*:?\s*([A-Z][A-Z\s\.]+?)(?:\n|$)"#,
            #"SENT\s+TO\s*:?\s*([A-Z][A-Z\s\.]+?)(?:\n|$)"#
        ]
        for p in beneficiaryPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []),
               let m = regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)),
               let range = Range(m.range(at: 1), in: textUpper) {
                let name = String(textUpper[range]).trimmingCharacters(in: .whitespaces)
                if name.count > 3 {
                    metadata["beneficiary_name"] = name
                    break
                }
            }
        }

        // Sender name
        let senderPatterns = [
            #"(?:FROM|SENDER|REMITTER|PAYER)\s*:?\s*([A-Z][A-Z\s\.]+?)(?:\n|$|ACCOUNT|BANK)"#,
            #"TRANSFER\s+FROM\s*:?\s*([A-Z][A-Z\s\.]+?)(?:\n|$)"#,
            #"RECEIVED\s+FROM\s*:?\s*([A-Z][A-Z\s\.]+?)(?:\n|$)"#
        ]
        for p in senderPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []),
               let m = regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)),
               let range = Range(m.range(at: 1), in: textUpper) {
                let name = String(textUpper[range]).trimmingCharacters(in: .whitespaces)
                if name.count > 3 {
                    metadata["sender_name"] = name
                    break
                }
            }
        }

        // Exchange rate
        let fxPatterns = [
            #"EXCHANGE\s+RATE\s*:?\s*([\d\.]+)"#,
            #"FX\s+RATE\s*:?\s*([\d\.]+)"#,
            #"RATE\s*:?\s*([\d\.]+)"#
        ]
        for p in fxPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []),
               let m = regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)),
               let range = Range(m.range(at: 1), in: textUpper) {
                metadata["exchange_rate"] = String(textUpper[range])
                break
            }
        }

        // Transfer fee
        let feePatterns = [
            #"FEE\s*:?\s*\$?([\d,\.]+)"#,
            #"CHARGE\s*:?\s*\$?([\d,\.]+)"#,
            #"TRANSFER\s+FEE\s*:?\s*\$?([\d,\.]+)"#,
            #"SERVICE\s+CHARGE\s*:?\s*\$?([\d,\.]+)"#
        ]
        for p in feePatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []),
               let m = regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)),
               let range = Range(m.range(at: 1), in: textUpper) {
                metadata["transfer_fee"] = String(textUpper[range])
                break
            }
        }

        // --- Direction ---
        let direction = determineDirection(text: text, textLower: textLower, textUpper: textUpper, amount: amount, metadata: metadata)

        // --- Is own account ---
        let isOwn = determineIsOwn(textLower: textLower, metadata: metadata, text: text)

        // Adjust direction for own account
        let finalDirection = isOwn ? "neutral" : direction

        // --- Scope ---
        let scope = determineScope(textUpper: textUpper, metadata: metadata)

        return TransferResult(
            isTransfer: true,
            transferType: best.type,
            transferSubtype: best.subtype,
            direction: finalDirection,
            scope: scope,
            isOwn: isOwn,
            paymentSystem: best.paymentSystem,
            confidence: best.confidence,
            metadata: metadata
        )
    }

    // MARK: - Direction

    private static func determineDirection(
        text: String,
        textLower: String,
        textUpper: String,
        amount: Double?,
        metadata: [String: String]
    ) -> String {

        // Neutral
        let neutralKeywords = [
            "between accounts", "internal transfer", "own account",
            "account to account", "inter account", "transfer between",
            "move money between", "from savings to current",
            "from current to savings", "between your"
        ]
        if neutralKeywords.contains(where: { textLower.contains($0) }) {
            return "neutral"
        }

        // CR / DR indicators
        if let regex = try? NSRegularExpression(pattern: #"\b\d+\.?\d*\s*CR\b"#, options: []),
           regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)) != nil {
            return "inflow"
        }
        if textUpper.contains(" CR ") { return "inflow" }

        if let regex = try? NSRegularExpression(pattern: #"\b\d+\.?\d*\s*DR\b"#, options: []),
           regex.firstMatch(in: textUpper, range: NSRange(textUpper.startIndex..., in: textUpper)) != nil {
            return "outflow"
        }
        if textUpper.contains(" DR ") { return "outflow" }

        // Keyword counting
        let inflowKeywords = [
            "received", "incoming", "credited", "deposited", "refund",
            "salary", "payment received", "inward", "money in", "from",
            "employer deposit", "direct deposit"
        ]
        let outflowKeywords = [
            "sent", "outgoing", "debited", "withdrawn", "payment sent",
            "wire to", "transfer to", "outward", "money out",
            "payment to", "paid to"
        ]

        let inflowCount = inflowKeywords.filter { textLower.contains($0) }.count
        let outflowCount = outflowKeywords.filter { textLower.contains($0) }.count

        if inflowCount > outflowCount { return "inflow" }
        if outflowCount > inflowCount { return "outflow" }

        if let amount = amount {
            return amount > 0 ? "inflow" : "outflow"
        }

        return "outflow"
    }

    // MARK: - Own Account Detection

    private static func determineIsOwn(textLower: String, metadata: [String: String], text: String) -> Bool {
        let ownKeywords = [
            "own account", "between accounts", "internal transfer",
            "inter account", "account to account", "transfer between your",
            "between your accounts", "from savings to current",
            "from current to savings", "move money between",
            "your accounts", "same customer", "same beneficiary"
        ]
        if ownKeywords.contains(where: { textLower.contains($0) }) {
            return true
        }

        // Check "transfer type: own account"
        if let regex = try? NSRegularExpression(
            pattern: #"transfer\s+type\s*:?\s*own\s+account"#,
            options: .caseInsensitive
        ), regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }

        // Greeting name matches beneficiary
        let greetingPatterns = [#"Dear\s+([^,\n]+)"#, #"Hello\s+([^,\n]+)"#, #"Hi\s+([^,\n]+)"#]
        var greetingName: String?
        for p in greetingPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(m.range(at: 1), in: text) {
                greetingName = String(text[range]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        if let greeting = greetingName?.lowercased(),
           let beneficiary = metadata["beneficiary_name"]?.lowercased(),
           !greeting.isEmpty && greeting == beneficiary {
            return true
        }

        // "To account" name matches greeting
        if let greeting = greetingName,
           let regex = try? NSRegularExpression(
            pattern: #"To\s+account\s+([^*\d\n]+)"#,
            options: .caseInsensitive
           ),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(m.range(at: 1), in: text) {
            let toName = String(text[range]).trimmingCharacters(in: .whitespaces)
            if toName.lowercased() == greeting.lowercased() {
                return true
            }
        }

        // Sender name matches beneficiary name
        if let senderName = metadata["sender_name"]?.lowercased(),
           let beneficiaryName = metadata["beneficiary_name"]?.lowercased(),
           !senderName.isEmpty && !beneficiaryName.isEmpty {
            let senderParts = Set(senderName.split(separator: " ").map(String.init))
            let beneficiaryParts = Set(beneficiaryName.split(separator: " ").map(String.init))
            let overlap = senderParts.intersection(beneficiaryParts).count
            let minParts = min(senderParts.count, beneficiaryParts.count)
            if minParts > 0 && Double(overlap) / Double(minParts) >= 0.7 {
                return true
            }
        }

        // Negative indicators
        let notOwnKeywords = [
            "payment to merchant", "bill payment", "vendor payment",
            "salary payment", "rent payment", "loan payment",
            "emi payment", "to third party", "beneficiary bank"
        ]
        if notOwnKeywords.contains(where: { textLower.contains($0) }) {
            return false
        }

        return false
    }

    // MARK: - Scope

    private static func determineScope(textUpper: String, metadata: [String: String]) -> String {
        let internationalIndicators: [Bool] = [
            metadata["swift"] != nil,
            metadata["exchange_rate"] != nil,
            textUpper.contains("INTERNATIONAL"),
            textUpper.contains("FOREIGN"),
            textUpper.contains("CROSS-BORDER"),
            textUpper.contains("CROSS BORDER"),
            textUpper.contains("OVERSEAS"),
            textUpper.contains("CORRESPONDENT BANK"),
            textUpper.contains("REMITTANCE"),
            textUpper.contains("INWARD REMITTANCE"),
            textUpper.contains("OUTWARD REMITTANCE")
        ]
        if internationalIndicators.contains(true) {
            return "international"
        }

        // IBAN country check
        let gccCountries: Set<String> = ["AE", "SA", "KW", "QA", "BH", "OM"]
        if let iban = metadata["iban"], iban.count >= 2 {
            let country = String(iban.prefix(2))
            if !gccCountries.contains(country) {
                return "international"
            }
        }

        // International services
        let intlServices = [
            "WESTERN UNION", "MONEYGRAM", "WISE", "TRANSFERWISE", "REMITLY", "XOOM"
        ]
        if intlServices.contains(where: { textUpper.contains($0) }) && !textUpper.contains("DOMESTIC") {
            return "international"
        }

        // Domestic systems
        let domesticSystems = [
            "ACH", "NEFT", "RTGS", "IMPS", "UPI", "ZELLE",
            "VENMO", "CASHAPP", "DOMESTIC", "LOCAL TRANSFER"
        ]
        if domesticSystems.contains(where: { textUpper.contains($0) }) {
            return "domestic"
        }

        return "domestic"
    }
}
