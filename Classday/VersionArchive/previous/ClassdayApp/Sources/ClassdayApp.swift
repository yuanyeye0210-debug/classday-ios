import Combine
import SwiftUI
import ClassdayCore

@main
struct ClassdayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .modifier(ChromeInstaller(model: model))
                .onOpenURL { url in
                    if url.host == "timetable",
                       let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value,
                       let payload = ShareCodec.decode(token) {
                        model.stageSharedTimetable(payload)
                    } else {
                        model.open(url: url)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.reloadFromDiskIfChanged()
                        model.refreshLiveActivityIfNeeded()
                        model.triggerDailyAutoCheck()
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
    // Passed in directly, not via @Environment: a modifier cannot see
    // environment values injected onto its own content, and reading a
    // missing @Environment object traps on the first graph update.
    var model: AppModel
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
        if arguments.contains("--detail"),
           let course = model.document.courses.first,
           let meeting = course.meetings.first {
            // CI screenshot hook: open the first course's detail page so the
            // run produces a preview of it alongside the theme shots.
            model.present(courseID: course.id, meetingID: meeting.id)
        }
        // CI screenshot hooks for the rebuilt frame's other pages.
        if arguments.contains("--week") {
            model.tab = .week
        }
        if arguments.contains("--courses") {
            model.tab = .courses
        }
        if arguments.contains("--exams") {
            model.tab = .today
            model.showExams = true
        }
        if arguments.contains("--smartimport") {
            model.smartImportSample = true
            model.showSmartImport = true
        }
        if arguments.contains("--mine") {
            model.tab = .settings
        }
        guard let index = arguments.firstIndex(of: "--theme"), index + 1 < arguments.count else { return }
        model.setAppearance(AppearanceChoice(themeID: arguments[index + 1], performance: .balanced))
    }
}
