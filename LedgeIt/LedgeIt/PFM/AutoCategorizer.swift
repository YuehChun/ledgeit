import Foundation

enum AutoCategorizer: Sendable {

    // MARK: - Lean Category

    enum LeanCategory: String, CaseIterable, Sendable {
        case foodAndDrink = "FOOD_AND_DRINK"
        case groceries = "GROCERIES"
        case entertainment = "ENTERTAINMENT"
        case travel = "TRAVEL"
        case healthcare = "HEALTHCARE"
        case personalCare = "PERSONAL_CARE"
        case education = "EDUCATION"
        case charity = "CHARITY"
        case bankFeesAndCharges = "BANK_FEES_AND_CHARGES"
        case utilities = "UTILITIES"
        case insurance = "INSURANCE"
        case investments = "INVESTMENTS"
        case shopping = "SHOPPING"
        case transport = "TRANSPORT"
        case salaryAndWages = "SALARY_AND_WAGES"
        case freelanceIncome = "FREELANCE_INCOME"
        case investmentReturns = "INVESTMENT_RETURNS"
        case refund = "REFUND"
        case general = "GENERAL"

        var displayName: String {
            switch self {
            case .foodAndDrink: return "Food & Drink"
            case .groceries: return "Groceries"
            case .entertainment: return "Entertainment"
            case .travel: return "Travel"
            case .healthcare: return "Healthcare"
            case .personalCare: return "Personal Care"
            case .education: return "Education"
            case .charity: return "Charity"
            case .bankFeesAndCharges: return "Bank Fees & Charges"
            case .utilities: return "Utilities"
            case .insurance: return "Insurance"
            case .investments: return "Investments"
            case .shopping: return "Shopping"
            case .transport: return "Transport"
            case .salaryAndWages: return "Salary & Wages"
            case .freelanceIncome: return "Freelance Income"
            case .investmentReturns: return "Investment Returns"
            case .refund: return "Refund"
            case .general: return "General"
            }
        }

        var dimension: String {
            switch self {
            case .foodAndDrink, .groceries, .entertainment, .travel,
                 .healthcare, .personalCare, .education, .charity:
                return "lifestyle"
            case .bankFeesAndCharges, .utilities, .insurance, .investments:
                return "financial"
            case .shopping, .transport, .general:
                return "commerce"
            case .salaryAndWages, .freelanceIncome, .investmentReturns, .refund:
                return "income"
            }
        }
    }

    // MARK: - Merchant Patterns (sorted longest first at init time)

