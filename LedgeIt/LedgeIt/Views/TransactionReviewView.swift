import SwiftUI
import GRDB

struct TransactionReviewView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var groupedData: [EmailGroup] = []
    @State private var cancellable: AnyDatabaseCancellable?
    @State private var countCancellable: AnyDatabaseCancellable?
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .unreviewed
    @State private var expandedEmails: Set<String> = []
    @State private var totalUnreviewed: Int = 0

    enum FilterMode: String, CaseIterable {
        case unreviewed, reviewed, deleted, all
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.transactionReview)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(l10n.unreviewedCount(totalUnreviewed))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(l10n.markAllReviewed) {
                    markAllReviewed()
                }
                .buttonStyle(.bordered)
                .disabled(filterMode == .deleted || groupedData.allSatisfy { $0.isAllReviewed })
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
                    Text(l10n.filterDeleted).tag(FilterMode.deleted)
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
                if filterMode == .deleted {
                    ContentUnavailableView(
                        l10n.noDeletedTransactions,
                        systemImage: "trash.slash",
                        description: Text(l10n.noDeletedDescription)
                    )
                } else {
                    ContentUnavailableView(
                        l10n.noUnreviewedTransactions,
                        systemImage: "checkmark.seal.fill",
                        description: Text(l10n.noUnreviewedDescription)
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groupedData) { group in
                            EmailGroupCard(
                                group: group,
                                l10n: l10n,
                                isExpanded: expandedEmails.contains(group.id),
                                isDeletedView: filterMode == .deleted,
                                onToggleExpand: { toggleExpand(group.id) },
                                onMarkReviewed: { markEmailReviewed(group) },
                                onDeleteTransaction: { tx in softDeleteTransaction(tx) },
                                onRestoreTransaction: { tx in restoreTransaction(tx) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(l10n.review)
        .onAppear {
            purgeExpiredDeletes()
            startObservation()
        }
        .onChange(of: searchText) { _, _ in startObservation() }
        .onChange(of: filterMode) { _, _ in startObservation() }
        .onDisappear { cancellable?.cancel(); countCancellable?.cancel() }
    }

    // MARK: - Observation

    private func startObservation() {
        let filter = filterMode
        let search = searchText.isEmpty ? nil : searchText

        let observation = ValueObservation.tracking { db -> [EmailGroup] in
            var txQuery = Transaction.all()
            switch filter {
            case .unreviewed:
                txQuery = txQuery.filter(Transaction.Columns.deletedAt == nil)
                    .filter(Transaction.Columns.isReviewed == false)
            case .reviewed:
                txQuery = txQuery.filter(Transaction.Columns.deletedAt == nil)
                    .filter(Transaction.Columns.isReviewed == true)
            case .deleted:
                txQuery = txQuery.filter(Transaction.Columns.deletedAt != nil)
            case .all:
                txQuery = txQuery.filter(Transaction.Columns.deletedAt == nil)
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
                .limit(500)
                .fetchAll(db)

            let grouped = Dictionary(grouping: transactions) { $0.emailId ?? "no-email" }

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

        let countObservation = ValueObservation.tracking { db -> Int in
            try Transaction
                .filter(Transaction.Columns.isReviewed == false)
                .filter(Transaction.Columns.deletedAt == nil)
                .fetchCount(db)
        }
        countCancellable = countObservation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { error in
            print("Count observation error: \(error)")
        } onChange: { count in
            totalUnreviewed = count
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

    private func softDeleteTransaction(_ tx: Transaction) {
        guard let id = tx.id else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        do {
            try AppDatabase.shared.db.write { db in
                try Transaction
                    .filter(Transaction.Columns.id == id)
                    .updateAll(db, Transaction.Columns.deletedAt.set(to: now))
            }
        } catch {
            print("Failed to soft-delete transaction: \(error)")
        }
    }

    private func restoreTransaction(_ tx: Transaction) {
        guard let id = tx.id else { return }
        do {
            try AppDatabase.shared.db.write { db in
                try Transaction
                    .filter(Transaction.Columns.id == id)
                    .updateAll(db, Transaction.Columns.deletedAt.set(to: nil as String?))
            }
        } catch {
            print("Failed to restore transaction: \(error)")
        }
    }

    private func purgeExpiredDeletes() {
        let sevenDaysAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 24 * 3600))
        do {
            try AppDatabase.shared.db.write { db in
                try Transaction
                    .filter(Transaction.Columns.deletedAt != nil)
                    .filter(Transaction.Columns.deletedAt < sevenDaysAgo)
                    .deleteAll(db)
            }
        } catch {
            print("Failed to purge expired deletes: \(error)")
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
        do {
            try AppDatabase.shared.db.write { db in
                try Transaction
                    .filter(Transaction.Columns.isReviewed == false)
                    .filter(Transaction.Columns.deletedAt == nil)
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
    let isDeletedView: Bool
    let onToggleExpand: () -> Void
    let onMarkReviewed: () -> Void
    let onDeleteTransaction: (Transaction) -> Void
    let onRestoreTransaction: (Transaction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Email header
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.blue)
                    .font(.callout)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.email?.sender ?? l10n.unknownSender)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(group.email?.subject ?? l10n.noSubject)
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
                TransactionRow(
                    tx: tx,
                    l10n: l10n,
                    isDeletedView: isDeletedView,
                    onDelete: { onDeleteTransaction(tx) },
                    onRestore: { onRestoreTransaction(tx) }
                )
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
                .buttonStyle(.plain)

                Spacer()

                if !isDeletedView && !group.isAllReviewed {
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
                    .lineLimit(80)
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

// MARK: - Transaction Row

private struct TransactionRow: View {
    let tx: Transaction
    let l10n: L10n
    let isDeletedView: Bool
    let onDelete: () -> Void
    let onRestore: () -> Void

    private var daysLeft: Int? {
        guard let deletedAt = tx.deletedAt,
              let date = ISO8601DateFormatter().date(from: deletedAt) else { return nil }
        let purgeDate = date.addingTimeInterval(7 * 24 * 3600)
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: purgeDate).day ?? 0
        return max(0, remaining)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let category = tx.category {
                CategoryIcon(category: category, size: 22)
                    .opacity(isDeletedView ? 0.4 : 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.merchant ?? "Unknown")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .strikethrough(isDeletedView, color: .red)
                    .opacity(isDeletedView ? 0.5 : 1)
                HStack(spacing: 6) {
                    if let date = tx.transactionDate {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let category = tx.category {
                        CategoryBadge(category: category)
                    }
                    if tx.isReviewed && !isDeletedView {
                        Text("\u{2713}")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .foregroundStyle(.green)
                            .background(.green.opacity(0.1), in: Capsule())
                    }
                    if let days = daysLeft, isDeletedView {
                        Text(l10n.daysUntilPurge(days))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .foregroundStyle(.orange)
                            .background(.orange.opacity(0.1), in: Capsule())
                    }
                }
            }

            Spacer(minLength: 8)

            AmountText(amount: tx.amount, currency: tx.currency, type: tx.type)
                .opacity(isDeletedView ? 0.4 : 1)

            // Action button
            if isDeletedView {
                Button(l10n.restore) {
                    onRestore()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.blue)
            } else {
                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 13))
                        Text(l10n.deleteTransaction)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.red, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}
