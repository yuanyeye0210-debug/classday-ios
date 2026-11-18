import XCTest
import ClassdayCore

final class ScheduleTests: XCTestCase {
    private let calendar = TestSupport.calendar()
    private let document = DemoData.makeDocument()

    func testWeekIndexMatchesAutumn2026Mock() {
        let monday = TestSupport.date(2026, 11, 2, 9, 0, calendar: calendar)
        let sunday = TestSupport.date(2026, 11, 8, 12, 0, calendar: calendar)
        let mondayW11 = TestSupport.date(2026, 11, 9, 8, 0, calendar: calendar)
        let sundayW11 = TestSupport.date(2026, 11, 15, 21, 0, calendar: calendar)
        let opening = TestSupport.date(2026, 8, 31, 8, 0, calendar: calendar)
        XCTAssertEqual(SemesterCalendar.weekIndex(for: monday, semester: document.semester, calendar: calendar), 10)
        XCTAssertEqual(SemesterCalendar.weekIndex(for: sunday, semester: document.semester, calendar: calendar), 10)
        XCTAssertEqual(SemesterCalendar.weekIndex(for: mondayW11, semester: document.semester, calendar: calendar), 11)
        XCTAssertEqual(SemesterCalendar.weekIndex(for: sundayW11, semester: document.semester, calendar: calendar), 11)
        XCTAssertEqual(SemesterCalendar.weekIndex(for: opening, semester: document.semester, calendar: calendar), 1)
        XCTAssertEqual(
            SemesterCalendar.weekRangeLabel(week: 10, semester: document.semester, calendar: calendar),
            "11.02 – 11.08"
        )
        XCTAssertEqual(
            SemesterCalendar.weekRangeLabel(week: 11, semester: document.semester, calendar: calendar),
            "11.09 – 11.15"
        )
        XCTAssertEqual(SemesterCalendar.isoWeekday(monday, calendar: calendar), 1)
        XCTAssertEqual(SemesterCalendar.isoWeekday(sunday, calendar: calendar), 7)
        XCTAssertEqual(SemesterCalendar.isoWeekday(sundayW11, calendar: calendar), 7)
        XCTAssertNil(SemesterCalendar.parseCivil("2026-02-31", calendar: calendar))
        XCTAssertNil(SemesterCalendar.weekIndex(
            for: TestSupport.date(2026, 8, 24, calendar: calendar),
            semester: document.semester,
            calendar: calendar
        ))
    }

    func testCivilWeeksAcrossClockLeapAndYearBoundaries() throws {
        var london = calendar
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        for start in ["2026-03-23", "2026-10-19", "2028-02-28", "2026-12-28"] {
            var semester = document.semester
            semester.startDate = start
            semester.totalWeeks = 3
            let monday = try XCTUnwrap(SemesterCalendar.parseCivil(start, calendar: london))
            for offset in -1...21 {
                let day = try XCTUnwrap(london.date(byAdding: .day, value: offset, to: monday))
                let late = try XCTUnwrap(london.date(bySettingHour: 23, minute: 59, second: 0, of: day))
                let expected: Int? = (0...20).contains(offset) ? offset / 7 + 1 : nil
                XCTAssertEqual(SemesterCalendar.weekIndex(for: late, semester: semester, calendar: london), expected, "\(start) + \(offset)")
            }
        }
    }

    func testDemoWeekTenHasTenSessionsAndNoWeekendClasses() {
        let items = ScheduleEngine.occurrences(
            inWeek: 10,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar
        )
        XCTAssertEqual(items.count, 10)
        XCTAssertTrue(ScheduleEngine.conflicts(among: document.courses).isEmpty)
        let summary = ScheduleCopy.weekSummary(occurrences: items)
        XCTAssertEqual(summary.headline, "本周 10 门次")
        XCTAssertEqual(summary.aside, "周末没有课，好好休息")
        let monday = items.filter { $0.weekday == 1 }.map(\.name)
        XCTAssertEqual(monday, ["高等数学", "大学英语", "程序设计"])
        let calculus = items.first { $0.courseID == DemoData.ID.calculus && $0.weekday == 1 }
        XCTAssertEqual(calculus?.timeText, "08:00–09:40")
        XCTAssertEqual(calculus?.locationShort, "A · 301")
        XCTAssertEqual(calculus?.location, "教学楼 A · 301")
        XCTAssertEqual(ScheduleCopy.heroTag(kind: "必修课", weeks: Array(1...16)), "必修课 / 第1–16周")
    }

    func testArrangementCopyIsAccurateWhenMeetingsDiffer() {
        let calculus = document.courses[0]
        XCTAssertEqual(
            ScheduleCopy.arrangementLines(course: calculus, semester: document.semester),
            [
                "周一 · 第 1–2 节 · 08:00–09:40",
                "周三 · 第 3–4 节 · 10:10–11:50",
                "2026-2027 学年 · 第一学期",
            ]
        )
        let programming = document.courses[2]
        XCTAssertEqual(
            ScheduleCopy.arrangementLines(course: programming, semester: document.semester).first,
            "第 5–6 节 · 每周一、周五"
        )
        let meeting = calculus.meetings[0]
        XCTAssertEqual(ScheduleCopy.heroTime(meeting: meeting, semester: document.semester), "周一 08:00–09:40")
    }

