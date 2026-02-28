import SwiftUI
import GRDB

struct GoalsView: View {
    @State private var goals: [FinancialGoal] = []
    @State private var filter: GoalFilter = .all
    @State private var hasInitializedFilter = false
    @State private var cancellable: AnyDatabaseCancellable?
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    enum GoalFilter: String, CaseIterable {
        case active = "Active"
        case suggested = "Suggested"
        case completed = "Completed"
        case all = "All"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(l10n.financialGoals)
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Picker(l10n.financialGoals, selection: $filter) {
                    Text(l10n.active).tag(GoalFilter.active)
                    Text(l10n.suggested).tag(GoalFilter.suggested)
                    Text(l10n.completed).tag(GoalFilter.completed)
                    Text(l10n.all).tag(GoalFilter.all)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if goals.isEmpty {
                Spacer()
                if filter == .all {
                    ContentUnavailableView(
                        l10n.noGoalsYet,
                        systemImage: "target",
                        description: Text(l10n.noGoalsDescription)
                    )
                } else {
                    let filterName: String = {
                        switch filter {
                        case .active: return l10n.active
                        case .suggested: return l10n.suggested
                        case .completed: return l10n.completed
                        case .all: return l10n.all
                        }
                    }()
                    ContentUnavailableView(
                        l10n.noGoalsForFilter(filterName),
                        systemImage: "target",
                        description: Text(l10n.noFilteredGoals)
                    )
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        let shortTerm = goals.filter { $0.type == "short_term" }
                        let longTerm = goals.filter { $0.type == "long_term" }

                        if !shortTerm.isEmpty {
                            goalSection(title: l10n.shortTermGoals, goals: shortTerm)
                        }
                        if !longTerm.isEmpty {
                            goalSection(title: l10n.longTermGoals, goals: longTerm)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            // Progress section for accepted/completed goals
            if goal.status == "accepted" || goal.status == "completed" {
                progressSection(goal)
            }

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
                    Button(l10n.accept) { updateStatus(goal.id, "accepted") }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button(l10n.dismiss) { updateStatus(goal.id, "dismissed") }
                        .buttonStyle(.plain).controlSize(.mini)
                        .foregroundStyle(.secondary)
                } else if goal.status == "accepted" {
                    Button(l10n.markComplete) { completeGoal(goal.id) }
                        .buttonStyle(.borderedProminent).controlSize(.mini)
                }
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Progress

    private func progressSection(_ goal: FinancialGoal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l10n.progress)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(goal.progress))%")
                    .font(.caption).fontWeight(.bold).monospacedDigit()
                    .foregroundStyle(goal.progress >= 100 ? .green : .primary)
            }

            if goal.status == "accepted" {
                Slider(value: progressBinding(for: goal.id), in: 0...100, step: 5)
                    .tint(progressColor(goal.progress))
                    .controlSize(.mini)
            } else {
                ProgressView(value: min(goal.progress, 100), total: 100)
                    .tint(.green)
            }
        }
    }

    private func progressColor(_ progress: Double) -> Color {
        if progress >= 80 { return .green }
        if progress >= 40 { return .orange }
        return .blue
    }

    private func progressBinding(for goalId: String) -> Binding<Double> {
        Binding(
            get: {
                goals.first(where: { $0.id == goalId })?.progress ?? 0
            },
            set: { newValue in
                if let idx = goals.firstIndex(where: { $0.id == goalId }) {
                    goals[idx].progress = newValue
                }
                saveProgress(goalId, newValue)
            }
        )
    }

    private func saveProgress(_ id: String, _ progress: Double) {
        let progressVal = progress
        Task {
            try? await AppDatabase.shared.db.write { db in
                if var g = try FinancialGoal.fetchOne(db, key: id) {
                    g.progress = progressVal
                    try g.update(db)
                }
            }
        }
    }

    private func completeGoal(_ id: String) {
        if let idx = goals.firstIndex(where: { $0.id == id }) {
            goals[idx].progress = 100
            goals[idx].status = "completed"
        }
        Task {
            try? await AppDatabase.shared.db.write { db in
                if var g = try FinancialGoal.fetchOne(db, key: id) {
                    g.progress = 100
                    g.status = "completed"
                    try g.update(db)
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusBadge(_ status: String) -> some View {
        let localizedStatus: String = {
            switch status {
            case "suggested": return l10n.suggested
            case "accepted": return l10n.active
            case "completed": return l10n.completed
            case "dismissed": return l10n.dismiss
            default: return status.capitalized
            }
        }()
        return Text(localizedStatus)
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
        loadGoals()
        if !hasInitializedFilter {
            hasInitializedFilter = true
            let suggestedCount = (try? AppDatabase.shared.db.read { db in
                try FinancialGoal.filter(FinancialGoal.Columns.status == "suggested").fetchCount(db)
            }) ?? 0
            if suggestedCount > 0 {
                filter = .suggested
                loadGoals()
            }
        }
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
