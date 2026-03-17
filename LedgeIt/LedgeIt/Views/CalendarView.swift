import SwiftUI
import GRDB

struct CalendarView: View {
    @State private var transactions: [Transaction] = []
    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var cancellable: AnyDatabaseCancellable?
    @State private var bills: [CreditCardBill] = []
    @State private var billCancellable: AnyDatabaseCancellable?
    @State private var diaryEntries: [SpendingDiaryEntry] = []
    @State private var diaryCancellable: AnyDatabaseCancellable?

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

    private var transactionsByDate: [String: [Transaction]] {
        Dictionary(grouping: transactions) { tx in
            tx.transactionDate ?? ""
        }
    }

    private var billsByDate: [String: [CreditCardBill]] {
        Dictionary(grouping: bills, by: { $0.dueDate })
    }

    private var datesWithTransactions: Set<String> {
        Set(transactionsByDate.keys)
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

    // MARK: - Diary Helpers

    private var diaryEntryForSelectedDate: SpendingDiaryEntry? {
        let dateString = dayFormatter.string(from: selectedDate)
        return diaryEntries.first { $0.date == dateString }
    }

    private var monthPrefix: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: displayedMonth)
    }

    private func dateFromString(_ string: String) -> Date? {
        dayFormatter.date(from: string)
    }

    private func hasDiaryEntry(for date: Date) -> Bool {
        let dateString = dayFormatter.string(from: date)
        return diaryEntries.contains { $0.date == dateString && $0.status == "completed" }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: month navigation + summary
            headerBar
            Divider()

            // Main content: compact calendar left, diary panel right
            HStack(alignment: .top, spacing: 0) {
                // Left: Compact calendar + month stats
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            calendarGrid
                                .padding(12)
                        }
                    }

                    Divider()

                    monthOverviewStats
                }
                .frame(width: 260)

                Divider()

                // Right: Diary panel
                DiaryPanelView(
                    selectedDate: selectedDate,
                    transactions: transactions,
                    bills: bills,
                    diaryEntry: diaryEntryForSelectedDate,
                    onRegenerate: { date in
                        Task {
                            await SpendingDiaryService.shared.regenerateEntry(for: date)
                        }
                    }
                )
            }
        }
        .navigationTitle("Calendar")
        .onAppear {
            startObservation()
            observeDiaryEntries()
        }
        .onDisappear {
            cancellable?.cancel()
            billCancellable?.cancel()
            diaryCancellable?.cancel()
        }
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
        let cellSize: CGFloat = 32

        return VStack(spacing: 2) {
            // Weekday headers
            HStack(spacing: 2) {
                ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: cellSize, height: 16)
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
                    VStack(spacing: 1) {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 12, design: .rounded))
                            .fontWeight(isToday ? .bold : .regular)
                            .foregroundStyle(isSelected ? .white : isToday ? .blue : .primary)

                        HStack(spacing: 2) {
                            if hasTxns {
                                let txns = transactionsByDate[dateStr] ?? []
                                let uniqueCats = Array(Set(txns.compactMap(\.category))).prefix(2)
                                ForEach(Array(uniqueCats.enumerated()), id: \.offset) { _, cat in
                                    Circle()
                                        .fill(isSelected ? .white.opacity(0.8) : CategoryStyle.style(forRawCategory: cat).color)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            if let dayBills = billsByDate[dateStr], !dayBills.isEmpty {
                                let billColor: Color = {
                                    if dayBills.allSatisfy({ $0.isPaid }) { return .green }
                                    let fmt = DateFormatter()
                                    fmt.dateFormat = "yyyy-MM-dd"
                                    if let d = fmt.date(from: dateStr),
                                       d < Calendar.current.startOfDay(for: Date()) { return .red }
                                    return .orange
                                }()
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(isSelected ? .white.opacity(0.8) : billColor)
                            }
                            if hasDiaryEntry(for: date) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
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

    // MARK: - Month Overview Stats

    @ViewBuilder
    private var monthOverviewStats: some View {
        let monthTxns = transactions.filter { tx in
            guard let txDate = dateFromString(tx.transactionDate ?? "") else { return false }
            return calendar.isDate(txDate, equalTo: displayedMonth, toGranularity: .month)
        }
        let totalSpending = monthTxns.filter { $0.type?.lowercased() != "credit" }.reduce(0.0) { $0 + abs($1.amount) }
        let diaryCount = diaryEntries.filter { $0.date.hasPrefix(monthPrefix) && $0.status == "completed" }.count
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        let dailyAvg = totalSpending / Double(max(1, daysInMonth))

        VStack(alignment: .leading, spacing: 6) {
            Text("Monthly Overview")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LabeledContent("Total Spending", value: "$\(String(format: "%.0f", totalSpending))")
                .font(.caption)
            LabeledContent("Diary Entries", value: "\(diaryCount)")
                .font(.caption)
            LabeledContent("Daily Avg", value: "$\(String(format: "%.0f", dailyAvg))")
                .font(.caption)
        }
        .padding(12)
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

        let billObservation = ValueObservation.tracking { db -> [CreditCardBill] in
            try CreditCardBill
                .order(CreditCardBill.Columns.dueDate.asc)
                .fetchAll(db)
        }

        billCancellable = billObservation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { error in
            print("Bill observation error: \(error)")
        } onChange: { newBills in
            bills = newBills
        }
    }

    private func observeDiaryEntries() {
        diaryCancellable = ValueObservation
            .tracking { db in
                try SpendingDiaryEntry
                    .order(SpendingDiaryEntry.Columns.date.desc)
                    .fetchAll(db)
            }
            .start(in: AppDatabase.shared.db, onError: { _ in }, onChange: { entries in
                diaryEntries = entries
            })
    }
}
