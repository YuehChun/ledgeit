import Foundation

enum PFMConfig: Sendable {

    // MARK: - Financial Email Recognition Keywords

    static let financialKeywords: [String: [String]] = [
        "invoice": [
            "invoice", "\u{0641}\u{0627}\u{062A}\u{0648}\u{0631}\u{0629}", "Rechnung", "bill", "billing",
            "\u{0641}\u{0627}\u{062A}\u{0648}\u{0631}\u{0629} \u{0627}\u{0644}\u{0643}\u{0647}\u{0631}\u{0628}\u{0627}\u{0621}",
            "\u{0641}\u{0627}\u{062A}\u{0648}\u{0631}\u{0629} \u{0627}\u{0644}\u{0645}\u{064A}\u{0627}\u{0647}"
        ],
        "receipt": [
            "receipt", "payment received", "\u{0625}\u{064A}\u{0635}\u{0627}\u{0644}",
            "payment confirmation", "transaction receipt"
        ],
        "statement": [
            "statement", "bank statement",
            "\u{0643}\u{0634}\u{0641} \u{062D}\u{0633}\u{0627}\u{0628}",
            "account statement", "financial statement", "aged summary",
            "balance", "invoice",
            "\u{0641}\u{0627}\u{062A}\u{0648}\u{0631}\u{0629}"
        ],
        "transaction": [
            "transaction", "transfer",
            "\u{0645}\u{0639}\u{0627}\u{0645}\u{0644}\u{0629}",
            "credited", "debited", "deposit", "withdrawal"
        ],
        "payment": [
            "payment", "pay", "paid",
            "\u{062F}\u{0641}\u{0639}",
            "amount due", "payment due", "payment processed"
        ],
        "order": [
            "order", "purchase",
            "\u{0637}\u{0644}\u{0628}",
            "confirmation", "booking", "package", "itinerary",
            "order placed", "order confirmed"
        ],
        "refund": [
            "refund", "return",
            "\u{0627}\u{0633}\u{062A}\u{0631}\u{062F}\u{0627}\u{062F}",
            "cashback", "reversal", "credit note"
        ],
        "subscription": [
            "subscription", "membership",
            "\u{0627}\u{0634}\u{062A}\u{0631}\u{0627}\u{0643}",
            "recurring", "monthly payment", "annual payment"
        ],
        "utilities": [
            "electricity", "water", "gas", "utility", "utilities",
            "\u{0634}\u{062D}\u{0646}",
            "\u{0643}\u{0647}\u{0631}\u{0628}\u{0627}\u{0621}",
            "\u{0645}\u{0627}\u{0621}",
            "dewa", "sewa", "addc", "taqa", "du", "etisalat", "virgin mobile"
        ],
        "company_statements": [
            "itec integrate", "itec group", "statement for",
            "receive statement", "issued statement"
        ],
        "groceries": [
            "talabat", "talabat mart",
            "\u{0637}\u{0644}\u{0628}\u{0627}\u{062A}",
            "talabat subscription",
            "carrefour", "carrefour online", "carrefour marketplace",
            "\u{0643}\u{0627}\u{0631}\u{0641}\u{0648}\u{0631}",
            "lulu", "lulu hypermarket",
            "\u{0644}\u{0648}\u{0644}\u{0648}",
            "lulu webstore",
            "instashop", "spinneys", "waitrose", "choithrams",
            "iherb", "noon minutes", "kibsons", "organic foods",
            "grocery", "groceries", "supermarket", "hypermarket"
        ],
        "income": [
            "salary", "salary credited", "salary deposit", "monthly salary", "payroll",
            "\u{0631}\u{0627}\u{062A}\u{0628}",
            "\u{062A}\u{0645} \u{0625}\u{064A}\u{062F}\u{0627}\u{0639} \u{0627}\u{0644}\u{0631}\u{0627}\u{062A}\u{0628}",
            "\u{0627}\u{0644}\u{0631}\u{0627}\u{062A}\u{0628} \u{0627}\u{0644}\u{0634}\u{0647}\u{0631}\u{064A}",
            "transfer received", "incoming transfer", "amount credited",
            "international transfer", "domestic transfer", "wire transfer",
            "\u{062D}\u{0648}\u{0627}\u{0644}\u{0629} \u{0648}\u{0627}\u{0631}\u{062F}\u{0629}",
            "\u{062A}\u{062D}\u{0648}\u{064A}\u{0644} \u{062F}\u{0648}\u{0644}\u{064A}",
            "\u{062A}\u{062D}\u{0648}\u{064A}\u{0644} \u{0645}\u{062D}\u{0644}\u{064A}",
            "remittance received", "funds received", "payment received",
            "refund processed", "cashback credited", "reversal"
        ],
        "travel": [
            "booking.com", "booking",
            "\u{0628}\u{0648}\u{0643}\u{064A}\u{0646}\u{062C}",
            "hotel reservation",
            "airbnb",
            "\u{0625}\u{064A}\u{0631} \u{0628}\u{064A} \u{0625}\u{0646} \u{0628}\u{064A}",
            "accommodation",
            "emirates", "etihad", "flydubai", "air arabia", "flyadeal",
            "\u{0627}\u{0644}\u{0625}\u{0645}\u{0627}\u{0631}\u{0627}\u{062A}",
            "\u{0627}\u{0644}\u{0627}\u{062A}\u{062D}\u{0627}\u{062F} \u{0644}\u{0644}\u{0637}\u{064A}\u{0631}\u{0627}\u{0646}",
            "\u{0641}\u{0644}\u{0627}\u{064A} \u{062F}\u{0628}\u{064A}",
            "flight", "airline", "boarding pass", "e-ticket",
            "airalo", "esim", "roaming"
        ],
        "shopping": [
            "amazon", "noon",
            "\u{0646}\u{0648}\u{0646}",
            "namshi", "shein",
            "temu", "aliexpress", "ebay",
            "home centre",
            "\u{0647}\u{0648}\u{0645} \u{0633}\u{0646}\u{062A}\u{0631}",
            "ikea",
            "\u{0625}\u{064A}\u{0643}\u{064A}\u{0627}",
            "ace hardware", "jumbo electronics", "sharaf dg",
            "online shopping", "e-commerce", "order delivered"
        ],
        "transportation": [
            "careem", "uber", "hala", "hala taxi",
            "\u{0643}\u{0631}\u{064A}\u{0645}",
            "\u{0623}\u{0648}\u{0628}\u{0631}",
            "\u{0647}\u{0644}\u{0627}",
            "taxi", "ride", "trip fare", "ride receipt"
        ],
        "entertainment": [
            "vox", "vox cinemas", "reel cinemas", "novo cinemas",
            "platinum list", "platinumlist", "ticketmaster",
            "cinema", "movie ticket", "concert ticket", "event ticket"
        ]
    ]