    static let merchantPatterns: [(pattern: String, category: LeanCategory)] = {
        let raw: [(String, LeanCategory)] = [
            // Lifestyle - Personal Care
            ("V Perfumes", .personalCare),
            ("Sephora", .personalCare),
            ("Bath & Body Works", .personalCare),
            ("salon", .personalCare),
            ("spa", .personalCare),

            // Lifestyle - Healthcare
            ("pharmacy", .healthcare),
            ("hospital", .healthcare),
            ("clinic", .healthcare),
            ("Aster", .healthcare),
            ("NMC", .healthcare),
            ("Nahdi", .groceries),

            // Lifestyle - Food & Drink
            ("Starbucks", .foodAndDrink),
            ("McDonald", .foodAndDrink),
            ("KFC", .foodAndDrink),
            ("restaurant", .foodAndDrink),
            ("cafe", .foodAndDrink),
            ("coffee", .foodAndDrink),

            // Lifestyle - Groceries
            ("Carrefour Online", .groceries),
            ("Carrefour", .groceries),
            ("Lulu Hypermarket", .groceries),
            ("Lulu", .groceries),
            ("Talabat (Mart)", .groceries),
            ("Talabat Subscription", .groceries),
            ("Talabat Service", .groceries),
            ("Talabat", .groceries),
            ("Instashop", .groceries),
            ("iHerb", .groceries),
            ("Spinneys", .groceries),
            ("Waitrose", .groceries),
            ("supermarket", .groceries),
            ("Grandiose Supermarket", .groceries),
            ("Grandiose", .groceries),

            // Lifestyle - Entertainment
            ("VOX Cinemas", .entertainment),
            ("Vox", .entertainment),
            ("Platinum List", .entertainment),
            ("Platinumlist", .entertainment),
            ("PLP Events", .entertainment),
            ("cinema", .entertainment),
            ("Spotify", .entertainment),
            ("Netflix", .entertainment),
            ("Tomorrowland", .entertainment),
            ("concert", .entertainment),

            // Lifestyle - Travel
            ("Etihad Airways", .travel),
            ("Emirates", .travel),
            ("Etihad", .travel),
            ("Flyadeal", .travel),
            ("Airalo", .travel),
            ("Booking.com", .travel),
            ("Airbnb", .travel),
            ("Studio One Hotel", .travel),
            ("Qatar Airways", .travel),
            ("Fairmont", .travel),
            ("hotel", .travel),

            // Financial - Utilities
            ("Dubai Electricity & Water Authority", .utilities),
            ("Dubai Electricity", .utilities),
            ("DEWA", .utilities),
            ("TAQA Distribution", .utilities),
            ("ADDC", .utilities),
            ("TAQA", .utilities),
            ("Etisalat Bill", .utilities),
            ("Etisalat", .utilities),
            ("e&", .utilities),
            ("du", .utilities),
            ("Virgin Mobile", .utilities),
            ("Saudi Electricity", .utilities),
            ("Hillwood Property", .utilities),
            ("Pam Golding", .utilities),
            ("Propati", .utilities),
            ("Itec Integrate", .utilities),
            ("property management", .utilities),
            ("RIZEK", .utilities),
            ("Rizek", .utilities),

            // Financial - Banking
            ("Mashreq", .bankFeesAndCharges),
            ("Emirates NBD", .bankFeesAndCharges),
            ("ADCB", .bankFeesAndCharges),
            ("transfer", .bankFeesAndCharges),

            // Commerce - Shopping
            ("Carrefour Marketplace", .shopping),
            ("Noon", .shopping),
            ("noon", .shopping),
            ("Amazon", .shopping),
            ("Home Centre", .shopping),
            ("Homecentre", .shopping),
            ("Home Center", .shopping),
            ("Jumbo Electronics", .shopping),
            ("Jumbo", .shopping),
            ("Temu", .shopping),
            ("Namshi", .shopping),
            ("Vercel Inc.", .shopping),
            ("Vercel", .shopping),
            ("Apple", .shopping),

            // Commerce - Transport
            ("Uber", .transport),
            ("Careem", .transport),
            ("RTA", .transport),
            ("SALIK", .transport),
            ("petrol", .transport),
            ("fuel", .transport),
        ]
        return raw.sorted { $0.0.count > $1.0.count }
    }()

    // MARK: - Description Patterns

    static let descriptionPatterns: [(keyword: String, category: LeanCategory)] = [
        // Utilities
        ("electricity", .utilities),
        ("water bill", .utilities),
        ("gas bill", .utilities),
        ("internet bill", .utilities),
        ("phone bill", .utilities),
        ("levy", .utilities),
        ("property", .utilities),
        ("rent", .utilities),
        ("maintenance", .utilities),
        ("statement balance", .utilities),

        // Food & Drink
        ("restaurant", .foodAndDrink),
        ("dining", .foodAndDrink),
        ("cafe", .foodAndDrink),
        ("coffee", .foodAndDrink),
        ("lunch", .foodAndDrink),
        ("dinner", .foodAndDrink),
        ("breakfast", .foodAndDrink),

        // Groceries
        ("grocery", .groceries),
        ("supermarket", .groceries),
        ("food shopping", .groceries),

        // Shopping
        ("order", .shopping),
        ("purchase", .shopping),
        ("shopping", .shopping),
        ("online order", .shopping),

        // Healthcare
        ("pharmacy", .healthcare),
        ("medical", .healthcare),
        ("health", .healthcare),
        ("doctor", .healthcare),
        ("hospital", .healthcare),
        ("clinic", .healthcare),

        // Transport
        ("uber", .transport),
        ("taxi", .transport),
        ("transport", .transport),
        ("parking", .transport),
        ("fuel", .transport),
        ("petrol", .transport),

        // Banking
        ("transfer", .bankFeesAndCharges),
        ("payment", .bankFeesAndCharges),
        ("fee", .bankFeesAndCharges),
        ("charge", .bankFeesAndCharges),
        ("bank", .bankFeesAndCharges),

        // Travel
        ("flight", .travel),
        ("hotel", .travel),
        ("booking", .travel),
        ("reservation", .travel),
        ("travel", .travel),

        // Entertainment
        ("ticket", .entertainment),
        ("cinema", .entertainment),
        ("movie", .entertainment),
        ("concert", .entertainment),
        ("event", .entertainment),

        // Insurance
        ("insurance", .insurance),
        ("premium", .insurance),

        // Investments
        ("investment", .investments),
        ("stock", .investments),
        ("fund", .investments),
    ]

