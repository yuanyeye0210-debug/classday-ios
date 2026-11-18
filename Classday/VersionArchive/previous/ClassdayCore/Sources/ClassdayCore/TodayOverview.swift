import Foundation

/// Read-only state for the home screen. An unreadable store is never a demo schedule.
public struct TodayOverview: Equatable, Sendable {
    public var readable: Bool
    public var courses: [Occurrence]
    public var focus: Occurrence?
    public var completedCount: Int

    public var inProgress: Bool

    /// Automatic app-only focus. Never represents the system Focus switch.
    public var classroomCourse: Occurrence? { readable && inProgress ? focus : nil }

    public func displayedCourses(showAll: Bool, focusFilter: Bool = false) -> [Occurrence] {
        if focusFilter && !showAll { return readable ? focus.map { [$0] } ?? [] : [] }
        guard !showAll, let current = classroomCourse else { return courses }
        return [current]
    }

    public func showsExtras(eventCount: Int, homeworkCount: Int, hasUpcomingExam: Bool) -> Bool {
        readable && (eventCount > 0 || homeworkCount > 0 || hasUpcomingExam)
    }
}

public enum TodayProjection {
    public static func make(at now: Date, document: StoreDocument?, calendar: Calendar) -> TodayOverview {
        guard let document else {
            return TodayOverview(readable: false, courses: [], focus: nil, completedCount: 0, inProgress: false)
        }
        let courses = ScheduleEngine.occurrences(on: now, courses: document.courses, semester: document.semester,
            calendar: calendar, context: document.scheduleContext).sorted { $0.start < $1.start }
        let focus = courses.first { $0.end > now } ?? ScheduleEngine.nextOccurrence(after: now,
            courses: document.courses, semester: document.semester, calendar: calendar, context: document.scheduleContext)
        return TodayOverview(readable: true, courses: courses, focus: focus,
            completedCount: courses.filter { $0.end <= now }.count,
            inProgress: focus.map { $0.start <= now && now < $0.end } ?? false)
    }
}
