import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    @State private var isEditing = false
    @State private var editAmount: String = ""
    @State private var editMerchant: String = ""
    @State private var editCategory: String = ""
    @State private var editDate: String = ""
    @State private var editType: String = ""
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    private let categories = AutoCategorizer.LeanCategory.allCases.map(\.rawValue)
    private let types = ["debit", "credit", "transfer"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.merchant ?? "Transaction")
                            .font(.title3).fontWeight(.bold)
                        if let date = transaction.transactionDate {
                            Text(date).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 16)
                    HStack(spacing: 8) {
                        confidenceBadge
                        AmountText(amount: transaction.amount, currency: transaction.currency, type: transaction.type)
                            .font(.title3)
                    }
                }

                Divider()

                if isEditing {
                    editForm
                } else {
                    detailContent

                    Divider()

                    Button {
                        startEditing()
                    } label: {
                        Label(l10n.editTransaction, systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 280, maxWidth: .infinity)
    }

    private var confidenceBadge: some View {
        let conf = transaction.confidence ?? 1.0
        let color: Color = conf >= 0.8 ? .green : conf >= 0.5 ? .yellow : .red
        let label = conf >= 0.8 ? l10n.highConfidence : conf >= 0.5 ? l10n.mediumConfidence : l10n.lowConfidence

        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let category = transaction.category {
                detailRow(l10n.category) {
                    HStack(spacing: 8) {
                        CategoryIcon(category: category, size: 28)
                        CategoryBadge(category: category)
                    }
                }
            }
            if let type = transaction.type {
                detailRow(l10n.type, value: type.capitalized)
            }
            detailRow("Currency", value: transaction.currency)
            if let transferType = transaction.transferType {
                detailRow("Transfer Type", value: transferType)
            }

            if let description = transaction.description, !description.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption).foregroundStyle(.secondary)
                    Text(description).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldGroup(l10n.amount) {
                TextField("0.00", text: $editAmount)
                    .textFieldStyle(.roundedBorder)
            }
            fieldGroup(l10n.merchant) {
                TextField("Merchant name", text: $editMerchant)
                    .textFieldStyle(.roundedBorder)
            }
            fieldGroup(l10n.category) {
                Picker(l10n.category, selection: $editCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(CategoryStyle.style(forRawCategory: cat).displayName).tag(cat)
                    }
                }
            }
            fieldGroup(l10n.date) {
                TextField("YYYY-MM-DD", text: $editDate)
                    .textFieldStyle(.roundedBorder)
            }
            fieldGroup(l10n.type) {
                Picker(l10n.type, selection: $editType) {
                    ForEach(types, id: \.self) { t in
                        Text(t.capitalized).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            HStack(spacing: 12) {
                Button(l10n.save) { saveEdits() }
                    .buttonStyle(.borderedProminent)
                Button(l10n.cancel) { isEditing = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button(role: .destructive) { flagAsIncorrect() } label: {
                    Label(l10n.flagIncorrect, systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    private func startEditing() {
        editAmount = String(format: "%.2f", transaction.amount)
        editMerchant = transaction.merchant ?? ""
        editCategory = transaction.category ?? "GENERAL"
        editDate = transaction.transactionDate ?? ""
        editType = transaction.type ?? "debit"
        isEditing = true
    }

    private func saveEdits() {
        guard let txId = transaction.id else { return }
        let amount = editAmount
        let merchant = editMerchant
        let category = editCategory
        let date = editDate
        let type = editType
        Task {
            try? await AppDatabase.shared.db.write { db in
                if var tx = try Transaction.fetchOne(db, key: txId) {
                    if let newAmount = Double(amount) { tx.amount = newAmount }
                    tx.merchant = merchant.isEmpty ? nil : merchant
                    tx.category = category
                    tx.transactionDate = date.isEmpty ? nil : date
                    tx.type = type
                    try tx.update(db)
                }
            }
            isEditing = false
        }
    }

    private func flagAsIncorrect() {
        guard let txId = transaction.id else { return }
        Task {
            try? await AppDatabase.shared.db.write { db in
                if var tx = try Transaction.fetchOne(db, key: txId) {
                    tx.confidence = 0
                    try tx.update(db)
                }
            }
            isEditing = false
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary).fontWeight(.medium)
            content()
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        detailRow(label) { Text(value).fontWeight(.medium) }
    }

    private func detailRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .font(.callout)
    }
}