    // MARK: - Categorize

    static func categorize(
        merchant: String?,
        description: String?,
        docType: String?,
        amount: Double?,
        type: String? = nil
    ) -> LeanCategory {
        let merchantStr = (merchant ?? "").trimmingCharacters(in: .whitespaces)
        let descriptionStr = (description ?? "").trimmingCharacters(in: .whitespaces)

        let merchantLower = merchantStr.lowercased()
        let descriptionLower = descriptionStr.lowercased()

        // Income categorization — check first for credit-type transactions
        if type?.lowercased() == "credit" {
            let salaryKeywords = ["salary", "payroll", "wages", "employer"]
            if salaryKeywords.contains(where: { merchantLower.contains($0) || descriptionLower.contains($0) }) {
                return .salaryAndWages
            }

            let freelanceKeywords = ["freelance", "invoice payment", "consulting fee"]
            if freelanceKeywords.contains(where: { merchantLower.contains($0) || descriptionLower.contains($0) }) {
                return .freelanceIncome
            }

            let investmentKeywords = ["dividend", "interest earned", "capital gains", "investment return"]
            if investmentKeywords.contains(where: { merchantLower.contains($0) || descriptionLower.contains($0) }) {
                return .investmentReturns
            }

            let refundKeywords = ["refund", "cashback", "reversal", "return credit"]
            if refundKeywords.contains(where: { merchantLower.contains($0) || descriptionLower.contains($0) }) {
                return .refund
            }
        }

        // 1. Carrefour special cases
        let marketplaceIndicators = ["marketplace", "seller"]
        let isMarketplace = marketplaceIndicators.contains { descriptionLower.contains($0) }

        if merchantLower.contains("carrefour marketplace") || (merchantLower.contains("carrefour") && isMarketplace) {
            return .shopping
        }
        if merchantLower.contains("carrefour online") || (merchantLower.contains("carrefour") && descriptionLower.contains("online")) {
            return .groceries
        }

        // 2. Merchant patterns (already sorted longest first)
        for (pattern, category) in merchantPatterns {
            if merchantLower.contains(pattern.lowercased()) {
                return category
            }
        }

        // 3. Description patterns
        for (keyword, category) in descriptionPatterns {
            if descriptionLower.contains(keyword.lowercased()) {
                return category
            }
        }

        // 4. Document type fallback
        if let docType = docType?.lowercased(), !docType.isEmpty {
            switch docType {
            case "receipt":
                let foodKeywords = ["food", "dining", "restaurant", "cafe"]
                if foodKeywords.contains(where: { descriptionLower.contains($0) }) {
                    return .foodAndDrink
                }
                return .shopping

            case "statement":
                let balanceKeywords = ["balance", "statement", "monthly"]
                if balanceKeywords.contains(where: { descriptionLower.contains($0) }) {
                    return .utilities
                }
                return .bankFeesAndCharges

            case "order":
                return .shopping

            case "payment":
                let propertyKeywords = ["property", "rent", "levy"]
                if propertyKeywords.contains(where: { descriptionLower.contains($0) }) {
                    return .utilities
                }
                return .bankFeesAndCharges

            default:
                break
            }
        }

        // 5. Default
        return .general
    }
}
