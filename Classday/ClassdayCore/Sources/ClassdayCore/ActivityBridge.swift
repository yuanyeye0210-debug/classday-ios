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
        // Rest-day guard: the Live Activity is a countdown the user watches
        // all day, so only today's remaining classes qualify. Counting down
        // to a class tomorrow (or later) keeps the Dynamic Island lit for
        // 24h+ and reads as a stuck timer on a day off.
        guard calendar.isDate(next.start, inSameDayAs: now) else { return nil }
        return Value(
            courseID: next.courseID.uuidString,
            title: next.name,
            location: next.location,
            endsAt: next.start,
            phase: "下一节",
            startsAt: next.start
        )
    }

    /// The next time the snapshot value produced by `make` can change:
    /// the end of the class in progress, the start of the next class, or
    /// the midnight at which the snapshot first appears for a new day
    /// (`make` returns nil when the next class is not today, so the
    /// snapshot flips nil -> "下一节" at midnight), whichever comes first.
    /// Only times strictly after `date` and within `horizon` count; `nil`
    /// when there is none (e.g. no more classes).
    public static func nextBoundary(after date: Date, document: StoreDocument, calendar: Calendar, horizon: TimeInterval = 36 * 60 * 60) -> Date? {
        var candidates = [
            ScheduleEngine.currentOccurrence(
                at: date,
                courses: document.courses,
                semester: document.semester,
                calendar: calendar,
                context: document.scheduleContext
            )?.end,
            ScheduleEngine.nextOccurrence(
                after: date,
                courses: document.courses,
                semester: document.semester,
                calendar: calendar,
                context: document.scheduleContext
            )?.start,
        ].compactMap { $0 }
        // Midnight flip: `make` is nil while the next class is on a later
        // day, so the snapshot can first appear at the midnight that starts
        // that day. Scan forward midnight by midnight (at most ~2 within
        // the horizon); the first midnight where `make` differs is a
        // candidate, since a later midnight cannot be earlier.
        let currentValue = make(document: document, now: date, calendar: calendar)
        var midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        while let dayStart = midnight, dayStart.timeIntervalSince(date) <= horizon {
            if make(document: document, now: dayStart, calendar: calendar) != currentValue {
                candidates.append(dayStart)
                break
            }
            midnight = calendar.date(byAdding: .day, value: 1, to: dayStart)
        }
        return candidates
            .filter { $0 > date && $0.timeIntervalSince(date) <= horizon }
            .min()
    }

    /// Diff gate for Live Activity updates: refresh only when the snapshot
    /// value actually changed (including appearing or disappearing).
    public static func shouldUpdate(previous: Value?, current: Value?) -> Bool {
        previous != current
    }
}
