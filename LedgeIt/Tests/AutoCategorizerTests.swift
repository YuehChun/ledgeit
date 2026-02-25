import Testing
@testable import LedgeIt

struct AutoCategorizerTests {

    // MARK: - Merchant Pattern Matching

    @Test func starbucks() {
        let result = AutoCategorizer.categorize(
            merchant: "Starbucks Coffee",
            description: nil,
            docType: nil,
            amount: nil
        )
        #expect(result == .foodAndDrink)
    }

    @Test func carrefour() {
        let result = AutoCategorizer.categorize(
            merchant: "Carrefour",
            description: nil,
            docType: nil,
            amount: nil
        )
        #expect(result == .groceries)
    }

    @Test func carrefourOnline() {
        let result = AutoCategorizer.categorize(
            merchant: "Carrefour Online",
            description: nil,
            docType: nil,
            amount: nil
        )
        #expect(result == .groceries)
    }

    @Test func carrefourMarketplace() {
        let result = AutoCategorizer.categorize(
            merchant: "Carrefour Marketplace",
            description: nil,
            docType: nil,
            amount: nil
        )
        #expect(result == .shopping)
    }

    @Test func carrefourWithMarketplaceDescription() {
        let result = AutoCategorizer.categorize(
            merchant: "Carrefour",
            description: "Order from marketplace seller",
            docType: nil,
            amount: nil
        )
        #expect(result == .shopping)
    }

    @Test func uber() {
        let result = AutoCategorizer.categorize(
            merchant: "Uber",
            description: "Trip from Downtown to Airport",
            docType: nil,
            amount: nil
        )
        #expect(result == .transport)
    }

    @Test func netflix() {
        let result = AutoCategorizer.categorize(
            merchant: "Netflix",
            description: "Monthly subscription",
            docType: nil,
            amount: nil
        )
        #expect(result == .entertainment)
    }

    @Test func dewa() {
        let result = AutoCategorizer.categorize(
            merchant: "DEWA",
            description: "Electricity and water bill",
            docType: nil,
            amount: nil
        )
        #expect(result == .utilities)
    }

    @Test func hospital() {
        let result = AutoCategorizer.categorize(
            merchant: "City Hospital",
            description: nil,
            docType: nil,
            amount: nil
        )
        #expect(result == .healthcare)
    }

    @Test func spotify() {
        let result = AutoCategorizer.categorize(
            merchant: "Spotify",
            description: nil,
            docType: nil,
            amount: nil
        )
        #expect(result == .entertainment)
    }

    @Test func etihad() {
        let result = AutoCategorizer.categorize(
            merchant: "Etihad Airways",
            description: "Flight booking",
            docType: nil,
            amount: nil
        )
        #expect(result == .travel)
    }

    // MARK: - Description Pattern Matching

    @Test func descriptionRestaurant() {
        let result = AutoCategorizer.categorize(
            merchant: "Unknown Merchant",
            description: "Restaurant dinner for two",
            docType: nil,
            amount: nil
        )
        #expect(result == .foodAndDrink)
    }

    @Test func descriptionInsurance() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: "Annual insurance premium renewal",
            docType: nil,
            amount: nil
        )
        #expect(result == .insurance)
    }

    @Test func descriptionFuel() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: "Fuel station fill up",
            docType: nil,
            amount: nil
        )
        #expect(result == .transport)
    }

    // MARK: - Document Type Fallback

    @Test func receiptDocType() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: nil,
            docType: "receipt",
            amount: nil
        )
        #expect(result == .shopping)
    }

    @Test func receiptWithFoodDescription() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: "restaurant dining receipt",
            docType: "receipt",
            amount: nil
        )
        #expect(result == .foodAndDrink)
    }

    @Test func statementDocType() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: nil,
            docType: "statement",
            amount: nil
        )
        #expect(result == .bankFeesAndCharges)
    }

    @Test func paymentDocTypeWithRent() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: "Monthly rent payment",
            docType: "payment",
            amount: nil
        )
        #expect(result == .utilities)
    }

    // MARK: - Amount Heuristic

    @Test func largeAmount() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: nil,
            docType: nil,
            amount: 7500.0
        )
        #expect(result == .utilities)
    }

    @Test func smallAmount() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: nil,
            docType: nil,
            amount: 25.0
        )
        #expect(result == .shopping)
    }

    // MARK: - Default

    @Test func defaultCategory() {
        let result = AutoCategorizer.categorize(
            merchant: nil,
            description: nil,
            docType: nil,
            amount: nil
        )
        #expect(result == .general)
    }

    // MARK: - LeanCategory Properties

    @Test func categoryDisplayNames() {
        #expect(AutoCategorizer.LeanCategory.foodAndDrink.displayName == "Food & Drink")
        #expect(AutoCategorizer.LeanCategory.bankFeesAndCharges.displayName == "Bank Fees & Charges")
        #expect(AutoCategorizer.LeanCategory.personalCare.displayName == "Personal Care")
    }

    @Test func categoryDimensions() {
        #expect(AutoCategorizer.LeanCategory.foodAndDrink.dimension == "lifestyle")
        #expect(AutoCategorizer.LeanCategory.utilities.dimension == "financial")
        #expect(AutoCategorizer.LeanCategory.shopping.dimension == "commerce")
    }

    @Test func allCategoriesCount() {
        #expect(AutoCategorizer.LeanCategory.allCases.count == 15)
    }
}
