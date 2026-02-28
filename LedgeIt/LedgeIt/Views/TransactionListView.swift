import SwiftUI
import GRDB

struct TransactionListView: View {
    @State private var transactions: [Transaction] = []
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var selectedTransaction: Transaction?
    @State private var cancellable: AnyDatabaseCancellable?

    private let categories = [
        "FOOD_AND_DRINK", "GROCERIES", "ENTERTAINMENT", "TRAVEL",
        "HEALTHCARE", "PERSONAL_CARE", "EDUCATION", "CHARITY",
        "BANK_FEES_AND_CHARGES", "UTILITIES", "INSURANCE",
        "INVESTMENTS", "SHOPPING", "TRANSPORT", "GENERAL"
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Left: transaction list
            VStack(spacing: 0) {
                // Filter bar
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.callout)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                    Picker("Category", selection: $selectedCategory) {
                        Text("All").tag(nil as String?)
                        Divider()
                        ForEach(categories, id: \.self) { cat in
                            Text(CategoryStyle.style(forRawCategory: cat).displayName)
                                .tag(cat as String?)
                        }
                    }
                    .frame(width: 150)

                    Text("\(transactions.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()

                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "creditcard",
                        description: Text("Transactions appear after processing emails.")
                    )
                } else {
                    List(transactions, selection: $selectedTransaction) { tx in
                        TransactionRow(transaction: tx)
                            .tag(tx)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(width: 400)

            Divider()

            // Right: detail
            if let tx = selectedTransaction {
                TransactionDetailView(transaction: tx)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .font(.title)
                        .foregroundStyle(.quaternary)
                    Text("Select a transaction")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Transactions")
        .onAppear { startObservation() }
        .onChange(of: searchText) { _, _ in startObservation() }
        .onChange(of: selectedCategory) { _, _ in startObservation() }
        .onDisappear { cancellable?.cancel() }
    }

    private func startObservation() {
        let category = selectedCategory
        let search = searchText.isEmpty ? nil : searchText

        let observation = ValueObservation.tracking { db -> [Transaction] in
            var query = Transaction.all()
            if let category {
                query = query.filter(Transaction.Columns.category == category)
            }
            if let search {
                let pattern = "%\(search)%"
                query = query.filter(
                    Transaction.Columns.merchant.like(pattern) ||
                    Transaction.Columns.description.like(pattern)
                )
            }
            return try query
                .order(Transaction.Columns.transactionDate.desc)
                .limit(500)
                .fetchAll(db)
        }

        cancellable = observation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { error in
            print("Transaction observation error: \(error)")
        } onChange: { newTransactions in
            transactions = newTransactions
        }
    }

}

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 6, height: 6)

            if let category = transaction.category {
                CategoryIcon(category: category, size: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant ?? "Unknown Merchant")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let date = transaction.transactionDate {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let category = transaction.category {
                        CategoryBadge(category: category)
                    }
                }
            }
            Spacer(minLength: 8)
            AmountText(amount: transaction.amount, currency: transaction.currency, type: transaction.type)
        }
        .padding(.vertical, 2)
        .listRowBackground(
            (transaction.confidence ?? 1.0) < 0.7
                ? Color.yellow.opacity(0.06)
                : Color.clear
        )
    }

    private var confidenceColor: Color {
        let conf = transaction.confidence ?? 1.0
        if conf >= 0.8 { return .green }
        if conf >= 0.5 { return .yellow }
        return .red
    }
}
