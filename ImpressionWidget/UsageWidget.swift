import SwiftUI
import WidgetKit

@main
struct ImpressionWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        #if os(iOS)
        LockScreenWidget()
        #endif
    }
}

struct UsageWidget: Widget {
    let kind = "UsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Monitor your Claude Code session and weekly limits.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium]
        #if os(iOS)
        families.append(.systemLarge)
        #endif
        #if os(macOS)
        families.append(.systemLarge)
        #endif
        return families
    }
}
