import Foundation
import XCTest
import ClassdayCore

final class ScheduleAnswersTests: XCTestCase {
    private let calendar = ClassdayCalendar.make(timeZone: TimeZone(secondsFromGMT: 0)!)

    func testMissingStoreIsNotAnEmptyOrDemoSchedule() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(ScheduleAnswers.nextClass(document: nil, at: now, calendar: calendar).contains("读不到课表"))
        XCTAssertTrue(ScheduleAnswers.endOfDay(document: nil, at: now, calendar: calendar).contains("读不到课表"))
        var document = DemoData.makeDocument()
        document.courses = []
        XCTAssertEqual(ScheduleAnswers.nextClass(document: document, at: now, calendar: calendar), "本学期没有待上的课程。")
        XCTAssertEqual(ScheduleAnswers.endOfDay(document: document, at: now, calendar: calendar), "今天没有课程。")
    }

    func testNextClassAndLastEndBoundary() throws {
        let document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let today = ScheduleEngine.occurrences(on: monday, courses: document.courses,
            semester: document.semester, calendar: calendar, context: document.scheduleContext)
        let first = try XCTUnwrap(today.min(by: { $0.start < $1.start }))
        let last = try XCTUnwrap(today.max(by: { $0.end < $1.end }))
        XCTAssertTrue(ScheduleAnswers.nextClass(document: document, at: first.start.addingTimeInterval(-1), calendar: calendar).contains(first.name))
        let upcoming = ScheduleAnswers.nextClass(document: document, at: first.start, calendar: calendar)
        let next = try XCTUnwrap(ScheduleEngine.nextOccurrence(after: first.start, courses: document.courses,
            semester: document.semester, calendar: calendar, context: document.scheduleContext))
        XCTAssertTrue(upcoming.contains(next.name))
        XCTAssertFalse(ScheduleAnswers.endOfDay(document: document, at: last.end.addingTimeInterval(-1), calendar: calendar).contains("已在"))
        XCTAssertTrue(ScheduleAnswers.endOfDay(document: document, at: last.end, calendar: calendar).contains("已在"))
    }

    func testClassroomAnswerUsesCurrentCourseAndDoesNotPromiseSystemFocus() throws {
        let document = DemoData.makeDocument()
        let monday = try XCTUnwrap(SemesterCalendar.semesterMonday(document.semester, calendar: calendar))
        let first = try XCTUnwrap(TodayProjection.make(at: monday, document: document, calendar: calendar).courses.first)
        let active = ScheduleAnswers.classroom(document: document, at: first.start, calendar: calendar)
        XCTAssertTrue(active.contains(first.name))
        XCTAssertTrue(active.contains("应用内上课专注"))
        XCTAssertTrue(active.contains("不会开启系统专注"))
        XCTAssertTrue(ScheduleAnswers.classroom(document: document, at: first.end, calendar: calendar).contains("现在没有"))
        XCTAssertTrue(ScheduleAnswers.classroom(document: nil, at: first.start, calendar: calendar).contains("读不到课表"))
    }
}
