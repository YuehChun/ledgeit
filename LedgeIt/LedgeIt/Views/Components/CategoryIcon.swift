import SwiftUI

struct CategoryIcon: View {
    let category: String
    var size: CGFloat = 20

    private var resolved: CategoryStyle {
        CategoryStyle.style(forRawCategory: category)
    }

    var body: some View {
        Image(systemName: resolved.icon)
            .font(.system(size: size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(resolved.color, in: Circle())
    }
}

struct CategoryDot: View {
    let category: String
    var size: CGFloat = 4

    private var resolved: CategoryStyle {
        CategoryStyle.style(forRawCategory: category)
    }

    var body: some View {
        Circle()
            .fill(resolved.color)
            .frame(width: size, height: size)
    }
}
