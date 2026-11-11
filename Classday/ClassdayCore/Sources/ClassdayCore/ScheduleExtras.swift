import Foundation

public enum WeekParity: String, Codable, Equatable, Hashable, Sendable {
    case any
    case odd
    case even

    public var title: String {
        switch self {
        case .any: return "每周"
        case .odd: return "单周"
        case .even: return "双周"
        }
    }

    public func contains(week: Int) -> Bool {
        switch self {
        case .any: return true
        case .odd: return week % 2 == 1
        case .even: return week % 2 == 0
        }
    }
}

public struct MeetingWeekRule: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var meetingID: UUID
    public var parity: WeekParity

    public var id: UUID { meetingID }

    public init(meetingID: UUID, parity: WeekParity) {
        self.meetingID = meetingID
        self.parity = parity
    }
}

public enum OverrideKind: String, Codable, Equatable, Hashable, Sendable {
    case cancelled
    case moved
    case delayed
}

/// A change that applies to one week of one meeting and leaves the rest of the term alone.
public struct OccurrenceOverride: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var courseID: UUID
    public var meetingID: UUID
    public var week: Int
    public var kind: OverrideKind
    public var weekday: Int?
    public var startPeriod: Int?
    public var endPeriod: Int?
    public var delayMinutes: Int?

    public init(
        id: UUID = UUID(),
        courseID: UUID,
        meetingID: UUID,
        week: Int,
        kind: OverrideKind,
        weekday: Int? = nil,
        startPeriod: Int? = nil,
        endPeriod: Int? = nil,
        delayMinutes: Int? = nil
    ) {
        self.id = id
        self.courseID = courseID
        self.meetingID = meetingID
        self.week = week
        self.kind = kind
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.delayMinutes = delayMinutes
    }
}

public struct ExamEvent: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var courseName: String
    public var location: String
    public var startISO: String
    public var endISO: String
    public var note: String

    public init(id: UUID = UUID(), courseName: String, location: String, startISO: String, endISO: String, note: String = "") {
        self.id = id
        self.courseName = courseName
        self.location = location
        self.startISO = startISO
        self.endISO = endISO
        self.note = note
    }
}

public struct HomeworkTask: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var courseName: String
    public var title: String
    public var dueISO: String
    public var done: Bool
    public var note: String

    public init(id: UUID = UUID(), courseName: String, title: String, dueISO: String, done: Bool = false, note: String = "") {
        self.id = id
        self.courseName = courseName
        self.title = title
        self.dueISO = dueISO
        self.done = done
        self.note = note
    }
}

public struct RoomPin: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var latitude: Double?
    public var longitude: Double?
    public var query: String

    public init(id: UUID = UUID(), name: String, latitude: Double? = nil, longitude: Double? = nil, query: String? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.query = query ?? name
    }
}

public struct StoredTimetable: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var semester: Semester
    public var courses: [Course]
    public var weekRules: [MeetingWeekRule]
    public var overrides: [OccurrenceOverride]
    public var exams: [ExamEvent]
    public var homework: [HomeworkTask]
    public var rooms: [RoomPin]

    public init(
        id: UUID,
        name: String,
        semester: Semester,
        courses: [Course],
        weekRules: [MeetingWeekRule],
        overrides: [OccurrenceOverride],
        exams: [ExamEvent],
        homework: [HomeworkTask],
        rooms: [RoomPin]
    ) {
        self.id = id
        self.name = name
        self.semester = semester
        self.courses = courses
        self.weekRules = weekRules
        self.overrides = overrides
        self.exams = exams
        self.homework = homework
        self.rooms = rooms
    }
}

public struct ScheduleContext: Equatable, Hashable, Sendable {
    public var weekRules: [MeetingWeekRule]
    public var overrides: [OccurrenceOverride]

    public init(weekRules: [MeetingWeekRule] = [], overrides: [OccurrenceOverride] = []) {
        self.weekRules = weekRules
        self.overrides = overrides
    }

    public static let empty = ScheduleContext()

    public func parity(for meetingID: UUID) -> WeekParity {
        weekRules.first { $0.meetingID == meetingID }?.parity ?? .any
    }

    public func override(courseID: UUID, meetingID: UUID, week: Int) -> OccurrenceOverride? {
        overrides.last { $0.courseID == courseID && $0.meetingID == meetingID && $0.week == week }
    }
}

public enum TimetableLibrary {
    public static let implicitID = UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!

    public static func snapshot(of document: StoreDocument, id: UUID, name: String) -> StoredTimetable {
        StoredTimetable(
            id: id,
            name: name,
            semester: document.semester,
            courses: document.courses,
            weekRules: document.weekRules,
            overrides: document.overrides,
            exams: document.exams,
            homework: document.homework,
            rooms: document.rooms
        )
    }

    public static func applying(_ stored: StoredTimetable, to document: StoreDocument) -> StoreDocument {
        var copy = document
        copy.activeTimetableID = stored.id
        copy.semester = stored.semester
        copy.courses = stored.courses
        copy.weekRules = stored.weekRules
        copy.overrides = stored.overrides
        copy.exams = stored.exams
        copy.homework = stored.homework
        copy.rooms = stored.rooms
        return copy
    }

    /// Keeps the current timetable in the library under its id, then loads `id`.
    public static func switching(_ document: StoreDocument, to id: UUID) -> StoreDocument? {
        guard document.activeTimetableID != id else { return document }
        guard let target = document.library.first(where: { $0.id == id }) else {
            return nil
        }
        var library = document.library.filter { $0.id != document.activeTimetableID && $0.id != id }
        library.append(snapshot(of: document, id: document.activeTimetableID, name: document.semester.shortName))
        library.sort { $0.name < $1.name }
        var next = applying(target, to: document)
        next.library = library
        return next
    }

