import Foundation
import UserNotifications

actor NotificationScheduler {
    private var scheduledResetIDs: Set<String> = []

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Reset notifications

    func scheduleResetNotification(type: ResetType, resetsAt: Date) {
        guard resetsAt > Date() else { return }

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

        UNUserNotificationCenter.current().add(request) { _ in }
        scheduledResetIDs.insert(type.notificationID)
    }

    // MARK: - Threshold warnings

    func checkThresholds(snapshot: UsageSnapshot, warningAt: Double, criticalAt: Double) {
        if snapshot.sessionUtilization >= criticalAt {
            sendThresholdNotification(
                id: "session-critical",
                title: "Session \(NSLocalizedString("即將耗盡", comment: ""))",
                body: formatResetTime(snapshot.sessionResetsAt)
            )
        } else if snapshot.sessionUtilization >= warningAt {
            sendThresholdNotification(
                id: "session-warning",
                title: "Session \(NSLocalizedString("已用", comment: "")) \(Int(snapshot.sessionUtilization))%",
                body: NSLocalizedString("預估剩餘約 1 小時", comment: "")
            )
        }
    }

    // MARK: - Token expiry reminders (iOS manual paste flow)

    func scheduleTokenExpiryReminder(expiresAt: Date) {
        let reminderTime = expiresAt.addingTimeInterval(-2 * 3600) // 2h before
        guard reminderTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Token 即將過期"
        content.body = "請在 Terminal 重新取得 token 並貼上"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminderTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "token-expiry-reminder",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Helpers

    private func sendThresholdNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // fire immediately
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func formatResetTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(formatter.localizedString(for: date, relativeTo: Date())) 後重置"
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        scheduledResetIDs.removeAll()
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
