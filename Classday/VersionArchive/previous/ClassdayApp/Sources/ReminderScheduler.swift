import UserNotifications
import ClassdayCore

@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func statusText() async -> String {
        switch await status() {
        case .notDetermined:
            return "未请求"
        case .denied:
            return "已拒绝"
        case .authorized, .provisional, .ephemeral:
            return "已允许"
        @unknown default:
            return "未知"
        }
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings().authorizationStatus
        switch current {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Replaces this app's pending reminders. Does not prompt. Skips delivery when permission is off.
    func apply(_ reminders: [PlannedReminder], calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let owned = pending.map(\.identifier).filter { $0.hasPrefix("classday-") }
        center.removePendingNotificationRequests(withIdentifiers: owned)
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else {
            return
        }
        for reminder in reminders.prefix(NotificationPlan.pendingLimit) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["reminderKind": reminder.kind.rawValue]
            if let courseID = reminder.courseID { content.userInfo["courseID"] = courseID.uuidString }
            if let meetingID = reminder.meetingID { content.userInfo["meetingID"] = meetingID.uuidString }
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