    public static func storingCurrent(_ document: StoreDocument, as name: String, id: UUID = UUID()) -> StoreDocument {
        var copy = document
        var library = copy.library.filter { $0.id != id }
        library.append(snapshot(of: document, id: id, name: name))
        copy.library = library.sorted { $0.name < $1.name }
        return copy
    }

    public static func settingParity(_ document: StoreDocument, meetingID: UUID, parity: WeekParity) -> StoreDocument {
        var copy = document
        copy.weekRules.removeAll { $0.meetingID == meetingID }
        if parity != .any {
            copy.weekRules.append(MeetingWeekRule(meetingID: meetingID, parity: parity))
        }
        return copy
    }

    public static func overriding(_ document: StoreDocument, with override: OccurrenceOverride) -> StoreDocument {
        var copy = document
        copy.overrides.removeAll { $0.courseID == override.courseID && $0.meetingID == override.meetingID && $0.week == override.week }
        copy.overrides.append(override)
        return copy
    }

    public static func clearingOverride(_ document: StoreDocument, courseID: UUID, meetingID: UUID, week: Int) -> StoreDocument {
        var copy = document
        copy.overrides.removeAll { $0.courseID == courseID && $0.meetingID == meetingID && $0.week == week }
        return copy
    }
}

public enum CivilStamp {
    public static func string(from date: Date, calendar: Calendar = ClassdayCalendar.make()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    public static func date(from raw: String, calendar: Calendar = ClassdayCalendar.make()) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let datePart = trimmed.prefix(10)
        guard datePart.count == 10, let day = SemesterCalendar.parseCivil(String(datePart), calendar: calendar) else {
            return nil
        }
        guard trimmed.count >= 16 else { return day }
        let clock = trimmed.dropFirst(11).prefix(5)
        guard let time = ClockTime.parse(String(clock)) else { return day }
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }
}

public struct ImportedCalendar: Equatable, Sendable {
    public var courses: [Course]
    public var exams: [ExamEvent]
    public var homework: [HomeworkTask]
    public var warnings: [String]

    public init(courses: [Course], exams: [ExamEvent], homework: [HomeworkTask], warnings: [String]) {
        self.courses = courses
        self.exams = exams
        self.homework = homework
        self.warnings = warnings
    }
}

public enum ICSImporter {
    public static func parse(_ text: String, calendar: Calendar = ClassdayCalendar.make(), totalWeeks: Int = 16) -> ImportedCalendar {
        let events = unfold(text).split(separator: "BEGIN:VEVENT").dropFirst().map { block -> [String: String] in
            var fields: [String: String] = [:]
            for line in block.split(whereSeparator: \.isNewline) {
                let raw = String(line)
                if raw.hasPrefix("END:VEVENT") { break }
                guard let colon = raw.firstIndex(of: ":") else { continue }
                let key = String(raw[..<colon]).split(separator: ";").first.map(String.init)?.uppercased() ?? ""
                fields[key] = String(raw[raw.index(after: colon)...])
            }
            return fields
        }
        var courses: [String: Course] = [:]
        var exams: [ExamEvent] = []
        var homework: [HomeworkTask] = []
        var warnings: [String] = []
        for event in events {
            guard let summary = event["SUMMARY"], !summary.isEmpty else { continue }
            let location = event["LOCATION"] ?? ""
            let start = event["DTSTART"].flatMap { parseICSDate($0, calendar: calendar) }
            let end = event["DTEND"].flatMap { parseICSDate($0, calendar: calendar) }
            let kind = classify(summary)
            if let rawStart = event["DTSTART"], rawStart.filter({ $0.isNumber }).count == 8 {
                warnings.append("跳过全天事件「\(summary)」")
                continue
            }
            if kind == .exam, let start {
                exams.append(ExamEvent(
                    courseName: summary,
                    location: location,
                    startISO: CivilStamp.string(from: start, calendar: calendar),
                    endISO: CivilStamp.string(from: end ?? start.addingTimeInterval(3600), calendar: calendar)
                ))
                continue
            }
            if kind == .homework, let start {
                homework.append(HomeworkTask(
                    courseName: summary,
                    title: summary,
                    dueISO: CivilStamp.string(from: start, calendar: calendar),
                    note: location
                ))
                continue
            }
            guard let start, let end, end > start else {
                warnings.append("跳过没有时间的事件「\(summary)」")
                continue
            }
            let weekday = SemesterCalendar.isoWeekday(start, calendar: calendar)
            let startClock = ClockTime(hour: calendar.component(.hour, from: start), minute: calendar.component(.minute, from: start))
            let endClock = ClockTime(hour: calendar.component(.hour, from: end), minute: calendar.component(.minute, from: end))
            let key = "\(summary)|\(location)"
            var course = courses[key] ?? Course(
                id: stableUUID(key),
                name: summary,
                teacher: "",
                location: location,
                colorID: CourseColors.all[Int(stableUUID(key).uuid.0) % CourseColors.all.count].id,
                weeks: Array(1...max(1, totalWeeks)),
                meetings: []
            )
            for meetingWeekday in rruleWeekdays(event["RRULE"]) ?? [weekday] {
                let meetingKey = "\(key)|\(meetingWeekday)|\(startClock.hhmm)|\(endClock.hhmm)"
                if !course.meetings.contains(where: { $0.id == stableUUID(meetingKey) }) {
                    course.meetings.append(Meeting(
                        id: stableUUID(meetingKey),
                        weekday: meetingWeekday,
                        startPeriod: periodGuess(startClock),
                        endPeriod: max(periodGuess(startClock), periodGuess(endClock.totalMinutes == startClock.totalMinutes ? endClock : ClockTime(hour: endClock.hour, minute: max(0, endClock.minute - 1))))
                    ))
                }
            }
            courses[key] = course
            _ = endClock
        }
        return ImportedCalendar(
            courses: courses.values.sorted { $0.name < $1.name },
            exams: exams,
            homework: homework,
            warnings: warnings
        )
    }

