import SwiftUI
import UIKit

/// One appearance for the whole app. Senior and family share it.
enum CareAppearance: String, CaseIterable {
    case system
    case light
    case dark

    static let storageKey = "care.appearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum CareTheme {
    static let background = adaptive(light: rgb(250, 250, 247), dark: rgb(28, 28, 26))
    static let card = adaptive(light: .white, dark: rgb(44, 44, 41))
    static let ink = adaptive(light: rgb(43, 43, 43), dark: rgb(245, 244, 240))
    static let secondaryText = adaptive(light: rgb(132, 132, 132), dark: rgb(176, 174, 168))
    static let mutedText = adaptive(light: rgb(102, 102, 102), dark: rgb(160, 158, 152))
    static let sage = adaptive(light: rgb(112, 160, 124), dark: rgb(138, 186, 150))
    /// Button fill behind white text. Stays dark in both appearances so the label stays readable.
    static let action = Color(red: 78 / 255, green: 118 / 255, blue: 90 / 255)
    /// Alert fill behind white text. Coral only, and dark enough in both appearances.
    static let danger = Color(red: 168 / 255, green: 68 / 255, blue: 54 / 255)
    static let sageDark = adaptive(light: rgb(91, 137, 105), dark: rgb(186, 220, 194))
    static let sagePale = adaptive(light: rgb(220, 242, 225), dark: rgb(36, 58, 44))
    static let coral = adaptive(light: rgb(231, 125, 105), dark: rgb(232, 140, 122))
    static let coralDark = adaptive(light: rgb(151, 61, 48), dark: rgb(245, 186, 176))
    static let coralPale = adaptive(light: rgb(255, 229, 223), dark: rgb(62, 36, 32))
    static let gold = adaptive(light: rgb(240, 178, 74), dark: rgb(232, 186, 96))
    static let goldDark = adaptive(light: rgb(107, 85, 43), dark: rgb(245, 220, 160))
    /// Text that sits on the solid gold fill. Stays dark in both appearances.
    static let onGold = Color(red: 107/255, green: 85/255, blue: 43/255)
    static let goldPale = adaptive(light: rgb(255, 244, 218), dark: rgb(58, 46, 28))
    static let blue = adaptive(light: rgb(86, 159, 205), dark: rgb(126, 186, 220))
    static let bluePale = adaptive(light: rgb(221, 241, 255), dark: rgb(28, 46, 58))
    static let grayPill = adaptive(light: rgb(244, 243, 240), dark: rgb(58, 58, 54))
    static let cardStroke = adaptive(light: UIColor.black.withAlphaComponent(0.10), dark: UIColor.white.withAlphaComponent(0.14))
    static let shadow = adaptive(light: UIColor.black.withAlphaComponent(0.08), dark: UIColor.black.withAlphaComponent(0.45))
    static let heading = adaptive(light: UIColor(red: 0.16, green: 0.23, blue: 0.31, alpha: 1),
                                  dark: UIColor(red: 0.90, green: 0.92, blue: 0.94, alpha: 1))
    static let hairline = adaptive(light: UIColor.black.withAlphaComponent(0.08), dark: UIColor.white.withAlphaComponent(0.12))

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static func seniorColor(at index: Int) -> Color {
        [gold, sage, blue, coral][index % 4]
    }
}

struct LovableCard<Content: View>: View {
    var padding: CGFloat = 20
    var fill: Color = CareTheme.card
    var stroke: Color = CareTheme.cardStroke
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(stroke))
            .shadow(color: CareTheme.shadow, radius: 12, x: 0, y: 5)
    }
}

struct CircleIcon: View {
    let systemName: String
    var color = CareTheme.sage
    var size: CGFloat = 48
    var iconSize: CGFloat = 22
    var fillOpacity: Double = 0.18

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(fillOpacity), in: Circle())
            .accessibilityHidden(true)
    }
}

struct AvatarCircle: View {
    let text: String
    var color = CareTheme.sage
    var size: CGFloat = 58
    var selected = false

    var body: some View {
        Text(text)
            .font(.system(size: size > 52 ? 16 : 13, weight: .bold))
            .foregroundStyle(CareTheme.ink)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: Circle())
            .overlay(Circle().stroke(selected ? color : CareTheme.cardStroke, lineWidth: selected ? 2 : 1))
            .accessibilityHidden(true)
    }
}

/// A senior's photo when the app bundles a portrait for their first name, otherwise their initials.
struct SeniorAvatar: View {
    let name: String
    let initials: String
    var color = CareTheme.sage
    var size: CGFloat = 58

