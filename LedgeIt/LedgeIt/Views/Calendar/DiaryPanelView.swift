// LedgeIt/LedgeIt/Views/Calendar/DiaryPanelView.swift
import SwiftUI
import GRDB

struct DiaryPanelView: View {
    let selectedDate: Date
    let transactions: [Transaction]
    let bills: [CreditCardBill]
    let diaryEntry: SpendingDiaryEntry?
    var onRegenerate: ((String) -> Void)? = nil

    @State private var isRegenerating = false

    private var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        return fmt
    }

    private var dayTransactions: [Transaction] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateString = fmt.string(from: selectedDate)
        return transactions.filter { $0.transactionDate == dateString }
    }

    private var dayBills: [CreditCardBill] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateString = fmt.string(from: selectedDate)
        return bills.filter { $0.dueDate == dateString }
    }

    private var daySpending: Double {
        dayTransactions.filter { $0.type == "debit" }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("\(dayTransactions.count) transactions · $\(String(format: "%.0f", daySpending)) spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let entry = diaryEntry {
                    Text(entry.personaId.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Bills section (if any)
            if !dayBills.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Bills Due", systemImage: "creditcard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(dayBills, id: \.id) { bill in
                        HStack {
                            Text(bill.bankName)
                                .font(.callout)
                            Spacer()
                            Text("\(bill.currency) \(String(format: "%.0f", bill.amountDue))")
                                .font(.callout)
                                .foregroundStyle(bill.isPaid ? .green : .orange)
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Compact transactions
            if !dayTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Transactions", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    FlowLayout(spacing: 8) {
                        ForEach(dayTransactions, id: \.id) { tx in
                            HStack(spacing: 4) {
                                Text(tx.merchant ?? "Unknown")
                                    .font(.caption)
                                Text("$\(String(format: "%.0f", tx.amount))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Diary content (main focus)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Spending Diary", systemImage: "pencil.line")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .textCase(.uppercase)
                    Spacer()
                    if isRegenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            let fmt = DateFormatter()
                            fmt.dateFormat = "yyyy-MM-dd"
                            let dateString = fmt.string(from: selectedDate)
                            isRegenerating = true
                            onRegenerate?(dateString)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate diary")
                    }
                }

                if let entry = diaryEntry, entry.status == "completed" {
                    Text(entry.content)
                        .font(.body)
                        .lineSpacing(6)
                } else if isRegenerating || (diaryEntry != nil && diaryEntry?.status == "pending") {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating diary...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if diaryEntry != nil, diaryEntry?.status == "failed" {
                    Text("Diary generation failed. Tap refresh to retry.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No diary entry for this date.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: diaryEntry?.content) { _, _ in
                isRegenerating = false
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.15), lineWidth: 1)
            )

            Spacer()
        }
        .padding()
    }
}

// Simple flow layout for compact transaction chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