    private enum Kind { case course, exam, homework }

    private static func classify(_ summary: String) -> Kind {
        let folded = summary.lowercased()
        if folded.contains("exam") || folded.contains("teste") || folded.contains("exame") || summary.contains("考试") || summary.contains("测验") {
            return .exam
        }
        if folded.contains("assignment") || folded.contains("trabalho") || folded.contains("homework") || summary.contains("作业") {
            return .homework
        }
        return .course
    }

    /// Weekdays named by an RRULE BYDAY list (FREQ=WEEKLY only); nil when the rule names none.
    private static func rruleWeekdays(_ rrule: String?) -> [Int]? {
        guard let rrule, rrule.uppercased().contains("FREQ=WEEKLY"),
              let byday = rrule.split(separator: ";").first(where: { $0.uppercased().hasPrefix("BYDAY=") }) else { return nil }
        let map = ["MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6, "SU": 7]
        let days = byday.dropFirst(6).split(separator: ",").compactMap { token -> Int? in
            map[String(token.filter { $0.isLetter }).uppercased()]
        }
        return days.isEmpty ? nil : Array(Set(days)).sorted()
    }

    private static func unfold(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
    }

    public static func parseICSDate(_ raw: String, calendar: Calendar) -> Date? {
        let digits = raw.filter { $0.isNumber }
        guard digits.count >= 8 else { return nil }
        let year = Int(digits.prefix(4)) ?? 0
        let month = Int(digits.dropFirst(4).prefix(2)) ?? 1
        let day = Int(digits.dropFirst(6).prefix(2)) ?? 1
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = raw.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0) : calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        if digits.count >= 12 {
            components.hour = Int(digits.dropFirst(8).prefix(2))
            components.minute = Int(digits.dropFirst(10).prefix(2))
        }
        return calendar.date(from: components) ?? components.date
    }

    private static func periodGuess(_ clock: ClockTime) -> Int {
        let table = [1: 8 * 60, 2: 8 * 60 + 55, 3: 10 * 60 + 10, 4: 11 * 60 + 5, 5: 14 * 60, 6: 14 * 60 + 55, 7: 16 * 60 + 10, 8: 17 * 60 + 5, 9: 19 * 60, 10: 19 * 60 + 55]
        return table.min { abs($0.value - clock.totalMinutes) < abs($1.value - clock.totalMinutes) }?.key ?? 1
    }

