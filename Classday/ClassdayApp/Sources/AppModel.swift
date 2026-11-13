import Combine
import Foundation
import Observation
import ClassdayCore

enum TimetableMode: String, CaseIterable, Identifiable {
    case week
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "周课表"
        case .day: return "日课表"
        }
    }
}

enum AppTab: Hashable {
    case today
    case week
    case courses
    case timetable
    case agenda
    case settings
}

struct CoursePresentation: Identifiable, Equatable {
    var courseID: UUID
    var meetingID: UUID
    var id: String { "\(courseID.uuidString)-\(meetingID.uuidString)" }
}

enum EditorRoute: Identifiable, Equatable {
    case newCourse
    case edit(UUID)
    case reschedule(courseID: UUID, meetingID: UUID)

    var id: String {
        switch self {
        case .newCourse:
            return "new"
        case .edit(let id):
            return "edit-\(id.uuidString)"
        case .reschedule(let courseID, let meetingID):
            return "move-\(courseID.uuidString)-\(meetingID.uuidString)"
        }
    }
}

struct DragSession: Equatable {
    var courseID: UUID
    var meetingID: UUID
    var duration: Int
    var originWeekday: Int
    var originStart: Int
    var proposedWeekday: Int
    var proposedStart: Int
    var fingerInside: Bool
}

struct UndoReschedule: Equatable, Identifiable {
    var id = UUID()
    var courseID: UUID
    var meetingID: UUID
    var weekday: Int
    var startPeriod: Int
    var endPeriod: Int
    var message: String
}

@MainActor
@Observable
final class AppModel {
    var document: StoreDocument
    var weekIndex: Int
    var selectedDay: Date
    var mode: TimetableMode = .week
    var tab: AppTab = .today
    var presented: CoursePresentation?
    var editor: EditorRoute?
    var drag: DragSession?
    var undo: UndoReschedule?
    var banner: String?
    var appGroupAvailable: Bool
    var appGroupNotice: String?
    var loadError: String?
    var notificationStatusText = "未请求"
    var showImporter = false
    var importErrors: String?
    var stagedImport: StoreDocument?
    var importWarnings: [String] = []
    var confirmDeleteCourseID: UUID?
    var confirmClear = false
    var confirmReset = false
    var weekSlideForward = true
    var preferSpecialLayout = true
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var showThemeGallery = false
    var showStudyDesk = false
    var showExams = false
    var showSmartImport = false
    /// Merge-review sheet (Task 4): opened from the all-courses entry
    /// row or the post-import banner. `applyCourseMerge` (Task 5)
    /// executes the user's decisions from the page.
    var showMergeReview = false
    /// Post-import banner (Task 4): set by `importCalendar` when
    /// duplicate groups exist afterwards; cleared when the review page
    /// is opened or the banner is dismissed.
    var showDuplicateImportBanner = false
    var smartImportSample = false

    // Update state shared with SettingsView and RootView (Task 6): the last
    // check's row note / download link / decision, and a blocking alert
    // (mandatory or below-minimum) that RootView surfaces app-wide.
    var lastUpdateNote: String?
    var lastUpdateDownloadURL: URL?
    var lastUpdateDecision: UpdateDecision?
    var updateAlert: UpdateService.UpdateAlertKind?
    /// Bounded re-raise flag (fix wave): set when a failed mandatory /
    /// below-minimum download re-raises the blocking alert once; reset
    /// by `applyUpdateCheck`, so one check re-raises at most once and a
    /// persistent network failure cannot loop the alert.
    private var didReRaiseUpdateAlertAfterFailure = false

    // In-app download state, shared so RootView's blocking-alert button
    // can start the download directly and SettingsView shows the same
    // progress / finished IPA / error (fix round 1: the alert button used
    // to only navigate to Settings, leaving a second tap — and a
    // dismissable "non-dismissable" alert — between the user and the
    // download). Owned here, driven by UpdateService.download.
    var downloadingUpdate = false
    var downloadProgress: Double?
    var downloadedIPA: URL?
    var downloadError: String?

    let calendar: Calendar
    private let storeURL: URL
    private var undoTask: Task<Void, Never>?
    private var storeFileModified: Date?
    private var lastLiveActivitySnapshot: NextClassSnapshot.Value?
    private var liveActivityTimer: AnyCancellable?

