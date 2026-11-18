import AppIntents
import Combine
import SwiftUI
import ClassdayCore

@main
struct ClassdayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    init() {
        ClassdayShortcuts.updateAppShortcutParameters()
    }

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
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        let filter = try? await ClassroomFocusFilter.current
                        guard !Task.isCancelled else { return }
                        await MainActor.run { model.systemFocusFilter = filter?.onlyCurrent ?? false }
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    }
                }
                .onAppear { openClassroomIfRequested() }
                .onReceive(NotificationCenter.default.publisher(for: ClassroomIntentRoute.notification)) { _ in
                    openClassroomIfRequested()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        openClassroomIfRequested()
                        model.reloadFromDiskIfChanged()
                        model.refreshLiveActivityIfNeeded()
                        model.triggerDailyAutoCheck()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .classdayOpenCourse)) { note in
                    if let kind = note.userInfo?["reminderKind"] as? Int {
                        if kind == PlannedReminder.Kind.exam.rawValue {
                            model.tab = .today
                            model.showExams = true
                        } else if kind == PlannedReminder.Kind.homework.rawValue {
                            model.tab = .settings
                            // Present after the destination tab has mounted its sheet.
                            DispatchQueue.main.async {
                                model.showStudyDesk = true
                            }
                        }
                        return
                    }
                    guard let courseID = note.userInfo?["courseID"] as? UUID else { return }
                    let meetingID = note.userInfo?["meetingID"] as? UUID
                    model.openCourse(courseID, meeting: meetingID)
                }
        }
    }
    private func openClassroomIfRequested() {
        guard ClassroomIntentRoute.consume() else { return }
        model.open(url: URL(string: "classday://classroom")!)
    }
}

// A pending route survives the intent running before the root view subscribes.
private enum ClassroomIntentRoute {
    static let notification = Notification.Name("classday.openClassroom")
    static let key = "classday.pendingClassroomRoute"
    static func request() {
        UserDefaults.standard.set(true, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }
    static func consume() -> Bool {
        guard UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.removeObject(forKey: key)
        return true
    }
}

private struct ChromeInstaller: ViewModifier {
    // Passed in directly, not via @Environment: a modifier cannot see
    // environment values injected onto its own content, and reading a
    // missing @Environment object traps on the first graph update.
    var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { tick in
            let classroom = TodayProjection.make(at: tick.date,
                document: model.loadError == nil ? model.document : nil,
                calendar: model.calendar).classroomCourse != nil
            let systemFilter = model.systemFocusFilter
            let chrome = ClassdayChrome.resolve(
                choice: model.document.appearance,
                reduceMotion: reduceMotion || classroom || systemFilter,
                lowPower: model.lowPower || classroom || systemFilter
            )
            content
                .environment(\.classdayChrome, chrome)
                .tint(Color(chrome.theme.accent.palette))
                .preferredColorScheme(chrome.theme.prefersDark ? .dark : .light)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
                    model.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                }
                .onAppear { applyScreenshotTheme() }
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


// The same primary/fallback decoding policy used by the widget provider.
private enum IntentScheduleStore {
    static func load() -> StoreDocument? {
        let primary = AppGroupContainer.storeURL().flatMap { try? Data(contentsOf: $0) }
        let fallback = AppGroupContainer.resolution().identifier.flatMap {
            UserDefaults(suiteName: $0)?.data(forKey: WidgetStoreSnapshot.defaultsKey)
        }
        return WidgetStoreSnapshot.document(primary: primary, fallback: fallback)
    }
}

struct NextClassIntent: AppIntent {
    static var title: LocalizedStringResource = "下节课是什么"
    static var description = IntentDescription("读取课曜已同步课表的下一节课。")
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = ScheduleAnswers.nextClass(document: IntentScheduleStore.load(), at: Date(), calendar: ClassdayCalendar.make())
        return .result(value: answer, dialog: "\(answer)")
    }
}

struct EndOfSchoolDayIntent: AppIntent {
    static var title: LocalizedStringResource = "今天几点下课"
    static var description = IntentDescription("读取今天最后一节课的结束时间。")
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = ScheduleAnswers.endOfDay(document: IntentScheduleStore.load(), at: Date(), calendar: ClassdayCalendar.make())
        return .result(value: answer, dialog: "\(answer)")
    }
}

// UI-only filtering: read the system's current configuration on foreground refresh.
// No App Group/signing changes and no attempt to turn system Focus on or off.
struct ClassroomFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "上课界面"
    static var description = IntentDescription("在已有系统专注开启时，仅突出当前或下一节课并减少背景动效。")
    @Parameter(title: "精简课曜界面", default: false)
    var onlyCurrent: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "上课界面", subtitle: onlyCurrent ? "精简课程与安排" : "显示完整安排")
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [ClassroomFocusFilter] {
        var filter = ClassroomFocusFilter()
        filter.onlyCurrent = true
        return [filter]
    }

    func perform() async throws -> some IntentResult { .result() }
}

struct StartClassroomFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "开始上课专注"
    static var description = IntentDescription("打开课曜的自动上课界面，不切换系统专注模式。")
    static var openAppWhenRun: Bool = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        ClassroomIntentRoute.request()
        let answer = ScheduleAnswers.classroom(document: IntentScheduleStore.load(), at: Date(), calendar: ClassdayCalendar.make())
        return .result(dialog: "\(answer)")
    }
}

struct ClassdayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextClassIntent(), phrases: ["\(.applicationName)下节课是什么", "\(.applicationName)下节课"],
                    shortTitle: "下节课是什么", systemImageName: "calendar")
        AppShortcut(intent: EndOfSchoolDayIntent(), phrases: ["\(.applicationName)今天几点下课", "\(.applicationName)下课时间"],
                    shortTitle: "今天几点下课", systemImageName: "clock")
        AppShortcut(intent: StartClassroomFocusIntent(), phrases: ["开始\(.applicationName)上课专注"],
                    shortTitle: "开始上课专注", systemImageName: "book.closed")
    }
}
