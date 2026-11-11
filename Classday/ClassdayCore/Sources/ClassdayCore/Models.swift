import Foundation

public enum WidgetID {
    public static let nextClass = "NextClassWidget"
    public static let todayCourses = "TodayCoursesWidget"
}

public enum DataOrigin: String, Codable, Equatable, Hashable, Sendable {
    case demo
    case user
}

public struct PaletteColor: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static func rgb(_ r: Int, _ g: Int, _ b: Int) -> PaletteColor {
        PaletteColor(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
    }
}

public struct CourseColorStyle: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var backgroundLight: PaletteColor
    public var backgroundDark: PaletteColor
    public var inkLight: PaletteColor
    public var inkDark: PaletteColor

    public init(
        id: String,
        name: String,
        backgroundLight: PaletteColor,
        backgroundDark: PaletteColor,
        inkLight: PaletteColor,
        inkDark: PaletteColor
    ) {
        self.id = id
        self.name = name
        self.backgroundLight = backgroundLight
        self.backgroundDark = backgroundDark
        self.inkLight = inkLight
        self.inkDark = inkDark
    }
}

public enum CourseColors {
    public static let all: [CourseColorStyle] = [
        CourseColorStyle(
            id: "blue", name: "蓝",
            backgroundLight: .rgb(228, 236, 255), backgroundDark: .rgb(36, 52, 95),
            inkLight: .rgb(42, 87, 214), inkDark: .rgb(214, 226, 255)
        ),
        CourseColorStyle(
            id: "orange", name: "橘",
            backgroundLight: .rgb(255, 232, 212), backgroundDark: .rgb(90, 58, 36),
            inkLight: .rgb(212, 106, 44), inkDark: .rgb(255, 215, 190)
        ),
        CourseColorStyle(
            id: "green", name: "绿",
            backgroundLight: .rgb(227, 246, 232), backgroundDark: .rgb(30, 70, 48),
            inkLight: .rgb(46, 139, 87), inkDark: .rgb(205, 238, 219)
        ),
        CourseColorStyle(
            id: "purple", name: "紫",
            backgroundLight: .rgb(240, 232, 255), backgroundDark: .rgb(58, 44, 85),
            inkLight: .rgb(122, 82, 199), inkDark: .rgb(228, 216, 255)
        ),
        CourseColorStyle(
            id: "pink", name: "粉",
            backgroundLight: .rgb(253, 231, 238), backgroundDark: .rgb(85, 36, 51),
            inkLight: .rgb(212, 83, 122), inkDark: .rgb(255, 213, 226)
        ),
        CourseColorStyle(
            id: "sage", name: "青",
            backgroundLight: .rgb(230, 243, 228), backgroundDark: .rgb(36, 56, 31),
            inkLight: .rgb(78, 143, 69), inkDark: .rgb(215, 240, 210)
        ),
    ]

    public static func style(for id: String) -> CourseColorStyle {
        all.first { $0.id == id } ?? all[0]
    }
}

public struct ClockTime: Equatable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var totalMinutes: Int { hour * 60 + minute }

    public var hhmm: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func parse(_ raw: String) -> ClockTime? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return ClockTime(hour: hour, minute: minute)
    }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.totalMinutes < rhs.totalMinutes
    }
}

public struct PeriodTemplate: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var index: Int
    public var start: String
    public var end: String

    public var id: Int { index }

    public init(index: Int, start: String, end: String) {
        self.index = index
        self.start = start
        self.end = end
    }
}

public struct Meeting: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var weekday: Int
    public var startPeriod: Int
    public var endPeriod: Int

    public init(id: UUID, weekday: Int, startPeriod: Int, endPeriod: Int) {
        self.id = id
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
    }

    public var periodCount: Int { endPeriod - startPeriod + 1 }
}

/// 记分规则里的一个分项（如 P、TEST60、EX1）：id 是稳定键，改名不影响引用。
public struct GradeComponent: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

/// 候选算法里的一项：某个分项 × 权重。
public struct GradeTerm: Codable, Equatable, Hashable, Sendable {
    public var componentID: String
    public var weight: Double

