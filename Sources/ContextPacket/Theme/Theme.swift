import SwiftUI
import AppKit

// MARK: - Minimalist Grey Design Tokens (Monochrome / Raycast Dark)
public enum Theme {
    // Corner Radii (Precision Linear geometry)
    public static let pillRadius: CGFloat = 16
    public static let cardCornerRadius: CGFloat = 8
    public static let containerCornerRadius: CGFloat = 10
    public static let cornerRadius: CGFloat = 6
    public static let buttonRadius: CGFloat = 6
    public static let badgeRadius: CGFloat = 4

    // Spacing
    public static let spacingTiny: CGFloat = 4
    public static let spacingSmall: CGFloat = 8
    public static let spacingMedium: CGFloat = 14
    public static let spacingLarge: CGFloat = 20

    // Typography
    public static let titleFont = Font.system(size: 13, weight: .semibold, design: .default)
    public static let headerFont = Font.system(size: 11, weight: .semibold, design: .default)
    public static let bodyFont = Font.system(size: 12, weight: .regular, design: .default)
    public static let monoFont = Font.system(size: 12, weight: .regular, design: .monospaced)
    public static let smallMonoFont = Font.system(size: 11, weight: .regular, design: .monospaced)
    public static let tinyMonoFont = Font.system(size: 10, weight: .medium, design: .monospaced)

    // Brand Display Typography (Bitcount Prop Single)
    public static func bitcountPropSingle(size: CGFloat = 26) -> Font {
        let candidateNames = [
            "Bitcount Prop Single",
            "BitcountPropSingle",
            "BitcountPropSingle-Regular",
            "BitcountPropSingle-Medium",
            "BitcountPropSingle-Bold",
            "Bitcount Prop Single Circle",
            "Bitcount Prop Single Square",
            "Bitcount Prop Single Line",
            "BitcountPropSingleCircle-Regular",
            "BitcountPropSingleSquare-Regular",
            "BitcountPropSingleLine-Regular",
            "Bitcount Prop Double",
            "Bitcount Mono Single"
        ]
        for name in candidateNames {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        if let matchingFamily = NSFontManager.shared.availableFontFamilies.first(where: { $0.localizedCaseInsensitiveContains("Bitcount") }) {
            return .custom(matchingFamily, size: size)
        }
        if let matching = NSFontManager.shared.availableFonts.first(where: { $0.localizedCaseInsensitiveContains("Bitcount") }) {
            return .custom(matching, size: size)
        }
        return .custom("Bitcount Prop Single", size: size)
    }

    public static var bitcountPropSingle: Font {
        bitcountPropSingle(size: 26)
    }

    // Sleek Dark Grey Surfaces (No rainbow colors)
    public static let canvas = Color(red: 0.063, green: 0.067, blue: 0.075)         // #101113 Deepest neutral grey
    public static let cardBackground = Color(red: 0.090, green: 0.094, blue: 0.106)   // #17181B Elevated grey card
    public static let cardHover = Color(red: 0.118, green: 0.122, blue: 0.137)       // #1E1F23 Card hover
    public static let surface = Color(red: 0.090, green: 0.094, blue: 0.106)
    public static let background = Color(red: 0.063, green: 0.067, blue: 0.075)

    // Razor-thin precision borders
    public static let subtleBorder = Color.white.opacity(0.08)
    public static let hoverBorder = Color.white.opacity(0.16)
    public static let focusBorder = Color.white.opacity(0.35)

    // Text Hierarchy
    public static let primaryText = Color.white.opacity(0.95)
    public static let secondaryText = Color(white: 0.60)
    public static let tertiaryText = Color(white: 0.40)

    // Minimalist Monochrome Status Accents (Refined, understated grey tones)
    public static let accent = Color.white.opacity(0.85)
    public static let indigo = Color.white.opacity(0.85)
    public static let emerald = Color(white: 0.85)
    public static let amber = Color(white: 0.85)
    public static let azure = Color(white: 0.85)
    public static let violet = Color(white: 0.85)
    public static let coral = Color(red: 0.95, green: 0.40, blue: 0.40)  // Kept subtle for errors only
    public static let gold = Color.white.opacity(0.85)
}

// MARK: - Dark Grey Wallpaper
public struct MacDesktopBackground: View {
    public init() {}

    public var body: some View {
        Theme.canvas
            .ignoresSafeArea()
    }
}

// MARK: - Keyboard Shortcut Keycap
public struct KeycapBadge: View {
    let key: String
    var onWhite: Bool = false

