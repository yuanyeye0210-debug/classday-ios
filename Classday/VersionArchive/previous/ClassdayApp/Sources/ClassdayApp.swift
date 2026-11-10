import Combine
import SwiftUI
import ClassdayCore

@main
struct ClassdayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .tint(Theme.accent)
                .onOpenURL { model.open(url: $0) }
                .onReceive(NotificationCenter.default.publisher(for: .classdayOpenCourse)) { note in
                    guard let courseID = note.userInfo?["courseID"] as? UUID else { return }
                    let meetingID = note.userInfo?["meetingID"] as? UUID
                    model.openCourse(courseID, meeting: meetingID)
                }
        }
    }
}
