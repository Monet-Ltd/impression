import Foundation
import Combine

@MainActor @Observable
final class UsageViewModel {
    var selectedProvider: UsageProviderKind
    var snapshot: UsageSnapshot
    var isLoading = false
    var error: String?
    var tokenStatus: TokenStatus = .unknown
    var onSnapshotChanged: (() -> Void)?
    private var hasSentFirstStatusNotification = false

    enum TokenStatus: Equatable {
        case unknown
        case valid
        case expiresSoon(Date)
        case expired
        case notFound
        case notRequired
    }

    private let usageService = UsageService()
    private let codexUsageService = CodexUsageService()
    private let notificationScheduler = NotificationScheduler()
    private let cloudSync = CloudSyncService.shared
    private let dataStore = SharedDataStore.shared
    private var timer: Timer?
    private var token: String?

    init() {
        self.selectedProvider = dataStore.selectedProvider
        self.snapshot = dataStore.readSnapshot(for: dataStore.selectedProvider)
            ?? cloudSync.readSnapshot(for: dataStore.selectedProvider)
            ?? .empty(for: dataStore.selectedProvider)

        // Listen for iCloud changes
        cloudSync.onSnapshotChanged = { [weak self] provider, snapshot in
            Task { @MainActor in
                guard let self else { return }
                if provider == self.selectedProvider {
                    self.snapshot = snapshot
                    self.onSnapshotChanged?()
                }
            }
        }

        if selectedProvider == .codexCLI {
            tokenStatus = .notRequired
        }
    }

    // MARK: - Token Management

    func setToken(_ token: String, expiresAt: Date? = nil) {
        let tokenChanged = (self.token != token)
        self.token = token
        self.tokenStatus = .valid
        _ = cloudSync.writeTokenToKeychain(token)
        if let expiresAt {
            cloudSync.writeTokenExpiry(expiresAt)
            updateTokenStatus(expiresAt: expiresAt)
            Task { await notificationScheduler.scheduleTokenExpiryReminder(expiresAt: expiresAt) }
        }
        // Token changed → start/restart polling (fetches immediately + restarts timer)
        if tokenChanged {
            NSLog("[Impression] Token changed, starting polling")
            startPolling()
        }
    }

    func loadToken() {
        guard selectedProvider.requiresToken else {
            tokenStatus = .notRequired
            return
        }

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
        if selectedProvider.requiresToken && token == nil {
            error = "No token"
            tokenStatus = .notFound
            return
        }

        isLoading = true
        error = nil

        do {
            let newSnapshot: UsageSnapshot
            if selectedProvider == .claudeCode {
                newSnapshot = try await usageService.fetch(token: token!)
            } else {
                newSnapshot = try await codexUsageService.fetch()
            }
            self.snapshot = newSnapshot
            self.isLoading = false
            onSnapshotChanged?()
            NSLog("[Impression] Fetched provider=\(newSnapshot.provider.rawValue) session=\(Int(newSnapshot.sessionUtilization))%% weekly=\(Int(newSnapshot.weeklyUtilization))%% source=\(newSnapshot.source.rawValue)")
            if let sr = newSnapshot.sessionResetsAt {
                NSLog("[Impression] Session resets at: \(sr)")
            }
            if let wr = newSnapshot.weeklyResetsAt {
                NSLog("[Impression] Weekly resets at: \(wr)")
            }

            // Persist locally and to iCloud
            dataStore.writeSnapshot(newSnapshot, for: selectedProvider)
            cloudSync.writeSnapshot(newSnapshot, for: selectedProvider)

            // Schedule reset notifications
            if dataStore.resetNotificationsEnabled && selectedProvider == .claudeCode {
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
            let recommendedInterval = selectedProvider == .claudeCode
                ? await usageService.recommendedInterval
                : dataStore.refreshInterval
            if recommendedInterval != dataStore.refreshInterval {
                rescheduleTimer(interval: recommendedInterval)
            }
        } catch UsageService.FetchError.unauthorized {
            self.isLoading = false
            self.tokenStatus = .expired
            self.error = "Token 已失效，請重新執行 claude login"
        } catch {
            self.isLoading = false
            if let cached = cloudSync.readSnapshot(for: selectedProvider) {
                self.snapshot = cached
            } else if let local = dataStore.readSnapshot(for: selectedProvider) {
                self.snapshot = local
            } else {
                self.snapshot = .empty(for: selectedProvider)
            }
            self.error = error.localizedDescription
            onSnapshotChanged?()
        }
    }

    private func rescheduleTimer(interval: TimeInterval? = nil) {
        timer?.invalidate()
        let iv = interval ?? dataStore.refreshInterval
        let newTimer = Timer(timeInterval: iv, repeats: true) { [weak self] _ in
            Task { await self?.fetchOnce() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
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

    var requiresOnboarding: Bool {
        selectedProvider.requiresToken && (tokenStatus == .notFound || tokenStatus == .unknown || tokenStatus == .expired)
    }

    var providerDisplayName: String {
        selectedProvider.displayName
    }

    var providerShortName: String {
        selectedProvider.shortName
    }

    func selectProvider(_ provider: UsageProviderKind) {
        guard selectedProvider != provider else { return }
        stopPolling()
        selectedProvider = provider
        dataStore.selectedProvider = provider
        error = nil
        snapshot = dataStore.readSnapshot(for: provider)
            ?? cloudSync.readSnapshot(for: provider)
            ?? .empty(for: provider)
        tokenStatus = provider.requiresToken ? .unknown : .notRequired
        onSnapshotChanged?()
        if provider.requiresToken {
            loadToken()
            if !requiresOnboarding {
                startPolling()
            }
        } else {
            startPolling()
        }
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
