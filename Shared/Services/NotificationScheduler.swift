import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

actor NotificationScheduler {
    private var scheduledResetIDs: Set<String> = []
    private var scheduledResetDates: [String: Date] = [:]  // tracks last scheduled date per ID
    private var sentThresholdIDs: Set<String> = []
    private var unPermission = false

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            unPermission = granted
            return granted
        } catch {
            NSLog("[Impression] UNUserNotificationCenter permission error: \(error)")
            unPermission = false
            return false
        }
    }

    func sendTestNotification() async -> Bool {
        let hasPermission = await ensurePermission()
        guard hasPermission else {
            #if os(macOS)
            Task { @MainActor in
                self.deliverLegacyMacNotification(
                title: "Impression test",
                body: "Notifications are working for \(Date.now.formatted(date: .omitted, time: .shortened))."
                )
            }
            return true
            #else
            NSLog("[Impression] Notifications disabled, skipping test notification")
            return false
            #endif
        }

        let content = UNMutableNotificationContent()
        content.title = "Impression test"
        content.body = "Notifications are working for \(Date.now.formatted(date: .omitted, time: .shortened))."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "test-notification",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Impression] UN test notification failed: \(error)")
            } else {
                NSLog("[Impression] UN test notification scheduled")
            }
        }
        return true
    }

    // MARK: - Reset notifications

    func scheduleResetNotification(type: ResetType, resetsAt: Date) {
        guard resetsAt > Date() else { return }
        // Skip if already scheduled for this exact reset time (prevents duplicate timers on each fetch)
        guard scheduledResetDates[type.notificationID] != resetsAt else { return }
        scheduledResetDates[type.notificationID] = resetsAt

        guard unPermission else {
            NSLog("[Impression] Notifications disabled, skipping \(type.notificationID)")
            return
        }

        scheduleViaUN(type: type, resetsAt: resetsAt)
    }

    /// Use the app's own local notifications for every platform.
    private func scheduleViaUN(type: ResetType, resetsAt: Date) {
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = type.body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: resetsAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: type.notificationID,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Impression] UN schedule failed for \(type.notificationID): \(error)")
            } else {
                NSLog("[Impression] UN scheduled \(type.notificationID) at \(resetsAt)")
            }
        }
        scheduledResetIDs.insert(type.notificationID)
    }

    // MARK: - Threshold warnings

    func checkThresholds(snapshot: UsageSnapshot, warningAt: Double, criticalAt: Double) {
        if snapshot.sessionUtilization >= criticalAt {
            if !sentThresholdIDs.contains("session-critical") {
                sentThresholdIDs.insert("session-critical")
                sendNotificationNow(
                    id: "session-critical",
                    title: "Session 即將耗盡",
                    body: formatResetTime(snapshot.sessionResetsAt)
                )
            }
        } else if snapshot.sessionUtilization >= warningAt {
            // Dropped below critical → allow re-notify if it climbs back
            sentThresholdIDs.remove("session-critical")
            if !sentThresholdIDs.contains("session-warning") {
                sentThresholdIDs.insert("session-warning")
                sendNotificationNow(
                    id: "session-warning",
                    title: "Session 已用 \(Int(snapshot.sessionUtilization))%",
                    body: "預估剩餘約 1 小時"
                )
            }
        } else {
            // Usage dropped below warning → reset both so next crossing triggers again
            sentThresholdIDs.remove("session-warning")
            sentThresholdIDs.remove("session-critical")
        }
    }

    // MARK: - Token expiry reminders (iOS manual paste flow)

    func scheduleTokenExpiryReminder(expiresAt: Date) {
        let reminderTime = expiresAt.addingTimeInterval(-2 * 3600) // 2h before
        guard reminderTime > Date() else { return }

        guard unPermission else {
            NSLog("[Impression] Notifications disabled, skipping token-expiry-reminder")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Token 即將過期"
        content.body = "請在 Terminal 重新取得 token 並貼上"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminderTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "token-expiry-reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Impression] UN schedule failed for token-expiry-reminder: \(error)")
            }
        }
    }

    // MARK: - Status notification (app sends on first fetch)

    func sendStatusNotification(snapshot: UsageSnapshot) {
        let sessionCD = formatCountdown(snapshot.sessionResetsAt) ?? "N/A"
        let weeklyCD = formatCountdown(snapshot.weeklyResetsAt) ?? "N/A"
        let title = "Session \(Int(snapshot.sessionUtilization))% · Weekly \(Int(snapshot.weeklyUtilization))%"
        let body = "Session 重置: \(sessionCD) | Weekly 重置: \(weeklyCD)"
        sendNotificationNow(id: "status-update", title: title, body: body)
    }

    private func formatCountdown(_ date: Date?) -> String? {
        guard let date, date > Date() else { return nil }
        let interval = date.timeIntervalSinceNow
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        return "\(hours)h \(minutes)m"
    }

    // MARK: - Send immediately

    private func sendNotificationNow(id: String, title: String, body: String) {
        guard unPermission else {
            #if os(macOS)
            Task { @MainActor in
                self.deliverLegacyMacNotification(title: title, body: body)
            }
            return
            #else
            NSLog("[Impression] Notifications disabled, skipping immediate notification \(id)")
            return
            #endif
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Impression] UN immediate notification failed for \(id): \(error)")
            }
        }
    }

    private func ensurePermission() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            unPermission = true
            return true
        case .notDetermined:
            return await requestPermission()
        case .denied:
            unPermission = false
            return false
        @unknown default:
            unPermission = false
            return false
        }
    }

    #if os(macOS)
    @MainActor
    private func deliverLegacyMacNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
        NSLog("[Impression] Delivered legacy macOS notification")
    }
    #endif

    private func formatResetTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(formatter.localizedString(for: date, relativeTo: Date())) 後重置"
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        scheduledResetIDs.removeAll()
        scheduledResetDates.removeAll()
    }

    enum ResetType {
        case session
        case weekly

        var notificationID: String {
            switch self {
            case .session: return "session-reset"
            case .weekly: return "weekly-reset"
            }
        }

        var title: String {
            switch self {
            case .session: return "Session 額度已重置"
            case .weekly: return "Weekly 額度已重置"
            }
        }

        var body: String {
            return "Claude Code 可以繼續使用了"
        }
    }
}
