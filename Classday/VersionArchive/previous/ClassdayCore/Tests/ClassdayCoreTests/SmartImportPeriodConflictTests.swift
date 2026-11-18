import XCTest
@testable import ClassdayCore

final class SmartImportPeriodConflictTests: XCTestCase {
    private let periods = [
        PeriodTemplate(index: 3, start: "09:00", end: "09:30"),
        PeriodTemplate(index: 4, start: "09:30", end: "10:00"),
        PeriodTemplate(index: 5, start: "10:00", end: "10:30")
    ]

    func testExplicitPeriodIsAuthoritativeButMustAgreeWithCompleteClock() {
        let exact = ImportedMeetingDraft(weekday: 1, startMinutes: 570, endMinutes: 630,
                                         startPeriod: 4, endPeriod: 5)
        XCTAssertEqual(exact.validatedSemesterPeriodSpan(in: periods)?.0, 4)
        XCTAssertEqual(exact.validatedSemesterPeriodSpan(in: periods)?.1, 5)

        let halfClock = ImportedMeetingDraft(weekday: 1, startMinutes: 570,
                                             startPeriod: 4, endPeriod: 5)
        XCTAssertEqual(halfClock.validatedSemesterPeriodSpan(in: periods)?.0, 4)

        // Half a clock range cannot contradict a stated period; it is simply ignored.
        let halfConflict = ImportedMeetingDraft(weekday: 1, startMinutes: 540,
                                                startPeriod: 4, endPeriod: 5)
        XCTAssertEqual(halfConflict.validatedSemesterPeriodSpan(in: periods)?.0, 4)
        XCTAssertEqual(halfConflict.validatedSemesterPeriodSpan(in: periods)?.1, 5)

        // The end half is equally weak: it cannot contradict the stated period either.
        let halfEndConflict = ImportedMeetingDraft(weekday: 1, endMinutes: 540,
                                                   startPeriod: 4, endPeriod: 5)
        XCTAssertEqual(halfEndConflict.validatedSemesterPeriodSpan(in: periods)?.0, 4)
        XCTAssertEqual(halfEndConflict.validatedSemesterPeriodSpan(in: periods)?.1, 5)

        let conflictingStart = ImportedMeetingDraft(weekday: 1, startMinutes: 540, endMinutes: 630,
                                                    startPeriod: 4, endPeriod: 5)
        XCTAssertNil(conflictingStart.validatedSemesterPeriodSpan(in: periods))

        let conflictingEnd = ImportedMeetingDraft(weekday: 1, startMinutes: 570, endMinutes: 600,
                                                  startPeriod: 4, endPeriod: 5)
        XCTAssertNil(conflictingEnd.validatedSemesterPeriodSpan(in: periods))

        let outOfRange = ImportedMeetingDraft(weekday: 1, startPeriod: 8, endPeriod: 9)
        XCTAssertNil(outOfRange.validatedSemesterPeriodSpan(in: periods))

        // A period this semester does not have must not hide a complete, usable clock.
        let fallback = ImportedMeetingDraft(weekday: 1, startMinutes: 540, endMinutes: 630,
                                            startPeriod: 8, endPeriod: 9)
        XCTAssertEqual(fallback.validatedSemesterPeriodSpan(in: periods)?.0, 3)
        XCTAssertEqual(fallback.validatedSemesterPeriodSpan(in: periods)?.1, 5)

        // Half a clock cannot stand in for a period this semester cannot represent.
        let halfOutOfRange = ImportedMeetingDraft(weekday: 1, startMinutes: 540,
                                                  startPeriod: 8, endPeriod: 9)
        XCTAssertNil(halfOutOfRange.validatedSemesterPeriodSpan(in: periods))
    }

    func testClockOnlyStillNeedsExactUniqueEndpoints() {
        let exact = ImportedMeetingDraft(weekday: 1, startMinutes: 540, endMinutes: 630)
        XCTAssertEqual(exact.validatedSemesterPeriodSpan(in: periods)?.0, 3)
        XCTAssertEqual(exact.validatedSemesterPeriodSpan(in: periods)?.1, 5)

        XCTAssertNil(ImportedMeetingDraft(weekday: 1, startMinutes: 540).validatedSemesterPeriodSpan(in: periods))
        XCTAssertNil(ImportedMeetingDraft(weekday: 1, startMinutes: 545, endMinutes: 630)
            .validatedSemesterPeriodSpan(in: periods))
    }

    func testFreeTextKeepsStatedPeriodWhenAClockIsAlsoPresent() {
        let onlyPeriod = ScheduleTextImporter.parseText("数学 周一 第4-5节").drafts.first?.meetings.first
        XCTAssertEqual(onlyPeriod?.startPeriod, 4)
        XCTAssertEqual(onlyPeriod?.endPeriod, 5)

        // The line states both; recognition must keep the period so confirmation can
        // compare it with the clock instead of dropping one side.
        let agreeing = ScheduleTextImporter.parseText("数学 周一 第4-5节 09:30-10:30").drafts.first?.meetings.first
        XCTAssertEqual(agreeing?.startMinutes, 570)
        XCTAssertEqual(agreeing?.endMinutes, 630)
        XCTAssertEqual(agreeing?.validatedSemesterPeriodSpan(in: periods)?.0, 4)
        XCTAssertEqual(agreeing?.validatedSemesterPeriodSpan(in: periods)?.1, 5)

        let conflicting = ScheduleTextImporter.parseText("数学 周一 第4-5节 09:00-10:00").drafts.first?.meetings.first
        XCTAssertNotNil(conflicting?.startPeriod)
        XCTAssertNil(conflicting?.validatedSemesterPeriodSpan(in: periods))
    }

    func testCsvKeepsExplicitPeriodWhenTheClockIsOnlyHalfKnown() {
        let half = ScheduleTextImporter.parseRows([
            ["课程名称", "星期", "节次", "开始时间"],
            ["数学", "周一", "4-5", "09:30"]
        ])
        let meeting = half?.drafts.first?.meetings.first
        XCTAssertEqual(meeting?.startPeriod, 4)
        XCTAssertEqual(meeting?.endPeriod, 5)
        XCTAssertNil(meeting?.startMinutes)
        XCTAssertEqual(meeting?.validatedSemesterPeriodSpan(in: periods)?.0, 4)

        let full = ScheduleTextImporter.parseRows([
            ["课程名称", "星期", "节次", "开始时间", "结束时间"],
            ["数学", "周一", "4-5", "09:30", "10:30"]
        ])
        let agreeing = full?.drafts.first?.meetings.first
        XCTAssertEqual(agreeing?.startMinutes, 570)
        XCTAssertEqual(agreeing?.endMinutes, 630)
        XCTAssertEqual(agreeing?.validatedSemesterPeriodSpan(in: periods)?.1, 5)

        let conflicting = ScheduleTextImporter.parseRows([
            ["课程名称", "星期", "节次", "开始时间", "结束时间"],
            ["数学", "周一", "4-5", "09:00", "10:00"]
        ])
        let rejected = conflicting?.drafts.first?.meetings.first
        XCTAssertNotNil(rejected?.startMinutes)
        XCTAssertNil(rejected?.validatedSemesterPeriodSpan(in: periods))
    }
}
