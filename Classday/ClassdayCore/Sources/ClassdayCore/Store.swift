import Foundation

public struct StoreValidationReport: Equatable, Sendable {
    public var errors: [String]
    public var warnings: [String]

    public init(errors: [String], warnings: [String]) {
        self.errors = errors
        self.warnings = warnings
    }

    public var isAcceptable: Bool { errors.isEmpty }
}

public struct ImportOutcome: Equatable, Sendable {
    public var document: StoreDocument?
    public var errors: [String]
    public var warnings: [String]

    public init(document: StoreDocument?, errors: [String], warnings: [String]) {
        self.document = document
        self.errors = errors
        self.warnings = warnings
    }
}

public enum StoreFileError: Error, Equatable {
    case invalid([String])
}

public enum StoreEditing {
    public static func cleared(_ document: StoreDocument) -> StoreDocument {
        var copy = document
        copy.courses = []
        copy.origin = .user
        return copy
    }

    public static func restoredDemo() -> StoreDocument {
        DemoData.makeDocument()
    }
}

public enum StoreCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func encode(_ document: StoreDocument) throws -> Data {
        try encoder().encode(normalized(document))
    }

    public static func normalized(_ document: StoreDocument) -> StoreDocument {
        var semester = document.semester
        semester.name = document.semester.name.trimmingCharacters(in: .whitespacesAndNewlines)
        semester.shortName = document.semester.shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        semester.periods = document.semester.periods
            .sorted { $0.index < $1.index }
            .map { period in
                var copy = period
                if let start = ClockTime.parse(period.start) { copy.start = start.hhmm }
                if let end = ClockTime.parse(period.end) { copy.end = end.hhmm }
                return copy
            }
        let courses = document.courses.map { course in
            Course(
                id: course.id,
                name: course.name.trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: course.teacher.trimmingCharacters(in: .whitespacesAndNewlines),
                location: course.location.trimmingCharacters(in: .whitespacesAndNewlines),
                department: course.department.trimmingCharacters(in: .whitespacesAndNewlines),
                note: course.note.trimmingCharacters(in: .whitespacesAndNewlines),
                colorID: course.colorID.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: course.kind.trimmingCharacters(in: .whitespacesAndNewlines),
                weeks: course.weeks,
                meetings: course.meetings.sorted {
                    if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
                    if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
                    return $0.id.uuidString < $1.id.uuidString
                },
                reminderLeadMinutes: course.reminderLeadMinutes,
                credits: course.credits,
                grade: course.grade,
                gradeScheme: course.gradeScheme
            )
        }
        return StoreDocument(
            schemaVersion: document.schemaVersion,
            origin: document.origin,
            semester: semester,
            courses: courses,
            weekRules: document.weekRules,
            overrides: document.overrides,
            exams: document.exams,
            homework: document.homework,
            personalEvents: document.personalEvents,
            rooms: document.rooms,
            library: document.library,
            activeTimetableID: document.activeTimetableID,
            appearance: document.appearance,
            subscribedICSURL: document.subscribedICSURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public static func validate(_ document: StoreDocument, calendar: Calendar = ClassdayCalendar.make(timeZone: TimeZone(secondsFromGMT: 0))) -> StoreValidationReport {
        var errors: [String] = []
        var warnings: [String] = []
        if document.schemaVersion != StoreDocument.currentSchema {
            errors.append("schemaVersion 必须为 1")
        }
        let semester = document.semester
        if semester.name.isEmpty { errors.append("学期名称不能为空") }
        if semester.shortName.isEmpty { errors.append("学期简称不能为空") }
        if SemesterCalendar.parseCivil(semester.startDate, calendar: calendar) == nil {
            errors.append("学期开始日期无效")
        }
        if !(1...30).contains(semester.totalWeeks) {
            errors.append("学期周数必须在 1 到 30 之间")
        }
        for holiday in semester.holidays {
            if SemesterCalendar.parseCivil(holiday.startDate, calendar: calendar) == nil
                || SemesterCalendar.parseCivil(holiday.endDate, calendar: calendar) == nil
                || holiday.startDate > holiday.endDate {
                errors.append("假期日期不正确")
            }
        }
        if !(0...180).contains(semester.defaultReminderMinutes) {
            errors.append("默认提醒分钟数必须在 0 到 180 之间")
        }
        if semester.periods.isEmpty {
            errors.append("至少需要 1 个节次")
        } else {
            let indexes = semester.periods.map(\.index).sorted()
            if indexes != Array(1...indexes.count) {
                errors.append("节次序号必须从 1 连续编号")
            }
            for period in semester.periods.sorted(by: { $0.index < $1.index }) {
                guard let start = ClockTime.parse(period.start), let end = ClockTime.parse(period.end) else {
                    errors.append("节次 \(period.index) 的时间无效")
                    continue
                }
                if end <= start {
                    errors.append("第 \(period.index) 节结束时间必须晚于开始时间")
                }
            }
            let parsed: [(PeriodTemplate, ClockTime, ClockTime)] = semester.periods.compactMap { period in
                guard let start = ClockTime.parse(period.start), let end = ClockTime.parse(period.end), end > start else {
                    return nil
                }
                return (period, start, end)
            }.sorted { $0.0.index < $1.0.index }
            if parsed.count >= 2 {
                for index in 0..<(parsed.count - 1) {
                    for other in (index + 1)..<parsed.count {
                        let left = parsed[index]
                        let right = parsed[other]
                        if left.1 < right.2 && right.1 < left.2 {
                            warnings.append("第 \(left.0.index) 节与第 \(right.0.index) 节的时钟时间重叠")
                        }
                    }
                }
            }
        }

        var courseIDs = Set<UUID>()
        var meetingIDs = Set<UUID>()
        let periodIndexes = Set(semester.periods.map(\.index))
        for (offset, course) in document.courses.enumerated() {
            if course.name.isEmpty {
                errors.append("第 \(offset + 1) 门课程的名称不能为空")
            }
            if !courseIDs.insert(course.id).inserted {
                errors.append("课程 ID 重复")
            }
            if course.meetings.isEmpty {
                errors.append("课程「\(displayName(course, offset: offset))」至少要有一个上课时间")
            }
            if course.weeks.isEmpty {
                errors.append("课程「\(displayName(course, offset: offset))」至少要有一周")
            }
            if course.weeks.contains(where: { $0 < 1 || $0 > semester.totalWeeks }) {
                errors.append("课程「\(displayName(course, offset: offset))」的周次超出学期范围")
            }
            if let lead = course.reminderLeadMinutes, !(0...180).contains(lead) {
                errors.append("课程「\(displayName(course, offset: offset))」的提醒分钟数无效")
            }
            for meeting in course.meetings {
                if !meetingIDs.insert(meeting.id).inserted {
                    errors.append("上课时间 ID 重复")
                }
                if !(1...7).contains(meeting.weekday) {
                    errors.append("课程「\(displayName(course, offset: offset))」的星期无效")
                }
                if meeting.startPeriod > meeting.endPeriod {
                    errors.append("课程「\(displayName(course, offset: offset))」的开始节次不能晚于结束节次")
                }
                if !periodIndexes.contains(meeting.startPeriod) || !periodIndexes.contains(meeting.endPeriod) {
                    errors.append("课程「\(displayName(course, offset: offset))」的节次超出范围")
                }
            }
        }

        for conflict in ScheduleEngine.conflicts(among: document.courses) {
            warnings.append(ScheduleCopy.conflictMessage(conflict))
        }
        return StoreValidationReport(errors: errors, warnings: warnings)
    }

    public static func importing(_ data: Data, calendar: Calendar = ClassdayCalendar.make(timeZone: TimeZone(secondsFromGMT: 0))) -> ImportOutcome {
        let decoded: StoreDocument
        do {
            decoded = try JSONDecoder().decode(StoreDocument.self, from: data)
        } catch {
            return ImportOutcome(document: nil, errors: ["无法解析 JSON"], warnings: [])
        }
        let document = normalized(decoded)
        let report = validate(document, calendar: calendar)
        if !report.errors.isEmpty {
            return ImportOutcome(document: nil, errors: report.errors, warnings: report.warnings)
        }
        return ImportOutcome(document: document, errors: [], warnings: report.warnings)
    }

    private static func displayName(_ course: Course, offset: Int) -> String {
        course.name.isEmpty ? "第 \(offset + 1) 门" : course.name
    }
}

public enum StoreFile {
    public static func load(from url: URL) throws -> StoreDocument {
        let data = try Data(contentsOf: url)
        let outcome = StoreCodec.importing(data)
        guard let document = outcome.document, outcome.errors.isEmpty else {
            throw StoreFileError.invalid(outcome.errors)
        }
        return document
    }

    public static func save(_ document: StoreDocument, to url: URL) throws {
        let normalized = StoreCodec.normalized(document)
        let report = StoreCodec.validate(normalized)
        guard report.errors.isEmpty else {
            throw StoreFileError.invalid(report.errors)
        }
        let data = try StoreCodec.encode(normalized)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
