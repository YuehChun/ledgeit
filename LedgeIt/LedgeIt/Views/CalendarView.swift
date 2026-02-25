import SwiftUI
import GRDB

struct CalendarView: View {
    @State private var transactions: [Transaction] = []
    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var cancellable: AnyDatabaseCancellable?

    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    private let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy (EEEE)"
        return f
    }()

    private var transactionsByDate: [String: [Transaction]] {
        Dictionary(grouping: transactions) { tx in
            tx.transactionDate ?? ""
        }
    }

    private var datesWithTransactions: Set<String> {
        Set(transactionsByDate.keys)
    }

    private var selectedDateTransactions: [Transaction] {
        let key = dayFormatter.string(from: selectedDate)
        return transactionsByDate[key] ?? []
    }

    // Month stats
    private var monthTransactions: [Transaction] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let monthStr = String(dayFormatter.string(from: monthStart).prefix(7))
        return transactions.filter { ($0.transactionDate ?? "").hasPrefix(monthStr) }
    }

    private var monthSpending: Double {
        monthTransactions.filter { $0.type?.lowercased() != "credit" }.reduce(0.0) { $0 + abs($1.amount) }
    }

    private var monthIncome: Double {
        monthTransactions.filter { $0.type?.lowercased() == "credit" }.reduce(0.0) { $0 + abs($1.amount) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: month navigation + summary
            headerBar
            Divider()

            // Main content: calendar left, transactions right
            HStack(spacing: 0) {
                // Left: calendar grid
                ScrollView {
                    VStack(spacing: 0) {
                        calendarGrid
                            .padding(16)
                    }
                }
                .frame(width: 340)
                .background(.background)

                Divider()

                // Right: selected day transactions
                selectedDayDetail
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Calendar")
        .onAppear { startObservation() }
        .onDisappear { cancellable?.cancel() }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            // Month navigation
            HStack(spacing: 12) {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(monthFormatter.string(from: displayedMonth))
                    .font(.headline)
                    .frame(width: 160)

                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Button("Today") {
                    displayedMonth = Date()
                    selectedDate = Date()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            // Month summary stats inline
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(.red.opacity(0.7)).frame(width: 6, height: 6)
                    Text(String(format: "%.0f", monthSpending))
                        .font(.callout)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }
                HStack(spacing: 4) {
                    Circle().fill(.green.opacity(0.7)).frame(width: 6, height: 6)
                    Text(String(format: "%.0f", monthIncome))
                        .font(.callout)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
                Text("\(monthTransactions.count) txns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let weeks = weeksInMonth(displayedMonth)
        let cellSize: CGFloat = 42

        return VStack(spacing: 2) {
            // Weekday headers
            HStack(spacing: 2) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: cellSize, height: 20)
                }
            }

            // Day cells
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { index in
                        if index < week.count {
                            dayCell(week[index], size: cellSize)
                        } else {
                            Color.clear.frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func dayCell(_ date: Date?, size: CGFloat) -> some View {
        Group {
            if let date {
                let dateStr = dayFormatter.string(from: date)
                let isToday = calendar.isDateInToday(date)
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let hasTxns = datesWithTransactions.contains(dateStr)

                Button {
                    selectedDate = date
                } label: {
                    VStack(spacing: 2) {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(isToday ? .bold : .regular)
                            .foregroundStyle(isSelected ? .white : isToday ? .blue : .primary)

                        if hasTxns {
                            let txns = transactionsByDate[dateStr] ?? []
                            let uniqueCats = Array(Set(txns.compactMap(\.category))).prefix(3)
                            HStack(spacing: 2) {
                                ForEach(Array(uniqueCats.enumerated()), id: \.offset) { _, cat in
                                    Circle()
                                        .fill(isSelected ? .white.opacity(0.8) : CategoryStyle.style(forRawCategory: cat).color)
                                        .frame(width: 4, height: 4)
                                }
                            }
                        } else {
                            Color.clear.frame(height: 4)
                        }
                    }
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? .blue : isToday ? .blue.opacity(0.08) : .clear)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: size, height: size)
            }
        }
    }

    // MARK: - Selected Day Detail

    private var selectedDayDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date header
            HStack {
                Text(shortDateFormatter.string(from: selectedDate))
                    .font(.headline)
                Spacer()
                if !selectedDateTransactions.isEmpty {
                    let dayTotal = selectedDateTransactions.reduce(0.0) { sum, tx in
                        let sign: Double = tx.type?.lowercased() == "credit" ? 1 : -1
                        return sum + sign * abs(tx.amount)
                    }
                    Text(String(format: "Net: %.0f", dayTotal))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(dayTotal >= 0 ? .green : .red)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if selectedDateTransactions.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 32))
                            .foregroundStyle(.quaternary)
                        Text("No transactions on this day")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(selectedDateTransactions) { tx in
                            HStack(spacing: 10) {
                                if let cat = tx.category {
                                    CategoryIcon(category: cat, size: 24)
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(tx.type?.lowercased() == "credit" ? .green : .red.opacity(0.6))
                                        .frame(width: 3, height: 32)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.merchant ?? "Unknown")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    if let desc = tx.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 8)

                                if let category = tx.category {
                                    CategoryBadge(category: category)
                                }

                                AmountText(amount: tx.amount, currency: tx.currency, type: tx.type)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                            Divider()
                                .padding(.leading, 29)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func changeMonth(_ delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func weeksInMonth(_ monthDate: Date) -> [[Date?]] {
        let comps = calendar.dateComponents([.year, .month], from: monthDate)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        var weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth) - 2
        if weekdayOfFirst < 0 { weekdayOfFirst += 7 }

        var days: [Date?] = Array(repeating: nil, count: weekdayOfFirst)

        for day in range {
            if let date = calendar.date(bySetting: .day, value: day, of: firstOfMonth) {
                days.append(date)
            }
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    // MARK: - Observation

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> [Transaction] in
            try Transaction
                .filter(Transaction.Columns.transactionDate != nil)
                .order(Transaction.Columns.transactionDate.desc)
                .fetchAll(db)
        }

        cancellable = observation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { error in
            print("Calendar observation error: \(error)")
        } onChange: { newTransactions in
            transactions = newTransactions
        }
    }
}