    private static func stableUUID(_ key: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        for index in 0..<8 {
            bytes[index] = UInt8((hash >> (8 * index)) & 0xff)
        }
        let hash2 = hash &* 0x9E3779B185EBCA87
        for index in 0..<8 {
            bytes[8 + index] = UInt8((hash2 >> (8 * index)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let tuple = (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}

public struct FenixClass: Equatable, Sendable {
    public var courseName: String
    public var location: String
    public var start: Date
    public var end: Date
}

public struct FenixEvaluation: Equatable, Sendable {
    public var name: String
    public var courseName: String
    public var location: String
    public var start: Date?
    public var end: Date?
    public var isExam: Bool
}

public enum FenixCalendar {
    public static func courses(from classes: [FenixClass], calendar: Calendar = ClassdayCalendar.make(), totalWeeks: Int = 16) -> [Course] {
        var grouped: [String: Course] = [:]
        for item in classes where item.end > item.start {
            let key = "\(item.courseName)|\(item.location)"
            var course = grouped[key] ?? Course(
                id: UUID(),
                name: item.courseName,
                teacher: "",
                location: item.location,
                colorID: "blue",
                weeks: Array(1...max(1, totalWeeks)),
                meetings: []
            )
            let weekday = SemesterCalendar.isoWeekday(item.start, calendar: calendar)
            let startPeriod = periodIndex(item.start, calendar: calendar)
            let endPeriod = max(startPeriod, periodIndex(item.end.addingTimeInterval(-60), calendar: calendar))
            if !course.meetings.contains(where: { $0.weekday == weekday && $0.startPeriod == startPeriod && $0.endPeriod == endPeriod }) {
                course.meetings.append(Meeting(id: UUID(), weekday: weekday, startPeriod: startPeriod, endPeriod: endPeriod))
            }
            grouped[key] = course
        }
        return grouped.values.sorted { $0.name < $1.name }
    }

    private static func periodIndex(_ date: Date, calendar: Calendar) -> Int {
        let clock = ClockTime(hour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date))
        let table = [1: 8 * 60, 2: 8 * 60 + 55, 3: 10 * 60 + 10, 4: 11 * 60 + 5, 5: 14 * 60, 6: 14 * 60 + 55, 7: 16 * 60 + 10, 8: 17 * 60 + 5, 9: 19 * 60, 10: 19 * 60 + 55]
        return table.min { abs($0.value - clock.totalMinutes) < abs($1.value - clock.totalMinutes) }?.key ?? 1
    }

    public static func exams(from evaluations: [FenixEvaluation], calendar: Calendar = ClassdayCalendar.make()) -> [ExamEvent] {
        evaluations.filter(\.isExam).compactMap { item in
            guard let start = item.start else { return nil }
            return ExamEvent(
                courseName: item.courseName.isEmpty ? item.name : item.courseName,
                location: item.location,
                startISO: CivilStamp.string(from: start, calendar: calendar),
                endISO: CivilStamp.string(from: item.end ?? start.addingTimeInterval(7200), calendar: calendar),
                note: item.name
            )
        }
    }

    private struct Named: Decodable { var name: String? }
    private struct ClassRow: Decodable {
        var course: Named?
        var courseName: String?
        var location: Named?
        var rooms: [Named]?
        var start: String?
        var end: String?
    }
    private struct EvaluationRow: Decodable {
        var name: String?
        var type: String?
        var courses: [Named]?
        var rooms: [Named]?
        var start: String?
        var end: String?
    }

    public static func decodeClasses(_ data: Data) -> [FenixClass] {
        let rows = (try? JSONDecoder().decode([ClassRow].self, from: data)) ?? []
        return rows.compactMap { row in
            let course = row.course?.name ?? row.courseName ?? ""
            let location = row.location?.name ?? row.rooms?.first?.name ?? ""
            guard let start = iso(row.start), let end = iso(row.end), !course.isEmpty else { return nil }
            return FenixClass(courseName: course, location: location, start: start, end: end)
        }
    }

    public static func decodeEvaluations(_ data: Data) -> [FenixEvaluation] {
        let rows = (try? JSONDecoder().decode([EvaluationRow].self, from: data)) ?? []
        return rows.compactMap { row in
            let name = row.name ?? ""
            let course = row.courses?.first?.name ?? ""
            let type = (row.type ?? "").uppercased()
            guard !name.isEmpty || !course.isEmpty else { return nil }
            let exam = type.contains("EXAM") || type.contains("TEST") || name.lowercased().contains("exame") || name.contains("考试")
            return FenixEvaluation(
                name: name,
                courseName: course.isEmpty ? name : course,
                location: row.rooms?.first?.name ?? "",
                start: iso(row.start),
                end: iso(row.end),
                isExam: exam
            )
        }
    }

    private static func iso(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isoFraction = ISO8601DateFormatter()
        isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFraction.date(from: trimmed) { return date }
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        if let date = isoPlain.date(from: trimmed) { return date }
        // Naive timestamps carry no offset: read them as local wall time, not GMT.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "dd-MM-yyyy HH:mm:ss", "dd-MM-yyyy HH:mm", "dd-MM-yyyy"] {
            local.dateFormat = format
            if let date = local.date(from: trimmed) { return date }
        }
        return nil
    }
}

public enum ShareCodec {
    public struct Payload: Codable, Equatable, Sendable {
        public var semester: Semester
        public var courses: [Course]
        public var weekRules: [MeetingWeekRule]
        public var overrides: [OccurrenceOverride]
        public var exams: [ExamEvent]
        public var homework: [HomeworkTask]
    }

    public static func encode(_ document: StoreDocument) -> String {
        let payload = Payload(
            semester: document.semester,
            courses: document.courses,
            weekRules: document.weekRules,
            overrides: document.overrides,
            exams: document.exams,
            homework: document.homework
        )
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ token: String) -> Payload? {
        var base = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base.count % 4) % 4
        base.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    public static func url(for document: StoreDocument) -> URL {
        var components = URLComponents()
        components.scheme = ClassdayLink.scheme
        components.host = "timetable"
        components.queryItems = [URLQueryItem(name: "d", value: encode(document))]
        return components.url ?? URL(string: "classday://timetable")!
    }
}

public enum CountdownCopy {
    public static func remaining(until date: Date, now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "已开始" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(max(minutes, 1)) 分钟"
    }
}

// MARK: - Smart import drafts (CSV / free text / OCR lines)
//
// Recognition only ever produces drafts. Nothing here writes to the store:
// the app shows every draft to the user first, fields stay editable, and only
// the confirmed drafts are converted into courses.

public struct ImportedMeetingDraft: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var weekday: Int // 1 = Monday ... 7 = Sunday, 0 = not recognized
    public var startMinutes: Int?
    public var endMinutes: Int?
    public var startPeriod: Int?
    public var endPeriod: Int?
    public var location: String
    public var parity: Int // per-meeting: 0 = every week, 1 = odd weeks, 2 = even weeks

    public init(id: UUID = UUID(), weekday: Int, startMinutes: Int? = nil, endMinutes: Int? = nil,
                startPeriod: Int? = nil, endPeriod: Int? = nil, location: String = "", parity: Int = 0) {
        self.id = id
        self.weekday = weekday
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.location = location
        self.parity = parity
    }
}

public struct ImportedCourseDraft: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var teacher: String
    public var location: String
    public var firstWeek: Int
    public var lastWeek: Int
    public var customWeeks: [Int] // empty = use the first...last range; non-empty = exactly these weeks
    public var meetings: [ImportedMeetingDraft]
    public var issues: [String]
    public var sourceLine: String

    public init(id: UUID = UUID(), name: String, teacher: String = "", location: String = "",
                firstWeek: Int = 1, lastWeek: Int = 16, customWeeks: [Int] = [],
                meetings: [ImportedMeetingDraft], issues: [String] = [], sourceLine: String = "") {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.location = location
        self.firstWeek = firstWeek
        self.lastWeek = lastWeek
        self.customWeeks = customWeeks
        self.meetings = meetings
        self.issues = issues
        self.sourceLine = sourceLine
    }
}

public enum ScheduleTextImporter {
    // MARK: public entry points

