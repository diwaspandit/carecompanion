import SwiftUI
import WidgetKit

struct CareHomeEntry: TimelineEntry {
    let date: Date
    let snapshot: CareWidgetSnapshot
}

struct CareHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> CareHomeEntry {
        CareHomeEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (CareHomeEntry) -> Void) {
        completion(CareHomeEntry(date: .now, snapshot: CareWidgetSnapshot.read() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CareHomeEntry>) -> Void) {
        let entry = CareHomeEntry(date: .now, snapshot: CareWidgetSnapshot.read() ?? .empty)
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct CareHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: CareWidgetSnapshot

    private var scheme: ColorScheme {
        switch CareWidgetSnapshot.readAppearance() {
        case "light": .light
        case "dark": .dark
        default: colorScheme
        }
    }

    private var ink: Color { scheme == .dark ? Color(red: 245/255, green: 244/255, blue: 240/255) : Color(red: 43/255, green: 43/255, blue: 43/255) }
    private var secondary: Color { scheme == .dark ? Color(red: 176/255, green: 174/255, blue: 168/255) : Color(red: 132/255, green: 132/255, blue: 132/255) }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            Text(snapshot.title)
                .font(.system(size: family == .systemSmall ? 13 : 15, weight: .black, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
            row("bubble.left.fill", "Message", snapshot.message, scheme == .dark ? Color(red: 186/255, green: 220/255, blue: 194/255) : Color(red: 91/255, green: 137/255, blue: 105/255))
            row("pills.fill", "Medicine", snapshot.medicine, scheme == .dark ? Color(red: 245/255, green: 220/255, blue: 160/255) : Color(red: 107/255, green: 85/255, blue: 43/255))
            row("calendar", "Visit", snapshot.visit, scheme == .dark ? Color(red: 245/255, green: 186/255, blue: 176/255) : Color(red: 176/255, green: 78/255, blue: 62/255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "carecompanion://open"))
    }

    private func row(_ icon: String, _ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: family == .systemSmall ? 10 : 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: family == .systemSmall ? 12 : 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(secondary)
                Text(value)
                    .font(.system(size: family == .systemSmall ? 12 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

@main
struct CareHomeWidget: Widget {
    static let kind = "CareHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CareHomeProvider()) { entry in
            CareHomeWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("CareCompanion")
        .description("A new message, the next medicine, and the next visit.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WidgetCanvas: View {
    @Environment(\.colorScheme) private var colorScheme

    private var scheme: ColorScheme {
        switch CareWidgetSnapshot.readAppearance() {
        case "light": .light
        case "dark": .dark
        default: colorScheme
        }
    }

    var body: some View {
        scheme == .dark
            ? Color(red: 28/255, green: 28/255, blue: 26/255)
            : Color(red: 250/255, green: 250/255, blue: 247/255)
    }
}
