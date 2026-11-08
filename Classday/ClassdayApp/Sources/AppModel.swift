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
    var tab: AppTab = .timetable
    var presented: CoursePresentation?
    var editor: EditorRoute?
    var drag: DragSession?
    var undo: UndoReschedule?
    var banner: String?
    var appGroupAvailable: Bool
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

    let calendar: Calendar
    private let storeURL: URL
    private var undoTask: Task<Void, Never>?

    init() {
        let calendar = ClassdayCalendar.make()
        self.calendar = calendar
        let fallback = StoreLocator.applicationSupportURL()
        let groupURL = AppGroupContainer.storeURL()
        let resolved = (try? StoreLocator.resolve(groupURL: groupURL, fallbackURL: fallback)) ?? fallback
        storeURL = resolved
        appGroupAvailable = groupURL != nil

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: resolved.path) {
            do {
                document = try StoreFile.load(from: resolved)
            } catch {
                document = DemoData.makeDocument()
                loadError = "课表文件无法读取，原文件还在，没有被覆盖。"
            }
        } else {
            document = DemoData.makeDocument()
            try? StoreFile.save(document, to: resolved)
            WidgetReloader.reload()
        }

        let now = Date()
        if let week = SemesterCalendar.weekIndex(for: now, semester: document.semester, calendar: calendar) {
            weekIndex = week
        } else {
            weekIndex = 1
            if loadError == nil {
                banner = "今天不在学期范围内"
            }
        }
        selectedDay = calendar.startOfDay(for: now)
        Task { [weak self] in
            await self?.refreshNotificationStatus()
            await self?.refreshReminders()
        }
    }

    init(document: StoreDocument, storeURL: URL, appGroupAvailable: Bool, now: Date = Date()) {
        self.document = document
        self.storeURL = storeURL
        self.appGroupAvailable = appGroupAvailable
        let calendar = ClassdayCalendar.make()
        self.calendar = calendar
        weekIndex = SemesterCalendar.weekIndex(for: now, semester: document.semester, calendar: calendar) ?? 1
        selectedDay = calendar.startOfDay(for: now)
    }

    static func preview() -> AppModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("classday-preview-\(UUID().uuidString).json")
        return AppModel(document: DemoData.makeDocument(), storeURL: url, appGroupAvailable: false)
    }

    func occurrences(inWeek week: Int? = nil) -> [Occurrence] {
        ScheduleEngine.occurrences(
            inWeek: week ?? weekIndex,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar
        )
    }

    func occurrences(on date: Date) -> [Occurrence] {
        ScheduleEngine.occurrences(on: date, courses: document.courses, semester: document.semester, calendar: calendar)
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
        tab = .timetable
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
        if let conflict = ScheduleEngine.conflicts(among: normalized.courses).first(where: {
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
            semester: document.semester
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
            semester: document.semester
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

    func course(_ id: UUID) -> Course? {
        document.courses.first { $0.id == id }
    }

    func conflicts() -> [MeetingConflict] {
        ScheduleEngine.conflicts(among: document.courses)
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

    private func persist(markUserEdited: Bool) {
        if markUserEdited {
            document.origin = .user
        }
        do {
            try StoreFile.save(document, to: storeURL)
            loadError = nil
        } catch {
            banner = "未能保存课表"
            return
        }
        WidgetReloader.reload()
        Task { [weak self] in
            await self?.refreshReminders()
        }
    }

    private func refreshReminders() async {
        await ReminderScheduler.shared.apply(
            NotificationPlan.make(document: document, now: Date(), calendar: calendar),
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
