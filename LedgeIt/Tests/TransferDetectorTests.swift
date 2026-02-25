import Testing
@testable import LedgeIt

struct TransferDetectorTests {

    // MARK: - Wire Transfers

    @Test func wireTransfer() {
        let result = TransferDetector.detectTransfer(
            in: "WIRE TRANSFER from SWIFT: EMIRAEADXXXX Amount credited USD 5000",
            amount: 5000
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "wire_transfer")
        #expect(result.paymentSystem == "SWIFT")
        #expect(result.confidence > 0.5)
    }

    // MARK: - ACH Transfers

    @Test func achTransfer() {
        let result = TransferDetector.detectTransfer(
            in: "ACH CREDIT from Employer Inc. Direct deposit",
            amount: 3000
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "ach_transfer")
        #expect(result.paymentSystem == "ACH")
    }

    // MARK: - Remittances

    @Test func westernUnion() {
        let result = TransferDetector.detectTransfer(
            in: "WESTERN UNION money transfer MTCN: 1234567890 sent to John",
            amount: -500
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "remittance")
        #expect(result.transferSubtype == "western_union")
        #expect(result.paymentSystem == "WESTERN_UNION")
    }

    @Test func wiseTransfer() {
        let result = TransferDetector.detectTransfer(
            in: "WISE TRANSFER completed. Your multi-currency transfer has been sent.",
            amount: -200
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "remittance")
        #expect(result.transferSubtype == "wise")
    }

    // MARK: - Refunds

    @Test func merchantRefund() {
        let result = TransferDetector.detectTransfer(
            in: "REFUND CONFIRMATION: Your refund for Order #12345 has been processed",
            amount: 50
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "refund")
        #expect(result.transferSubtype == "merchant")
    }

    @Test func taxRefund() {
        let result = TransferDetector.detectTransfer(
            in: "IRS REFUND deposited. Your TAX REFUND of $2500 has been credited.",
            amount: 2500
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "refund")
        #expect(result.transferSubtype == "tax")
    }

    // MARK: - P2P Payments

    @Test func venmoPayment() {
        let result = TransferDetector.detectTransfer(
            in: "VENMO FROM @johndoe paid you $25 for dinner",
            amount: 25
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "p2p_payment")
        #expect(result.paymentSystem == "VENMO")
    }

    @Test func zellePayment() {
        let result = TransferDetector.detectTransfer(
            in: "Zelle payment received from Jane Smith. Sent with Zelle.",
            amount: 100
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "p2p_payment")
        #expect(result.transferSubtype == "zelle")
    }

    // MARK: - Salary

    @Test func salaryDeposit() {
        let result = TransferDetector.detectTransfer(
            in: "Your salary has been credited to your account. SALARY DEPOSIT from ABC Corp.",
            amount: 5000
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "salary")
        #expect(result.paymentSystem == "PAYROLL")
    }

    // MARK: - Internal Transfer

    @Test func ownAccountTransfer() {
        let result = TransferDetector.detectTransfer(
            in: "INTERNAL TRANSFER between accounts. Transfer from savings to current account.",
            amount: 1000
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "internal_transfer")
        #expect(result.isOwn)
        #expect(result.direction == "neutral")
    }

    // MARK: - Direction Detection

    @Test func inflowDirection() {
        let result = TransferDetector.detectTransfer(
            in: "Amount credited to your account via bank transfer. Payment received.",
            amount: 1000
        )
        #expect(result.isTransfer)
        #expect(result.direction == "inflow")
    }

    @Test func outflowDirection() {
        let result = TransferDetector.detectTransfer(
            in: "Amount debited from your account. Bank transfer sent. Payment to merchant.",
            amount: -500
        )
        #expect(result.isTransfer)
        #expect(result.direction == "outflow")
    }

    // MARK: - Scope Detection

    @Test func internationalScope() {
        let result = TransferDetector.detectTransfer(
            in: "INTERNATIONAL WIRE TRANSFER SWIFT: CHASUS33XXX Exchange rate: 3.67",
            amount: 5000
        )
        #expect(result.isTransfer)
        #expect(result.scope == "international")
    }

    @Test func domesticScope() {
        let result = TransferDetector.detectTransfer(
            in: "LOCAL TRANSFER. Domestic bank transfer to local account via ACH",
            amount: -200
        )
        #expect(result.isTransfer)
        #expect(result.scope == "domestic")
    }

    // MARK: - Metadata Extraction

    @Test func extractsSwiftCode() {
        let result = TransferDetector.detectTransfer(
            in: "Wire transfer via SWIFT: EMIRAEADXXX from international bank",
            amount: 5000
        )
        #expect(result.metadata["swift"] == "EMIRAEADXXX")
    }

    @Test func extractsReferenceNumber() {
        let result = TransferDetector.detectTransfer(
            in: "Bank transfer completed. REFERENCE: TXN-ABC-12345 debited from account",
            amount: -300
        )
        #expect(result.metadata["reference_number"] != nil)
    }

    // MARK: - No Transfer

    @Test func emptyText() {
        let result = TransferDetector.detectTransfer(in: "", amount: nil)
        #expect(!result.isTransfer)
        #expect(result.transferType == nil)
        #expect(result.confidence == 0)
    }

    @Test func regularPurchase() {
        let result = TransferDetector.detectTransfer(
            in: "Thank you for your purchase at Store ABC. Item: Widget, Price: $29.99",
            amount: -29.99
        )
        #expect(!result.isTransfer)
    }

    // MARK: - Loan

    @Test func loanRepayment() {
        let result = TransferDetector.detectTransfer(
            in: "LOAN REPAYMENT: Your EMI payment of $500 has been debited",
            amount: -500
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "loan_transfer")
        #expect(result.transferSubtype == "repayment")
    }

    // MARK: - Crypto

    @Test func cryptoTransfer() {
        let result = TransferDetector.detectTransfer(
            in: "CRYPTO TRANSFER: BTC TRANSFER to wallet 0x1234567890abcdef1234567890abcdef12345678",
            amount: nil
        )
        #expect(result.isTransfer)
        #expect(result.transferType == "crypto_transfer")
        #expect(result.paymentSystem == "CRYPTO")
    }
}
