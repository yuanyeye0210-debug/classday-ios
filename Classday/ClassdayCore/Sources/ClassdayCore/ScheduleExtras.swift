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
