import Foundation

public struct PlannedReminder: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var courseID: UUID
    public var meetingID: UUID
    public var opensCourse: Bool

    public init(id: String, fireDate: Date, title: String, body: String, courseID: UUID, meetingID: UUID, opensCourse: Bool = true) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.courseID = courseID
        self.meetingID = meetingID
        self.opensCourse = opensCourse
    }
}

public enum NotificationPlan {
    /// iOS allows 64 pending local notifications. Keep the nearest ones.
    public static let pendingLimit = 64

    public static func make(
        document: StoreDocument,
        now: Date,
        calendar: Calendar,
        limit: Int = pendingLimit
    ) -> [PlannedReminder] {
        guard limit > 0 else { return [] }
        let planned = classReminders(document: document, now: now, calendar: calendar)
            + examReminders(document: document, now: now, calendar: calendar)
            + homeworkReminders(document: document, now: now, calendar: calendar)
        return Array(planned.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.id < $1.id
        }.prefix(limit))
    }

    private static func classReminders(document: StoreDocument, now: Date, calendar: Calendar) -> [PlannedReminder] {
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
        return planned
    }

    private static func examReminders(document: StoreDocument, now: Date, calendar: Calendar) -> [PlannedReminder] {
        let lead = document.semester.defaultReminderMinutes
        guard lead > 0 else { return [] }
        return document.exams.compactMap { exam in
            guard let start = CivilStamp.date(from: exam.startISO, calendar: calendar), start > now else { return nil }
            guard let fire = calendar.date(byAdding: .minute, value: -lead, to: start), fire > now else { return nil }
            let place = exam.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = place.isEmpty ? "\(lead) 分钟后" : "\(lead) 分钟后 · \(place)"
            return PlannedReminder(
                id: "classday-exam-\(exam.id.uuidString)",
                fireDate: fire,
                title: "即将考试 · \(exam.courseName)",
                body: body,
                courseID: exam.id,
                meetingID: exam.id,
                opensCourse: false
            )
        }
    }

    private static func homeworkReminders(document: StoreDocument, now: Date, calendar: Calendar) -> [PlannedReminder] {
        let lead = document.semester.defaultReminderMinutes
        guard lead > 0 else { return [] }
        return document.homework.compactMap { task in
            guard !task.done else { return nil }
            guard let due = CivilStamp.date(from: task.dueISO, calendar: calendar), due > now else { return nil }
            guard let fire = calendar.date(byAdding: .minute, value: -lead, to: due), fire > now else { return nil }
            let course = task.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = course.isEmpty ? "\(lead) 分钟后截止" : "\(lead) 分钟后截止 · \(course)"
            return PlannedReminder(
                id: "classday-homework-\(task.id.uuidString)",
                fireDate: fire,
                title: "作业将截止 · \(task.title)",
                body: body,
                courseID: task.id,
                meetingID: task.id,
                opensCourse: false
            )
        }
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

#if canImport(UserNotifications)
import UserNotifications

public enum ReminderDelivery {
    /// Replaces pending `classday-` notifications with `reminders`. Does not ask for permission.
    public static func replacePending(_ reminders: [PlannedReminder], calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let owned = pending.map(\.identifier).filter { $0.hasPrefix("classday-") }
        center.removePendingNotificationRequests(withIdentifiers: owned)
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else {
            return
        }
        for reminder in reminders.prefix(NotificationPlan.pendingLimit) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            if reminder.opensCourse {
                content.userInfo = [
                    "courseID": reminder.courseID.uuidString,
                    "meetingID": reminder.meetingID.uuidString,
                ]
            }
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
#endif
