import Foundation

public struct PlannedReminder: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var courseID: UUID
    public var meetingID: UUID

    public init(id: String, fireDate: Date, title: String, body: String, courseID: UUID, meetingID: UUID) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.courseID = courseID
        self.meetingID = meetingID
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
        guard let startMonday = SemesterCalendar.semesterMonday(document.semester, calendar: calendar) else {
            return []
        }
        let startWeek: Int
        if now < startMonday {
            startWeek = 1
        } else if let week = SemesterCalendar.weekIndex(for: now, semester: document.semester, calendar: calendar) {
            startWeek = week
        } else {
            return []
        }

        var planned: [PlannedReminder] = []
        for week in startWeek...document.semester.totalWeeks {
            let items = ScheduleEngine.occurrences(
                inWeek: week,
                courses: document.courses,
                semester: document.semester,
                calendar: calendar
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
                if planned.count == limit { return planned }
            }
        }
        return planned
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
