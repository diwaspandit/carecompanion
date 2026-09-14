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
    static let coralPale = Color(red: 255/255, green: 229/255, blue: 223/255)
    static let gold = Color(red: 240/255, green: 178/255, blue: 74/255)
    static let goldPale = Color(red: 255/255, green: 244/255, blue: 218/255)
    static let blue = Color(red: 86/255, green: 159/255, blue: 205/255)
    static let bluePale = Color(red: 221/255, green: 241/255, blue: 255/255)
    static let grayPill = Color(red: 244/255, green: 243/255, blue: 240/255)
    static let cardStroke = Color.black.opacity(0.10)
    static let shadow = Color.black.opacity(0.08)
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
    }
}

struct ReferenceBottomBar<Item: Hashable>: View {
    let items: [(Item, String, String, Int?)]
    @Binding var selection: Item
    var activeColor = CareTheme.sageDark

    var body: some View {
        HStack {
            ForEach(items, id: \.0) { item, title, icon, badge in
                Button {
                    selection = item
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: icon)
                                .font(.system(size: 21, weight: .medium))
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
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == item ? activeColor : CareTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tabIdentifier(for: title))
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .background(.white)
        .overlay(Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1), alignment: .top)
    }

    private func tabIdentifier(for title: String) -> String {
        switch title {
        case "Home": return "tab.home"
        case "Health": return "tab.health"
        case "Alerts": return "tab.alerts"
        case "Visits": return "tab.appointments"
        case "Chats": return "tab.chats"
        default: return "tab.\(title.lowercased())"
        }
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
