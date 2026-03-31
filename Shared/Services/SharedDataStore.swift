import Foundation
import WidgetKit

/// Local App Group UserDefaults for sharing data between main app and widget extension.
final class SharedDataStore {
    static let shared = SharedDataStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        self.defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }

    // MARK: - Usage Snapshot

    func writeSnapshot(_ snapshot: UsageSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: "usageSnapshot")
        WidgetCenter.shared.reloadTimelines(ofKind: "UsageWidget")
    }

    func readSnapshot() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: "usageSnapshot") else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    // MARK: - Settings

    var refreshInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: "refreshInterval")
            return val > 0 ? val : AppConstants.defaultRefreshInterval
        }
        set { defaults.set(newValue, forKey: "refreshInterval") }
    }

    var warningThreshold: Double {
        get {
            let val = defaults.double(forKey: "warningThreshold")
            return val > 0 ? val : AppConstants.warningThresholdDefault
        }
        set { defaults.set(newValue, forKey: "warningThreshold") }
    }

    var criticalThreshold: Double {
        get {
            let val = defaults.double(forKey: "criticalThreshold")
            return val > 0 ? val : AppConstants.criticalThresholdDefault
        }
        set { defaults.set(newValue, forKey: "criticalThreshold") }
    }

    var resetNotificationsEnabled: Bool {
        get { defaults.object(forKey: "resetNotifications") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "resetNotifications") }
    }

    var thresholdNotificationsEnabled: Bool {
        get { defaults.object(forKey: "thresholdNotifications") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "thresholdNotifications") }
    }
}
