import Foundation

public struct Occurrence: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var courseID: UUID
    public var meetingID: UUID
    public var name: String
    public var teacher: String
    public var location: String
    public var locationShort: String
    public var department: String
    public var note: String
    public var colorID: String
    public var kind: String
    public var weekday: Int
    public var startPeriod: Int
    public var endPeriod: Int
    public var weekIndex: Int
    public var weeks: [Int]
    public var start: Date
    public var end: Date
    public var timeText: String
    public var reminderLeadMinutes: Int?

    public init(
        id: String,
        courseID: UUID,
        meetingID: UUID,
        name: String,
        teacher: String,
        location: String,
        locationShort: String,
        department: String,
        note: String,
        colorID: String,
        kind: String,
        weekday: Int,
        startPeriod: Int,
        endPeriod: Int,
        weekIndex: Int,
        weeks: [Int],
        start: Date,
        end: Date,
        timeText: String,
        reminderLeadMinutes: Int?
    ) {
        self.id = id
        self.courseID = courseID
        self.meetingID = meetingID
        self.name = name
        self.teacher = teacher
        self.location = location
        self.locationShort = locationShort
        self.department = department
        self.note = note
        self.colorID = colorID
        self.kind = kind
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.weekIndex = weekIndex
        self.weeks = weeks
        self.start = start
        self.end = end
        self.timeText = timeText
        self.reminderLeadMinutes = reminderLeadMinutes
    }
}

public struct MeetingConflict: Equatable, Hashable, Sendable {
    public var courseID: UUID
    public var meetingID: UUID
    public var courseName: String
    public var otherCourseID: UUID
    public var otherMeetingID: UUID
    public var otherCourseName: String
    public var weekday: Int
    public var startPeriod: Int
    public var endPeriod: Int
    public var weeks: [Int]

    public init(
        courseID: UUID,
        meetingID: UUID,
        courseName: String,
        otherCourseID: UUID,
        otherMeetingID: UUID,
        otherCourseName: String,
        weekday: Int,
        startPeriod: Int,
        endPeriod: Int,
        weeks: [Int]
    ) {
        self.courseID = courseID
        self.meetingID = meetingID
        self.courseName = courseName
        self.otherCourseID = otherCourseID
        self.otherMeetingID = otherMeetingID
        self.otherCourseName = otherCourseName
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.weeks = weeks
    }
}

public enum MoveValidation: Equatable, Sendable {
    case unchanged
    case ok([Course])
    case outOfBounds
    case missing
    case conflict([MeetingConflict])
}

