import SwiftUI
import GRDB

struct TransactionReviewView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var groupedData: [EmailGroup] = []
    @State private var cancellable: AnyDatabaseCancellable?
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .unreviewed
    @State private var expandedEmails: Set<String> = []
    @State private var deleteTarget: Transaction?
    @State private var showDeleteConfirm = false

    enum FilterMode: String, CaseIterable {
        case unreviewed, reviewed, all
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.transactionReview)
                        .font(.title2)
                        .fontWeight(.bold)
                    let unreviewedTotal = groupedData.filter { !$0.isAllReviewed }.reduce(0) { $0 + $1.transactions.count }
                    Text(l10n.unreviewedCount(unreviewedTotal))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(l10n.markAllReviewed) {
                    markAllReviewed()
                }
                .buttonStyle(.bordered)
                .disabled(groupedData.allSatisfy { $0.isAllReviewed })
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

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

                Picker("Filter", selection: $filterMode) {
                    Text(l10n.filterUnreviewed).tag(FilterMode.unreviewed)
                    Text(l10n.filterReviewed).tag(FilterMode.reviewed)
                    Text(l10n.all).tag(FilterMode.all)
                }
                .frame(width: 140)

                Text("\(groupedData.reduce(0) { $0 + $1.transactions.count })")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Content
            if groupedData.isEmpty {
                ContentUnavailableView(
                    l10n.noUnreviewedTransactions,
                    systemImage: "checkmark.seal.fill",
                    description: Text(l10n.noUnreviewedDescription)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groupedData) { group in
                            EmailGroupCard(
                                group: group,
                                l10n: l10n,
                                isExpanded: expandedEmails.contains(group.id),
                                onToggleExpand: { toggleExpand(group.id) },
                                onMarkReviewed: { markEmailReviewed(group) },
                                onDeleteTransaction: { tx in
                                    deleteTarget = tx
                                    showDeleteConfirm = true
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(l10n.review)
        .onAppear { startObservation() }
        .onChange(of: searchText) { _, _ in startObservation() }
        .onChange(of: filterMode) { _, _ in startObservation() }
        .onDisappear { cancellable?.cancel() }
        .alert(l10n.deleteConfirmTitle, isPresented: $showDeleteConfirm, presenting: deleteTarget) { tx in
            Button(l10n.deleteTransaction, role: .destructive) {
                deleteTransaction(tx)
            }
            Button(l10n.cancel, role: .cancel) {}
        } message: { _ in
            Text(l10n.deleteConfirmMessage)
        }
    }

    // MARK: - Observation

    private func startObservation() {
        let filter = filterMode
        let search = searchText.isEmpty ? nil : searchText

        let observation = ValueObservation.tracking { db -> [EmailGroup] in
            var txQuery = Transaction.all()
            switch filter {
            case .unreviewed:
                txQuery = txQuery.filter(Transaction.Columns.isReviewed == false)
            case .reviewed:
                txQuery = txQuery.filter(Transaction.Columns.isReviewed == true)
            case .all:
                break
            }

            if let search {
                let pattern = "%\(search)%"
                txQuery = txQuery.filter(
                    Transaction.Columns.merchant.like(pattern) ||
                    Transaction.Columns.description.like(pattern)
                )
            }

            let transactions = try txQuery
                .order(Transaction.Columns.transactionDate.desc)
                .fetchAll(db)

            // Group by emailId
            let grouped = Dictionary(grouping: transactions) { $0.emailId ?? "no-email" }

            // Fetch associated emails
            let emailIds = Set(transactions.compactMap { $0.emailId })
            let emails: [String: Email]
            if !emailIds.isEmpty {
                let emailRows = try Email
                    .filter(emailIds.contains(Email.Columns.id))
                    .fetchAll(db)
                emails = Dictionary(uniqueKeysWithValues: emailRows.map { ($0.id, $0) })
            } else {
                emails = [:]
            }

            // Build groups sorted by most recent transaction date
            return grouped.map { emailId, txs in
                let email = emails[emailId]
                return EmailGroup(
                    emailId: emailId,
                    email: email,
                    transactions: txs.sorted { ($0.transactionDate ?? "") > ($1.transactionDate ?? "") }
                )
            }
            .sorted { $0.latestDate > $1.latestDate }
        }

        cancellable = observation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { error in
            print("Review observation error: \(error)")
        } onChange: { newData in
            groupedData = newData
        }
    }

    // MARK: - Actions

    private func toggleExpand(_ emailId: String) {
        if expandedEmails.contains(emailId) {
            expandedEmails.remove(emailId)
        } else {
            expandedEmails.insert(emailId)
        }
    }

    private func deleteTransaction(_ tx: Transaction) {
        guard let id = tx.id else { return }
        do {
            try AppDatabase.shared.db.write { db in
                _ = try Transaction.deleteOne(db, id: id)
            }
        } catch {
            print("Failed to delete transaction: \(error)")
        }
    }

    private func markEmailReviewed(_ group: EmailGroup) {
        let ids = group.transactions.compactMap { $0.id }
        guard !ids.isEmpty else { return }
        do {
            try AppDatabase.shared.db.write { db in
                try Transaction
                    .filter(ids.contains(Transaction.Columns.id))
                    .updateAll(db, Transaction.Columns.isReviewed.set(to: true))
            }
        } catch {
            print("Failed to mark reviewed: \(error)")
        }
    }

    private func markAllReviewed() {
        let allIds = groupedData.flatMap { $0.transactions.compactMap { $0.id } }
        guard !allIds.isEmpty else { return }
        do {
            try AppDatabase.shared.db.write { db in
                try Transaction
                    .filter(allIds.contains(Transaction.Columns.id))
                    .updateAll(db, Transaction.Columns.isReviewed.set(to: true))
            }
        } catch {
            print("Failed to mark all reviewed: \(error)")
        }
    }
}

// MARK: - Data Models

struct EmailGroup: Identifiable {
    let emailId: String
    let email: Email?
    let transactions: [Transaction]

    var id: String { emailId }

    var isAllReviewed: Bool {
        transactions.allSatisfy { $0.isReviewed }
    }

    var latestDate: String {
        transactions.first?.transactionDate ?? ""
    }
}

// MARK: - Email Group Card

private struct EmailGroupCard: View {
    let group: EmailGroup
    let l10n: L10n
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onMarkReviewed: () -> Void
    let onDeleteTransaction: (Transaction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Email header
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.blue)
                    .font(.callout)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.email?.sender ?? "Unknown sender")
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(group.email?.subject ?? "No subject")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(l10n.transactionsFromEmail(group.transactions.count))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let date = group.email?.date {
                    Text(date.prefix(10))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Transactions
            ForEach(group.transactions) { tx in
                HStack(spacing: 8) {
                    if let category = tx.category {
                        CategoryIcon(category: category, size: 22)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.merchant ?? "Unknown")
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let date = tx.transactionDate {
                                Text(date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let category = tx.category {
                                CategoryBadge(category: category)
                            }
                            if tx.isReviewed {
                                Text("\u{2713}")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .foregroundStyle(.green)
                                    .background(.green.opacity(0.1), in: Capsule())
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    AmountText(amount: tx.amount, currency: tx.currency, type: tx.type)

                    Button(role: .destructive) {
                        onDeleteTransaction(tx)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 1)
            }

            // Actions row
            HStack {
                Button {
                    onToggleExpand()
                } label: {
                    Label(
                        isExpanded ? l10n.hideOriginalEmail : l10n.viewOriginalEmail,
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                if !group.isAllReviewed {
                    Button(l10n.markReviewed) {
                        onMarkReviewed()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Expanded email body
            if isExpanded, let bodyText = group.email?.bodyText {
                Text(bodyText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
