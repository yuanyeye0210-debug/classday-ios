import Foundation

#if os(iOS)
import ActivityKit

public struct NextClassAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var location: String
        public var endsAt: Date
        public var phase: String

        public init(title: String, location: String, endsAt: Date, phase: String) {
            self.title = title
            self.location = location
            self.endsAt = endsAt
            self.phase = phase
        }
    }

    public var courseID: String

    public init(courseID: String) {
        self.courseID = courseID
    }
}
#endif

public enum NextClassSnapshot {
    public struct Value: Equatable, Sendable {
        public var courseID: String
        public var title: String
        public var location: String
        public var endsAt: Date
        public var phase: String
        public var startsAt: Date
    }

    public static func make(document: StoreDocument, now: Date = Date(), calendar: Calendar = ClassdayCalendar.make()) -> Value? {
        if let current = ScheduleEngine.currentOccurrence(
            at: now,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar,
            context: document.scheduleContext
        ) {
            return Value(
                courseID: current.courseID.uuidString,
                title: current.name,
                location: current.location,
                endsAt: current.end,
                phase: "上课中",
                startsAt: current.start
            )
        }
        guard let next = ScheduleEngine.nextOccurrence(
            after: now,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar,
            context: document.scheduleContext
        ) else { return nil }
        return Value(
            courseID: next.courseID.uuidString,
            title: next.name,
            location: next.location,
            endsAt: next.start,
            phase: "下一节",
            startsAt: next.start
        )
    }
}