public enum ScheduleEngine {
    public static func occurrences(
        inWeek week: Int,
        courses: [Course],
        semester: Semester,
        calendar: Calendar
    ) -> [Occurrence] {
        guard week >= 1, week <= semester.totalWeeks else { return [] }
        var built: [Occurrence] = []
        for course in courses where course.weeks.contains(week) {
            for meeting in course.meetings {
                guard let clocks = ScheduleCopy.clocks(for: meeting, semester: semester),
                      let start = SemesterCalendar.date(
                        week: week,
                        weekday: meeting.weekday,
                        time: clocks.start,
                        semester: semester,
                        calendar: calendar
                      ),
                      let end = SemesterCalendar.date(
                        week: week,
                        weekday: meeting.weekday,
                        time: clocks.end,
                        semester: semester,
                        calendar: calendar
                      ),
                      end > start else {
                    continue
                }
                built.append(
                    Occurrence(
                        id: "\(course.id.uuidString)-\(meeting.id.uuidString)-\(week)",
                        courseID: course.id,
                        meetingID: meeting.id,
                        name: course.name,
                        teacher: course.teacher,
                        location: course.location,
                        locationShort: LocationText.short(course.location),
                        department: course.department,
                        note: course.note,
                        colorID: course.colorID,
                        kind: course.kind,
                        weekday: meeting.weekday,
                        startPeriod: meeting.startPeriod,
                        endPeriod: meeting.endPeriod,
                        weekIndex: week,
                        weeks: course.weeks,
                        start: start,
                        end: end,
                        timeText: ScheduleCopy.timeRange(clocks.start, clocks.end),
                        reminderLeadMinutes: course.reminderLeadMinutes
                    )
                )
            }
        }
        return built.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
            return $0.name < $1.name
        }
    }

    public static func occurrences(
        on date: Date,
        courses: [Course],
        semester: Semester,
        calendar: Calendar
    ) -> [Occurrence] {
        guard let week = SemesterCalendar.weekIndex(for: date, semester: semester, calendar: calendar) else {
            return []
        }
        let weekday = SemesterCalendar.isoWeekday(date, calendar: calendar)
        return occurrences(inWeek: week, courses: courses, semester: semester, calendar: calendar)
            .filter { $0.weekday == weekday }
    }

    public static func currentOccurrence(
        at date: Date,
        courses: [Course],
        semester: Semester,
        calendar: Calendar
    ) -> Occurrence? {
        guard let week = SemesterCalendar.weekIndex(for: date, semester: semester, calendar: calendar) else {
            return nil
        }
        return occurrences(inWeek: week, courses: courses, semester: semester, calendar: calendar)
            .first { $0.start <= date && date < $0.end }
    }

    public static func nextOccurrence(
        after date: Date,
        courses: [Course],
        semester: Semester,
        calendar: Calendar
    ) -> Occurrence? {
        guard let startMonday = SemesterCalendar.semesterMonday(semester, calendar: calendar) else {
            return nil
        }
        let startWeek: Int
        if date < startMonday {
            startWeek = 1
        } else if let week = SemesterCalendar.weekIndex(for: date, semester: semester, calendar: calendar) {
            startWeek = week
        } else {
            return nil
        }
        for week in startWeek...semester.totalWeeks {
            if let found = occurrences(inWeek: week, courses: courses, semester: semester, calendar: calendar)
                .sorted(by: { $0.start < $1.start })
                .first(where: { $0.start > date }) {
                return found
            }
        }
        return nil
    }

    public static func conflicts(among courses: [Course]) -> [MeetingConflict] {
        struct Item {
            var course: Course
            var meeting: Meeting
        }
        let items = courses.flatMap { course in
            course.meetings.map { Item(course: course, meeting: $0) }
        }
        var result: [MeetingConflict] = []
        guard items.count >= 2 else { return [] }
        for index in 0..<(items.count - 1) {
            for other in (index + 1)..<items.count {
                let left = items[index]
                let right = items[other]
                guard left.meeting.weekday == right.meeting.weekday else { continue }
                guard rangesOverlap(
                    left.meeting.startPeriod, left.meeting.endPeriod,
                    right.meeting.startPeriod, right.meeting.endPeriod
                ) else { continue }
                let weeks = Array(Set(left.course.weeks).intersection(right.course.weeks)).sorted()
                guard !weeks.isEmpty else { continue }
                result.append(
                    MeetingConflict(
                        courseID: left.course.id,
                        meetingID: left.meeting.id,
                        courseName: left.course.name,
                        otherCourseID: right.course.id,
                        otherMeetingID: right.meeting.id,
                        otherCourseName: right.course.name,
                        weekday: left.meeting.weekday,
                        startPeriod: max(left.meeting.startPeriod, right.meeting.startPeriod),
                        endPeriod: min(left.meeting.endPeriod, right.meeting.endPeriod),
                        weeks: weeks
                    )
                )
            }
        }
        return result.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
            return $0.courseName < $1.courseName
        }
    }

    public static func validateMove(
        courseID: UUID,
        meetingID: UUID,
        weekday: Int,
        startPeriod: Int,
        courses: [Course],
        semester: Semester
    ) -> MoveValidation {
        guard let courseIndex = courses.firstIndex(where: { $0.id == courseID }) else {
            return .missing
        }
        let course = courses[courseIndex]
        guard let meeting = course.meetings.first(where: { $0.id == meetingID }) else {
            return .missing
        }
        let duration = meeting.endPeriod - meeting.startPeriod + 1
        guard duration >= 1 else { return .outOfBounds }
        let endPeriod = startPeriod + duration - 1
        let maxPeriod = semester.periods.map(\.index).max() ?? 0
        guard (1...7).contains(weekday), startPeriod >= 1, endPeriod <= maxPeriod else {
            return .outOfBounds
        }
        if weekday == meeting.weekday, startPeriod == meeting.startPeriod {
            return .unchanged
        }
        var moved = course
        moved.meetings = course.meetings.map { item in
            guard item.id == meetingID else { return item }
            return Meeting(id: item.id, weekday: weekday, startPeriod: startPeriod, endPeriod: endPeriod)
        }
        var updated = courses
        updated[courseIndex] = moved
        let involved = conflicts(among: updated).filter {
            $0.meetingID == meetingID || $0.otherMeetingID == meetingID
        }
        if involved.isEmpty {
            return .ok(updated)
        }
        return .conflict(involved)
    }

    public static func replacingMeeting(
        courses: [Course],
        courseID: UUID,
        meetingID: UUID,
        weekday: Int,
        startPeriod: Int,
        endPeriod: Int
    ) -> [Course]? {
        guard let courseIndex = courses.firstIndex(where: { $0.id == courseID }),
              courses[courseIndex].meetings.contains(where: { $0.id == meetingID }) else {
            return nil
        }
        var updated = courses
        var course = updated[courseIndex]
        course.meetings = course.meetings.map { item in
            guard item.id == meetingID else { return item }
            return Meeting(id: item.id, weekday: weekday, startPeriod: startPeriod, endPeriod: endPeriod)
        }
        updated[courseIndex] = course
        return updated
    }

    private static func rangesOverlap(_ start: Int, _ end: Int, _ otherStart: Int, _ otherEnd: Int) -> Bool {
        start <= otherEnd && otherStart <= end
    }
}
