import SwiftUI

enum CareTheme {
    static let background = Color(red: 250/255, green: 250/255, blue: 247/255)
    static let ink = Color(red: 43/255, green: 43/255, blue: 43/255)
    static let secondaryText = Color(red: 132/255, green: 132/255, blue: 132/255)
    static let mutedText = Color(red: 102/255, green: 102/255, blue: 102/255)
    static let sage = Color(red: 112/255, green: 160/255, blue: 124/255)
    static let sageDark = Color(red: 91/255, green: 137/255, blue: 105/255)
    static let sagePale = Color(red: 220/255, green: 242/255, blue: 225/255)
    static let coral = Color(red: 231/255, green: 125/255, blue: 105/255)
    static let coralDark = Color(red: 151/255, green: 61/255, blue: 48/255)
    static let coralPale = Color(red: 255/255, green: 229/255, blue: 223/255)
    static let gold = Color(red: 240/255, green: 178/255, blue: 74/255)
    static let goldDark = Color(red: 107/255, green: 85/255, blue: 43/255)
    static let goldPale = Color(red: 255/255, green: 244/255, blue: 218/255)
    static let blue = Color(red: 86/255, green: 159/255, blue: 205/255)
    static let bluePale = Color(red: 221/255, green: 241/255, blue: 255/255)
    static let grayPill = Color(red: 244/255, green: 243/255, blue: 240/255)
    static let cardStroke = Color.black.opacity(0.10)
    static let shadow = Color.black.opacity(0.08)
    static let heading = Color(red: 0.16, green: 0.23, blue: 0.31)

    static func seniorColor(at index: Int) -> Color {
        [gold, sage, blue, coral][index % 4]
    }
}

struct LovableCard<Content: View>: View {
    var padding: CGFloat = 20
    var fill: Color = .white
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
            .overlay(Circle().stroke(selected ? color : Color.black.opacity(0.08), lineWidth: selected ? 2 : 1))
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
        .background(.white)
        .overlay(Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1), alignment: .top)
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
    var fill = CareTheme.sage
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
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CareTheme.cardStroke))
    }
}

struct PrimaryActionButton: View {
    let title: String
    var isLoading = false
    var isDisabled = false
    var fill = CareTheme.sage
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

/// Phone links for the dialer and Messages. Returns nil when the string has no digits.
enum PhoneLinks {
    static func call(_ phone: String) -> URL? { url("tel", phone) }
    static func text(_ phone: String) -> URL? { url("sms", phone) }

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
