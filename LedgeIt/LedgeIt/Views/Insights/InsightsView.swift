import SwiftUI
import GRDB

struct InsightsView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var insights: [HeartbeatInsight] = []
    private let database = AppDatabase.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if insights.isEmpty {
                    emptyState
                } else {
                    ForEach(insights) { insight in
                        insightCard(insight)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(l10n.insights)
        .task {
            await loadInsights()
            await markTodayAsRead()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(l10n.noInsightsYet)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func insightCard(_ insight: HeartbeatInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatDate(insight.date))
                    .font(.headline)
                Spacer()
                if !insight.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }

            switch insight.status {
            case "completed":
                Text(insight.content)
                    .font(.body)
                    .textSelection(.enabled)
            case "pending":
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.generatingInsights)
                        .foregroundStyle(.secondary)
                }
            case "failed":
                Text(l10n.insightsNotUpdated)
                    .foregroundStyle(.secondary)
                    .italic()
            default:
                EmptyView()
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadInsights() async {
        do {
            insights = try await database.db.read { db in
                try HeartbeatInsight
                    .order(HeartbeatInsight.Columns.date.desc)
                    .limit(7)
                    .fetchAll(db)
            }
        } catch {
            insights = []
        }
    }

    private func markTodayAsRead() async {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        try? await database.db.write { db in
            try db.execute(
                sql: "UPDATE heartbeat_insights SET is_read = 1 WHERE date = ? AND is_read = 0",
                arguments: [today]
            )
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let inputFmt = DateFormatter()
        inputFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inputFmt.date(from: dateString) else { return dateString }
        let outputFmt = DateFormatter()
        outputFmt.dateStyle = .medium
        return outputFmt.string(from: date)
    }
}
