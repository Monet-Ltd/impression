import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageTimelineProvider: TimelineProvider {
    private let dataStore = SharedDataStore.shared
    private let cloudSync = CloudSyncService.shared

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .init(
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

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = loadBestSnapshot()
        completion(UsageEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = loadBestSnapshot()
        let entry = UsageEntry(date: .now, snapshot: snapshot)

        // Request next update in 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    /// Load best available data: local App Group first, then iCloud KV store.
    private func loadBestSnapshot() -> UsageSnapshot {
        if let local = dataStore.readSnapshot() {
            return local
        }
        if let cloud = cloudSync.readSnapshot() {
            return cloud
        }
        return .empty
    }
}