    public init(componentID: String, weight: Double) {
        self.componentID = componentID
        self.weight = weight
    }
}

/// 每门课自己的记分规则：总成绩 = 各候选算法（分项加权和）里最高的一条。
/// 例（优化与算法，0–20 分制）：G = 0.25P + max(0.25·TEST60 + 0.50·EX1, 0.75·EX1, 0.75·EX2)。
public struct GradeScheme: Codable, Equatable, Hashable, Sendable {
    public var scale: Double
    public var components: [GradeComponent]
    public var scores: [String: Double]
    public var branches: [[GradeTerm]]

    public init(scale: Double = 100, components: [GradeComponent] = [], scores: [String: Double] = [:], branches: [[GradeTerm]] = []) {
        self.scale = scale
        self.components = components
        self.scores = scores
        self.branches = branches
    }

    private enum CodingKeys: String, CodingKey { case scale, components, scores, branches }

    /// 手写解码：字段缺失给默认值，规则结构以后加字段也不炸旧存档。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scale: try container.decodeIfPresent(Double.self, forKey: .scale) ?? 100,
            components: try container.decodeIfPresent([GradeComponent].self, forKey: .components) ?? [],
            scores: try container.decodeIfPresent([String: Double].self, forKey: .scores) ?? [:],
            branches: try container.decodeIfPresent([[GradeTerm]].self, forKey: .branches) ?? []
        )
    }

    /// 一条候选算法的值；任一分项还没录分（或分项已被删）返回 nil，不参与取最高。
    public func value(of branch: [GradeTerm]) -> Double? {
        guard !branch.isEmpty else { return nil }
        var total = 0.0
        for term in branch {
            guard let score = scores[term.componentID] else { return nil }
            total += term.weight * score
        }
        return total
    }

    public var bestBranchIndex: Int? {
        var best: Int?
        var bestValue = -Double.infinity
        for (index, branch) in branches.enumerated() {
            guard let value = value(of: branch) else { continue }
            if value > bestValue { bestValue = value; best = index }
        }
        return best
    }

    /// 总成绩（规则自己的分制）。
    public var finalGrade: Double? {
        guard let index = bestBranchIndex else { return nil }
        return value(of: branches[index])
    }

    /// 折合百分制：写进 Course.grade、进 GPA 的口径。
    public var normalizedFinal: Double? {
        guard let final = finalGrade, scale > 0 else { return nil }
        return final / scale * 100
    }
}

public struct Course: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var teacher: String
    public var location: String
    public var department: String
    public var note: String
    public var colorID: String
    public var kind: String
    public var weeks: [Int]
    public var meetings: [Meeting]
    public var reminderLeadMinutes: Int?
    public var credits: Double
    public var grade: Double?
    public var gradeScheme: GradeScheme?

    public init(
        id: UUID,
        name: String,
        teacher: String,
        location: String,
        department: String = "",
        note: String = "",
        colorID: String,
        kind: String = "必修课",
        weeks: [Int],
        meetings: [Meeting],
        reminderLeadMinutes: Int? = nil,
        credits: Double = 0,
        grade: Double? = nil,
        gradeScheme: GradeScheme? = nil
    ) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.location = location
        self.department = department
        self.note = note
        self.colorID = colorID
        self.kind = kind
        self.weeks = Array(Set(weeks)).sorted()
        self.meetings = meetings
        self.reminderLeadMinutes = reminderLeadMinutes
        self.credits = credits
        self.grade = grade
        self.gradeScheme = gradeScheme
    }
}

extension Course {
    private enum CodingKeys: String, CodingKey {
        case id, name, teacher, location, department, note, colorID, kind, weeks, meetings, reminderLeadMinutes, credits, grade, gradeScheme
    }

