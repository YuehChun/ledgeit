import SwiftUI

struct AmountText: View {
    let amount: Double
    let currency: String
    let type: String?

    init(amount: Double, currency: String = "USD", type: String? = nil) {
        self.amount = amount
        self.currency = currency
        self.type = type
    }

    var body: some View {
        Text(formattedAmount)
            .fontWeight(.semibold)
            .foregroundStyle(amountColor)
            .monospacedDigit()
    }

    private var formattedAmount: String {
        let prefix = isCredit ? "+" : "-"
        return "\(prefix)\(currency) \(String(format: "%.2f", abs(amount)))"
    }

    private var isCredit: Bool {
        type?.lowercased() == "credit" || type?.lowercased() == "income"
    }

    private var amountColor: Color {
        isCredit ? .green : .primary
    }
}
