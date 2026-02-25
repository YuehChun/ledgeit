import SwiftUI
import GRDB

struct EmailListView: View {
    @State private var emails: [Email] = []
    @State private var selectedEmail: Email?
    @State private var filterFinancial = false
    @State private var cancellable: AnyDatabaseCancellable?

    var body: some View {
        HStack(spacing: 0) {
            // Left: email list
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Toggle("Financial Only", isOn: $filterFinancial)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                    Text("\(emails.count) emails")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()

                if emails.isEmpty {
                    ContentUnavailableView(
                        "No Emails",
                        systemImage: "envelope",
                        description: Text("Synced emails appear after connecting Google.")
                    )
                } else {
                    List(emails, selection: $selectedEmail) { email in
                        EmailRow(email: email)
                            .tag(email)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(width: 380)

            Divider()

            // Right: detail
            if let email = selectedEmail {
                EmailDetailView(email: email)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .font(.title)
                        .foregroundStyle(.quaternary)
                    Text("Select an email")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Emails")
        .onAppear { startObservation() }
        .onChange(of: filterFinancial) { _, _ in startObservation() }
        .onDisappear { cancellable?.cancel() }
    }

    private func startObservation() {
        let financial = filterFinancial
        let observation = ValueObservation.tracking { db -> [Email] in
            var query = Email.all()
            if financial {
                query = query.filter(Email.Columns.isFinancial == true)
            }
            return try query
                .order(Email.Columns.createdAt.desc)
                .limit(500)
                .fetchAll(db)
        }

        cancellable = observation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { error in
            print("Email observation error: \(error)")
        } onChange: { newEmails in
            emails = newEmails
        }
    }
}

private struct EmailRow: View {
    let email: Email

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(email.subject ?? "(No Subject)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if email.isFinancial {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                if email.isProcessed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
            HStack(spacing: 6) {
                Text(email.sender ?? "Unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let date = email.date {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let snippet = email.snippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EmailDetailView: View {
    let email: Email

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(email.subject ?? "(No Subject)")
                    .font(.title3)
                    .fontWeight(.bold)

                HStack {
                    Label(email.sender ?? "Unknown", systemImage: "person")
                    Spacer()
                    if let date = email.date {
                        Text(date)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)

                HStack(spacing: 10) {
                    if email.isFinancial {
                        Label("Financial", systemImage: "dollarsign.circle")
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.1))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    if email.isProcessed {
                        Label("Processed", systemImage: "checkmark.circle")
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                Divider()

                Text(email.bodyText ?? "(No body)")
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
