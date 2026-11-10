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
                .modifier(ChromeInstaller())
                .onOpenURL { url in
                    if url.host == "timetable",
                       let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value,
                       let payload = ShareCodec.decode(token) {
                        model.applySharedTimetable(payload)
                    } else {
                        model.open(url: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .classdayOpenCourse)) { note in
                    guard let courseID = note.userInfo?["courseID"] as? UUID else { return }
                    let meetingID = note.userInfo?["meetingID"] as? UUID
                    model.openCourse(courseID, meeting: meetingID)
                }
        }
    }
}

private struct ChromeInstaller: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let chrome = ClassdayChrome.resolve(
            choice: model.document.appearance,
            reduceMotion: reduceMotion,
            lowPower: model.lowPower
        )
        content
            .environment(\.classdayChrome, chrome)
            .tint(Color(chrome.theme.accent.palette))
            .preferredColorScheme(chrome.theme.prefersDark ? .dark : .light)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
                model.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onAppear {
                applyScreenshotTheme()
            }
    }

    private func applyScreenshotTheme() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--theme"), index + 1 < arguments.count else { return }
        model.setAppearance(AppearanceChoice(themeID: arguments[index + 1], performance: .balanced))
    }
}
