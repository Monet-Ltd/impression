import Foundation
import Combine

@MainActor @Observable
final class UsageViewModel {
    struct ClaudeTokenResolution: Equatable {
        let token: String?
        let expiry: Date?
        let status: TokenStatus
    }
    var selectedProvider: UsageProviderKind
    var snapshot: UsageSnapshot
    var isLoading = false
    var error: String?
    var tokenStatus: TokenStatus = .unknown
    var currentRefreshInterval: TimeInterval
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
        self.currentRefreshInterval = dataStore.refreshInterval
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

        #if os(macOS)
        let fallbackCredentials = ClaudeCredentialsSource.readOAuthCredentials()
        #else
        let fallbackCredentials: OAuthCredentials? = nil
        #endif

        let resolution = Self.resolveClaudeToken(
            syncedToken: cloudSync.readTokenFromKeychain(),
            syncedExpiry: cloudSync.readTokenExpiry(),
            fallbackCredentials: fallbackCredentials
        )

        token = resolution.token
        tokenStatus = resolution.status
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
        currentRefreshInterval = iv
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

    func sendTestNotification() async {
        let delivered = await notificationScheduler.sendTestNotification()
        if !delivered {
            error = "Notifications are disabled for Impression"
            onSnapshotChanged?()
        }
    }

    // MARK: - Helpers

    var sessionColor: UsageColor {
        UsageColor.from(utilization: snapshot.sessionUtilization)
    }

    var weeklyColor: UsageColor {
        UsageColor.from(utilization: snapshot.weeklyUtilization)
    }

    var sessionResetCountdown: String? {
        resetDisplayText(for: snapshot.sessionResetsAt, utilization: snapshot.sessionUtilization)
    }

    var weeklyResetCountdown: String? {
        resetDisplayText(for: snapshot.weeklyResetsAt, utilization: snapshot.weeklyUtilization)
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

    private func resetDisplayText(for date: Date?, utilization: Double) -> String? {
        if let date, date > Date() {
            return formatCountdown(date)
        }

        if snapshot.fetchedAt == .distantPast {
            return nil
        }

        if utilization >= 100 {
            return "Reset pending"
        }

        if utilization > 0 {
            return "Tracking"
        }

        return "Not started"
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

    var sourceDisplayName: String {
        snapshot.sourceDisplayName
    }

    var refreshCadenceText: String {
        let formatted = Self.formatInterval(currentRefreshInterval)
        if selectedProvider == .claudeCode && currentRefreshInterval > AppConstants.defaultRefreshInterval {
            return "Adaptive now \(formatted)"
        }
        return "Every \(formatted)"
    }

    var statusSummaryText: String {
        if let plan = snapshot.normalizedPlanName {
            return "\(plan) plan"
        }

        switch tokenStatus {
        case .unknown:
            return "Checking"
        case .valid:
            return selectedProvider.requiresToken ? "Authenticated" : "Ready"
        case .expiresSoon:
            return "Expires soon"
        case .expired:
            return "Expired"
        case .notFound:
            return "Login required"
        case .notRequired:
            return "Local"
        }
    }
    static func resolveClaudeToken(
        syncedToken: String?,
        syncedExpiry: Date?,
        fallbackCredentials: OAuthCredentials?
    ) -> ClaudeTokenResolution {
        if let syncedToken {
            let status = tokenStatus(for: syncedExpiry)
            return ClaudeTokenResolution(token: syncedToken, expiry: syncedExpiry, status: status)
        }

        if let fallbackCredentials {
            let expiry = fallbackCredentials.expiresAtDate
            let status = tokenStatus(for: expiry)
            return ClaudeTokenResolution(token: fallbackCredentials.accessToken, expiry: expiry, status: status)
        }

        return ClaudeTokenResolution(token: nil, expiry: nil, status: .notFound)
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

    private static func tokenStatus(for expiry: Date?) -> TokenStatus {
        guard let expiry else { return .valid }
        if expiry < Date() {
            return .expired
        }
        if expiry.timeIntervalSinceNow < 2 * 3600 {
            return .expiresSoon(expiry)
        }
        return .valid
    }

    private static func formatInterval(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval.rounded()) / 60, 1)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes)m"
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