    /// 手写解码：credits / grade 是后加字段，旧数据没有这两个键时给默认值，不能让老课表解码失败。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            teacher: try container.decode(String.self, forKey: .teacher),
            location: try container.decode(String.self, forKey: .location),
            department: try container.decodeIfPresent(String.self, forKey: .department) ?? "",
            note: try container.decodeIfPresent(String.self, forKey: .note) ?? "",
            colorID: try container.decode(String.self, forKey: .colorID),
            kind: try container.decodeIfPresent(String.self, forKey: .kind) ?? "必修课",
            weeks: try container.decode([Int].self, forKey: .weeks),
            meetings: try container.decode([Meeting].self, forKey: .meetings),
            reminderLeadMinutes: try container.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes),
            credits: try container.decodeIfPresent(Double.self, forKey: .credits) ?? 0,
            grade: try container.decodeIfPresent(Double.self, forKey: .grade),
            gradeScheme: try container.decodeIfPresent(GradeScheme.self, forKey: .gradeScheme)
        )
    }
}

public struct PersonalEvent: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var note: String
    public var startISO: String
    public var endISO: String

    public init(id: UUID = UUID(), title: String, note: String = "", startISO: String, endISO: String) {
        self.id = id
        self.title = title
        self.note = note
        self.startISO = startISO
        self.endISO = endISO
    }
}

/// A no-class period (school holiday, break, or a personal no-class stretch).
/// Dates are civil "yyyy-MM-dd" strings, both ends inclusive - the same
/// representation Semester.startDate uses.
public struct HolidayPeriod: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var startDate: String
    public var endDate: String

    public init(id: UUID, name: String, startDate: String, endDate: String) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct Semester: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var shortName: String
    public var startDate: String
    public var totalWeeks: Int
    public var periods: [PeriodTemplate]
    public var defaultReminderMinutes: Int
    public var holidays: [HolidayPeriod]

    public init(
        name: String,
        shortName: String,
        startDate: String,
        totalWeeks: Int,
        periods: [PeriodTemplate],
        defaultReminderMinutes: Int,
        holidays: [HolidayPeriod] = []
    ) {
        self.name = name
        self.shortName = shortName
        self.startDate = startDate
        self.totalWeeks = totalWeeks
        self.periods = periods
        self.defaultReminderMinutes = defaultReminderMinutes
        self.holidays = holidays
    }

    private enum CodingKeys: String, CodingKey {
        case name, shortName, startDate, totalWeeks, periods, defaultReminderMinutes, holidays
    }

    /// Hand-written decode so documents saved before holidays existed
    /// (no `holidays` key) still load; every other field stays strict.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        shortName = try container.decode(String.self, forKey: .shortName)
        startDate = try container.decode(String.self, forKey: .startDate)
        totalWeeks = try container.decode(Int.self, forKey: .totalWeeks)
        periods = try container.decode([PeriodTemplate].self, forKey: .periods)
        defaultReminderMinutes = try container.decode(Int.self, forKey: .defaultReminderMinutes)
        holidays = try container.decodeIfPresent([HolidayPeriod].self, forKey: .holidays) ?? []
    }
}

public struct StoreDocument: Codable, Equatable, Hashable, Sendable {
    public static let currentSchema = 1

    public var schemaVersion: Int
    public var origin: DataOrigin
    public var semester: Semester
    public var courses: [Course]
    public var weekRules: [MeetingWeekRule]
    public var overrides: [OccurrenceOverride]
    public var exams: [ExamEvent]
    public var homework: [HomeworkTask]
    public var personalEvents: [PersonalEvent]
    public var rooms: [RoomPin]
    public var library: [StoredTimetable]
    public var activeTimetableID: UUID
    public var appearance: AppearanceChoice
    public var subscribedICSURL: String