    public static func parseText(_ text: String) -> (drafts: [ImportedCourseDraft], unparsed: [String]) {
        var rawMeetings: [(course: ImportedCourseDraft, meeting: ImportedMeetingDraft)] = []
        var unparsed: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if weekdayTokenCount(line) >= 3 { continue } // a timetable header row, not a course
            if let parsed = parseLine(line) {
                for meeting in parsed.meetings { rawMeetings.append((parsed, meeting)) }
            } else {
                unparsed.append(line)
            }
        }
        return (group(rawMeetings), unparsed)
    }

    public static func parseCSV(_ text: String) -> (drafts: [ImportedCourseDraft], unparsed: [String]) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return ([], []) }
        let delimiter = [",", ";", "\t"].max { a, b in
            headerLine.filter { $0 == Character(a) }.count < headerLine.filter { $0 == Character(b) }.count
        } ?? ","
        let header = splitCSV(headerLine, delimiter: delimiter).map { normalizeHeader($0) }
        func column(_ synonyms: [String]) -> Int? {
            header.firstIndex { synonyms.contains($0) }
        }
        guard let nameCol = column(["课程名称", "课程名", "课程", "课名", "名称", "name", "course"]),
              let weekdayCol = column(["星期", "周几", "星期几", "上课星期", "weekday", "day"]) else {
            return ([], lines)
        }
        let startCol = column(["开始时间", "上课时间", "开始", "起始时间", "start", "from"])
        let endCol = column(["结束时间", "下课时间", "结束", "end", "to"])
        let periodCol = column(["节次", "节数", "上课节次", "period", "节"])
        let locationCol = column(["教室", "上课地点", "地点", "教学地点", "上课教室", "location", "room"])
        let teacherCol = column(["教师", "老师", "任课教师", "授课教师", "主讲教师", "teacher"])
        let weeksCol = column(["周次", "周数", "上课周次", "起止周", "上课周", "weeks", "week"])
        var rawMeetings: [(course: ImportedCourseDraft, meeting: ImportedMeetingDraft)] = []
        var unparsed: [String] = []
        for line in lines.dropFirst() {
            let cells = splitCSV(line, delimiter: delimiter)
            func cell(_ index: Int?) -> String {
                guard let index, index < cells.count else { return "" }
                return cells[index].trimmingCharacters(in: .whitespaces)
            }
            let name = cell(nameCol)
            guard !name.isEmpty, let weekday = weekdayNumber(in: cell(weekdayCol)) else {
                unparsed.append(line)
                continue
            }
            var meeting = ImportedMeetingDraft(weekday: weekday, location: cell(locationCol))
            let startText = cell(startCol), endText = cell(endCol)
            if let range = timeRange(in: startText) {
                meeting.startMinutes = range.0
                meeting.endMinutes = range.1
            } else {
                meeting.startMinutes = clockMinutes(startText)
                meeting.endMinutes = clockMinutes(endText)
            }
            if meeting.startMinutes == nil, let periodText = Optional(cell(periodCol)), !periodText.isEmpty {
                let periods = periodRange(in: periodText)
                meeting.startPeriod = periods.0
                meeting.endPeriod = periods.1
            }
            let weeks = weekRange(in: cell(weeksCol))
            meeting.parity = weeks.2
            var issues: [String] = []
            if meeting.startMinutes == nil && meeting.startPeriod == nil { issues.append("时间没认出") }
            if meeting.location.isEmpty { issues.append("教室没认出") }
            let course = ImportedCourseDraft(
                name: name, teacher: cell(teacherCol), location: meeting.location,
                firstWeek: weeks.0, lastWeek: weeks.1,
                meetings: [], issues: issues, sourceLine: line)
            rawMeetings.append((course, meeting))
        }
        return (group(rawMeetings), unparsed)
    }

    // MARK: one free-text line

    private static func parseLine(_ line: String) -> ImportedCourseDraft? {
        guard weekdayRanges(in: line).count > 0 || timeRange(in: line) != nil || periodRange(in: line).0 != nil else {
            return nil
        }
        let weeks = weekRange(in: line)
        var issues: [String] = []
        var teacher = ""
        if let match = firstMatch(#"(?:教师|老师|任课教师)[:：]?\s*([一-龥]{2,4})"#, in: line) {
            teacher = match.groups[0]
        }
        var lineLocation = ""
        if let match = firstMatch(#"(?:教室|地点)[:：]?\s*([^\s，,；;]+)"#, in: line) {
            lineLocation = match.groups[0]
        }
        let weekdayMatches = weekdayRanges(in: line)
        var meetings: [ImportedMeetingDraft] = []
        if weekdayMatches.isEmpty {
            var meeting = ImportedMeetingDraft(weekday: 0, location: lineLocation, parity: weeks.2)
            applyTime(from: line, to: &meeting)
            meetings.append(meeting)
            issues.append("星期没认出")
        } else {
            for (index, match) in weekdayMatches.enumerated() {
                let segmentEnd = index + 1 < weekdayMatches.count ? weekdayMatches[index + 1].range.lowerBound : line.endIndex
                let segment = String(line[match.range.upperBound..<segmentEnd])
                var meeting = ImportedMeetingDraft(weekday: match.weekday, location: locationToken(in: segment) ?? lineLocation, parity: weeks.2)
                applyTime(from: segment, to: &meeting)
                meetings.append(meeting)
            }
        }
        var namePart = weekdayMatches.first.map { String(line[line.startIndex..<$0.range.lowerBound]) } ?? line
        namePart = stripExtracted(namePart)
        if namePart.isEmpty {
            // The name may sit after the schedule info ("周一 08:00 高等数学 A301").
            let tail = weekdayMatches.last.map { String(line[$0.range.upperBound...]) } ?? ""
            namePart = stripExtracted(tail).components(separatedBy: .whitespaces).first ?? ""
        }
        let name = namePart.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        if name.isEmpty { issues.append("课程名没认出") }
        if meetings.contains(where: { $0.startMinutes == nil && $0.startPeriod == nil }) { issues.append("时间没认出") }
        if meetings.allSatisfy({ $0.location.isEmpty }) && lineLocation.isEmpty { issues.append("教室没认出") }
        let firstLocation = meetings.first(where: { !$0.location.isEmpty })?.location ?? lineLocation
        return ImportedCourseDraft(
            name: name, teacher: teacher, location: firstLocation,
            firstWeek: weeks.0, lastWeek: weeks.1,
            meetings: meetings, issues: issues, sourceLine: line)
    }

    private static func applyTime(from segment: String, to meeting: inout ImportedMeetingDraft) {
        if let range = timeRange(in: segment) {
            meeting.startMinutes = range.0
            meeting.endMinutes = range.1
        } else {
            let periods = periodRange(in: segment)
            meeting.startPeriod = periods.0
            meeting.endPeriod = periods.1
        }
        if meeting.location.isEmpty, let location = locationToken(in: segment) {
            meeting.location = location
        }
    }

    private static func stripExtracted(_ text: String) -> String {
        var result = text
        let patterns = [
            #"第?\s*\d{1,2}\s*[-–—~～]\s*\d{1,2}\s*周"#,
            #"第\s*\d{1,2}\s*周"#, #"单周|双周"#,
            #"\d{1,2}[:：]\d{2}\s*[-–—~～至]\s*\d{1,2}[:：]\d{2}"#,
            #"第?\s*\d{1,2}\s*(?:[-–—~～至]\s*\d{1,2})?\s*节"#,
            #"(?:教室|地点)[:：]?\s*[^\s，,；;]+"#,
            #"(?:教师|老师|任课教师)[:：]?\s*[一-龥]{2,4}"#,
            #"[^\s，,；;]*(?:楼|室|馆|机房|实验室)[^\s，,；;]*"#,
        ]
        for pattern in patterns {
            result = replaceAll(pattern, in: result)
        }
        return result
    }

    // MARK: grouping

    private static func group(_ raw: [(course: ImportedCourseDraft, meeting: ImportedMeetingDraft)]) -> [ImportedCourseDraft] {
        var order: [String] = []
        var map: [String: ImportedCourseDraft] = [:]
        for (course, meeting) in raw {
            let key = [course.name, course.teacher, String(course.firstWeek), String(course.lastWeek)].joined(separator: "|")
            if var existing = map[key] {
                existing.meetings.append(meeting)
                if existing.location.isEmpty { existing.location = meeting.location }
                for issue in course.issues where !existing.issues.contains(issue) { existing.issues.append(issue) }
                map[key] = existing
            } else {
                var fresh = course
                fresh.meetings = [meeting]
                map[key] = fresh
                order.append(key)
            }
        }
        return order.compactMap { map[$0] }
    }

    // MARK: field extractors

    static func weekdayNumber(in text: String) -> Int? {
        if let match = firstMatch(#"(?:周|星期)\s*([一二三四五六日天1-7])"#, in: text) {
            return weekdayValue(match.groups[0])
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let digit = Int(trimmed), (1...7).contains(digit) { return digit }
        return nil
    }

    private static func weekdayValue(_ token: String) -> Int? {
        switch token {
        case "一", "1": return 1
        case "二", "2": return 2
        case "三", "3": return 3
        case "四", "4": return 4
        case "五", "5": return 5
        case "六", "6": return 6
        case "日", "天", "7": return 7
        default: return nil
        }
    }

    private static func weekdayTokenCount(_ text: String) -> Int {
        weekdayRanges(in: text).count
    }

    private static func weekdayRanges(in text: String) -> [(range: Range<String.Index>, weekday: Int)] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:周|星期)\s*([一二三四五六日天1-7])"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let groupRange = Range(match.range(at: 1), in: text),
                  let weekday = weekdayValue(String(text[groupRange])) else { return nil }
            return (range, weekday)
        }
    }

    static func timeRange(in text: String) -> (Int, Int)? {
        guard let match = firstMatch(#"(\d{1,2})[:：](\d{2})\s*[-–—~～至]\s*(\d{1,2})[:：](\d{2})"#, in: text),
              let h1 = Int(match.groups[0]), let m1 = Int(match.groups[1]),
              let h2 = Int(match.groups[2]), let m2 = Int(match.groups[3]) else { return nil }
        return (h1 * 60 + m1, h2 * 60 + m2)
    }

    static func clockMinutes(_ text: String) -> Int? {
        guard let match = firstMatch(#"^\s*(\d{1,2})[:：](\d{2})\s*$"#, in: text),
              let h = Int(match.groups[0]), let m = Int(match.groups[1]) else { return nil }
        return h * 60 + m
    }

    static func periodRange(in text: String) -> (Int?, Int?) {
        if let match = firstMatch(#"(\d{1,2})\s*[-–—~～至]\s*(\d{1,2})\s*节"#, in: text),
           let start = Int(match.groups[0]), let end = Int(match.groups[1]) {
            return (start, end)
        }
        if let match = firstMatch(#"第\s*(\d{1,2})\s*节"#, in: text), let only = Int(match.groups[0]) {
            return (only, only)
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let match = firstMatch(#"^(\d{1,2})\s*[-–—~～]\s*(\d{1,2})$"#, in: trimmed),
           let start = Int(match.groups[0]), let end = Int(match.groups[1]) {
            return (start, end)
        }
        if let only = Int(trimmed), (1...16).contains(only) { return (only, only) }
        return (nil, nil)
    }

    static func weekRange(in text: String) -> (Int, Int, Int) {
        var parity = 0
        if text.contains("单周") { parity = 1 }
        if text.contains("双周") { parity = 2 }
        if let match = firstMatch(#"(\d{1,2})\s*[-–—~～]\s*(\d{1,2})\s*周"#, in: text),
           let first = Int(match.groups[0]), let last = Int(match.groups[1]) {
            return (first, last, parity)
        }
        if let match = firstMatch(#"第\s*(\d{1,2})\s*周"#, in: text), let only = Int(match.groups[0]) {
            return (only, only, parity)
        }
        return (1, 16, parity)
    }

    private static func locationToken(in segment: String) -> String? {
        if let match = firstMatch(#"(?:教室|地点)[:：]?\s*([^\s，,；;]+)"#, in: segment) {
            return match.groups[0]
        }
        let tokens = segment.components(separatedBy: CharacterSet(charactersIn: " \t，,；;、（）()【】"))
        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.contains("楼") || trimmed.contains("机房") || trimmed.contains("实验室")
                || trimmed.contains("体育馆") || trimmed.contains("操场") {
                return trimmed
            }
            if firstMatch(#"^[A-Za-z]{1,2}\d{3,4}$"#, in: trimmed) != nil { return trimmed }
            if firstMatch(#"^\d{3,4}室$"#, in: trimmed) != nil { return trimmed }
        }
        return nil
    }

    // MARK: regex helpers

    private struct Match {
        var groups: [String]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        return Match(groups: groups)
    }

    private static func replaceAll(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
    }

    private static func normalizeHeader(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "（", with: "(")
            .lowercased()
    }

    private static func splitCSV(_ line: String, delimiter: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if inQuotes, index + 1 < chars.count, chars[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                inQuotes.toggle()
                index += 1
                continue
            }
            if !inQuotes, String(char) == delimiter {
                cells.append(current)
                current = ""
                index += 1
                continue
            }
            current.append(char)
            index += 1
        }
        cells.append(current)
        return cells
    }
}

// MARK: - App changelog (shown under 设置 › 关于 › 更新日志)
//
// Maintenance rule: every release adds its entry at the TOP of this list in
// the same commit that bumps MARKETING_VERSION. User-facing wording only.
// A structural test in V2FeatureTests guards ordering and completeness.

public enum AppChangelog {
    public struct Entry: Equatable, Sendable {
        public var version: String
        public var title: String
        public var changes: [String]

        public init(version: String, title: String, changes: [String]) {
            self.version = version
            self.title = title
            self.changes = changes
        }
    }

    public static let entries: [Entry] = [
        Entry(version: "2.1.2", title: "智能导入按预览改版", changes: [
            "智能导入页重做成预览的样子：来源是带图标的卡片、每门课一张带颜色的确认卡（星期做成色块徽章）、修改页每个上课安排一张独立卡，不再是满屏文字表单",
        ]),
        Entry(version: "2.1.1", title: "图片网格识别", changes: [
            "课表截图按版面识别：网格课表能对齐星期列与时间行，整张表一次读完",
        ]),
        Entry(version: "2.1.0", title: "智能导入课表", changes: [
            "新增智能导入：课表图片、CSV 文件、粘贴文本都能自动认出课程名、上课时间、教室和老师",
            "导入前逐门确认：每个上课安排的星期、时间、教室、单双周都能单独改，还能自定义上课周",
            "认不出的内容会原样列出来，不会瞎编时间硬塞进课表",
            "新增本页：更新日志",
        ]),
        Entry(version: "2.0.1", title: "修复共享组警告", changes: [
            "「我的」页不再弹出 App Group 不可用警告，侧载安装时安静使用本机存储",
            "新增一个独有共享组，小组件读取课表更稳",
        ]),
        Entry(version: "2.0.0", title: "新框架与三项新功能", changes: [
            "全新框架：今日、周览、课程、我的四个页签加浮动玻璃底栏",
            "考试倒计时卡与考试页，作业待办上了今日页",
            "自定义日程：课程外的安排和课程一起排进时间线",
            "成绩记录与 GPA：按学分加权，汇总进课程页",
        ]),
    ]
}

// MARK: - OCR grid mode (timetable screenshots laid out as a table)
//
// Input blocks carry Vision-style normalized coordinates (origin at the
// bottom-left, y grows upward). The parser looks for a weekday header row,
// clusters the remaining blocks into rows and columns, and reads each cell
// as one meeting. It returns nil when the image does not look like a grid,
// so callers can fall back to line mode.

public struct OCRTextBlock: Equatable, Sendable {
    public var text: String
    public var centerX: Double
    public var centerY: Double
    public var height: Double

    public init(text: String, centerX: Double, centerY: Double, height: Double) {
        self.text = text
        self.centerX = centerX
        self.centerY = centerY
        self.height = height
    }
}

public extension ScheduleTextImporter {
    static func parseGrid(_ blocks: [OCRTextBlock]) -> (drafts: [ImportedCourseDraft], unparsed: [String])? {
        // 1. Weekday header blocks define the columns.
        var headerBlocks: [(weekday: Int, block: OCRTextBlock)] = []
        for block in blocks {
            let trimmed = block.text.trimmingCharacters(in: .whitespaces)
            guard trimmed.count <= 6, let weekday = weekdayNumber(in: trimmed) else { continue }
            headerBlocks.append((weekday, block))
        }
        headerBlocks.sort { $0.block.centerX < $1.block.centerX }
        var columns: [(weekday: Int, centerX: Double)] = []
        for header in headerBlocks {
            if let last = columns.last, abs(last.centerX - header.block.centerX) < 0.05 { continue }
            columns.append((header.weekday, header.block.centerX))
        }
        guard columns.count >= 3, let headerY = headerBlocks.map({ $0.block.centerY }).max() else { return nil }
        let columnWidth = columns.count > 1
            ? zip(columns, columns.dropFirst()).map { $1.centerX - $0.centerX }.reduce(0, +) / Double(columns.count - 1)
            : 0.14

        // 2. Cluster body blocks (below the header) into rows by centerY.
        let medianHeight = blocks.map(\.height).sorted().dropFirst(blocks.count / 2).first ?? 0.02
        let tolerance = max(0.012, medianHeight * 0.9)
        let body = blocks.filter { $0.centerY < headerY - tolerance }
            .sorted { $0.centerY > $1.centerY }
        var rows: [[OCRTextBlock]] = []
        for block in body {
            if let last = rows.last, let anchor = last.first, abs(anchor.centerY - block.centerY) <= tolerance {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }

        // 3. Each row: time info may sit in the left gutter or inside a cell.
        var rawMeetings: [(course: ImportedCourseDraft, meeting: ImportedMeetingDraft)] = []
        var unparsed: [String] = []
        var rowIndex = 0
        for row in rows {
            rowIndex += 1
            let gutter = row.filter { $0.centerX < (columns.first?.centerX ?? 0) - columnWidth * 0.45 }
            var rowStart: Int?, rowEnd: Int?, rowStartPeriod: Int?, rowEndPeriod: Int?
            for block in gutter {
                if let range = timeRange(in: block.text) { rowStart = range.0; rowEnd = range.1 }
                let periods = periodRange(in: block.text)
                if periods.0 != nil { rowStartPeriod = periods.0; rowEndPeriod = periods.1 }
            }
            var cells: [Int: [OCRTextBlock]] = [:]
            for block in row where !gutter.contains(block) {
                var best: (index: Int, distance: Double)?
                for (index, column) in columns.enumerated() {
                    let distance = abs(column.centerX - block.centerX)
                    if distance < columnWidth * 0.62, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                        best = (index, distance)
                    }
                }
                if let best { cells[best.index, default: []].append(block) }
            }
            for (columnIndex, cellBlocks) in cells {
                let cellText = cellBlocks
                    .sorted { abs($0.centerY - $1.centerY) > 0.008 ? $0.centerY > $1.centerY : $0.centerX < $1.centerX }
                    .map(\.text).joined(separator: " ")
                guard let parsed = parseCell(cellText, weekday: columns[columnIndex].weekday,
                                              rowStart: rowStart, rowEnd: rowEnd,
                                              rowStartPeriod: rowStartPeriod, rowEndPeriod: rowEndPeriod,
                                              rowIndex: rowIndex) else {
                    unparsed.append(cellText)
                    continue
                }
                rawMeetings.append(parsed)
            }
        }
        guard !rawMeetings.isEmpty else { return nil }
        return (group(rawMeetings), unparsed)
    }

    private static func parseCell(_ cellText: String, weekday: Int,
                                  rowStart: Int?, rowEnd: Int?,
                                  rowStartPeriod: Int?, rowEndPeriod: Int?,
                                  rowIndex: Int) -> (course: ImportedCourseDraft, meeting: ImportedMeetingDraft)? {
        let trimmed = cellText.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }
        var meeting = ImportedMeetingDraft(weekday: weekday)
        if let range = timeRange(in: trimmed) {
            meeting.startMinutes = range.0
            meeting.endMinutes = range.1
        } else {
            meeting.startMinutes = rowStart
            meeting.endMinutes = rowEnd
            let periods = periodRange(in: trimmed)
            meeting.startPeriod = periods.0 ?? rowStartPeriod
            meeting.endPeriod = periods.1 ?? rowEndPeriod
        }
        let weeks = weekRange(in: trimmed)
        meeting.parity = weeks.2
        if let location = locationToken(in: trimmed) { meeting.location = location }
        var teacher = ""
        if let match = firstMatch(#"(?:教师|老师|任课教师)[:：]?\s*([一-龥]{2,4})"#, in: trimmed) {
            teacher = match.groups[0]
        }
        var name = stripExtracted(trimmed)
        if let location = Optional(meeting.location), !location.isEmpty {
            name = name.replacingOccurrences(of: location, with: " ")
        }
        name = name.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        guard !name.isEmpty else { return nil }
        var issues: [String] = []
        if meeting.startMinutes == nil && meeting.startPeriod == nil { issues.append("时间没认出") }
        if meeting.location.isEmpty { issues.append("教室没认出") }
        let course = ImportedCourseDraft(
            name: name, teacher: teacher, location: meeting.location,
            firstWeek: weeks.0, lastWeek: weeks.1,
            meetings: [], issues: issues, sourceLine: trimmed)
        return (course, meeting)
    }
}
