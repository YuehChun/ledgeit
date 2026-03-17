import SwiftUI
import WebKit
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
                MarkdownWebView(markdown: insight.content)
                    .frame(minHeight: 400)
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

// MARK: - Markdown WebView

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = wrapMarkdownInHTML(markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private func wrapMarkdownInHTML(_ md: String) -> String {
        // Escape for JS string
        let escaped = md
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
                font-size: 13px;
                line-height: 1.7;
                color: #e0e0e0;
                background: transparent;
                padding: 4px 0;
            }
            h1 { font-size: 18px; font-weight: 700; color: #f0f0f0; margin: 16px 0 8px 0; }
            h2 { font-size: 15px; font-weight: 600; color: #f0f0f0; margin: 14px 0 6px 0; }
            h3 { font-size: 14px; font-weight: 600; color: #d0d0d0; margin: 10px 0 4px 0; }
            p { margin: 6px 0; }
            strong { color: #f0f0f0; font-weight: 600; }
            em { font-style: italic; color: #c0c0c0; }
            hr {
                border: none;
                border-top: 1px solid #333;
                margin: 12px 0;
            }
            ul, ol { padding-left: 20px; margin: 6px 0; }
            li { margin: 3px 0; }
            table {
                width: 100%;
                border-collapse: collapse;
                margin: 8px 0;
                font-size: 12px;
            }
            th {
                text-align: left;
                padding: 6px 10px;
                background: rgba(255,255,255,0.06);
                border-bottom: 1px solid #444;
                font-weight: 600;
                color: #c0c0c0;
            }
            td {
                padding: 5px 10px;
                border-bottom: 1px solid #2a2a2a;
            }
            tr:hover td { background: rgba(255,255,255,0.03); }
            blockquote {
                border-left: 3px solid #4a90d9;
                padding: 4px 12px;
                margin: 8px 0;
                color: #a0b8d0;
                background: rgba(74,144,217,0.05);
                border-radius: 0 6px 6px 0;
            }
            code {
                background: rgba(255,255,255,0.08);
                padding: 1px 5px;
                border-radius: 4px;
                font-size: 12px;
            }
            a { color: #6baaff; text-decoration: none; }
            a:hover { text-decoration: underline; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
            document.getElementById('content').innerHTML = marked.parse(`\(escaped)`);
        </script>
        </body>
        </html>
        """
    }
}
