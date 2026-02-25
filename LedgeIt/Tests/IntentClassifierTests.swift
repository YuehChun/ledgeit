import Testing
@testable import LedgeIt

struct IntentClassifierTests {

    let classifier = IntentClassifier()

    // MARK: - Rule 1: Trusted bank + transaction keywords

    @Test func trustedBankWithTransactionKeyword() {
        let result = classifier.classify(
            subject: "Your transaction alert",
            body: "A payment of AED 500 has been debited from your account",
            sender: "Emirates NBD Alerts",
            senderEmail: "alerts@emiratesnbd.com"
        )
        #expect(result.decision == .accept)
        #expect(result.confidence == 0.95)
        #expect(result.method == .ruleBased)
    }

    @Test func trustedBankWithoutTransactionKeyword() {
        let result = classifier.classify(
            subject: "Welcome to our new app",
            body: "We are excited to announce our new mobile app",
            sender: "Emirates NBD",
            senderEmail: "info@emiratesnbd.com"
        )
        // Should NOT match rule 1 (no transaction keywords)
        #expect(result.decision != .accept || result.reasoning != "Trusted bank (emiratesnbd.com) + transaction keywords")
    }

    // MARK: - Rule 2: Payment confirmation + transaction ID

    @Test func paymentConfirmationWithTransactionId() {
        let result = classifier.classify(
            subject: "Payment Confirmed",
            body: "Your payment has been confirmed. Order #ABC-12345 for $99.00",
            sender: "Store",
            senderEmail: "noreply@store.com"
        )
        #expect(result.decision == .accept)
        #expect(result.reasoning.contains("Payment confirmation"))
    }

    // MARK: - Rule 3: Bank statement

    @Test func bankStatement() {
        let result = classifier.classify(
            subject: "Your Monthly Account Statement",
            body: "Please find attached your account statement for January 2024",
            sender: "Bank",
            senderEmail: "statements@bank.com"
        )
        #expect(result.decision == .accept)
        #expect(result.reasoning.contains("statement"))
    }

    @Test func statementNotification() {
        // "statement is available" should NOT match (it's a notification, not a statement)
        let result = classifier.classify(
            subject: "Your statement is available",
            body: "Your latest statement is available to view online",
            sender: "Bank",
            senderEmail: "notifications@randombank.com"
        )
        // Should not be accepted by rule 3
        #expect(result.decision != .accept || !result.reasoning.contains("Bank statement"))
    }

    // MARK: - Rule 4: Amount with payment verb

    @Test func amountWithPaymentVerb() {
        let result = classifier.classify(
            subject: "Payment Alert",
            body: "You have been charged USD 150.00 at Store ABC",
            sender: "Bank Alerts",
            senderEmail: "alerts@somebank.com"
        )
        #expect(result.decision == .accept)
        #expect(result.reasoning.contains("amount with payment verb"))
    }

    @Test func amountWithThirdPartyContext() {
        let result = classifier.classify(
            subject: "Court orders company to pay",
            body: "The court ordered the company to pay. Executives paid 500000 in damages",
            sender: "News",
            senderEmail: "newsletter@news.com"
        )
        // Should be rejected (news domain + third party)
        #expect(result.decision == .reject)
    }

    // MARK: - Rule 5: News sender

    @Test func newsletterSender() {
        let result = classifier.classify(
            subject: "Breaking: Market Update",
            body: "Stock prices went up today",
            sender: "Daily Newsletter",
            senderEmail: "info@dailynewsletter.com"
        )
        #expect(result.decision == .reject)
        #expect(result.reasoning.contains("News"))
    }

    // MARK: - Rule 6: Strong exclude keywords

    @Test func strongExcludeKeyword() {
        let result = classifier.classify(
            subject: "Flash Sale! 50% off everything",
            body: "Don't miss our exclusive offer, shop now and save big",
            sender: "Store",
            senderEmail: "promo@store.com"
        )
        #expect(result.decision == .reject)
    }

    // MARK: - Rule 9: Promotional keywords

    @Test func multiplePromotionalKeywords() {
        let result = classifier.classify(
            subject: "Amazing Deals Inside",
            body: "Flash sale happening now! Shop now for amazing deals! Buy now today! Limited time offer ends soon! Save now on everything!",
            sender: "Shop",
            senderEmail: "deals@shop.com"
        )
        #expect(result.decision == .reject)
    }

    // MARK: - Rule 10: Very long emails

    @Test func veryLongPromotionalEmail() {
        let longBody = String(repeating: "This is a promotional email with lots of content. ", count: 300)
        let result = classifier.classify(
            subject: "Check out our latest deals",
            body: longBody,
            sender: "Deals",
            senderEmail: "deals@promo.com"
        )
        #expect(result.decision == .reject)
        #expect(result.reasoning.contains("Very long email"))
    }

    @Test func longEmailFromAirline() {
        let longBody = String(repeating: "Flight details and booking information. ", count: 300)
        let result = classifier.classify(
            subject: "Your Flight Confirmation",
            body: longBody,
            sender: "Emirates",
            senderEmail: "noreply@emirates.com"
        )
        // Airlines should NOT be rejected by the long email rule
        #expect(result.decision != .reject || !result.reasoning.contains("Very long email"))
    }

    // MARK: - Uncertain

    @Test func ambiguousEmail() {
        let result = classifier.classify(
            subject: "Update from your account",
            body: "Here is some information about your account.",
            sender: "Service",
            senderEmail: "info@someservice.com"
        )
        #expect(result.decision == .uncertain)
        #expect(result.confidence == 0.5)
    }
}