    func testCurrentProgressAndNextCountdown() {
        let during = TestSupport.date(2026, 11, 9, 8, 30, calendar: calendar)
        let current = ScheduleEngine.currentOccurrence(
            at: during,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar
        )
        XCTAssertEqual(current?.name, "高等数学")
        XCTAssertEqual(ScheduleCopy.progress(from: current!.start, to: current!.end, now: during), 0.3, accuracy: 0.001)
        XCTAssertEqual(ScheduleCopy.remainingFootnote(from: during, to: current!.end), "还剩 70 分钟")
        XCTAssertEqual(
            ScheduleCopy.statusBanner(current: current, next: nil, now: during, calendar: calendar),
            "正在上课 · 高等数学 · 已上 30%"
        )

        let before = TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar)
        let next = ScheduleEngine.nextOccurrence(
            after: before,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar
        )
        XCTAssertEqual(next?.name, "高等数学")
        XCTAssertEqual(ScheduleCopy.upcomingFootnote(from: before, to: next!.start, calendar: calendar), "距上课 20 分钟")

        let boundary = TestSupport.date(2026, 11, 9, 9, 40, calendar: calendar)
        XCTAssertNil(ScheduleEngine.currentOccurrence(
            at: boundary, courses: document.courses, semester: document.semester, calendar: calendar
        ))
        let following = ScheduleEngine.nextOccurrence(
            after: boundary, courses: document.courses, semester: document.semester, calendar: calendar
        )
        XCTAssertEqual(following?.name, "大学英语")
        XCTAssertEqual(
            ScheduleCopy.upcomingFootnote(from: boundary, to: following!.start, calendar: calendar),
            "距上课 30 分钟"
        )

        let sunday = TestSupport.date(2026, 11, 8, 12, 0, calendar: calendar)
        let mondayNext = ScheduleEngine.nextOccurrence(
            after: sunday, courses: document.courses, semester: document.semester, calendar: calendar
        )
        XCTAssertEqual(mondayNext?.name, "高等数学")
        XCTAssertEqual(
            ScheduleCopy.upcomingFootnote(from: sunday, to: mondayNext!.start, calendar: calendar),
            "明天 08:00"
        )
    }

    func testOverlapDetectionAndMoveValidation() {
        let overlap = ScheduleEngine.validateMove(
            courseID: DemoData.ID.english,
            meetingID: DemoData.ID.englishMonday,
            weekday: 1,
            startPeriod: 2,
            courses: document.courses,
            semester: document.semester
        )
        guard case let .conflict(conflicts) = overlap else {
            return XCTFail("expected conflict, got \(overlap)")
        }
        XCTAssertTrue(conflicts.contains { $0.otherCourseID == DemoData.ID.calculus || $0.courseID == DemoData.ID.calculus })

        let allowed = ScheduleEngine.validateMove(
            courseID: DemoData.ID.linear,
            meetingID: DemoData.ID.linearTuesday,
            weekday: 5,
            startPeriod: 1,
            courses: document.courses,
            semester: document.semester
        )
        guard case let .ok(updated) = allowed else {
            return XCTFail("expected ok, got \(allowed)")
        }
        let moved = updated.first { $0.id == DemoData.ID.linear }?.meetings.first
        XCTAssertEqual(moved?.weekday, 5)
        XCTAssertEqual(moved?.startPeriod, 1)
        XCTAssertEqual(moved?.endPeriod, 2)

        let unchanged = ScheduleEngine.validateMove(
            courseID: DemoData.ID.linear,
            meetingID: DemoData.ID.linearTuesday,
            weekday: 2,
            startPeriod: 5,
            courses: document.courses,
            semester: document.semester
        )
        XCTAssertEqual(unchanged, .unchanged)

        let bounds = ScheduleEngine.validateMove(
            courseID: DemoData.ID.linear,
            meetingID: DemoData.ID.linearTuesday,
            weekday: 5,
            startPeriod: 10,
            courses: document.courses,
            semester: document.semester
        )
        XCTAssertEqual(bounds, .outOfBounds)

        var separated = document.courses
        separated[0].weeks = [1]
        separated[1].weeks = [2]
        separated[1].meetings[0] = Meeting(
            id: DemoData.ID.englishMonday, weekday: 1, startPeriod: 1, endPeriod: 2
        )
        XCTAssertTrue(ScheduleEngine.conflicts(among: separated).isEmpty)
    }

    func testAdjacentPeriodsDoNotOverlap() {
        let conflicts = ScheduleEngine.conflicts(among: document.courses)
        XCTAssertTrue(conflicts.isEmpty)
        let monday = ScheduleEngine.occurrences(
            on: TestSupport.date(2026, 11, 2, calendar: calendar),
            courses: document.courses,
            semester: document.semester,
            calendar: calendar
        )
        XCTAssertEqual(monday.map(\.startPeriod), [1, 3, 5])
    }
}
