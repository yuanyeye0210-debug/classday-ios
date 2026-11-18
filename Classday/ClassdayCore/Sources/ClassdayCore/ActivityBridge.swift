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

    /// Returns the Live Activity snapshot when the store loaded cleanly, or
    /// `nil` when a load error caused the app to fall back to demo data.
    public static func makeForStoredLoad(
        document: StoreDocument,
        loadError: String?,
        now: Date = Date(),
        calendar: Calendar = ClassdayCalendar.make()
    ) -> Value? {
        guard loadError == nil else { return nil }
        return make(document: document, now: now, calendar: calendar)
    }

    /// The next time the snapshot value produced by `make` can change:
    /// the end of the class in progress, the start of the next class, or
    /// the midnight at which the snapshot first appears for a new day
    /// (`make` returns nil when the next class is not today, so the
    /// snapshot flips nil -> "下一节" at midnight), whichever comes first.
    /// Only times strictly after `date` and within `horizon` count; `nil`
    /// when there is none (e.g. no more classes). The default horizon is
    /// 7 days, Apple's recommended maximum for `earliestBeginDate`, so a
    /// Friday evening can already see Monday 00:00 (56h away) and the
    /// background-refresh chain survives the weekend.
    public static func nextBoundary(after date: Date, document: StoreDocument, calendar: Calendar, horizon: TimeInterval = 7 * 24 * 60 * 60) -> Date? {
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
        // that day. Scan forward midnight by midnight (at most 7 within
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

    /// Heartbeat for the background-refresh chain: the next fixed midnight
    /// after `date`. Used when `nextBoundary` finds nothing within the
    /// horizon (e.g. a holiday with no classes for 7+ days): scheduling
    /// at the next midnight keeps the chain alive, and the task callback
    /// re-runs sync + schedule, so the chain re-evaluates daily until a
    /// real boundary appears. Pure date math — the `BGTaskScheduler`
    /// submission stays in the app layer.
    public static func nextHeartbeat(after date: Date, calendar: Calendar) -> Date? {
        return calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
    }

    /// Pre-class wake (scheme B): when the next snapshot change is a
    /// midnight flip and the flipped day's first class starts 8 hours or
    /// more after that midnight, wake 60 minutes before the first class
    /// instead of at midnight — an Activity created at midnight would
    /// expire exactly as the first class starts (8-hour lifetime), so
    /// the wake moves to 07:00 for a Monday 08:00 first class. Otherwise
    /// returns the next boundary unchanged (in-day boundaries are
    /// unaffected); nil when there is no boundary within the horizon
    /// (the caller falls back to the heartbeat). "8 hours or more" is
    /// inclusive on purpose: the canonical Monday 08:00 first class is
    /// exactly 8 hours after midnight, and the design doc requires it
    /// to wake at 07:00. Pure date math — the `BGTaskScheduler`
    /// submission stays in the app layer.
    public static func nextWakeDate(after date: Date, document: StoreDocument, calendar: Calendar) -> Date? {
        guard let boundary = nextBoundary(after: date, document: document, calendar: calendar) else { return nil }
        // Only a midnight flip qualifies: in-day boundaries (a class
        // ending or starting) are returned unchanged. No class starts
        // at exactly midnight, so a boundary equal to the start of its
        // day is a flip.
        guard boundary == calendar.startOfDay(for: boundary) else { return boundary }
        guard let flipped = make(document: document, now: boundary, calendar: calendar) else { return boundary }
        let firstClassStart = flipped.startsAt
        guard firstClassStart.timeIntervalSince(boundary) >= 8 * 60 * 60 else { return boundary }
        return firstClassStart.addingTimeInterval(-60 * 60)
    }

    /// Long-day rebuild rule (scheme B): an Activity lives at most
    /// 8 hours, so when it is already 7 hours old and there are still
    /// classes to show, the caller should end it and request a fresh
    /// one (reopening an 8-hour window) instead of merely updating it.
    /// The 7-hour threshold leaves a 1-hour margin before the system
    /// ends the old Activity. "Still classes" is the current snapshot
    /// being non-nil — at a boundary sync that is the class in progress
    /// or the next class today; a nil snapshot ends all activities
    /// anyway. Unknown request time never rebuilds.
    public static func shouldRebuild(activityStartedAt: Date?, now: Date, snapshot: Value?) -> Bool {
        guard let activityStartedAt, snapshot != nil else { return false }
        return now.timeIntervalSince(activityStartedAt) >= 7 * 60 * 60
    }

    /// Diff gate for Live Activity updates: refresh only when the snapshot
    /// value actually changed (including appearing or disappearing).
    public static func shouldUpdate(previous: Value?, current: Value?) -> Bool {
        previous != current
    }
}
