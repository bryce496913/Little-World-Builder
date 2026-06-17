import SwiftUI

struct AppTheme {
    static let background = Color.black
    static let surface = Color(red: 0.12, green: 0.04, blue: 0.2)
    static let accent = Color(red: 0.72, green: 0.29, blue: 0.95)
    static let highlight = Color(red: 0.98, green: 0.32, blue: 0.67)
    static let text = Color.white
    static let mutedText = Color.white.opacity(0.72)
}

enum AppTextStyle {
    case h1, h2, h3, paragraph

    var size: CGFloat {
        switch self {
        case .h1: return 16
        case .h2: return 14
        case .h3: return 12
        case .paragraph: return 10
        }
    }

    var weight: Font.Weight {
        switch self {
        case .h1, .h2: return .bold
        case .h3: return .semibold
        case .paragraph: return .regular
        }
    }
}

extension Text {
    func appText(_ style: AppTextStyle, color: Color = AppTheme.text) -> some View {
        self.font(.system(size: style.size, weight: style.weight, design: .rounded))
            .foregroundColor(color)
    }
}

struct AppScreenHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).appText(.h1)
            if let subtitle = subtitle {
                Text(subtitle).appText(.paragraph, color: AppTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppSurface<Content: View>: View {
    let borderColor: Color
    let content: Content

    init(borderColor: Color = AppTheme.accent.opacity(0.45), @ViewBuilder content: () -> Content) {
        self.borderColor = borderColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

struct AppButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let systemImage: String?
    let style: Style
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, style: Style = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    private var color: Color {
        switch style {
        case .primary: return AppTheme.highlight
        case .secondary: return AppTheme.accent
        case .destructive: return AppTheme.highlight
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage = systemImage { Image(systemName: systemImage) }
                Text(title).appText(.h3)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color.opacity(style == .secondary ? 0.22 : 0.95))
            .foregroundColor(AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
