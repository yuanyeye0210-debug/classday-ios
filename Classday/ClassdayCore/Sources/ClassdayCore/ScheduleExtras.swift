import Foundation
import Compression
import CoreFoundation

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
        guard !lines.isEmpty else { return ([], []) }
        var delimiter = ","
        var bestCount = -1
        for candidate in [",", ";", "\t"] {
            let needle = Character(candidate)
            var total = 0
            for line in lines { total += line.filter { $0 == needle }.count }
            if total > bestCount { bestCount = total; delimiter = candidate }
        }
        let rows = lines.map { splitCSV($0, delimiter: delimiter) }
        if let parsed = parseRows(rows) { return parsed }
        return ([], lines)
    }

    /// Shared pipeline for every tabular source (CSV rows, HTML tables, XLSX
    /// and DOCX grids): a weekday-header row means grid layout, a synonym
    /// header row means list layout. Returns nil when neither fits.
    public static func parseRows(_ rows: [[String]], spans: [String: Int] = [:]) -> (drafts: [ImportedCourseDraft], unparsed: [String])? {
        if let table = parseTable(rows, spans: spans) { return table }
        return listFromRows(rows)
    }

    private static func listFromRows(_ rows: [[String]]) -> (drafts: [ImportedCourseDraft], unparsed: [String])? {
        // Real exports carry title/info rows above the header; scan the
        // first rows and keep the one that matches the most column synonyms.
        var best: (index: Int, score: Int, columns: [String: Int])?
        for (index, row) in rows.prefix(6).enumerated() {
            let normalized = row.map { normalizeHeader($0) }
            func column(_ synonyms: [String]) -> Int? {
                normalized.firstIndex { cell in
                    synonyms.contains { synonym in
                        cell == synonym || cell.hasPrefix(synonym) || (synonym.count >= 2 && cell.contains(synonym))
                    }
                }
            }
            var columns: [String: Int] = [:]
            if let value = column(["课程名称", "课程名", "课程", "课名", "课目", "名称", "name", "course"]) { columns["name"] = value }
            if let value = column(["星期", "周几", "星期几", "上课星期", "授课星期", "weekday", "day"]) { columns["weekday"] = value }
            if let value = column(["开始时间", "上课时间", "开始", "起始时间", "上课时间段", "时间", "start", "from"]) { columns["start"] = value }
            if let value = column(["结束时间", "下课时间", "结束", "end", "to"]) { columns["end"] = value }
            if let value = column(["节次", "节数", "上课节次", "period", "节"]) { columns["period"] = value }
            if let value = column(["教室", "上课地点", "地点", "教学地点", "上课教室", "location", "room"]) { columns["location"] = value }
            if let value = column(["教师", "老师", "任课教师", "授课教师", "主讲教师", "teacher"]) { columns["teacher"] = value }
            if let value = column(["周次", "周数", "上课周次", "起止周", "上课周", "weeks", "week"]) { columns["weeks"] = value }
            if let value = column(["时间地点", "上课安排", "时间安排"]) { columns["combined"] = value }
            let score = columns.count
            if columns["name"] != nil, columns["weekday"] != nil || columns["start"] != nil || columns["combined"] != nil,
               score > (best?.score ?? 0) {
                best = (index, score, columns)
            }
        }
        guard let header = best else { return nil }
        let columns = header.columns
        var rawMeetings: [(course: ImportedCourseDraft, meeting: ImportedMeetingDraft)] = []
        var unparsed: [String] = []
        var lastName = "", lastTeacher = ""
        for row in rows.dropFirst(header.index + 1) {
            func cell(_ key: String) -> String {
                guard let index = columns[key], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespaces)
            }
            var name = cleanCourseName(cell("name"))
            if name.isEmpty { name = lastName } else { lastName = name }
            var teacher = cell("teacher")
            if teacher.isEmpty { teacher = lastTeacher } else { lastTeacher = teacher }
            let combined = [cell("start"), cell("combined")].filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty,
                  let weekday = weekdayNumber(in: cell("weekday")) ?? weekdayNumber(in: combined) else {
                unparsed.append(row.joined(separator: ","))
                continue
            }
            var meeting = ImportedMeetingDraft(weekday: weekday, location: cell("location"))
            if let range = timeRange(in: cell("start")) {
                meeting.startMinutes = range.0
                meeting.endMinutes = range.1
            } else if let range = timeRange(in: combined) {
                meeting.startMinutes = range.0
                meeting.endMinutes = range.1
            } else {
                meeting.startMinutes = clockMinutes(cell("start"))
                meeting.endMinutes = clockMinutes(cell("end"))
            }
            if meeting.startMinutes == nil {
                let periods = periodRange(in: cell("period").isEmpty ? combined : cell("period"))
                meeting.startPeriod = periods.0
                meeting.endPeriod = periods.1
            }
            if meeting.location.isEmpty, let found = locationToken(in: combined) { meeting.location = found }
            let weeksInfo = explicitWeeks(in: cell("weeks").isEmpty ? combined : cell("weeks"))
            meeting.parity = weeksInfo.parity
            var issues: [String] = []
            if meeting.startMinutes == nil && meeting.startPeriod == nil { issues.append("时间没认出") }
            if meeting.location.isEmpty { issues.append("教室没认出") }
            let course = ImportedCourseDraft(
                name: name, teacher: teacher, location: meeting.location,
                firstWeek: weeksInfo.first, lastWeek: weeksInfo.last, customWeeks: weeksInfo.custom,
                meetings: [], issues: issues, sourceLine: row.joined(separator: ","))
            rawMeetings.append((course, meeting))
        }
        guard !rawMeetings.isEmpty else { return nil }
        return (group(rawMeetings), unparsed)
    }

    /// Course names in exports carry serial numbers and bracketed course
    /// codes / credit notes ("(A210331)", "（3学分）"); strip them.
    private static func cleanCourseName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading serial numbers like "1. " / "2、"
        if let first = name.first, first.isNumber {
            let digits = name.prefix { $0.isNumber }
            if digits.count <= 3 {
                let rest = name.dropFirst(digits.count)
                if let marker = rest.first, marker == "." || marker == "、" || marker == "．" {
                    name = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // Bracketed chunks carrying a course code or credit note are cut;
        // anything else in brackets stays part of the name.
        let openers: [Character: Character] = ["(": ")", "（": "）", "[": "]", "【": "】"]
        var output = ""
        var index = name.startIndex
        while index < name.endIndex {
            let character = name[index]
            if let closer = openers[character] {
                let contentStart = name.index(after: index)
                if contentStart < name.endIndex,
                   let closeIndex = name[contentStart...].firstIndex(of: closer) {
                    let inner = name[contentStart..<closeIndex]
                    if inner.contains(where: { $0.isNumber }) || inner.contains("学分")
                        || inner.contains("代码") || inner.contains("英文") {
                        index = name.index(after: closeIndex)
                        continue
                    }
                }
            }
            output.append(character)
            index = name.index(after: index)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Week info beyond weekRange's basics: bare "1-16" ranges and explicit
    /// lists like "1,3,5,7周" (which become an exact custom-weeks list).
    private static func explicitWeeks(in text: String) -> (first: Int, last: Int, custom: [Int], parity: Int) {
        let base = weekRange(in: text)
        let numbers = allMatches(#"(\d{1,2})"#, in: text).compactMap { Int($0.groups[0]) }.filter { (1...40).contains($0) }
        if (text.contains(",") || text.contains("，") || text.contains("、")) && numbers.count >= 2 {
            let custom = Array(Set(numbers)).sorted()
            return (custom.first ?? base.0, custom.last ?? base.1, custom, base.2)
        }
        if base.0 == 1 && base.1 == 16 && base.2 == 0,
           let match = firstMatch(#"^\s*(\d{1,2})\s*[-–—~～]\s*(\d{1,2})\s*$"#, in: text),
           let first = Int(match.groups[0]), let last = Int(match.groups[1]) {
            return (first, last, [], 0)
        }
        return (base.0, base.1, [], base.2)
    }

    private static func allMatches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            return Match(groups: groups)
        }
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
            #"(?i)every\s+2\s+weeks?\s*\(starting\s+week\s+\d+\)"#,
            #"(?i)weeks?\s+[\d\s,–—\-]+"#,
            #"(?i)\broom\s+[A-Za-z0-9.]+"#,
            #"\b[A-Za-z]{1,5}-[A-Za-z]*\d+\b"#,
            #"(?i)\b[A-Z]{2,}[A-Z]*\d[A-Z0-9]*\b"#,
            #"\s*[·•]\s*"#,
        ]
        for pattern in patterns {
            result = replaceAll(pattern, in: result)
        }
        return result
    }

    /// English week specs found in international timetables:
    /// "Weeks 1–4, 6–7, 9–15" (disjoint ranges become an exact week list)
    /// and "Every 2 weeks (starting Week 2)".
    static func englishWeeks(in text: String) -> (first: Int, last: Int, custom: [Int])? {
        guard text.lowercased().contains("week") else { return nil }
        if let match = firstMatch(#"(?i)every\s+2\s+weeks?\s*\(starting\s+week\s+(\d{1,2})\)"#, in: text),
           let start = Int(match.groups[0]) {
            let custom = Array(stride(from: start, through: 16, by: 2))
            return (start, custom.last ?? start, custom)
        }
        var weeks = Set<Int>()
        for match in allMatches(#"(\d{1,2})\s*[-–—]\s*(\d{1,2})"#, in: text) {
            if let a = Int(match.groups[0]), let b = Int(match.groups[1]), a <= b, b <= 40 {
                for week in a...b { weeks.insert(week) }
            }
        }
        if let keyword = text.lowercased().range(of: "week") {
            let tail = String(text[keyword.upperBound...])
            let tailNoRanges = replaceAll(#"\d{1,2}\s*[-–—]\s*\d{1,2}"#, in: tail)
            for match in allMatches(#"(?<![A-Za-z0-9])(\d{1,2})(?![A-Za-z0-9])"#, in: tailNoRanges) {
                if let number = Int(match.groups[0]), (1...40).contains(number) { weeks.insert(number) }
            }
        }
        guard let first = weeks.min(), let last = weeks.max() else { return nil }
        let sorted = weeks.sorted()
        return (first, last, sorted == Array(first...last) ? [] : sorted)
    }

    /// "Weeks 2–7: Room AM" style segments — one course meeting in
    /// different rooms for different week ranges.
    static func weekRoomSegments(in text: String) -> [(first: Int, last: Int, room: String)] {
        allMatchesDotAll(#"(?i)weeks?\s+(\d{1,2})\s*[-–—]\s*(\d{1,2})\s*[:：]?\s*room\s+([A-Za-z0-9.]+)"#, in: text)
            .compactMap { match in
                guard let first = Int(match.groups[0]), let last = Int(match.groups[1]) else { return nil }
                return (first, last, match.groups[2])
            }
    }

    // MARK: grouping

    private static func group(_ raw: [(course: ImportedCourseDraft, meeting: ImportedMeetingDraft)]) -> [ImportedCourseDraft] {
        var order: [String] = []
        var map: [String: ImportedCourseDraft] = [:]
        for (course, meeting) in raw {
            let key = [course.name, course.teacher, String(course.firstWeek), String(course.lastWeek),
                       course.customWeeks.map(String.init).joined(separator: ",")].joined(separator: "|")
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
        let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
        let englishNames: [(String, Int)] = [("monday", 1), ("tuesday", 2), ("wednesday", 3),
                                             ("thursday", 4), ("friday", 5), ("saturday", 6), ("sunday", 7),
                                             ("mon", 1), ("tue", 2), ("wed", 3), ("thu", 4),
                                             ("fri", 5), ("sat", 6), ("sun", 7)]
        for (word, value) in englishNames
        where lowered == word || lowered.hasPrefix(word + " ") || lowered.hasPrefix(word + "(") {
            return value
        }
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
            let value = match.groups[0]
            if !value.hasPrefix("未定") { return value }
        }
        if let match = firstMatch(#"(?i)\broom\s+([A-Za-z0-9][A-Za-z0-9.]*)"#, in: segment) {
            let code = match.groups[0]
            if code.lowercased() != "tba" { return "Room \(code)" }
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
        var value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        value = replaceAll(#"[\(\[（【][^\)\]）】*[\)\]）】]"#, in: value)
        return value.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
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


// MARK: - Tabular grids, HTML tables and Office files (2.2 engine)

public extension ScheduleTextImporter {
    /// Grid layout from cell rows: a header row of weekday names, time or
    /// period labels in the leading columns, one course per cell. Used by
    /// CSV grids, HTML tables, XLSX and DOCX alike.
    static func parseTable(_ rows: [[String]], spans: [String: Int] = [:]) -> (drafts: [ImportedCourseDraft], unparsed: [String])? {
        // Find the header row: at least three weekday-labelled cells.
        var header: (index: Int, columns: [Int: Int])?
        for (index, row) in rows.prefix(6).enumerated() {
            var columns: [Int: Int] = [:]
            for (column, cell) in row.enumerated() {
                let trimmed = cell.trimmingCharacters(in: .whitespaces)
                guard trimmed.count <= 16 else { continue }
                if let weekday = weekdayNumber(in: trimmed) { columns[column] = weekday }
            }
            if columns.count >= 3 { header = (index, columns); break }
        }
        guard let headerRow = header else { return nil }
        let firstWeekdayColumn = headerRow.columns.keys.min() ?? 0
        var rawMeetings: [(course: ImportedCourseDraft, meeting: ImportedMeetingDraft)] = []
        var unparsed: [String] = []
        for (rowOffset, row) in rows.dropFirst(headerRow.index + 1).enumerated() {
            let absoluteRow = headerRow.index + 1 + rowOffset
            // A legend/explainer section ends the timetable proper.
            if let first = row.first, first.contains("Legend") || first.contains("图例") { break }
            let label = row.prefix(firstWeekdayColumn).joined(separator: " ")
            let rowTimes = timeRange(in: label)
            let rowPeriods = periodRange(in: label)
            // Rows with no time/period label and no in-cell clock time are
            // not class rows (legend entries live in cells like these).
            let rowHasOwnTimes = row.enumerated().contains { column, cell in
                headerRow.columns[column] != nil && timeRange(in: cell) != nil
            }
            if rowTimes == nil && rowPeriods.0 == nil && !rowHasOwnTimes { continue }
            for (column, weekday) in headerRow.columns.sorted(by: { $0.key < $1.key }) {
                guard column < row.count else { continue }
                let cell = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                if cell.isEmpty { continue }
                if ["周一", "周二", "周三", "周四", "周五", "周六", "周日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"].contains(cell) { continue }
                // Merged cells (XLSX) stretch this meeting to a later row.
                let endRow = spans["\(absoluteRow),\(column)"] ?? absoluteRow
                let endLabel = endRow < rows.count && endRow != absoluteRow
                    ? rows[endRow].prefix(firstWeekdayColumn).joined(separator: " ")
                    : label
                let effectiveEnd = timeRange(in: endLabel)?.1 ?? rowTimes?.1
                let effectiveEndPeriod = periodRange(in: endLabel).1 ?? rowPeriods.1
                // Split-room courses: one draft per week-range segment.
                let segments = weekRoomSegments(in: cell)
                if segments.count >= 2 {
                    let rawName = (cell.components(separatedBy: "Week").first ?? cell)
                        .replacingOccurrences(of: "\n", with: " ")
                    let name = stripExtracted(rawName)
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                        .trimmingCharacters(in: .punctuationCharacters)
                    for segment in segments {
                        var meeting = ImportedMeetingDraft(weekday: weekday, location: "Room \(segment.room)")
                        meeting.startMinutes = rowTimes?.0
                        meeting.endMinutes = effectiveEnd
                        meeting.startPeriod = rowPeriods.0
                        meeting.endPeriod = effectiveEndPeriod
                        let issues = meeting.startMinutes == nil && meeting.startPeriod == nil ? ["时间没认出"] : []
                        let course = ImportedCourseDraft(
                            name: name, location: meeting.location,
                            firstWeek: segment.first, lastWeek: segment.last,
                            meetings: [], issues: issues, sourceLine: cell)
                        rawMeetings.append((course, meeting))
                    }
                    continue
                }
                let folded = cell.replacingOccurrences(of: "\n", with: " ")
                if let parsed = parseCell(folded, weekday: weekday,
                                          rowStart: rowTimes?.0, rowEnd: effectiveEnd,
                                          rowStartPeriod: rowPeriods.0, rowEndPeriod: effectiveEndPeriod,
                                          rowIndex: rowOffset) {
                    rawMeetings.append(parsed)
                } else {
                    unparsed.append(cell)
                }
            }
        }
        guard !rawMeetings.isEmpty else { return nil }
        return (group(rawMeetings), unparsed)
    }

    /// 教务系统 "xls" exports are often HTML tables in disguise.
    static func parseHTML(_ html: String) -> (drafts: [ImportedCourseDraft], unparsed: [String]) {
        var rows: [[String]] = []
        for rowMatch in allMatchesDotAll(#"<tr[^>]*>(.*?)</tr>"#, in: html) {
            var cells: [String] = []
            for cellMatch in allMatchesDotAll(#"<t[dh][^>]*>(.*?)</t[dh]>"#, in: rowMatch.groups[0]) {
                let text = xmlUnescape(replaceAll(#"<[^>]+>"#, in: cellMatch.groups[0]))
                    .replacingOccurrences(of: " ", with: " ")
                cells.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        if let parsed = parseRows(rows) { return parsed }
        let plain = replaceAll(#"<[^>]+>"#, in: html)
        return parseText(plain)
    }

    /// Minimal read-only ZIP reader (central directory + stored/deflate),
    /// enough for the OOXML containers behind .xlsx and .docx.
    static func unzip(_ data: Data) -> [String: Data] {
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        // End of central directory: scan the tail for PK\x05\x06.
        var eocd = -1
        var index = bytes.count - 22
        while index >= 0 && index >= bytes.count - 66000 {
            if bytes[index] == 0x50 && bytes[index + 1] == 0x4B && bytes[index + 2] == 0x05 && bytes[index + 3] == 0x06 {
                eocd = index
                break
            }
            index -= 1
        }
        guard eocd >= 0 else { return [:] }
        let count = u16(eocd + 10)
        var cursor = u32(eocd + 16)
        var entries: [String: Data] = [:]
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, bytes[cursor] == 0x50, bytes[cursor + 1] == 0x4B,
                  bytes[cursor + 2] == 0x01, bytes[cursor + 3] == 0x02 else { break }
            let method = u16(cursor + 10)
            let compressedSize = u32(cursor + 20)
            let rawSize = u32(cursor + 24)
            let nameLength = u16(cursor + 28)
            let extraLength = u16(cursor + 30)
            let commentLength = u16(cursor + 32)
            let localOffset = u32(cursor + 42)
            let name = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8) ?? ""
            if localOffset + 30 <= bytes.count {
                let localName = u16(localOffset + 26)
                let localExtra = u16(localOffset + 28)
                let dataStart = localOffset + 30 + localName + localExtra
                let dataEnd = min(dataStart + compressedSize, bytes.count)
                if dataStart <= dataEnd {
                    let raw = Data(bytes[dataStart..<dataEnd])
                    if method == 0 {
                        entries[name] = raw
                    } else if method == 8, rawSize > 0 {
                        var output = Data(count: rawSize)
                        let written = output.withUnsafeMutableBytes { dst -> Int in
                            raw.withUnsafeBytes { src in
                                compression_decode_buffer(
                                    dst.bindMemory(to: UInt8.self).baseAddress!, rawSize,
                                    src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                    nil, COMPRESSION_ZLIB)
                            }
                        }
                        if written == rawSize { entries[name] = output }
                    }
                }
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    static func parseXLSX(_ data: Data) -> (drafts: [ImportedCourseDraft], unparsed: [String])? {
        let entries = unzip(data)
        guard let sheetName = entries.keys.filter({ $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }).sorted().first,
              let sheetData = entries[sheetName],
              let sheetXML = String(data: sheetData, encoding: .utf8) else { return nil }
        var shared: [String] = []
        if let sharedData = entries["xl/sharedStrings.xml"], let sharedXML = String(data: sharedData, encoding: .utf8) {
            for chunk in sharedXML.components(separatedBy: "<si>").dropFirst() {
                let runs = allMatchesDotAll(#"<t[^>]*>([^<]*)</t>"#, in: chunk)
                shared.append(xmlUnescape(runs.map { $0.groups[0] }.joined()))
            }
        }
        // Merged ranges: a course cell stretched over several time rows.
        var merges: [(startRow: Int, startCol: Int, endRow: Int)] = []
        for match in allMatchesDotAll(#"<mergeCell ref="([A-Z]+)(\d+):([A-Z]+)(\d+)""#, in: sheetXML) {
            func columnIndex(_ letters: String) -> Int {
                letters.reduce(0) { $0 * 26 + (Int($1.unicodeScalars.first!.value) - 64) } - 1
            }
            if let startRow = Int(match.groups[1]), let endRow = Int(match.groups[3]) {
                merges.append((startRow, columnIndex(match.groups[0]), endRow))
            }
        }
        var rowsByNumber: [Int: [String]] = [:]
        for rowChunk in sheetXML.components(separatedBy: "<row").dropFirst() {
            let rowNumber = firstMatch(#"^\s*r="(\d+)""#, in: rowChunk).flatMap { Int($0.groups[0]) }
                ?? ((rowsByNumber.keys.max() ?? 0) + 1)
            var cells: [String] = []
            for cellMatch in allMatchesDotAll(#"<c\s([^>]*?)(/>|>(.*?)</c>)"#, in: rowChunk) {
                let attributes = cellMatch.groups[0]
                let inner = cellMatch.groups[2]
                var value = ""
                if attributes.contains("t=\"s\""), let v = firstMatchDotAll(#"<v>([^<]*)</v>"#, in: inner),
                   let sharedIndex = Int(v.groups[0]), sharedIndex < shared.count {
                    value = shared[sharedIndex]
                } else if attributes.contains("t=\"inlineStr\"") {
                    value = xmlUnescape(allMatchesDotAll(#"<t[^>]*>([^<]*)</t>"#, in: inner).map { $0.groups[0] }.joined())
                } else if let v = firstMatchDotAll(#"<v>([^<]*)</v>"#, in: inner) {
                    value = xmlUnescape(v.groups[0])
                }
                var column = cells.count
                if let ref = firstMatch(#"r=\"([A-Z]+)\d+\""#, in: attributes) {
                    column = ref.groups[0].reduce(0) { $0 * 26 + (Int($1.unicodeScalars.first!.value) - 64) } - 1
                }
                while cells.count < column { cells.append("") }
                if cells.count == column { cells.append(value) } else if column < cells.count { cells[column] = value }
            }
            rowsByNumber[rowNumber] = cells
        }
        var rows: [[String]] = []
        var spans: [String: Int] = [:]
        if let firstRow = rowsByNumber.keys.min(), let lastRow = rowsByNumber.keys.max() {
            for number in firstRow...lastRow { rows.append(rowsByNumber[number] ?? []) }
            for merge in merges where merge.endRow > merge.startRow {
                spans["\(merge.startRow - firstRow),\(merge.startCol)"] = merge.endRow - firstRow
            }
        }
        if let parsed = parseRows(rows, spans: spans) { return parsed }
        let joined = rows.map { $0.filter { !$0.isEmpty }.joined(separator: " ") }.filter { !$0.isEmpty }
        return parseText(joined.joined(separator: "\n"))
    }

    static func parseDOCX(_ data: Data) -> (drafts: [ImportedCourseDraft], unparsed: [String])? {
        let entries = unzip(data)
        guard let documentData = entries["word/document.xml"],
              let xml = String(data: documentData, encoding: .utf8) else { return nil }
        func cellText(_ chunk: String) -> String {
            xmlUnescape(allMatchesDotAll(#"<w:t[^>]*>([^<]*)</w:t>"#, in: chunk).map { $0.groups[0] }.joined())
        }
        if xml.contains("<w:tbl") {
            var rows: [[String]] = []
            for tableChunk in xml.components(separatedBy: "<w:tbl").dropFirst() {
                for rowChunk in tableChunk.components(separatedBy: "<w:tr").dropFirst() {
                    var cells: [String] = []
                    for cellChunk in rowChunk.components(separatedBy: "<w:tc").dropFirst() {
                        cells.append(cellText(cellChunk))
                    }
                    if !cells.isEmpty { rows.append(cells) }
                }
                break // first table only: it is the timetable
            }
            if let parsed = parseRows(rows) { return parsed }
        }
        let lines = xml.components(separatedBy: "<w:p").dropFirst().map { cellText($0) }
        return parseText(lines.joined(separator: "\n"))
    }

    /// One entry point for arbitrary file bytes: OOXML containers, HTML
    /// tables masquerading as .xls, and plain text as the fallback.
    static func parseFileData(_ data: Data) -> (drafts: [ImportedCourseDraft], unparsed: [String])? {
        if data.count >= 4, data[0] == 0x50, data[1] == 0x4B {
            if let xlsx = parseXLSX(data) { return xlsx }
            if let docx = parseDOCX(data) { return docx }
            return nil
        }
        guard let text = decodeText(data) else { return nil }
        let lowered = text.lowercased()
        if lowered.contains("<table") || lowered.contains("<html") {
            return parseHTML(text)
        }
        let csv = parseCSV(text)
        if !csv.drafts.isEmpty { return csv }
        return parseText(text)
    }

    /// UTF-8 first, then GB18030 (legacy exports), then UTF-16.
    static func decodeText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(1586))
        if let legacy = String(data: data, encoding: String.Encoding(rawValue: gb18030)) { return legacy }
        return String(data: data, encoding: .utf16)
    }

    static func xmlUnescape(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        for match in allMatches(#"&#(\d+);"#, in: result) {
            if let code = Int(match.groups[0]), let scalar = UnicodeScalar(code) {
                result = result.replacingOccurrences(of: "&#\(code);", with: String(scalar))
            }
        }
        for match in allMatches(#"&#x([0-9a-fA-F]+);"#, in: result) {
            if let code = Int(match.groups[0], radix: 16), let scalar = UnicodeScalar(code) {
                result = result.replacingOccurrences(of: "&#x\(match.groups[0]);", with: String(scalar))
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func allMatchesDotAll(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            return Match(groups: groups)
        }
    }

    private static func firstMatchDotAll(_ pattern: String, in text: String) -> Match? {
        allMatchesDotAll(pattern, in: text).first
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
        Entry(version: "2.3.6", title: "周览日程可编辑与检查更新", changes: [
            "周览页的日程现在可以点开编辑（与今日页一致：改标题 / 备注 / 时间，或删除）",
            "「我的 → 关于」新增检查更新：有新版会提示版本号并出现下载按钮（侧载版下载后覆盖安装，数据不丢）",
        ]),
        Entry(version: "2.3.5", title: "流畅度优化与作业管理", changes: [
            "背景特效瘦身：删掉一层重复背景、模糊光斑改用渐变绘制、着色器只作用在装饰层上，滑动列表和切换页面明显更跟手",
            "倾斜视觉改走低频量化通道：手机放着不动时，界面不再跟着传感器每秒重绘 30 次",
            "学习面板的作业支持右划删除与编辑（标题 / 课程 / 截止时间）；删掉作业标题输入栏",
            "订阅导入的结果直接显示在面板里（导入了几门课、几场考试都写明），不再被弹层挡住看不见",
        ]),
        Entry(version: "2.3.4", title: "震动反馈重做：每套主题一种震法", changes: [
            "八套主题各有自己的震动：霓虹电流强震、机甲金属重击、HUD 仪器强刻度、轨道摆正双震扣合，步长、音色、归位方式各不相同",
            "灵敏度三档（标准 / 灵敏 / 最敏感），默认最敏感：最小 2.5° 就震一记、跨刻度立即触发、摆正更容易震到",
            "所有震动强度拉满到硬件上限，拿在手里清清楚楚",
            "主题页震动卡新增「试震一下」按钮和当前震法标注，不用晃手机就能当场验",
        ]),
        Entry(version: "2.3.3", title: "玻璃主题虹彩过曝修复", changes: [
            "玻璃主题的薄膜虹彩降强度：背景虹彩由浓转淡，卡片上的虹彩改成柔光薄层，只在卡面留一层淡淡光泽",
            "课程名、教室、下一次上课时间等文字恢复本色，不再被虹彩染色，看得清了",
        ]),
        Entry(version: "2.3.2", title: "特效高级版：全主题倾斜 + 震动反馈 + 节次保险", changes: [
            "灵动岛修复：下一节课倒计时只在今天还有课时出现，休息日不再挂一整天",
            "八套主题全部跟随手机倾斜：立方网格剪切滑动、HUD 圆环摆动、机甲高光带、玻璃薄膜虹彩、星尘引力透镜，跟踪改用弹簧引擎，带惯性和回弹",
            "倾斜震动反馈：倾斜每跨 8° 轻震一记，转动方位每 45° 也有刻度感，手机摆正时一记「归位」；主题页可开关",
            "今日主角卡和课程卡随倾斜微微立体转动，光从重力上方扫过；玻璃主题下卡面带全息箔变色",
            "主题页新增「倾斜实时读数」卡，传感器是否在工作一眼可见",
            "学期设置新增节次模板：一键套用 30 分钟 × 20 节（里斯本 IST）或 45 分钟 × 10 节；保存节次前自动把当前课表备份进课表库",
            "新增节次改为继承上一节的时长，不再默认 45 分钟；学期编辑防覆盖：未加载完不能保存，外部变更不会冲掉未保存的编辑",
        ]),
        Entry(version: "2.3.1", title: "特效实时跟随手机倾斜", changes: [
            "修好特效被系统底色盖住的问题：背景光晕在四个主页面都能看见了",
            "特效改成实时跟踪手机倾斜：光晕按视差错位、粒子顺着重力方向流动——手机往哪倾，效果就往哪走，不是固定动画",
            "新增主题「星尘引力」：三层星尘加受重力牵引的尘粒，往低处沉、撞到边缘会弹，摇晃手机能把它们震散",
            "玻璃主题加了随倾斜滑动的折射流光；极光的粒子也会顺着倾斜方向漂移",
        ]),
        Entry(version: "2.3.0", title: "主题特效修好了", changes: [
            "高性能档的特效以前基本看不见，这次修好：背景光晕真正流动起来，玻璃主题的虹彩在浅色底上也看得清",
            "极光主题的粒子上浮补上了真渲染；霓虹的扫描线、深空 HUD 的旋转表盘、星际轨道的行星都会动了",
            "视差改成晃手机时光晕跟着错位（以前平移的是一整块纯色背景，看不出来）",
            "主题页的预览卡换成活的背景，选中哪套就动哪套；被系统低电量自动降档时，页面会写明实际生效的档位",
        ]),
        Entry(version: "2.2.1", title: "拿真实课表校准识别", changes: [
            "修好了一个会让导入直接崩溃的 bug（周次写成列表时触发）",
            "Excel 里跨了好几行的合并课程，结束时间现在按最后一行算准；英文课表全支持：Monday 表头、Weeks 周次列表、分段换教室、每两周一次的课都认了",
            "课表下方的课程图例不再被误认成课程；图片识别改成按左侧时间栏分行，跨格的大课不再被切碎",
        ]),
        Entry(version: "2.2.0", title: "所有文件都能导入，识别更准", changes: [
            "智能导入的文件入口打通了：Excel(.xlsx)、Word(.docx)、PDF、网页表格文件（教务系统导出的那种）、日历 .ics 都能直接选进来识别，老式 .xls 会给出另存提示",
            "识别引擎重做：网格课表（横着星期、竖着节次）现在 CSV、Excel、Word、PDF 都能按格子对位；表头不在第一行、列名带后缀、时间地点挤在一格的情况也认了",
            "课程名会自动去掉序号和课程代码括号，空白课程名会自动接上一行的课程，周次支持「1,3,5周」这种逐周列表",
        ]),
        Entry(version: "2.1.3", title: "设置页全页重包", changes: [
            "「我的」页所有文字项都装上了修饰：主题/数据/更新日志等改成彩色图标行、保存改成整宽按钮、节次加了序号徽章、通知权限带状态点和检查胶囊钮",
        ]),
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
            guard trimmed.count <= 12, let weekday = weekdayNumber(in: trimmed) else { continue }
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

        // 2. Gutter time labels define row bands. A course cell in a real
        // timetable spans several bands and holds several text lines, so
        // blocks are grouped per column by vertical proximity and the
        // meeting time comes from every band the merged cell touches.
        let medianHeight = blocks.map(\.height).sorted().dropFirst(blocks.count / 2).first ?? 0.02
        let tolerance = max(0.012, medianHeight * 0.9)
        let gutterLimit = (columns.first?.centerX ?? 0) - columnWidth * 0.45
        let timedGutter = blocks
            .filter { $0.centerX < gutterLimit && $0.centerY < headerY && (timeRange(in: $0.text) != nil || periodRange(in: $0.text).0 != nil) }
            .sorted { $0.centerY > $1.centerY }
        struct Band {
            var top: Double
            var bottom: Double
            var start: Int?
            var end: Int?
            var startPeriod: Int?
            var endPeriod: Int?
        }
        var bands: [Band] = []
        if timedGutter.count >= 2 {
            for (index, block) in timedGutter.enumerated() {
                let top = index == 0
                    ? block.centerY + block.height * 1.6
                    : (timedGutter[index - 1].centerY + block.centerY) / 2
                let bottom = index == timedGutter.count - 1
                    ? block.centerY - block.height * 1.6
                    : (block.centerY + timedGutter[index + 1].centerY) / 2
                let range = timeRange(in: block.text)
                let periods = periodRange(in: block.text)
                bands.append(Band(top: top, bottom: bottom, start: range?.0, end: range?.1,
                                  startPeriod: periods.0, endPeriod: periods.1))
            }
        }
        if !bands.isEmpty {
            var rawMeetings: [(course: ImportedCourseDraft, meeting: ImportedMeetingDraft)] = []
            var unparsed: [String] = []
            let bodyBlocks = blocks.filter { $0.centerY < headerY - tolerance && $0.centerX >= gutterLimit }
            var perColumn: [Int: [OCRTextBlock]] = [:]
            for block in bodyBlocks {
                var best: (index: Int, distance: Double)?
                for (index, column) in columns.enumerated() {
                    let distance = abs(column.centerX - block.centerX)
                    if distance < columnWidth * 0.62, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                        best = (index, distance)
                    }
                }
                if let best { perColumn[best.index, default: []].append(block) }
            }
            for (columnIndex, columnBlocks) in perColumn {
                let sorted = columnBlocks.sorted { $0.centerY > $1.centerY }
                var cells: [[OCRTextBlock]] = []
                for block in sorted {
                    if let previous = cells.last?.last {
                        let gap = (previous.centerY - previous.height / 2) - (block.centerY + block.height / 2)
                        if gap <= max(0.015, medianHeight * 0.9) {
                            cells[cells.count - 1].append(block)
                            continue
                        }
                    }
                    cells.append([block])
                }
                for (cellIndex, cell) in cells.enumerated() {
                    let cellText = cell.map(\.text).joined(separator: " ")
                    if cellText.contains("Legend") || cellText.contains("图例") { continue }
                    let top = cell.map { $0.centerY + $0.height / 2 }.max() ?? 0
                    let bottom = cell.map { $0.centerY - $0.height / 2 }.min() ?? 0
                    let hit = bands.filter { $0.top > bottom && $0.bottom < top }
                    if hit.isEmpty && timeRange(in: cellText) == nil {
                        unparsed.append(cellText)
                        continue
                    }
                    guard let parsed = parseCell(cellText, weekday: columns[columnIndex].weekday,
                                                  rowStart: hit.first?.start, rowEnd: hit.last?.end,
                                                  rowStartPeriod: hit.first?.startPeriod, rowEndPeriod: hit.last?.endPeriod,
                                                  rowIndex: cellIndex) else {
                        unparsed.append(cellText)
                        continue
                    }
                    rawMeetings.append(parsed)
                }
            }
            guard !rawMeetings.isEmpty else { return nil }
            return (group(rawMeetings), unparsed)
        }

        // Fallback: cluster body blocks into rows by centerY (no usable
        // gutter), the original line-up behaviour.
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
        let english = englishWeeks(in: trimmed)
        meeting.parity = english == nil ? weeks.2 : 0
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
            firstWeek: english?.first ?? weeks.0, lastWeek: english?.last ?? weeks.1,
            customWeeks: english?.custom ?? [],
            meetings: [], issues: issues, sourceLine: trimmed)
        return (course, meeting)
    }
}