    // MARK: - Exclude Keywords

    static let strongExcludeKeywords: [String] = [
        // Marketing
        "unsubscribe", "opt-out", "manage preferences", "email preferences",
        "click here to unsubscribe", "stop receiving", "update your preferences",
        // News/information
        "breaking news", "daily digest", "headlines", "news roundup",
        "today's top stories", "latest news", "news alert", "news update",
        // Promotional
        "limited time offer", "flash sale", "exclusive deal", "special promotion",
        "discount code", "promo code", "coupon code", "save now", "shop now",
        "clearance sale", "seasonal sale", "get yours today", "don't miss out",
        // Advertisement
        "advertisement", "sponsored content", "sponsored post", "featured offer",
        "partner offer", "recommended for you",
        // Social/Community
        "community update", "community announcement", "social update",
        "construction notice", "public notice", "general announcement",
        // Multilingual
        "\u{0625}\u{0644}\u{063A}\u{0627}\u{0621} \u{0627}\u{0644}\u{0627}\u{0634}\u{062A}\u{0631}\u{0627}\u{0643}",
        "\u{0627}\u{0644}\u{0639}\u{0631}\u{0648}\u{0636} \u{0627}\u{0644}\u{062A}\u{0631}\u{0648}\u{064A}\u{062C}\u{064A}\u{0629}",
        "\u{0627}\u{0644}\u{0623}\u{062E}\u{0628}\u{0627}\u{0631} \u{0627}\u{0644}\u{064A}\u{0648}\u{0645}\u{064A}\u{0629}"
    ]