    public init(_ key: String, onWhite: Bool = false) {
        self.key = key
        self.onWhite = onWhite
    }

    public var body: some View {
        Text(key)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(onWhite ? Color.black.opacity(0.75) : Color.white.opacity(0.7))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(onWhite ? Color.black.opacity(0.08) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(onWhite ? Color.black.opacity(0.15) : Color.white.opacity(0.12), lineWidth: 0.75)
            )
    }
}

// MARK: - Section Card (Minimalist Dark Grey Panel)
public struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let badge: String?
    let badgeColor: Color?
    let icon: String?
    let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        badgeColor: Color? = nil,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.badgeColor = badgeColor
        self.icon = icon
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.9))

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }

                Spacer()

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.02))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Theme.subtleBorder),
                alignment: .bottom
            )

            // Content Area
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                content
            }
            .padding(14)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }
}

// MARK: - Monochrome Status Badges
public struct GoldenGateBadge: View {
    let text: String
    let tint: Color
    var systemImage: String? = nil
    var hasGlow: Bool = false
    var isInverted: Bool = false

    public init(
        text: String,
        tint: Color = Theme.accent,
        systemImage: String? = nil,
        hasGlow: Bool = false,
        isInverted: Bool = false
    ) {
        self.text = text
        self.tint = tint
        self.systemImage = systemImage
        self.hasGlow = hasGlow
        self.isInverted = isInverted
    }

    public var body: some View {
        HStack(spacing: 4) {
            if hasGlow {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 5, height: 5)
            } else if let icon = systemImage {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }

            Text(text)
                .font(.system(size: 10, weight: .medium, design: .default))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(Color.white.opacity(0.85))
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
        )
    }
}

// MARK: - Button Style (Solid White Primary CTA, Minimalist Dark Secondary)
public struct GoldenGatePillButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    var tint: Color = Theme.accent
    @State private var isHovered = false

    public init(isProminent: Bool = false, tint: Color = Theme.accent) {
        self.isProminent = isProminent
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        configuration.label
            .font(.system(size: 12, weight: isProminent ? .semibold : .medium, design: .default))
            .foregroundStyle(isProminent ? Color.black : (isHovered ? Color.white : Color.white.opacity(0.85)))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                if isProminent {
                    // White CTA
                    RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                        .fill(isPressed ? Color(white: 0.82) : (isHovered ? Color(white: 0.94) : Color.white))
                } else {
                    RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                        .fill(Color.white.opacity(isPressed ? 0.12 : (isHovered ? 0.08 : 0.04)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .stroke(
                        isProminent
                            ? Color.white
                            : (isHovered ? Color.white.opacity(0.2) : Theme.subtleBorder),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isProminent ? Color.black.opacity(0.2) : Color.clear,
                radius: isProminent ? 4 : 0,
                y: 1
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                self.isHovered = hovering
            }
    }
}

// MARK: - Icon-Only Button Style (Minimalist Grey Square)
public struct GoldenGateIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.85))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .fill(Color.white.opacity(isPressed ? 0.14 : (isHovered ? 0.08 : 0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .stroke(isHovered ? Color.white.opacity(0.22) : Theme.subtleBorder, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                self.isHovered = hovering
            }
    }
}


// MARK: - Radio Button Chip
public struct MacRadioButton: View {
    let isSelected: Bool
    let label: String
    let action: () -> Void

    public init(isSelected: Bool, label: String, action: @escaping () -> Void) {
        self.isSelected = isSelected
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .default))
                .foregroundStyle(isSelected ? Color.black : Theme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        Color.white
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        Color.clear
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - High Contrast Linear Input Field
public struct LinearInputField: View {
    let placeholder: String
    @Binding var text: String
    var onCommit: (() -> Void)? = nil

    public init(_ placeholder: String, text: Binding<String>, onCommit: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.onCommit = onCommit
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.white.opacity(0.40))
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.bodyFont)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .onSubmit {
                    onCommit?()
                }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }
}

// MARK: - Compatibility Shims
public struct MacWindowModifier: ViewModifier {
    public init(shadowOffset: CGFloat = 0) {}
    public func body(content: Content) -> some View {
        content
    }
}

public extension View {
    func macWindow(shadowOffset: CGFloat = 0) -> some View {
        self
    }
    func liquidGlass(cornerRadius: CGFloat = Theme.cardCornerRadius, isInteractive: Bool = false) -> some View {
        self
    }
}

// MARK: - Floating Toast HUD
public struct ToastBanner: View {
    let message: String

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.15))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 14, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
