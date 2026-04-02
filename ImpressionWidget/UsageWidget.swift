import SwiftUI
import WidgetKit
import AppIntents

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
        AppIntentConfiguration(kind: kind, intent: UsageWidgetConfigurationIntent.self, provider: UsageTimelineProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Usage Monitor")
        .description("Monitor Claude Code or Codex CLI session and weekly limits.")
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

enum UsageWidgetProviderOption: String, AppEnum {
    case claudeCode
    case codexCLI

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static let caseDisplayRepresentations: [UsageWidgetProviderOption: DisplayRepresentation] = [
        .claudeCode: DisplayRepresentation(title: "Claude Code"),
        .codexCLI: DisplayRepresentation(title: "Codex CLI"),
    ]

    var providerKind: UsageProviderKind {
        switch self {
        case .claudeCode: return .claudeCode
        case .codexCLI: return .codexCLI
        }
    }
}

struct UsageWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Usage Provider"
    static let description = IntentDescription("Choose which provider this widget shows.")

    @Parameter(title: "Provider")
    var provider: UsageWidgetProviderOption?

    init() {
        provider = .claudeCode
    }
}
