import WidgetKit
import SwiftUI
import AppIntents

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = UsageWidgetConfigurationIntent

    private let dataStore = SharedDataStore.shared
    private let cloudSync = CloudSyncService.shared

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .init(
            provider: .claudeCode,
            sessionUtilization: 42,
            sessionResetsAt: Date().addingTimeInterval(3600 * 2),
            weeklyUtilization: 15,
            weeklyResetsAt: Date().addingTimeInterval(3600 * 24 * 3),
            opusUtilization: 8,
            sonnetUtilization: 3,
            fetchedAt: .now,
            source: .icloudCache
        ))
    }

    func snapshot(for configuration: UsageWidgetConfigurationIntent, in context: Context) async -> UsageEntry {
        let provider = configuration.provider?.providerKind ?? .claudeCode
        let snapshot = loadBestSnapshot(for: provider)
        return UsageEntry(date: .now, snapshot: snapshot)
    }

    func timeline(for configuration: UsageWidgetConfigurationIntent, in context: Context) async -> Timeline<UsageEntry> {
        let provider = configuration.provider?.providerKind ?? .claudeCode
        let snapshot = loadBestSnapshot(for: provider)
        let entry = UsageEntry(date: .now, snapshot: snapshot)

        // Request next update in 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    /// Load best available data: local App Group first, then iCloud KV store.
    private func loadBestSnapshot(for provider: UsageProviderKind) -> UsageSnapshot {
        if let local = dataStore.readSnapshot(for: provider) {
            return local
        }
        if let cloud = cloudSync.readSnapshot(for: provider) {
            return cloud
        }
        return .empty(for: provider)
    }
}
