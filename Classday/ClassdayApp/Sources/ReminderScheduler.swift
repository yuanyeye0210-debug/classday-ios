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
        await ReminderDelivery.replacePending(reminders, calendar: calendar)
    }
}
