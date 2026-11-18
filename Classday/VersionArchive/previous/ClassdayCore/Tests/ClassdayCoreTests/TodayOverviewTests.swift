import Foundation
import XCTest
import ClassdayCore

final class TodayOverviewTests: XCTestCase {
    private let calendar = ClassdayCalendar.make(timeZone: TimeZone(secondsFromGMT: 0)!)

    func testCourseStartAndEndBoundaries() throws {
        let document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let day = TodayProjection.make(at: monday, document: document, calendar: calendar)
        let first = try XCTUnwrap(day.courses.first)
        let before = TodayProjection.make(at: first.start.addingTimeInterval(-1), document: document, calendar: calendar)
        XCTAssertFalse(before.inProgress)
        XCTAssertEqual(before.focus?.id, first.id)
        let atStart = TodayProjection.make(at: first.start, document: document, calendar: calendar)
        XCTAssertTrue(atStart.inProgress)
        XCTAssertEqual(atStart.focus?.id, first.id)
        let atEnd = TodayProjection.make(at: first.end, document: document, calendar: calendar)
        XCTAssertNotEqual(atEnd.focus?.id, first.id)
        XCTAssertGreaterThanOrEqual(atEnd.completedCount, 1)
    }

    func testGapBetweenClassesFocusesNextClassToday() throws {
        let document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let day = TodayProjection.make(at: monday, document: document, calendar: calendar)
        XCTAssertGreaterThanOrEqual(day.courses.count, 2)
        let first = try XCTUnwrap(day.courses.first)
        let second = try XCTUnwrap(day.courses.dropFirst().first)
        let gap = first.end.addingTimeInterval(60)
        XCTAssertLessThan(gap, second.start)
        let state = TodayProjection.make(at: gap, document: document, calendar: calendar)
        XCTAssertFalse(state.inProgress)
        XCTAssertEqual(state.focus?.id, second.id)
        XCTAssertEqual(state.completedCount, 1)
        XCTAssertEqual(state.courses.map { $0.id }, day.courses.map { $0.id })
    }

    func testNoCourseTodayCanStillShowFutureCourse() throws {
        var document = DemoData.makeDocument()
        var course = try XCTUnwrap(document.courses.first)
        var meeting = try XCTUnwrap(course.meetings.first)
        meeting.weekday = 2
        course.meetings = [meeting]
        course.weeks = [1]
        document.courses = [course]
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let state = TodayProjection.make(at: monday, document: document, calendar: calendar)
        XCTAssertTrue(state.courses.isEmpty)
        XCTAssertEqual(state.focus?.weekday, 2)
        XCTAssertFalse(state.inProgress)
        XCTAssertEqual(state.completedCount, 0)
    }

    func testAfterLastClassShowsNextDayAndAllCompleted() throws {
        let document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let day = TodayProjection.make(at: monday, document: document, calendar: calendar)
        let last = try XCTUnwrap(day.courses.max { $0.end < $1.end })
        let state = TodayProjection.make(at: last.end, document: document, calendar: calendar)
        XCTAssertEqual(state.completedCount, state.courses.count)
        XCTAssertFalse(state.inProgress)
        let next = try XCTUnwrap(state.focus)
        XCTAssertGreaterThan(next.start, last.end)
        XCTAssertFalse(calendar.isDate(next.start, inSameDayAs: monday))
    }

    func testReadFailureEmptyStoreAndRecoveryAreDistinct() {
        let now = Date(timeIntervalSince1970: 0)
        let missing = TodayProjection.make(at: now, document: nil, calendar: calendar)
        XCTAssertFalse(missing.readable)
        XCTAssertTrue(missing.courses.isEmpty)
        XCTAssertNil(missing.focus)
        XCTAssertFalse(missing.showsExtras(eventCount: 2, homeworkCount: 1, hasUpcomingExam: true))
        var document = DemoData.makeDocument()
        document.courses = []
        let recovered = TodayProjection.make(at: now, document: document, calendar: calendar)
        XCTAssertTrue(recovered.readable)
        XCTAssertNil(recovered.focus)
        XCTAssertFalse(recovered.showsExtras(eventCount: 0, homeworkCount: 0, hasUpcomingExam: false))
        XCTAssertTrue(recovered.showsExtras(eventCount: 1, homeworkCount: 0, hasUpcomingExam: false))
        XCTAssertTrue(recovered.showsExtras(eventCount: 0, homeworkCount: 1, hasUpcomingExam: false))
        XCTAssertTrue(recovered.showsExtras(eventCount: 0, homeworkCount: 0, hasUpcomingExam: true))
    }

