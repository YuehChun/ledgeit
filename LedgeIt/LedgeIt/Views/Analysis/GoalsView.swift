import SwiftUI
import GRDB

struct GoalsView: View {
    @State private var goals: [FinancialGoal] = []
    @State private var filter: GoalFilter = .active
    @State private var cancellable: AnyDatabaseCancellable?

    enum GoalFilter: String, CaseIterable {
        case active = "Active"
        case suggested = "Suggested"
        case completed = "Completed"
        case all = "All"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Financial Goals")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Picker("Filter", selection: $filter) {
                    ForEach(GoalFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if goals.isEmpty {
                ContentUnavailableView(
                    "No Goals",
                    systemImage: "target",
                    description: Text("Generate a financial analysis to get AI-suggested goals.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        let shortTerm = goals.filter { $0.type == "short_term" }
                        let longTerm = goals.filter { $0.type == "long_term" }

                        if !shortTerm.isEmpty {
                            goalSection(title: "Short-Term Goals (1-3 months)", goals: shortTerm)
                        }
                        if !longTerm.isEmpty {
                            goalSection(title: "Long-Term Goals (1-3 years)", goals: longTerm)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Goals")
        .onAppear { startObservation() }
        .onDisappear { cancellable?.cancel() }
        .onChange(of: filter) { _, _ in loadGoals() }
    }

    private func goalSection(title: String, goals: [FinancialGoal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            ForEach(goals, id: \.id) { goal in
                goalCard(goal)
            }
        }
    }

    private func goalCard(_ goal: FinancialGoal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: goalIcon(goal.category ?? "savings"))
                    .foregroundStyle(goalColor(goal.category ?? "savings"))
                Text(goal.title)
                    .font(.callout).fontWeight(.semibold)
                Spacer()
                statusBadge(goal.status)
            }

            Text(goal.description)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let amount = goal.targetAmount {
                    Label("\(String(format: "%.0f", amount))", systemImage: "dollarsign.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let date = goal.targetDate {
                    Label(date.prefix(10).description, systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                if goal.status == "suggested" {
                    Button("Accept") { updateStatus(goal.id, "accepted") }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button("Dismiss") { updateStatus(goal.id, "dismissed") }
                        .buttonStyle(.plain).controlSize(.mini)
                        .foregroundStyle(.secondary)
                } else if goal.status == "accepted" {
                    Button("Complete") { updateStatus(goal.id, "completed") }
                        .buttonStyle(.borderedProminent).controlSize(.mini)
                }
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor(status), in: Capsule())
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "suggested": return .blue
        case "accepted": return .orange
        case "completed": return .green
        case "dismissed": return .gray
        default: return .secondary
        }
    }

    private func goalIcon(_ category: String) -> String {
        switch category {
        case "savings": return "banknote"
        case "budget": return "chart.pie"
        case "investment": return "chart.line.uptrend.xyaxis"
        case "debt": return "creditcard"
        default: return "target"
        }
    }

    private func goalColor(_ category: String) -> Color {
        switch category {
        case "savings": return .green
        case "budget": return .orange
        case "investment": return .blue
        case "debt": return .red
        default: return .secondary
        }
    }

    private func updateStatus(_ id: String, _ status: String) {
        Task {
            try await AppDatabase.shared.db.write { db in
                if var goal = try FinancialGoal.fetchOne(db, key: id) {
                    goal.status = status
                    try goal.update(db)
                }
            }
        }
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> Int in
            try FinancialGoal.fetchCount(db)
        }
        cancellable = observation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { _ in } onChange: { _ in loadGoals() }
    }

    private func loadGoals() {
        do {
            goals = try AppDatabase.shared.db.read { db in
                var query = FinancialGoal.all()
                switch filter {
                case .active:
                    query = query.filter(FinancialGoal.Columns.status == "accepted")
                case .suggested:
                    query = query.filter(FinancialGoal.Columns.status == "suggested")
                case .completed:
                    query = query.filter(FinancialGoal.Columns.status == "completed")
                case .all:
                    break
                }
                return try query.order(FinancialGoal.Columns.createdAt.desc).fetchAll(db)
            }
        } catch {
            print("GoalsView: failed to load goals: \(error.localizedDescription)")
        }
    }
}