    public init(
        schemaVersion: Int,
        origin: DataOrigin,
        semester: Semester,
        courses: [Course],
        weekRules: [MeetingWeekRule] = [],
        overrides: [OccurrenceOverride] = [],
        exams: [ExamEvent] = [],
        homework: [HomeworkTask] = [],
        personalEvents: [PersonalEvent] = [],
        rooms: [RoomPin] = [],
        library: [StoredTimetable] = [],
        activeTimetableID: UUID = TimetableLibrary.implicitID,
        appearance: AppearanceChoice = .standard,
        subscribedICSURL: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.origin = origin
        self.semester = semester
        self.courses = courses
        self.weekRules = weekRules
        self.overrides = overrides
        self.exams = exams
        self.homework = homework
        self.personalEvents = personalEvents
        self.rooms = rooms
        self.library = library
        self.activeTimetableID = activeTimetableID
        self.appearance = appearance
        self.subscribedICSURL = subscribedICSURL
    }

    public var scheduleContext: ScheduleContext {
        ScheduleContext(weekRules: weekRules, overrides: overrides)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, origin, semester, courses, weekRules, overrides, exams, homework, personalEvents, rooms, library
        case activeTimetableID, appearance, subscribedICSURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        origin = try container.decode(DataOrigin.self, forKey: .origin)
        semester = try container.decode(Semester.self, forKey: .semester)
        courses = try container.decode([Course].self, forKey: .courses)
        weekRules = try container.decodeIfPresent([MeetingWeekRule].self, forKey: .weekRules) ?? []
        overrides = try container.decodeIfPresent([OccurrenceOverride].self, forKey: .overrides) ?? []
        exams = try container.decodeIfPresent([ExamEvent].self, forKey: .exams) ?? []
        homework = try container.decodeIfPresent([HomeworkTask].self, forKey: .homework) ?? []
        personalEvents = try container.decodeIfPresent([PersonalEvent].self, forKey: .personalEvents) ?? []
        rooms = try container.decodeIfPresent([RoomPin].self, forKey: .rooms) ?? []
        library = try container.decodeIfPresent([StoredTimetable].self, forKey: .library) ?? []
        activeTimetableID = try container.decodeIfPresent(UUID.self, forKey: .activeTimetableID) ?? TimetableLibrary.implicitID
        appearance = try container.decodeIfPresent(AppearanceChoice.self, forKey: .appearance) ?? .standard
        subscribedICSURL = try container.decodeIfPresent(String.self, forKey: .subscribedICSURL) ?? ""
    }
}

public struct CourseLink: Equatable, Hashable, Sendable {
    public var courseID: UUID
    public var meetingID: UUID?

    public init(courseID: UUID, meetingID: UUID?) {
        self.courseID = courseID
        self.meetingID = meetingID
    }
}

public enum ClassdayLink {
    public static let scheme = "classday"

    public static func course(_ id: UUID, meeting: UUID? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "course"
        components.path = "/\(id.uuidString)"
        if let meeting {
            components.queryItems = [URLQueryItem(name: "meeting", value: meeting.uuidString)]
        }
        guard let url = components.url else {
            preconditionFailure("Unable to build a classday course URL")
        }
        return url
    }

    public static func parse(_ url: URL) -> CourseLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.host?.lowercased() == "course" else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let courseID = UUID(uuidString: raw) else { return nil }
        let meeting = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "meeting" }?
            .value
            .flatMap(UUID.init(uuidString:))
        return CourseLink(courseID: courseID, meetingID: meeting)
    }
}

public enum ClassdayCalendar {
    public static func make(timeZone: TimeZone? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? .current
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}

public enum LocationText {
    public static func short(_ location: String) -> String {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "教学楼") else { return trimmed }
        let rest = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? trimmed : rest
    }
}

public enum StoreLocator {
    public static func applicationSupportURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Classday", isDirectory: true)
            .appendingPathComponent(AppGroup.storeFileName)
    }

    /// Prefers the App Group file. If that file is missing and a fallback exists, copies it across.
    public static func resolve(groupURL: URL?, fallbackURL: URL, fileManager: FileManager = .default) throws -> URL {
        guard let groupURL else { return fallbackURL }
        if !fileManager.fileExists(atPath: groupURL.path), fileManager.fileExists(atPath: fallbackURL.path) {
            try fileManager.createDirectory(
                at: groupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: fallbackURL, to: groupURL)
        }
        return groupURL
    }
}

