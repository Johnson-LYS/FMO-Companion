import SwiftUI

enum AppTheme {
    static let pageSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 18
}

extension View {
    func appCard() -> some View {
        padding(AppTheme.cardPadding)
            .background(.background.secondary, in: .rect(cornerRadius: AppTheme.cardRadius))
    }
}

struct BrandPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Color.accentColor.opacity(configuration.isPressed ? 0.72 : 1),
                in: .rect(cornerRadius: 14)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