    private var portraitName: String? {
        guard let first = name.split(separator: " ").first else { return nil }
        let asset = "\(first.prefix(1).uppercased())\(first.dropFirst().lowercased())Portrait"
        return UIImage(named: asset) == nil ? nil : asset
    }

    var body: some View {
        if let portraitName {
            Image(portraitName)
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Text(initials)
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(CareTheme.ink)
                .frame(width: size, height: size)
                .background(color.opacity(0.22), in: Circle())
                .accessibilityHidden(true)
        }
    }
}

struct ReferenceBottomBar<Item: Hashable>: View {
    let items: [(Item, String, String, Int?)]
    @Binding var selection: Item
    var activeColor = CareTheme.sageDark

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item, title, icon, badge in
                Button {
                    selection = item
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: icon)
                                .font(.system(size: 20, weight: .medium))
                            if let badge {
                                Text("\(badge)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(CareTheme.coral, in: Circle())
                                    .offset(x: 10, y: -8)
                            }
                        }
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selection == item ? activeColor : CareTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(badge.map { "\(title), \($0) active" } ?? title)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
                .accessibilityIdentifier("tab.\(title.lowercased())")
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
        .background(CareTheme.card)
        .overlay(Rectangle().fill(CareTheme.hairline).frame(height: 1), alignment: .top)
    }
}

struct PlainPill: View {
    let text: String
    var icon: String?
    var color = CareTheme.sageDark
    var fill = CareTheme.grayPill

    var body: some View {
        Label {
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } icon: {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(fill, in: Capsule())
    }
}

struct ReferenceButtonStyle: ButtonStyle {
    var fill = CareTheme.action
    var foreground = Color.white
    var height: CGFloat = 96
    var radius: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill.opacity(configuration.isPressed ? 0.86 : 1), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .shadow(color: fill.opacity(0.22), radius: 16, y: 8)
    }
}

// MARK: - Forms

extension View {
    /// White rounded field background used by every input in the app.
    func careField() -> some View {
        padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CareTheme.cardStroke))
    }
}

struct PrimaryActionButton: View {
    let title: String
    var isLoading = false
    var isDisabled = false
    var fill = CareTheme.action
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill.opacity(isDisabled ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }
}

struct FormErrorText: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CareTheme.coralDark)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("form.error")
        }
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(CareTheme.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(CareTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(CareTheme.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Phone links for FaceTime, the dialer, and Messages. Returns nil when the string has no digits.
enum PhoneLinks {
    static func video(_ phone: String) -> URL? { url("facetime", phone) }
    static func call(_ phone: String) -> URL? { url("tel", phone) }
    static func text(_ phone: String) -> URL? { url("sms", phone) }

    static func sameNumber(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.filter(\.isNumber)
        let right = rhs.filter(\.isNumber)
        return !left.isEmpty && left == right
    }

    private static func url(_ scheme: String, _ phone: String) -> URL? {
        let allowed = phone.filter { $0.isNumber || $0 == "+" }
        guard allowed.contains(where: \.isNumber) else { return nil }
        return URL(string: "\(scheme):\(allowed)")
    }
}

struct TimeZoneField: View {
    @Binding var identifier: String

    var body: some View {
        NavigationLink {
            TimeZoneListView(selection: $identifier)
        } label: {
            HStack {
                Text("Time zone").foregroundStyle(CareTheme.ink)
                Spacer()
                Text(TimeZoneListView.label(for: identifier))
                    .foregroundStyle(CareTheme.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CareTheme.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

struct TimeZoneListView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { Self.label(for: $0).localizedCaseInsensitiveContains(query) }
    }

    static func label(for identifier: String) -> String {
        let city = identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
        guard let zone = TimeZone(identifier: identifier) else { return city }
        let offset = zone.secondsFromGMT() / 60
        let sign = offset >= 0 ? "+" : "-"
        return String(format: "%@ (UTC%@%d:%02d)", city, sign, abs(offset) / 60, abs(offset) % 60)
    }

    var body: some View {
        List(identifiers, id: \.self) { identifier in
            Button {
                selection = identifier
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.label(for: identifier)).foregroundStyle(CareTheme.ink)
                        Text(identifier).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText)
                    }
                    Spacer()
                    if identifier == selection {
                        Image(systemName: "checkmark").foregroundStyle(CareTheme.sageDark)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search city")
        .navigationTitle("Time zone")
        .navigationBarTitleDisplayMode(.inline)
    }
}