    init() {
        let calendar = ClassdayCalendar.make()
        self.calendar = calendar
        let fallback = StoreLocator.applicationSupportURL()
        let group = AppGroupContainer.resolution()
        let groupURL = AppGroupContainer.storeURL()
        let resolved = (try? StoreLocator.resolve(groupURL: groupURL, fallbackURL: fallback)) ?? fallback
        storeURL = resolved
        appGroupAvailable = group.identifier != nil
        appGroupNotice = group.identifier == nil
            ? AppGroupSupport.unavailableNotice(profileGroups: group.profileGroups)
            : nil
        undoTask = nil

        let fileManager = FileManager.default
        let loaded: StoreDocument
        var initialError: String?
        var shouldSaveFreshCopy = false
        if fileManager.fileExists(atPath: resolved.path) {
            do {
                loaded = try StoreFile.load(from: resolved)
            } catch {
                // Preserve the unreadable file before any later save can
                // overwrite it with the demo fallback.
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = resolved.deletingLastPathComponent()
                    .appendingPathComponent("classday-store-corrupt-\(stamp).json")
                try? fileManager.copyItem(at: resolved, to: backup)
                loaded = DemoData.makeDocument()
                initialError = "课表文件无法读取，已另存一份损坏文件备份，没有直接覆盖。"
            }
        } else {
            loaded = DemoData.makeDocument()
            shouldSaveFreshCopy = true
        }
        document = loaded
        loadError = initialError
        storeFileModified = Self.modificationDate(of: resolved)

        let now = Date()
        if let week = SemesterCalendar.weekIndex(for: now, semester: loaded.semester, calendar: calendar) {
            weekIndex = week
        } else {
            weekIndex = 1
            if initialError == nil {
                banner = "今天不在学期范围内"
            }
        }
        selectedDay = calendar.startOfDay(for: now)
        if shouldSaveFreshCopy {
            try? StoreFile.save(loaded, to: resolved)
            WidgetReloader.reload()
        }
        Task { [weak self] in
            await self?.refreshNotificationStatus()
            await self?.refreshReminders()
        }
        // Launch-only: a stored version that differs from the current one
        // means this version was just installed. First launch stores
        // silently and reports nothing.
        UpdateService.reportInstalledIfNeeded()
        // Re-sync the Live Activity once a minute while the app is active, so
        // the lock screen flips at class boundaries even if the app stays
        // open. The diff gate inside refreshLiveActivityIfNeeded() means a
        // tick that changes nothing pushes nothing. The timer does nothing
        // while the app is suspended in the background (Task 4).
        liveActivityTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshLiveActivityIfNeeded()
            }
    }

    init(document: StoreDocument, storeURL: URL, appGroupAvailable: Bool, now: Date = Date()) {
        self.document = document
        self.storeURL = storeURL
        self.appGroupAvailable = appGroupAvailable
        self.appGroupNotice = appGroupAvailable ? nil : AppGroupSupport.unavailableNotice(profileGroups: [])
        let calendar = ClassdayCalendar.make()
        self.calendar = calendar
        storeFileModified = Self.modificationDate(of: storeURL)
        weekIndex = SemesterCalendar.weekIndex(for: now, semester: document.semester, calendar: calendar) ?? 1
        selectedDay = calendar.startOfDay(for: now)
    }

    static func preview() -> AppModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("classday-preview-\(UUID().uuidString).json")
        return AppModel(document: DemoData.makeDocument(), storeURL: url, appGroupAvailable: false)
    }

    /// Applies one completed update check (manual or automatic) to the
    /// shared state: the Settings row, the download link, and — only for a
    /// mandatory update or a below-minimum install — the blocking alert.
    /// Network errors ("检查失败") and "already latest" never raise an alert.
    func applyUpdateCheck(_ result: UpdateService.CheckResult) {
        lastUpdateNote = result.note
        lastUpdateDownloadURL = result.downloadURL
        lastUpdateDecision = result.decision
        // A new check resets the bounded re-raise: one check re-raises
        // the blocking alert at most once after a failed download.
        didReRaiseUpdateAlertAfterFailure = false
        switch result.decision {
        case let .updateAvailable(release, mandatory: true):
            updateAlert = .mandatory(release: release)
        case let .belowMinimumSupported(release):
            updateAlert = .belowMinimum(release: release)
        default:
            // A later up-to-date / failure result clears a stale alert, so
            // a dismissed update does not keep blocking the app after the
            // next check says there is nothing to install.
            updateAlert = nil
        }
    }

    /// Starts the in-app IPA download for `release` with Range resume +
    /// progress, SHA-256 verification, and the finished IPA on success.
    /// Shared entry point: RootView's blocking-alert "下载更新" button and
    /// the Settings download row both call this, so the alert button
    /// really downloads. A second call while a download is running is a
    /// no-op. On total failure the error is kept in `downloadError` and
    /// the Safari fallback in Settings stays available; a failed
    /// mandatory / below-minimum download re-raises the blocking alert
    /// once (see `reRaiseBlockingAlertIfNeeded`), so the user is not
    /// silently un-blocked until the next day.
    func startUpdateDownload(release: ReleaseEntry) async {
        guard !downloadingUpdate else { return }
        downloadingUpdate = true
        downloadError = nil
        downloadedIPA = nil
        downloadProgress = 0
        defer { downloadingUpdate = false }
        // The service reports progress from a background context; hop to
        // the main actor before touching view state.
        let result = await UpdateService.download(release: release) { [weak self] value in
            Task { @MainActor in self?.downloadProgress = value }
        }
        switch result {
        case let .success(url):
            downloadedIPA = url
            downloadProgress = 1
        case let .failure(reason):
            downloadError = reason
            downloadProgress = nil
            reRaiseBlockingAlertIfNeeded()
        }
    }

    /// Re-raises the blocking alert once per check when a mandatory or
    /// below-minimum download failed: the alert was already cleared when
    /// the user tapped "下载更新", and the daily auto-check gate was
    /// already consumed, so without this the user would be silently
    /// un-blocked until tomorrow or a manual tap. Bounded by
    /// `didReRaiseUpdateAlertAfterFailure` (reset on each new check), so
    /// a persistent network failure cannot loop the alert; the Settings
    /// error text + retry row is the escape hatch. Ordinary
    /// (non-mandatory, above-minimum) updates never re-raise.
    private func reRaiseBlockingAlertIfNeeded() {
        guard !didReRaiseUpdateAlertAfterFailure else { return }
        switch lastUpdateDecision {
        case let .updateAvailable(release, mandatory: true):
            updateAlert = .mandatory(release: release)
            didReRaiseUpdateAlertAfterFailure = true
        case let .belowMinimumSupported(release):
            updateAlert = .belowMinimum(release: release)
            didReRaiseUpdateAlertAfterFailure = true
        default:
            break
        }
    }

    /// Silent daily auto-check, triggered from the existing foreground path
    /// (`scenePhase == .active`, which also fires on launch). At most once
    /// per calendar day; never blocks launch — the check runs in a detached
    /// `Task` and only surfaces UI (row note, blocking alert) when an
    /// update, mandatory, or below-minimum condition is found. A manual tap
    /// in Settings always checks and does not consult this gate.
    func triggerDailyAutoCheck() {
        guard UpdateService.shouldAutoCheck() else { return }
        // Record the date when the check STARTS, not when it completes:
        // two foreground transitions during one slow check would both pass
        // the gate and run duplicate checks (and duplicate `update_check`
        // reports). `checkForUpdate` still records on completion as well.
        UpdateService.recordCheckDate()
        Task { [weak self] in
            guard let self else { return }
            let result = await UpdateService.checkForUpdate(currentVersion: UpdateService.currentVersion())
            self.applyUpdateCheck(result)
        }
    }

    func occurrences(inWeek week: Int? = nil) -> [Occurrence] {
        ScheduleEngine.occurrences(
            inWeek: week ?? weekIndex,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar,
            context: document.scheduleContext
        )
    }

    func occurrences(on date: Date) -> [Occurrence] {
        ScheduleEngine.occurrences(on: date, courses: document.courses, semester: document.semester, calendar: calendar, context: document.scheduleContext)
    }

    func holiday(on date: Date) -> HolidayPeriod? {
        SemesterCalendar.holiday(on: date, semester: document.semester, calendar: calendar)
    }

    func shiftWeek(by delta: Int) {
        let next = min(max(1, weekIndex + delta), document.semester.totalWeeks)
        guard next != weekIndex else { return }
        weekSlideForward = delta > 0
        let weekday = SemesterCalendar.isoWeekday(selectedDay, calendar: calendar)
        weekIndex = next
        let dates = SemesterCalendar.dates(inWeek: next, semester: document.semester, calendar: calendar)
        if weekday >= 1, weekday <= dates.count {
            selectedDay = dates[weekday - 1]
        }
    }

    func returnToCurrentWeek() {
        let now = Date()
        weekSlideForward = true
        if let week = SemesterCalendar.weekIndex(for: now, semester: document.semester, calendar: calendar) {
            let current = weekIndex
            weekSlideForward = week >= current
            weekIndex = week
            selectedDay = calendar.startOfDay(for: now)
        } else {
            weekIndex = 1
            banner = "今天不在学期范围内"
        }
    }

    func shiftDay(by delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: delta, to: selectedDay),
              let week = SemesterCalendar.weekIndex(for: next, semester: document.semester, calendar: calendar) else {
            banner = "已经到学期边界"
            return
        }
        weekSlideForward = delta > 0
        selectedDay = calendar.startOfDay(for: next)
        weekIndex = week
    }

    func select(day: Date) {
        guard let week = SemesterCalendar.weekIndex(for: day, semester: document.semester, calendar: calendar) else { return }
        selectedDay = calendar.startOfDay(for: day)
        weekIndex = week
        mode = .day
    }

    func present(courseID: UUID, meetingID: UUID) {
        presented = CoursePresentation(courseID: courseID, meetingID: meetingID)
    }

    func openCourse(_ courseID: UUID, meeting meetingID: UUID?) {
        guard let course = document.courses.first(where: { $0.id == courseID }) else {
            banner = "找不到这门课"
            return
        }
        guard let meetingID = meetingID ?? course.meetings.first?.id else { return }
        tab = .week
        if let week = SemesterCalendar.weekIndex(for: Date(), semester: document.semester, calendar: calendar),
           course.weeks.contains(week) {
            weekIndex = week
        } else if let first = course.weeks.first {
            weekIndex = first
        }
        presented = CoursePresentation(courseID: courseID, meetingID: meetingID)
    }

    func open(url: URL) {
        guard let link = ClassdayLink.parse(url) else { return }
        openCourse(link.courseID, meeting: link.meetingID)
    }

    func beginNewCourse() {
        editor = .newCourse
    }

    func saveCourse(_ course: Course) -> String? {
        var next = document
        if let index = next.courses.firstIndex(where: { $0.id == course.id }) {
            next.courses[index] = course
        } else {
            next.courses.append(course)
        }
        let normalized = StoreCodec.normalized(next)
        let report = StoreCodec.validate(normalized, calendar: calendar)
        if let error = report.errors.first { return error }
        if let conflict = ScheduleEngine.conflicts(among: normalized.courses, context: normalized.scheduleContext).first(where: {
            $0.courseID == course.id || $0.otherCourseID == course.id
        }) {
            return ScheduleCopy.conflictMessage(conflict)
        }
        document = normalized
        editor = nil
        persist(markUserEdited: true)
        banner = "已保存"
        return nil
    }

    func deleteCourse(_ courseID: UUID) {
        document.courses.removeAll { $0.id == courseID }
        if presented?.courseID == courseID { presented = nil }
        confirmDeleteCourseID = nil
        persist(markUserEdited: true)
        banner = "已删除课程"
    }

    func updateSemester(_ semester: Semester) -> String? {
        var next = document
        if semester.periods != document.semester.periods {
            // Insurance: a period table re-maps every class in the book, so
            // stash the pre-change document in the library first - the old
            // table stays one tap away if the new one is wrong.
            next = TimetableLibrary.storingCurrent(next, as: "节次修改前备份")
        }
        next.semester = semester
        let normalized = StoreCodec.normalized(next)
        let report = StoreCodec.validate(normalized, calendar: calendar)
        if let error = report.errors.first { return error }
        document = normalized
        if weekIndex > document.semester.totalWeeks {
            weekIndex = document.semester.totalWeeks
        }
        persist(markUserEdited: true)
        if let warning = report.warnings.first(where: { $0.contains("时钟") }) {
            banner = warning
        } else {
            banner = "学期设置已保存"
        }
        return nil
    }

    func setReminder(courseID: UUID, enabled: Bool) async {
        guard let index = document.courses.firstIndex(where: { $0.id == courseID }) else { return }
        if enabled {
            let granted = await ReminderScheduler.shared.requestAuthorization()
            let lead = document.semester.defaultReminderMinutes == 0 ? 10 : document.semester.defaultReminderMinutes
            document.courses[index].reminderLeadMinutes = lead
            if !granted {
                banner = "已记下提醒，但系统通知尚未允许"
            }
        } else {
            document.courses[index].reminderLeadMinutes = 0
        }
        persist(markUserEdited: true)
        await refreshNotificationStatus()
    }

    func stageImport(_ data: Data) {
        let outcome = StoreCodec.importing(data, calendar: calendar)
        if !outcome.errors.isEmpty {
            importErrors = outcome.errors.joined(separator: "\n")
            stagedImport = nil
            importWarnings = []
            return
        }
        guard let document = outcome.document else { return }
        if outcome.warnings.isEmpty {
            replace(with: document)
            banner = "已导入 \(document.courses.count) 门课程"
        } else {
            stagedImport = document
            importWarnings = outcome.warnings
        }
    }

    func commitStagedImport() {
        guard let stagedImport else { return }
        replace(with: stagedImport)
        banner = "已导入，含 \(importWarnings.count) 条重叠提示"
        self.stagedImport = nil
        importWarnings = []
    }

    func exportData() throws -> Data {
        try StoreCodec.encode(document)
    }

    func resetDemo() {
        document = DemoData.makeDocument()
        presented = nil
        undo = nil
        drag = nil
        realignWeek()
        persist(markUserEdited: false)
        banner = "已恢复演示数据"
        confirmReset = false
    }

    func clearCourses() {
        document = StoreEditing.cleared(document)
        presented = nil
        undo = nil
        drag = nil
        persist(markUserEdited: false)
        banner = "已清空课程"
        confirmClear = false
    }

    func beginDrag(_ occurrence: Occurrence) {
        drag = DragSession(
            courseID: occurrence.courseID,
            meetingID: occurrence.meetingID,
            duration: occurrence.endPeriod - occurrence.startPeriod + 1,
            originWeekday: occurrence.weekday,
            originStart: occurrence.startPeriod,
            proposedWeekday: occurrence.weekday,
            proposedStart: occurrence.startPeriod,
            fingerInside: true
        )
    }

    func updateDrag(weekday: Int, startPeriod: Int, fingerInside: Bool) {
        guard var drag else { return }
        drag.proposedWeekday = weekday
        drag.proposedStart = startPeriod
        drag.fingerInside = fingerInside
        self.drag = drag
    }

    func dragValidation() -> MoveValidation? {
        guard let drag else { return nil }
        return ScheduleEngine.validateMove(
            courseID: drag.courseID,
            meetingID: drag.meetingID,
            weekday: drag.proposedWeekday,
            startPeriod: drag.proposedStart,
            courses: document.courses,
            semester: document.semester,
            context: document.scheduleContext
        )
    }

    func commitDrag() {
        guard let drag else { return }
        defer { self.drag = nil }
        guard drag.fingerInside else {
            Haptics.warning()
            banner = "已取消调整"
            return
        }
        let validation = ScheduleEngine.validateMove(
            courseID: drag.courseID,
            meetingID: drag.meetingID,
            weekday: drag.proposedWeekday,
            startPeriod: drag.proposedStart,
            courses: document.courses,
            semester: document.semester,
            context: document.scheduleContext
        )
        switch validation {
        case .ok(let courses):
            guard let original = document.courses.first(where: { $0.id == drag.courseID })?
                .meetings.first(where: { $0.id == drag.meetingID }) else { return }
            document.courses = courses
            let end = drag.proposedStart + drag.duration - 1
            undo = UndoReschedule(
                courseID: drag.courseID,
                meetingID: drag.meetingID,
                weekday: original.weekday,
                startPeriod: original.startPeriod,
                endPeriod: original.endPeriod,
                message: "已改到\(ScheduleCopy.weekdayName(drag.proposedWeekday)) \(ScheduleCopy.periodSpan(drag.proposedStart, end))"
            )
            scheduleUndoExpiry()
            persist(markUserEdited: true)
            Haptics.success()
        case .conflict(let conflicts):
            banner = conflicts.first.map(ScheduleCopy.conflictMessage) ?? "时间冲突，已取消"
            Haptics.warning()
        case .unchanged:
            break
        case .outOfBounds:
            banner = "超出节次范围，已取消"
            Haptics.warning()
        case .missing:
            banner = "找不到要调整的课程"
        }
    }

    func cancelDrag() {
        drag = nil
        banner = "已取消调整"
    }

    func performUndo() {
        guard let undo else { return }
        guard let courses = ScheduleEngine.replacingMeeting(
            courses: document.courses,
            courseID: undo.courseID,
            meetingID: undo.meetingID,
            weekday: undo.weekday,
            startPeriod: undo.startPeriod,
            endPeriod: undo.endPeriod
        ) else {
            self.undo = nil
            return
        }
        document.courses = courses
        self.undo = nil
        persist(markUserEdited: true)
        banner = "已撤销调整"
    }

    func refreshNotificationStatus() async {
        notificationStatusText = await ReminderScheduler.shared.statusText()
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Diff-gated Live Activity refresh: only push to ActivityKit when the
    /// snapshot actually changed, so identical content is never re-pushed
    /// (iOS throttles Live Activity updates).
    func refreshLiveActivityIfNeeded(now: Date = Date()) {
        // Scheduling is NOT diff-gated: a rest-day open (snapshot nil, was
        // nil) must still queue the next boundary, or the background chain
        // is never seeded. Re-submitting replaces the pending request.
        NextClassActivity.scheduleBackgroundRefresh(document: document, calendar: calendar, now: now)
        let snapshot = NextClassSnapshot.make(document: document, now: now, calendar: calendar)
        guard NextClassSnapshot.shouldUpdate(previous: lastLiveActivitySnapshot, current: snapshot) else { return }
        lastLiveActivitySnapshot = snapshot
        NextClassActivity.sync(document: document, calendar: calendar)
    }

    /// The widget extension can rewrite the shared store (e.g. "推迟 10 分钟").
    /// When the app comes back to the foreground, adopt the on-disk version
    /// instead of silently overwriting it on the next save.
    func reloadFromDiskIfChanged() {
        guard let modified = Self.modificationDate(of: storeURL),
              modified != storeFileModified,
              let reloaded = try? StoreFile.load(from: storeURL),
              reloaded != document else { return }
        document = reloaded
        storeFileModified = modified
        loadError = nil
        presented = nil
        undo = nil
        drag = nil
        realignWeek()
        banner = "已载入小组件里的修改"
        WidgetReloader.reload()
        refreshLiveActivityIfNeeded()
        if CalendarSync.isEnabled {
            CalendarSync.sync(document, calendar: calendar)
        }
        Task { [weak self] in
            await self?.refreshReminders()
        }
    }

    func course(_ id: UUID) -> Course? {
        document.courses.first { $0.id == id }
    }

    func conflicts() -> [MeetingConflict] {
        ScheduleEngine.conflicts(among: document.courses, context: document.scheduleContext)
    }

    private func replace(with incoming: StoreDocument) {
        document = StoreCodec.normalized(incoming)
        presented = nil
        undo = nil
        drag = nil
        realignWeek()
        persist(markUserEdited: false)
    }

    private func realignWeek() {
        let now = Date()
        weekIndex = SemesterCalendar.weekIndex(for: now, semester: document.semester, calendar: calendar) ?? 1
        selectedDay = calendar.startOfDay(for: now)
    }

    func setAppearance(_ choice: AppearanceChoice) {
        document.appearance = choice
        preferSpecialLayout = choice.theme.usesOrbit || choice.theme.usesCube
        Haptics.play(choice.theme.haptic)
        persist(markUserEdited: false)
    }

    func setPerformance(_ tier: PerformanceTier) {
        document.appearance.performance = tier
        persist(markUserEdited: false)
    }

    func cancelThisWeek(_ occurrence: Occurrence) {
        document = TimetableLibrary.overriding(document, with: OccurrenceOverride(
            courseID: occurrence.courseID, meetingID: occurrence.meetingID, week: occurrence.weekIndex, kind: .cancelled
        ))
        banner = "已取消本周这一节，其他周不变"
        persist(markUserEdited: true)
    }

    func delayThisWeek(_ occurrence: Occurrence, minutes: Int = 10) {
        document = TimetableLibrary.overriding(document, with: OccurrenceOverride(
            courseID: occurrence.courseID, meetingID: occurrence.meetingID, week: occurrence.weekIndex, kind: .delayed, delayMinutes: minutes
        ))
        banner = "本周这一节推迟 \(minutes) 分钟"
        persist(markUserEdited: true)
    }

    /// Applies per-meeting odd/even rules for freshly imported courses without
    /// overwriting the import banner once per meeting.
    func applyImportedParities(_ pairs: [(meetingID: UUID, parity: WeekParity)]) {
        guard !pairs.isEmpty else { return }
        for pair in pairs {
            document = TimetableLibrary.settingParity(document, meetingID: pair.meetingID, parity: pair.parity)
        }
        persist(markUserEdited: true)
    }

    func setParity(meetingID: UUID, parity: WeekParity) {
        document = TimetableLibrary.settingParity(document, meetingID: meetingID, parity: parity)
        banner = parity == .any ? "改回每周都上" : "改为\(parity.title)"
        persist(markUserEdited: true)
    }

    func duplicateTimetable(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document = TimetableLibrary.storingCurrent(document, as: trimmed)
        banner = "已另存「\(trimmed)」"
        persist(markUserEdited: true)
    }

    func switchTimetable(to id: UUID) {
        guard let next = TimetableLibrary.switching(document, to: id) else {
            banner = "没有这张课表"
            return
        }
        document = next
        realignWeek()
        persist(markUserEdited: true)
    }

    func addHomework(title: String, courseName: String, due: Date) {
        document.homework.append(HomeworkTask(
            courseName: courseName,
            title: title,
            dueISO: CivilStamp.string(from: due, calendar: calendar)
        ))
        persist(markUserEdited: true)
    }

    func toggleHomework(_ id: UUID) {
        guard let index = document.homework.firstIndex(where: { $0.id == id }) else { return }
        document.homework[index].done.toggle()
        persist(markUserEdited: true)
    }

    func deleteHomework(_ id: UUID) {
        document.homework.removeAll { $0.id == id }
        persist(markUserEdited: true)
    }

    func updateHomework(_ id: UUID, title: String, courseName: String, due: Date) {
        guard let index = document.homework.firstIndex(where: { $0.id == id }) else { return }
        document.homework[index].title = title
        document.homework[index].courseName = courseName
        document.homework[index].dueISO = CivilStamp.string(from: due, calendar: calendar)
        persist(markUserEdited: true)
    }

    func addExam(courseName: String, location: String, start: Date, end: Date) {
        document.exams.append(ExamEvent(
            courseName: courseName,
            location: location,
            startISO: CivilStamp.string(from: start, calendar: calendar),
            endISO: CivilStamp.string(from: end, calendar: calendar)
        ))
        persist(markUserEdited: true)
    }

    func deleteExam(_ id: UUID) {
        document.exams.removeAll { $0.id == id }
        persist(markUserEdited: true)
    }

    func addEvent(title: String, note: String, start: Date, end: Date) {
        document.personalEvents.append(PersonalEvent(
            title: title,
            note: note,
            startISO: CivilStamp.string(from: start, calendar: calendar),
            endISO: CivilStamp.string(from: end, calendar: calendar)
        ))
        persist(markUserEdited: true)
    }

    func updateEvent(_ id: UUID, title: String, note: String, start: Date, end: Date) {
        guard let index = document.personalEvents.firstIndex(where: { $0.id == id }) else { return }
        document.personalEvents[index].title = title
        document.personalEvents[index].note = note
        document.personalEvents[index].startISO = CivilStamp.string(from: start, calendar: calendar)
        document.personalEvents[index].endISO = CivilStamp.string(from: end, calendar: calendar)
        persist(markUserEdited: true)
    }

    func deleteEvent(_ id: UUID) {
        document.personalEvents.removeAll { $0.id == id }
        persist(markUserEdited: true)
    }

    func setCourseGrade(_ courseID: UUID, grade: Double?) {
        guard let index = document.courses.firstIndex(where: { $0.id == courseID }) else { return }
        document.courses[index].grade = grade
        persist(markUserEdited: true)
    }

    /// 设置/移除一门课的记分规则；有规则时总成绩由规则算出，折合百分制写回 grade 进 GPA。
    func setCourseGradeScheme(_ courseID: UUID, scheme: GradeScheme?) {
        guard let index = document.courses.firstIndex(where: { $0.id == courseID }) else { return }
        document.courses[index].gradeScheme = scheme
        if let scheme {
            document.courses[index].grade = scheme.normalizedFinal
        }
        persist(markUserEdited: true)
    }

    var gradedCourses: [Course] {
        document.courses.filter { $0.grade != nil }
    }

    /// Groups of courses sharing a normalized name (Task 4, design §1/§5).
    /// Computed live from the document, so the entry row, banner, and
    /// review page always reflect the current courses.
    var duplicateGroups: [DuplicateGroup] {
        findDuplicateGroups(courses: document.courses)
    }

    var mergeableScheduleGroups: [DuplicateGroup] {
        duplicateGroups.filter { hasMergeableCoursePair($0.courses, context: document.scheduleContext) }
    }

    /// Opens the merge-review page and clears the post-import banner:
    /// reaching the page is the banner's destination.
    func openMergeReview() {
        showDuplicateImportBanner = false
        showMergeReview = true
    }

    /// Banner text `persist` sets when the store save fails. Shared
    /// so `applyCourseMerge` can tell a failed backup save apart
    /// from a successful one without re-matching a literal.
    private static let saveFailedMessage = "未能保存课表"

    /// "合并前备份 11-12 16:30" (design §6): the library name for a
    /// merge backup, stamped at execution time.
    private static func mergeBackupName(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return "合并前备份 \(formatter.string(from: now))"
    }

    /// Executes the user's merge decisions from the review page
    /// (Task 5, design §6): computes every merge first, backs the
    /// current document up into the timetable library, then applies
    /// the merges, remaps overrides/cancellations, and persists.
    /// The review page reports decisions only; this function does
    /// the merging. A group with fewer than two members left after
    /// exclusion, or with a grade conflict and no choice, is skipped
    /// — never merged silently, and never passed to
    /// `mergeDuplicateGroup` unresolved (it traps on that).
    func applyCourseMerge(groups: [DuplicateGroup], exclusions: [String: Set<UUID>], gradeChoices: [String: UUID?]) {
        // 1. Pure computation first: no mutation until every merge
        // result is known.
        struct ComputedMerge {
            let merged: Course
            let removedIDs: Set<UUID>
        }
        var computed: [ComputedMerge] = []
        var skippedSchedules = false
        var combinedRemap: CourseIDRemap = [:]
        var combinedMeetingRemap: MeetingIDRemap = [:]
        for group in groups {
            let excludedIDs = exclusions[group.normalizedName] ?? []
            let includedIDs = Set(group.courses.map(\.id)).subtracting(excludedIDs)
            // Resolve against the current document, in document order,
            // so the survivor is the first member as stored now.
            let members = document.courses.filter { includedIDs.contains($0.id) }
            guard members.count >= 2 else { continue }
            guard canMergeCourseSchedules(members, context: document.scheduleContext) else {
                skippedSchedules = true
                continue
            }
            let gradeSourceID = gradeChoices[group.normalizedName].flatMap { $0 }
            // An unresolved grade conflict must never reach
            // mergeDuplicateGroup: skip the group and leave it on
            // the review page for the user to decide.
            let distinctGrades = Set(members.compactMap(\.grade))
            if distinctGrades.count > 1 {
                guard let gradeSourceID, members.contains(where: { $0.id == gradeSourceID && $0.grade != nil }) else { continue }
            }
            let resolvedGroup = DuplicateGroup(normalizedName: group.normalizedName, courses: members)
            let result = mergeDuplicateGroup(
                resolvedGroup,
                gradeSourceID: gradeSourceID
            )
            combinedRemap.merge(result.remap) { _, new in new }
            combinedMeetingRemap.merge(droppedMeetingRemap(of: resolvedGroup)) { _, new in new }
            computed.append(ComputedMerge(merged: result.course, removedIDs: Set(result.remap.keys)))
        }
        guard !computed.isEmpty else {
            if skippedSchedules { banner = "周次、教室或同一时段的单双周规则不同，已保留为独立课程。" }
            return
        }

        // 2. Back up the current (pre-merge) document into the
        // timetable library (design §6). `duplicateTimetable`
        // persists the backup; if that save fails, `persist`
        // reports it via the failure banner — abort instead of
        // merging without a backup. The backup entry stays in the
        // in-memory library, so a later successful save still
        // preserves it.
        duplicateTimetable(named: Self.mergeBackupName(now: Date()))
        guard banner != Self.saveFailedMessage else { return }

        // 3. Apply: replace each group's members with its merged
        // course (survivor position kept) and drop the merged-away
        // members, then remap overrides/cancellations to the
        // survivor. Exams/homework are name-based and untouched.
        // Overrides and week rules are meeting-anchored: kept meetings
        // keep their ids, while a duplicate-slot meeting dropped by
        // the dedup is remapped to the kept meeting for its slot
        // (see below) — meeting ids are not all preserved.
        var mergedBySurvivorID: [UUID: Course] = [:]
        var removedIDs: Set<UUID> = []
        for item in computed {
            mergedBySurvivorID[item.merged.id] = item.merged
            removedIDs.formUnion(item.removedIDs)
        }
        document.courses = document.courses.compactMap { course in
            if removedIDs.contains(course.id) {
                return nil
            }
            if let merged = mergedBySurvivorID[course.id] {
                return merged
            }
            return course
        }
        document.overrides = remapOccurrenceOverrides(document.overrides, remap: combinedRemap)
        // A duplicate-slot meeting dropped by the dedup keeps no meeting
        // in the merged course, so an override or week rule anchored to
        // its id is rewritten to the kept meeting for that slot (I1).
        // Without this the override would survive, unfindable by the
        // per-(course, meeting) lookup, and its effect — e.g. a week-3
        // cancellation — would silently vanish.
        document.overrides = remapOverrideMeetingIDs(document.overrides, remap: combinedMeetingRemap)
        document.weekRules = remapWeekRuleMeetingIDs(document.weekRules, remap: combinedMeetingRemap)
        document.semester.cancellations = remapClassCancellations(document.semester.cancellations, remap: combinedRemap)
        // A course-detail sheet open on a merged-away course would
        // point at a deleted id (same guard as `deleteCourse`).
        if let presented, removedIDs.contains(presented.courseID) {
            self.presented = nil
        }

        // 4. Persist through the existing path, so reminders, Live
        // Activity, and widgets recompute from the new document.
        // The banner is set before `persist` so a failed save
        // overwrites it with the failure message (persist's own
        // behaviour) instead of claiming success. The review page
        // dismisses itself once `duplicateGroups` is empty; when
        // groups remain (per-group merge) it stays open.
        showDuplicateImportBanner = false
        let mergedCount = computed.count
        banner = "已合并 \(mergedCount) 组同名课程" + (skippedSchedules ? "；周次、教室或同一时段单双周不同的课程已保持独立。" : "")
        persist(markUserEdited: true)
    }

    /// 学分加权（没填学分的按 1 计权重）
    var weightedScoreAverage: Double? {
        let graded = gradedCourses
        guard !graded.isEmpty else { return nil }
        var totalWeight = 0.0
        var total = 0.0
        for course in graded {
            let weight = course.credits > 0 ? course.credits : 1
            total += (course.grade ?? 0) * weight
            totalWeight += weight
        }
        return totalWeight > 0 ? total / totalWeight : nil
    }

    var gpaAverage: Double? {
        let graded = gradedCourses
        guard !graded.isEmpty else { return nil }
        var totalWeight = 0.0
        var total = 0.0
        for course in graded {
            let weight = course.credits > 0 ? course.credits : 1
            total += AppModel.gradePoint(for: course.grade ?? 0) * weight
            totalWeight += weight
        }
        return totalWeight > 0 ? total / totalWeight : nil
    }

    var earnedCredits: Double {
        gradedCourses.reduce(0) { $0 + $1.credits }
    }

    static func gradePoint(for score: Double) -> Double {
        switch score {
        case 90...: return 4.0
        case 85...: return 3.7
        case 82...: return 3.3
        case 78...: return 3.0
        case 75...: return 2.7
        case 72...: return 2.3
        case 68...: return 2.0
        case 64...: return 1.5
        case 60...: return 1.0
        default: return 0
        }
    }

    func events(on date: Date) -> [PersonalEvent] {
        document.personalEvents
            .compactMap { event in CivilStamp.date(from: event.startISO, calendar: calendar).map { (event, $0) } }
            .filter { calendar.isDate($0.1, inSameDayAs: date) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private static func courseSignature(_ course: Course) -> String {
        let meetings = course.meetings
            .map { "\($0.weekday):\($0.startPeriod)-\($0.endPeriod)" }
            .sorted()
            .joined(separator: ",")
        return "\(course.name)|\(course.location)|\(meetings)"
    }

    func importCalendar(_ imported: ImportedCalendar, subscribeURL: String? = nil) {
        var knownIDs = Set(document.courses.map(\.id))
        var knownSignatures = Set(document.courses.map(Self.courseSignature))
        var newCourses: [Course] = []
        for course in imported.courses {
            let signature = Self.courseSignature(course)
            guard !knownIDs.contains(course.id), !knownSignatures.contains(signature) else { continue }
            knownIDs.insert(course.id)
            knownSignatures.insert(signature)
            newCourses.append(course)
        }
        var knownExams = Set(document.exams.map { "\($0.courseName)|\($0.startISO)|\($0.location)" })
        var newExams: [ExamEvent] = []
        for exam in imported.exams {
            let key = "\(exam.courseName)|\(exam.startISO)|\(exam.location)"
            guard !knownExams.contains(key) else { continue }
            knownExams.insert(key)
            newExams.append(exam)
        }
        var knownHomework = Set(document.homework.map { "\($0.courseName)|\($0.title)|\($0.dueISO)" })
        var newHomework: [HomeworkTask] = []
        for task in imported.homework {
            let key = "\(task.courseName)|\(task.title)|\(task.dueISO)"
            guard !knownHomework.contains(key) else { continue }
            knownHomework.insert(key)
            newHomework.append(task)
        }
        document.courses.append(contentsOf: newCourses)
        document.exams.append(contentsOf: newExams)
        document.homework.append(contentsOf: newHomework)
        if let subscribeURL { document.subscribedICSURL = subscribeURL }
        let skipped = imported.courses.count - newCourses.count
        banner = skipped > 0
            ? "导入了 \(newCourses.count) 门课、\(newExams.count) 场考试，跳过 \(skipped) 门重复课程"
            : "导入了 \(newCourses.count) 门课、\(newExams.count) 场考试"
        // Post-import duplicate banner (Task 4, design §5): if the new
        // document has same-name groups, offer the merge-review page.
        if !mergeableScheduleGroups.isEmpty {
            showDuplicateImportBanner = true
        }
        persist(markUserEdited: true)
    }

    var pendingShare: ShareCodec.Payload?

    func stageSharedTimetable(_ payload: ShareCodec.Payload) {
        pendingShare = payload
    }

    func commitSharedTimetable() {
        guard let payload = pendingShare else { return }
        pendingShare = nil
        applySharedTimetable(payload)
    }

    func cancelSharedTimetable() {
        pendingShare = nil
    }

    func applySharedTimetable(_ payload: ShareCodec.Payload) {
        // Keep the current timetable recoverable in the library first.
        document = TimetableLibrary.storingCurrent(document, as: "导入前备份")
        document.semester = payload.semester
        document.courses = payload.courses
        document.weekRules = payload.weekRules
        document.overrides = payload.overrides
        document.exams = payload.exams
        document.homework = payload.homework
        banner = "已导入分享的课表，原课表已存入课表库"
        realignWeek()
        persist(markUserEdited: true)
    }

    func rememberRoom(_ name: String, latitude: Double?, longitude: Double?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.rooms.removeAll { $0.name == trimmed }
        document.rooms.append(RoomPin(name: trimmed, latitude: latitude, longitude: longitude))
        persist(markUserEdited: false)
    }

    private func persist(markUserEdited: Bool) {
        if markUserEdited {
            document.origin = .user
        }
        do {
            try StoreFile.save(document, to: storeURL)
            loadError = nil
            storeFileModified = Self.modificationDate(of: storeURL)
        } catch {
            banner = Self.saveFailedMessage
            return
        }
        WidgetReloader.reload()
        refreshLiveActivityIfNeeded()
        if CalendarSync.isEnabled {
            CalendarSync.sync(document, calendar: calendar)
        }
        Task { [weak self] in
            await self?.refreshReminders()
        }
    }

    private func refreshReminders() async {
        await ReminderScheduler.shared.apply(
            NotificationPlan.makeForStoredLoad(document: document, loadError: loadError, now: Date(), calendar: calendar),
            calendar: calendar
        )
    }

    private func scheduleUndoExpiry() {
        undoTask?.cancel()
        let token = undo?.id
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                guard let self, self.undo?.id == token else { return }
                self.undo = nil
            }
        }
    }
}
