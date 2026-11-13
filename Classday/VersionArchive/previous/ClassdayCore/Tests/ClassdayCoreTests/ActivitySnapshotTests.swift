import XCTest
import ClassdayCore

final class ActivitySnapshotTests: XCTestCase {
    private let calendar = TestSupport.calendar()
    private let document = DemoData.makeDocument()

    /// Two adjacent Monday classes, A 08:00–09:40 and B 09:40–11:20.
    /// DemoData's own period templates cannot produce a 09:40 start or an
    /// 11:20 end, so this fixture uses a custom Semester with the same
    /// start date and week count as DemoData.
    private var backToBack: StoreDocument {
        var doc = DemoData.makeDocument()
        doc.semester = Semester(
            name: doc.semester.name,
            shortName: doc.semester.shortName,
            startDate: doc.semester.startDate,
            totalWeeks: doc.semester.totalWeeks,
            periods: [
                PeriodTemplate(index: 1, start: "08:00", end: "08:45"),
                PeriodTemplate(index: 2, start: "08:55", end: "09:40"),
                PeriodTemplate(index: 3, start: "09:40", end: "10:25"),
                PeriodTemplate(index: 4, start: "10:35", end: "11:20"),
            ],
            defaultReminderMinutes: doc.semester.defaultReminderMinutes
        )
        doc.courses = [
            Course(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
                name: "A",
                teacher: "",
                location: "",
                colorID: "blue",
                weeks: Array(1...16),
                meetings: [
                    Meeting(
                        id: UUID(uuidString: "50000000-0000-0000-0000-000000000011")!,
                        weekday: 1, startPeriod: 1, endPeriod: 2)
                ]
            ),
            Course(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
                name: "B",
                teacher: "",
                location: "",
                colorID: "green",
                weeks: Array(1...16),
                meetings: [
                    Meeting(
                        id: UUID(uuidString: "50000000-0000-0000-0000-000000000012")!,
                        weekday: 1, startPeriod: 3, endPeriod: 4)
                ]
            ),
        ]
        return doc
    }

    /// A document whose Monday first (and only) class starts at 07:00:
    /// 7 hours after the midnight flip, inside the 8-hour Activity
    /// lifetime — the pre-class wake rule must not move it.
    /// Same construction pattern as `backToBack` (custom Semester with
    /// DemoData's start date and week count).
    private var earlyFirstClass: StoreDocument {
        var doc = DemoData.makeDocument()
        doc.semester = Semester(
            name: doc.semester.name,
            shortName: doc.semester.shortName,
            startDate: doc.semester.startDate,
            totalWeeks: doc.semester.totalWeeks,
            periods: [
                PeriodTemplate(index: 1, start: "07:00", end: "07:45"),
            ],
            defaultReminderMinutes: doc.semester.defaultReminderMinutes
        )
        doc.courses = [
            Course(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000003")!,
                name: "早课",
                teacher: "",
                location: "",
                colorID: "blue",
                weeks: Array(1...16),
                meetings: [
                    Meeting(
                        id: UUID(uuidString: "50000000-0000-0000-0000-000000000013")!,
                        weekday: 1, startPeriod: 1, endPeriod: 1)
                ]
            ),
        ]
        return doc
    }

    func testSnapshotFlipsToNextClassAfterOneEnds() {
        let at0950 = TestSupport.date(2026, 11, 9, 9, 50, calendar: calendar)
        let snapshot = NextClassSnapshot.make(document: document, now: at0950, calendar: calendar)
        XCTAssertEqual(snapshot?.title, "大学英语")
        XCTAssertEqual(snapshot?.phase, "下一节")
        XCTAssertEqual(snapshot?.startsAt, TestSupport.date(2026, 11, 9, 10, 10, calendar: calendar))
        XCTAssertEqual(snapshot?.endsAt, TestSupport.date(2026, 11, 9, 10, 10, calendar: calendar))
    }

    func testSnapshotDuringClassIsInProgress() {
        let at0830 = TestSupport.date(2026, 11, 9, 8, 30, calendar: calendar)
        let snapshot = NextClassSnapshot.make(document: document, now: at0830, calendar: calendar)
        XCTAssertEqual(snapshot?.title, "高等数学")
        XCTAssertEqual(snapshot?.phase, "上课中")
        XCTAssertEqual(snapshot?.endsAt, TestSupport.date(2026, 11, 9, 9, 40, calendar: calendar))
    }

    func testSnapshotIsNilAfterLastClassOfDay() {
        let at1600 = TestSupport.date(2026, 11, 9, 16, 0, calendar: calendar)
        XCTAssertNil(NextClassSnapshot.make(document: document, now: at1600, calendar: calendar))
    }

