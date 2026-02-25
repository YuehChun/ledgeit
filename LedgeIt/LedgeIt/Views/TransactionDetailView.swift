import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.merchant ?? "Transaction")
                            .font(.title3)
                            .fontWeight(.bold)
                        if let date = transaction.transactionDate {
                            Text(date)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 16)
                    AmountText(amount: transaction.amount, currency: transaction.currency, type: transaction.type)
                        .font(.title3)
                }

                Divider()

                // Details
                VStack(alignment: .leading, spacing: 8) {
                    if let category = transaction.category {
                        detailRow("Category") {
                            HStack(spacing: 8) {
                                CategoryIcon(category: category, size: 28)
                                VStack(alignment: .trailing, spacing: 2) {
                                    CategoryBadge(category: category)
                                    if CategoryStyle.style(forRawCategory: category).isFinancialObligation {
                                        Text("Financial Obligation")
                                            .font(.caption2)
                                            .foregroundStyle(CategoryStyle.style(forRawCategory: category).color)
                                    }
                                }
                            }
                        }
                    }
                    if let type = transaction.type {
                        detailRow("Type", value: type.capitalized)
                    }
                    detailRow("Currency", value: transaction.currency)
                    if let transferType = transaction.transferType {
                        detailRow("Transfer Type", value: transferType)
                    }
                }

                if let description = transaction.description, !description.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(description)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 280, maxWidth: .infinity)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        detailRow(label) {
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func detailRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .font(.callout)
    }
}
