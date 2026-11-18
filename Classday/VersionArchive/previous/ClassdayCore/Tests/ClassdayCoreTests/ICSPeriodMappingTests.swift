import XCTest
@testable import ClassdayCore

final class ICSPeriodMappingTests: XCTestCase {
    func testCalendarUsesCurrentSemesterClocks() {
        let periods = [
            PeriodTemplate(index: 3, start: "09:00", end: "09:30"),
            PeriodTemplate(index: 4, start: "09:30", end: "10:00")
        ]
        func parse(_ start: String, _ end: String) -> ImportedCalendar {
            ICSImporter.parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Math\nDTSTART:\(start)\nDTEND:\(end)\nEND:VEVENT\nEND:VCALENDAR", periods: periods)
        }
        let good = parse("20261102T090000", "20261102T100000")
        XCTAssertEqual(good.courses.first?.meetings.first?.startPeriod, 3)
        XCTAssertEqual(good.courses.first?.meetings.first?.endPeriod, 4)
        XCTAssertTrue(good.warnings.isEmpty)
        for (start, end) in [
            ("20261102T090500", "20261102T100000"),
            ("20261102T090000", "20261102T095500"),
            ("20261102T090001", "20261102T100000"),
            ("20261102T090000", "20261103T100000")
        ] {
            let bad = parse(start, end)
            XCTAssertTrue(bad.courses.isEmpty)
            XCTAssertEqual(bad.warnings.count, 1)
        }
    }
}
