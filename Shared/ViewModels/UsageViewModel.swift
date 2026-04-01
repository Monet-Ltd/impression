import Foundation
import Combine

@MainActor @Observable
final class UsageViewModel {
    var snapshot: UsageSnapshot = .empty
    var isLoading = false
    var error: String?
    var tokenStatus: TokenStatus = .unknown
    private var hasSentFirstStatusNotification = false

    enum TokenStatus: Equatable {
        case unknown
        case valid
        case expiresSoon(Date)
        case expired
        case notFound
    }

    private let usageService = UsageService()
    private let notificationScheduler = NotificationScheduler()
    private let cloudSync = CloudSyncService.shared
    private let dataStore = SharedDataStore.shared
    private var timer: Timer?
    private var token: String?

    init() {
        // Listen for iCloud changes
        cloudSync.onSnapshotChanged = { [weak self] snapshot in
            Task { @MainActor in
                self?.snapshot = snapshot
            }
        }
    }

    // MARK: - Token Management

    func setToken(_ token: String, expiresAt: Date? = nil) {
        self.token = token
        self.tokenStatus = .valid
        cloudSync.writeTokenToKeychain(token)
        if let expiresAt {
            cloudSync.writeTokenExpiry(expiresAt)
            updateTokenStatus(expiresAt: expiresAt)
            Task { await notificationScheduler.scheduleTokenExpiryReminder(expiresAt: expiresAt) }
        }
    }

    func loadToken() {
        // Try iCloud Keychain first
        if let keychainToken = cloudSync.readTokenFromKeychain() {
            self.token = keychainToken
            self.tokenStatus = .valid
            if let expiry = cloudSync.readTokenExpiry() {
                updateTokenStatus(expiresAt: expiry)
            }
            return
        }
        self.tokenStatus = .notFound
    }

    private func updateTokenStatus(expiresAt: Date) {
        if expiresAt < Date() {
            tokenStatus = .expired
        } else if expiresAt.timeIntervalSinceNow < 2 * 3600 {
            tokenStatus = .expiresSoon(expiresAt)
        } else {
            tokenStatus = .valid
        }
    }

    // MARK: - Fetching

    func startPolling() {
        Task { await fetchOnce() }
        rescheduleTimer()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func fetchOnce() async {
        guard let token else {
            error = "No token"
            return
        }

        isLoading = true
        error = nil

        do {
            let newSnapshot = try await usageService.fetch(token: token)
            self.snapshot = newSnapshot
            self.isLoading = false
            NSLog("[Impression] Fetched: session=\(Int(newSnapshot.sessionUtilization))%% weekly=\(Int(newSnapshot.weeklyUtilization))%% source=\(newSnapshot.source.rawValue)")
            if let sr = newSnapshot.sessionResetsAt {
                NSLog("[Impression] Session resets at: \(sr)")
            }
            if let wr = newSnapshot.weeklyResetsAt {
                NSLog("[Impression] Weekly resets at: \(wr)")
            }

            // Persist locally and to iCloud
            dataStore.writeSnapshot(newSnapshot)
            cloudSync.writeSnapshot(newSnapshot)

            // Schedule reset notifications
            if dataStore.resetNotificationsEnabled {
                if let sessionReset = newSnapshot.sessionResetsAt {
                    await notificationScheduler.scheduleResetNotification(type: .session, resetsAt: sessionReset)
                }
                if let weeklyReset = newSnapshot.weeklyResetsAt {
                    await notificationScheduler.scheduleResetNotification(type: .weekly, resetsAt: weeklyReset)
                }
            }

            // Send status notification on first successful fetch
            if !hasSentFirstStatusNotification {
                hasSentFirstStatusNotification = true
                await notificationScheduler.sendStatusNotification(snapshot: newSnapshot)
            }

            // Check threshold warnings
            if dataStore.thresholdNotificationsEnabled {
                await notificationScheduler.checkThresholds(
                    snapshot: newSnapshot,
                    warningAt: dataStore.warningThreshold,
                    criticalAt: dataStore.criticalThreshold
                )
            }

            // Adjust polling interval based on backoff
            let recommendedInterval = await usageService.recommendedInterval
            if recommendedInterval != dataStore.refreshInterval {
                rescheduleTimer(interval: recommendedInterval)
            }
        } catch {
            self.isLoading = false
            if let cached = cloudSync.readSnapshot() {
                self.snapshot = cached
            } else if let local = dataStore.readSnapshot() {
                self.snapshot = local
            }
            self.error = error.localizedDescription
        }
    }

    private func rescheduleTimer(interval: TimeInterval? = nil) {
        timer?.invalidate()
        let iv = interval ?? dataStore.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: iv, repeats: true) { [weak self] _ in
            Task { await self?.fetchOnce() }
        }
    }

    // MARK: - Request notification permission

    func requestNotificationPermission() async -> Bool {
        await notificationScheduler.requestPermission()
    }

    // MARK: - Helpers

    var sessionColor: UsageColor {
        UsageColor.from(utilization: snapshot.sessionUtilization)
    }

    var weeklyColor: UsageColor {
        UsageColor.from(utilization: snapshot.weeklyUtilization)
    }

    var sessionResetCountdown: String? {
        guard let date = snapshot.sessionResetsAt, date > Date() else { return nil }
        return formatCountdown(date)
    }

    var weeklyResetCountdown: String? {
        guard let date = snapshot.weeklyResetsAt, date > Date() else { return nil }
        return formatCountdown(date)
    }

    private func formatCountdown(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}

enum UsageColor: String {
    case green, yellow, orange, red

    static func from(utilization: Double) -> UsageColor {
        switch utilization {
        case 0..<60: return .green
        case 60..<80: return .yellow
        case 80..<95: return .orange
        default: return .red
        }
    }
}
