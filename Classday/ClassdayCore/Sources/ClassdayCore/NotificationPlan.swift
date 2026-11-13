import Foundation

public struct PlannedReminder: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var courseID: UUID?
    public var meetingID: UUID?
    public var kind: Kind

    public enum Kind: Int, Sendable {
        case exam, homework, course
    }

    public init(id: String, fireDate: Date, title: String, body: String, courseID: UUID? = nil, meetingID: UUID? = nil, kind: Kind = .course) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.courseID = courseID
        self.meetingID = meetingID
        self.kind = kind
    }
}

public enum NotificationPlan {
    /// iOS allows 64 pending local notifications. Leave a small margin.
    public static let pendingLimit = 60

    public static func make(
        document: StoreDocument,
        now: Date,
        calendar: Calendar,
        limit: Int = pendingLimit
    ) -> [PlannedReminder] {
        guard limit > 0 else { return [] }
        var planned = extraReminders(document: document, now: now, calendar: calendar)
        guard let startMonday = SemesterCalendar.semesterMonday(document.semester, calendar: calendar) else {
            return capped(planned, limit: limit)
        }
        let startWeek: Int
        if now < startMonday {
            startWeek = 1
        } else if let week = SemesterCalendar.weekIndex(for: now, semester: document.semester, calendar: calendar) {
            startWeek = week
        } else {
            return capped(planned, limit: limit)
        }

        for week in startWeek...document.semester.totalWeeks {
            let items = ScheduleEngine.occurrences(
                inWeek: week,
                courses: document.courses,
                semester: document.semester,
                calendar: calendar,
                context: document.scheduleContext
            ).sorted { $0.start < $1.start }
            for item in items {
                let lead = item.reminderLeadMinutes ?? document.semester.defaultReminderMinutes
                guard lead > 0, item.start > now else { continue }
                guard let fire = calendar.date(byAdding: .minute, value: -lead, to: item.start), fire > now else {
                    continue
                }
                planned.append(
                    PlannedReminder(
                        id: identifier(for: item, calendar: calendar),
                        fireDate: fire,
                        title: "即将上课 · \(item.name)",
                        body: "\(lead) 分钟后 · \(item.location) · \(ScheduleCopy.periodSpan(item.startPeriod, item.endPeriod))",
                        courseID: item.courseID,
                        meetingID: item.meetingID
                    )
                )
            }
        }
        return capped(planned, limit: limit)
    }

    /// Returns planned reminders when the store loaded cleanly, or an empty
    /// plan when a load error caused the app to fall back to demo data.
    public static func makeForStoredLoad(
        document: StoreDocument,
        loadError: String?,
        now: Date,
        calendar: Calendar,
        limit: Int = pendingLimit
    ) -> [PlannedReminder] {
        guard loadError == nil else { return [] }
        return make(document: document, now: now, calendar: calendar, limit: limit)
    }

    private static func capped(_ reminders: [PlannedReminder], limit: Int) -> [PlannedReminder] {
        Array(reminders.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.id < $1.id
        }.prefix(min(limit, pendingLimit)))
    }

    private static func extraReminders(document: StoreDocument, now: Date, calendar: Calendar) -> [PlannedReminder] {
        let lead = document.semester.defaultReminderMinutes
        guard lead > 0 else { return [] }
        func fire(_ stamp: String) -> Date? {
            guard let date = CivilStamp.date(from: stamp, calendar: calendar), date > now,
                  let fireDate = calendar.date(byAdding: .minute, value: -lead, to: date), fireDate > now else { return nil }
            return fireDate
        }
        var reminders: [PlannedReminder] = []
        for exam in document.exams {
            guard let date = fire(exam.startISO) else { continue }
            reminders.append(PlannedReminder(id: "classday-exam-\(exam.id.uuidString)", fireDate: date,
                title: "即将考试 · \(exam.courseName)", body: "\(lead) 分钟后 · \(exam.location)", kind: .exam))
        }
        for task in document.homework where !task.done {
            guard let date = fire(task.dueISO) else { continue }
            reminders.append(PlannedReminder(id: "classday-homework-\(task.id.uuidString)", fireDate: date,
                title: "作业即将截止 · \(task.title)", body: "\(lead) 分钟后截止 · \(task.courseName)", kind: .homework))
        }
        return reminders
    }

    public static func identifier(for occurrence: Occurrence, calendar: Calendar) -> String {
        let stamp = SemesterCalendar.formatCivil(occurrence.start, calendar: calendar)
        let hour = calendar.component(.hour, from: occurrence.start)
        let minute = calendar.component(.minute, from: occurrence.start)
        return String(
            format: "classday-%@-%@-%@-%02d%02d",
            occurrence.courseID.uuidString,
            occurrence.meetingID.uuidString,
            stamp,
            hour,
            minute
        )
    }
}
