import SwiftUI

struct CategoryBadge: View {
    let category: String
    var compact: Bool = false

    private var resolved: CategoryStyle {
        CategoryStyle.style(forRawCategory: category)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: resolved.icon)
                .font(.system(size: compact ? 10 : 9))

            if !compact {
                Text(resolved.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .foregroundStyle(resolved.color)
        .background(resolved.color.opacity(0.15))
        .overlay(alignment: .leading) {
            if resolved.isFinancialObligation {
                UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
                    .fill(resolved.color)
                    .frame(width: 2.5)
            }
        }
        .clipShape(Capsule())
    }
}