    func testClassroomFocusEntersAtStartRestoresAtEndAndCanRevealCourses() throws {
        let document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let first = try XCTUnwrap(TodayProjection.make(at: monday, document: document, calendar: calendar).courses.first)
        let before = TodayProjection.make(at: first.start.addingTimeInterval(-1), document: document, calendar: calendar)
        XCTAssertNil(before.classroomCourse)
        XCTAssertEqual(before.displayedCourses(showAll: false), before.courses)
        let active = TodayProjection.make(at: first.start, document: document, calendar: calendar)
        XCTAssertEqual(active.classroomCourse?.id, first.id)
        XCTAssertEqual(active.displayedCourses(showAll: false), [first])
        XCTAssertEqual(active.displayedCourses(showAll: true), active.courses)
        let ended = TodayProjection.make(at: first.end, document: document, calendar: calendar)
        XCTAssertNil(ended.classroomCourse)
        XCTAssertEqual(ended.displayedCourses(showAll: false), ended.courses)
    }

    func testHolidayAndReadFailureNeverActivateClassroomFocus() throws {
        var document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let first = try XCTUnwrap(TodayProjection.make(at: monday, document: document, calendar: calendar).courses.first)
        let date = SemesterCalendar.formatCivil(first.start, calendar: calendar)
        document.semester.holidays = [HolidayPeriod(id: UUID(), name: "放假", startDate: date, endDate: date)]
        XCTAssertNil(TodayProjection.make(at: first.start, document: document, calendar: calendar).classroomCourse)
        XCTAssertNil(TodayProjection.make(at: first.start, document: nil, calendar: calendar).classroomCourse)
    }

    func testCancellationAndDelayChangeFocusOnlyForAffectedWeek() throws {
        var document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let first = try XCTUnwrap(TodayProjection.make(at: monday, document: document, calendar: calendar).courses.first)
        document.overrides = [OccurrenceOverride(courseID: first.courseID, meetingID: first.meetingID,
            week: first.weekIndex, kind: .cancelled)]
        XCTAssertNil(TodayProjection.make(at: first.start, document: document, calendar: calendar).classroomCourse)
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: first.start))
        XCTAssertNotNil(TodayProjection.make(at: nextWeek, document: document, calendar: calendar).classroomCourse)
        document.overrides = [OccurrenceOverride(courseID: first.courseID, meetingID: first.meetingID,
            week: first.weekIndex, kind: .delayed, delayMinutes: 10)]
        XCTAssertNil(TodayProjection.make(at: first.start, document: document, calendar: calendar).classroomCourse)
        XCTAssertEqual(TodayProjection.make(at: first.start.addingTimeInterval(600), document: document,
            calendar: calendar).classroomCourse?.courseID, first.courseID)
    }

    func testSystemFocusFilterCanShowNextCourseOutsideClassAndUserCanRevealAll() throws {
        let document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let state = TodayProjection.make(at: monday, document: document, calendar: calendar)
        XCTAssertNil(state.classroomCourse)
        let next = try XCTUnwrap(state.focus)
        XCTAssertEqual(state.displayedCourses(showAll: false, focusFilter: true), [next])
        XCTAssertEqual(state.displayedCourses(showAll: true, focusFilter: true), state.courses)
        XCTAssertEqual(state.displayedCourses(showAll: false, focusFilter: false), state.courses)
    }

    func testSystemFocusFilterDoesNotInventUnreadableOrEmptyCourses() {
        let now = Date(timeIntervalSince1970: 0)
        let missing = TodayProjection.make(at: now, document: nil, calendar: calendar)
        XCTAssertTrue(missing.displayedCourses(showAll: false, focusFilter: true).isEmpty)
        var document = DemoData.makeDocument()
        document.courses = []
        let empty = TodayProjection.make(at: now, document: document, calendar: calendar)
        XCTAssertTrue(empty.displayedCourses(showAll: false, focusFilter: true).isEmpty)
    }
}
