import UIKit
import UserNotifications

extension Notification.Name {
    static let classdayOpenCourse = Notification.Name("classday.openCourse")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
        guard let rawCourse = info["courseID"] as? String, let courseID = UUID(uuidString: rawCourse) else { return }
        let meetingID = (info["meetingID"] as? String).flatMap(UUID.init(uuidString:))
        var payload: [String: Any] = ["courseID": courseID]
        if let meetingID {
            payload["meetingID"] = meetingID
        }
        NotificationCenter.default.post(name: .classdayOpenCourse, object: nil, userInfo: payload)
    }
}