    func testNextBoundary() {
        XCTAssertEqual(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 9, 8, 0, calendar: calendar))
        XCTAssertEqual(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 8, 30, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 9, 9, 40, calendar: calendar))
        XCTAssertEqual(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 9, 50, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 9, 10, 10, calendar: calendar))
        XCTAssertEqual(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 12, 0, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 9, 14, 0, calendar: calendar))
    }

    func testNextBoundaryOnRestDayAndHorizon() {
        // Sunday 12:00: the snapshot is nil, and it first appears at the
        // midnight that starts Monday (Mon 00:00, 12h away), not at the
        // first class (Mon 08:00).
        XCTAssertEqual(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 8, 12, 0, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 9, 0, 0, calendar: calendar))
        // Saturday 12:00: Sunday's midnight changes nothing (still nil),
        // but Monday 00:00 is exactly 36h away, so the inclusive horizon
        // (`<= horizon`) keeps it.
        XCTAssertEqual(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 14, 12, 0, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 16, 0, 0, calendar: calendar))
        // Friday 16:00: the last class (程序设计 14:00–15:40) has ended and
        // the next change, Monday 00:00, is 56h away — beyond the old 36h
        // horizon, but inside the 7-day horizon, so it is now returned
        // and the background-refresh chain survives the weekend.
        XCTAssertEqual(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 13, 16, 0, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 16, 0, 0, calendar: calendar))
        var empty = document
        empty.courses = []
        XCTAssertNil(NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), document: empty, calendar: calendar))
    }

    func testNextBoundaryFridayEveningReachesMondayMidnight() {
        // Friday 16:00: the last class (程序设计 14:00–15:40) has ended;
        // the next snapshot change, Monday 00:00, is 56h away — inside
        // the 7-day horizon, so the background-refresh chain survives
        // the weekend instead of dying on Friday.
        XCTAssertEqual(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 13, 16, 0, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 16, 0, 0, calendar: calendar))
    }

    func testHeartbeatFallsOnNextMidnightDuringLongHoliday() {
        // A document with no classes at all (a holiday longer than the
        // 7-day horizon): no boundary exists, so the heartbeat must land
        // on the next midnight — never now, never days away.
        var empty = document
        empty.courses = []
        XCTAssertNil(NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), document: empty, calendar: calendar))
        XCTAssertEqual(
            NextClassSnapshot.nextHeartbeat(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), calendar: calendar),
            TestSupport.date(2026, 11, 10, 0, 0, calendar: calendar))
        XCTAssertEqual(
            NextClassSnapshot.nextHeartbeat(after: TestSupport.date(2026, 11, 13, 16, 0, calendar: calendar), calendar: calendar),
            TestSupport.date(2026, 11, 14, 0, 0, calendar: calendar))
    }

    func testHeartbeatChainAdvancesWithoutLooping() {
        // Simulate the heartbeat chain over a class-free stretch: each
        // midnight the task re-runs sync + schedule, finds no boundary,
        // and re-queues the next midnight. Every heartbeat must be
        // strictly later than the previous one — the chain advances one
        // day at a time and never re-schedules the same instant.
        var empty = document
        empty.courses = []
        var now = TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar)
        var previousHeartbeat: Date?
        for day in 10...17 {
            XCTAssertNil(NextClassSnapshot.nextBoundary(after: now, document: empty, calendar: calendar))
            guard let heartbeat = NextClassSnapshot.nextHeartbeat(after: now, calendar: calendar) else {
                XCTFail("heartbeat must exist when there is no boundary")
                return
            }
            XCTAssertEqual(heartbeat, TestSupport.date(2026, 11, day, 0, 0, calendar: calendar))
            if let previousHeartbeat {
                XCTAssertGreaterThan(heartbeat, previousHeartbeat)
            }
            previousHeartbeat = heartbeat
            now = heartbeat
        }
    }

    func testNextWakeDateMovesToSixtyMinutesBeforeFirstClassAfterMidnightFlip() {
        // Friday 16:00: the next change is the Monday 00:00 flip, and
        // Monday's first class (高等数学 08:00) starts exactly 8 hours
        // after it — an Activity created at midnight would expire just
        // as the class starts, so the wake moves to 07:00, 60 minutes
        // before the first class.
        XCTAssertEqual(
            NextClassSnapshot.nextWakeDate(after: TestSupport.date(2026, 11, 13, 16, 0, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 16, 7, 0, calendar: calendar))
        // Sunday 12:00: same flip (Monday 00:00), same first class —
        // same 07:00 wake.
        XCTAssertEqual(
            NextClassSnapshot.nextWakeDate(after: TestSupport.date(2026, 11, 8, 12, 0, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 9, 7, 0, calendar: calendar))
    }

    func testNextWakeDateLeavesInDayBoundariesAlone() {
        // Monday 07:40: the next change is today's 08:00 class start,
        // not a midnight flip — the wake stays at the boundary itself.
        XCTAssertEqual(
            NextClassSnapshot.nextWakeDate(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 9, 8, 0, calendar: calendar))
        // Monday 12:00: the next change is the 14:00 class start —
        // likewise unchanged.
        XCTAssertEqual(
            NextClassSnapshot.nextWakeDate(after: TestSupport.date(2026, 11, 9, 12, 0, calendar: calendar), document: document, calendar: calendar),
            TestSupport.date(2026, 11, 9, 14, 0, calendar: calendar))
        // No boundary at all (empty timetable): nil, so the caller falls
        // back to the midnight heartbeat.
        var empty = document
        empty.courses = []
        XCTAssertNil(NextClassSnapshot.nextWakeDate(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), document: empty, calendar: calendar))
    }

    func testNextWakeDateKeepsMidnightWhenFirstClassIsWithinEightHours() {
        // Monday's only class starts 07:00 — 7 hours after the midnight
        // flip, inside the 8-hour Activity lifetime — so the wake stays
        // at midnight instead of moving to 06:00.
        XCTAssertEqual(
            NextClassSnapshot.nextWakeDate(after: TestSupport.date(2026, 11, 8, 12, 0, calendar: calendar), document: earlyFirstClass, calendar: calendar),
            TestSupport.date(2026, 11, 9, 0, 0, calendar: calendar))
    }

    func testShouldRebuildAfterSevenHoursWithClassesRemaining() {
        // Monday 14:00, 程序设计 in progress: the snapshot is non-nil.
        let snapshot = NextClassSnapshot.make(document: document, now: TestSupport.date(2026, 11, 9, 14, 0, calendar: calendar), calendar: calendar)
        XCTAssertNotNil(snapshot)
        // Activity requested at 07:00 for the 08:00 class: at 14:00 it
        // is exactly 7 hours old and classes remain — rebuild.
        XCTAssertTrue(NextClassSnapshot.shouldRebuild(
            activityStartedAt: TestSupport.date(2026, 11, 9, 7, 0, calendar: calendar),
            now: TestSupport.date(2026, 11, 9, 14, 0, calendar: calendar),
            snapshot: snapshot))
        // One minute earlier — 6h59m old — the rule must not fire.
        XCTAssertFalse(NextClassSnapshot.shouldRebuild(
            activityStartedAt: TestSupport.date(2026, 11, 9, 7, 0, calendar: calendar),
            now: TestSupport.date(2026, 11, 9, 13, 59, calendar: calendar),
            snapshot: snapshot))
        // No snapshot (no classes left): nothing to rebuild for.
        XCTAssertFalse(NextClassSnapshot.shouldRebuild(
            activityStartedAt: TestSupport.date(2026, 11, 9, 7, 0, calendar: calendar),
            now: TestSupport.date(2026, 11, 9, 14, 0, calendar: calendar),
            snapshot: nil))
        // Unknown request time: the age cannot be judged, never rebuild.
        XCTAssertFalse(NextClassSnapshot.shouldRebuild(
            activityStartedAt: nil,
            now: TestSupport.date(2026, 11, 9, 14, 0, calendar: calendar),
            snapshot: snapshot))
    }

    func testBackToBackClassesFlipAtBoundary() {
        // Build a minimal document following DemoData.makeDocument's construction:
        // Monday 2026-11-09, course A 08:00–09:40, course B 09:40–11:20 (same weekday, adjacent periods).
        let at0940 = TestSupport.date(2026, 11, 9, 9, 40, calendar: calendar)
        let snapshot = NextClassSnapshot.make(document: backToBack, now: at0940, calendar: calendar)
        XCTAssertEqual(snapshot?.title, "B")
        XCTAssertEqual(snapshot?.phase, "上课中")
    }

    func testShouldUpdateDiffGate() {
        let at0830 = TestSupport.date(2026, 11, 9, 8, 30, calendar: calendar)
        let value = NextClassSnapshot.make(document: document, now: at0830, calendar: calendar)
        XCTAssertTrue(NextClassSnapshot.shouldUpdate(previous: nil, current: value))
        XCTAssertFalse(NextClassSnapshot.shouldUpdate(previous: value, current: value))
        XCTAssertTrue(NextClassSnapshot.shouldUpdate(previous: value, current: nil))
        let at0959 = TestSupport.date(2026, 11, 9, 9, 59, calendar: calendar)
        let before = NextClassSnapshot.make(document: document, now: at0959, calendar: calendar)
        // 10:10, not 10:00: 大学英语 starts at 10:10, so the snapshots at
        // 09:59 and 10:00 are identical and the diff gate must stay closed.
        // At 10:10 the class is in progress and the phase flips to "上课中".
        let at1010 = TestSupport.date(2026, 11, 9, 10, 10, calendar: calendar)
        let during = NextClassSnapshot.make(document: document, now: at1010, calendar: calendar)
        XCTAssertTrue(NextClassSnapshot.shouldUpdate(previous: before, current: during))
    }
}
