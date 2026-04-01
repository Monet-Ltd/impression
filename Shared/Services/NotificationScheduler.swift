import Foundation
import UserNotifications

actor NotificationScheduler {
    private var scheduledResetIDs: Set<String> = []
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

    // MARK: - Reset notifications

    func scheduleResetNotification(type: ResetType, resetsAt: Date) {
        guard resetsAt > Date() else { return }

        if unPermission {
            scheduleViaUN(type: type, resetsAt: resetsAt)
        } else {
            #if os(macOS)
            scheduleViaMacFallback(type: type, resetsAt: resetsAt)
            #endif
        }
    }

    /// Primary: UNUserNotificationCenter (works on signed apps, iOS always)
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
                #if os(macOS)
                Task { await self.scheduleViaMacFallback(type: type, resetsAt: resetsAt) }
                #endif
            } else {
                NSLog("[Impression] UN scheduled \(type.notificationID) at \(resetsAt)")
            }
        }
        scheduledResetIDs.insert(type.notificationID)
    }

    #if os(macOS)
    /// Fallback for unsigned macOS builds: use DispatchSourceTimer + osascript
    private func scheduleViaMacFallback(type: ResetType, resetsAt: Date) {
        let delay = resetsAt.timeIntervalSinceNow
        guard delay > 0 else { return }

        NSLog("[Impression] macOS fallback: scheduling \(type.notificationID) in \(Int(delay))s via timer")

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            let script = """
            display notification "\(type.body)" with title "\(type.title)" subtitle "Impression" sound name "default"
            """
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            try? proc.run()
            proc.waitUntilExit()
            NSLog("[Impression] macOS fallback: fired \(type.notificationID)")
        }
        scheduledResetIDs.insert(type.notificationID)
    }
    #endif

    // MARK: - Threshold warnings

    func checkThresholds(snapshot: UsageSnapshot, warningAt: Double, criticalAt: Double) {
        if snapshot.sessionUtilization >= criticalAt {
            sendNotificationNow(
                id: "session-critical",
                title: "Session 即將耗盡",
                body: formatResetTime(snapshot.sessionResetsAt)
            )
        } else if snapshot.sessionUtilization >= warningAt {
            sendNotificationNow(
                id: "session-warning",
                title: "Session 已用 \(Int(snapshot.sessionUtilization))%",
                body: "預估剩餘約 1 小時"
            )
        }
    }

    // MARK: - Token expiry reminders (iOS manual paste flow)

    func scheduleTokenExpiryReminder(expiresAt: Date) {
        let reminderTime = expiresAt.addingTimeInterval(-2 * 3600) // 2h before
        guard reminderTime > Date() else { return }

        if unPermission {
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
            UNUserNotificationCenter.current().add(request) { _ in }
        } else {
            #if os(macOS)
            let delay = reminderTime.timeIntervalSinceNow
            guard delay > 0 else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                let script = "display notification \"請在 Terminal 重新取得 token 並貼上\" with title \"Token 即將過期\" subtitle \"Impression\" sound name \"default\""
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                proc.arguments = ["-e", script]
                try? proc.run()
            }
            #endif
        }
    }

    // MARK: - Send immediately

    private func sendNotificationNow(id: String, title: String, body: String) {
        if unPermission {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in }
        } else {
            #if os(macOS)
            let script = "display notification \"\(body)\" with title \"\(title)\" subtitle \"Impression\" sound name \"default\""
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            try? proc.run()
            #endif
        }
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
