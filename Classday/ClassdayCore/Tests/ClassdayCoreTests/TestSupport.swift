import Foundation
import XCTest
import ClassdayCore

enum TestSupport {
    static func calendar() -> Calendar {
        guard let zone = TimeZone(identifier: "Asia/Shanghai") else {
            preconditionFailure("Asia/Shanghai timezone is unavailable")
        }
        return ClassdayCalendar.make(timeZone: zone)
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components) else {
            preconditionFailure("Invalid test date")
        }
        return date
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("classday-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func repositoryClassdayRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
