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
        // the next change, Monday 00:00, is 56h away — beyond the horizon.
        XCTAssertNil(
            NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 13, 16, 0, calendar: calendar), document: document, calendar: calendar))
        var empty = document
        empty.courses = []
        XCTAssertNil(NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), document: empty, calendar: calendar))
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