    static let weakExcludeKeywords: [String] = [
        "newsletter", "subscription update", "monthly update",
        "promotion", "marketing", "campaign"
    ]

    // MARK: - Trusted Financial Institutions

    static let trustedFinancialInstitutions: [String] = [
        // UAE banks
        "mashreq.com", "mashreqbank.com",
        "enbd.com", "emiratesnbd.com",
        "adcb.com", "adcb.ae",
        "fab.ae", "firstabu.com",
        "dib.ae", "dibdubai.com",
        "rakbank.ae",
        "cbd.ae", "commercialbank.ae",
        // International banks
        "hsbc.com", "hsbc.ae",
        "standardchartered.com", "sc.com",
        "citibank.com", "citi.com",
        // Payment platforms
        "paypal.com", "paypal-communications.com",
        "stripe.com", "stripe.network",
        "square.com", "squareup.com",
        // Credit cards
        "visa.com", "mastercard.com", "americanexpress.com",
        // Financial management
        "mint.com", "quickbooks.intuit.com",
        "xero.com", "wave.com"
    ]

    // MARK: - Trusted Subscription Services

    static let trustedSubscriptionServices: [String] = [
        // Tech platforms
        "google.com", "googleplay", "google.co", "gmail.com",
        "apple.com", "itunes.apple.com", "icloud.com",
        "microsoft.com", "office365.com", "outlook.com",
        // Development tools
        "github.com", "gitlab.com", "bitbucket.org",
        "replit.com", "cursor.sh", "vercel.com", "netlify.com",
        "aws.amazon.com", "azure.com", "cloud.google.com",
        // Subscription services
        "spotify.com", "netflix.com", "amazon.com", "amazon.ae",
        "adobe.com", "creative.adobe.com",
        "notion.so", "evernote.com", "dropbox.com",
        // Online education
        "udemy.com", "coursera.org", "edx.org", "linkedin.com",
        "skillshare.com", "pluralsight.com",
        // Payment platforms
        "paypal.com", "stripe.com", "square.com", "venmo.com",
        "wise.com", "revolut.com", "n26.com",
        // UAE local services
        "du.ae", "etisalat.ae", "dewa.gov.ae", "sewa.gov.ae",
        "noon.com", "careem.com", "talabat.com",
        // Groceries and food delivery
        "carrefouruae.com", "carrefour.com", "luluhypermarket.com",
        "instashop.com", "spinneys.com", "waitrose.ae",
        "iherb.com", "kibsons.com",
        // Travel and accommodation
        "booking.com", "airbnb.com", "hotels.com",
        "emirates.com", "etihad.com", "flydubai.com", "airarabia.com",
        "flyadeal.com", "airalo.com",
        // Shopping and e-commerce
        "temu.com", "aliexpress.com", "namshi.com", "shein.com",
        "homecentre.com", "ikea.com", "aceuae.com",
        "jumbo.ae", "sharafdg.com",
        // Transportation
        "uber.com", "hala.ae",
        // Entertainment
        "voxcinemas.com", "reelcinemas.ae", "novo-cinemas.com",
        "platinumlist.net", "ticketmaster.ae",
        // Utilities and telecom
        "virginmobile.ae", "taqa.ae", "addc.ae"
    ]

    // MARK: - Intent Classification Thresholds

    struct IntentThresholds: Sendable {
        let acceptTransactionIntent: Int
        let acceptMaxMarketing: Int
        let acceptMaxRisk: Int
        let rejectTransactionIntent: Int
        let rejectMinMarketing: Int
        let rejectMinRisk: Int
        let reviewMinTransactionIntent: Int
    }

    static let intentThresholds = IntentThresholds(
        acceptTransactionIntent: 7,
        acceptMaxMarketing: 4,
        acceptMaxRisk: 5,
        rejectTransactionIntent: 4,
        rejectMinMarketing: 8,
        rejectMinRisk: 7,
        reviewMinTransactionIntent: 5
    )

    // MARK: - LLM Configuration

    static let llmTemperature = 0.1
    static let llmMaxTokens = 2000
    static let classificationModel = "anthropic/claude-haiku-4-5"
    static let extractionModel = "anthropic/claude-sonnet-4-6"
    static let visionModel = "anthropic/claude-sonnet-4-6"
}
