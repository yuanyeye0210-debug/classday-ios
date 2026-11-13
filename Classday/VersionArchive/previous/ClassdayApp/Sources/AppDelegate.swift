import BackgroundTasks
import UIKit
import UserNotifications
import ClassdayCore

extension Notification.Name {
    static let classdayOpenCourse = Notification.Name("classday.openCourse")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: NextClassActivity.backgroundTaskID,
            using: nil
        ) { task in
            Task {
                // SharedWidgetStore lives in the widget extension target and is
                // not visible to the app target; this mirrors its load() exactly
                // using the same ClassdayCore calls (AppGroupContainer +
                // StoreCodec). If the shared store has no document, there is
                // nothing to refresh and nothing to re-queue.
                guard let storeURL = AppGroupContainer.storeURL(),
                      let data = try? Data(contentsOf: storeURL),
                      let document = StoreCodec.importing(data).document else {
                    task.setTaskCompleted(success: true)
                    return
                }
                let calendar = ClassdayCalendar.make()
                // Await the ActivityKit updates before completing the task:
                // completing first would let the system suspend the app
                // while the lock-screen updates are still in flight.
                await NextClassActivity.syncAsync(document: document, calendar: calendar)
                NextClassActivity.scheduleBackgroundRefresh(document: document, calendar: calendar)
                task.setTaskCompleted(success: true)
            }
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let kind = info["reminderKind"] as? Int, kind != PlannedReminder.Kind.course.rawValue {
            NotificationCenter.default.post(name: .classdayOpenCourse, object: nil, userInfo: ["reminderKind": kind])
            return
        }
        guard let rawCourse = info["courseID"] as? String, let courseID = UUID(uuidString: rawCourse) else { return }
        let meetingID = (info["meetingID"] as? String).flatMap(UUID.init(uuidString:))
        var payload: [String: Any] = ["courseID": courseID]
        if let meetingID {
            payload["meetingID"] = meetingID
        }
        NotificationCenter.default.post(name: .classdayOpenCourse, object: nil, userInfo: payload)
    }
}
