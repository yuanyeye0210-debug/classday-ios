import Combine
import SwiftUI
import ClassdayCore

@main
struct ClassdayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppRuntime.model

    var body: some Scene {
        WindowGroup {
            RootView()
                .supplyingAppModel(model)
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
    @Environment(\.appModel) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let chrome = ClassdayChrome.resolve(
            choice: model.document.appearance,
            reduceMotion: reduceMotion,
            lowPower: model.lowPower
        )
        content
            .supplyingAppModel(model)
            .environment(\.classdayChrome, chrome)
            .tint(Color(chrome.theme.accent.palette))
            .preferredColorScheme(chrome.theme.prefersDark ? .dark : .light)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
                model.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onAppear {
                applyScreenshotTheme()
                Task { await exerciseIfRequested() }
            }
    }

    private func exerciseIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--exercise") else { return }
        model.tab = .timetable
        try? await Task.sleep(nanoseconds: 500_000_000)
        for tab in [AppTab.timetable, .agenda, .settings] {
            model.tab = tab
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        model.tab = .timetable
        for theme in ClassdayThemes.all {
            model.setAppearance(AppearanceChoice(themeID: theme.id, performance: .balanced))
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = folder.appendingPathComponent("exercise-ok.txt")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data("ok\n".utf8).write(to: url)
    }

    private func applyScreenshotTheme() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--theme"), index + 1 < arguments.count else { return }
        model.setAppearance(AppearanceChoice(themeID: arguments[index + 1], performance: .balanced))
    }
}
