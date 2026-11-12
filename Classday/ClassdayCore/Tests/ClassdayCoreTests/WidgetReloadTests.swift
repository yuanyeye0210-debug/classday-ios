import XCTest
import ClassdayCore

final class WidgetReloadTests: XCTestCase {
    func testEveryTimelineKindIsReloaded() throws {
        XCTAssertEqual(
            WidgetID.all,
            [WidgetID.nextClass, WidgetID.todayCourses, WidgetID.fanStack, WidgetID.weekBoard, WidgetID.lockScreen]
        )
        let root = TestSupport.repositoryClassdayRoot()
        let reloader = try String(
            contentsOf: root.appendingPathComponent("ClassdayApp/Sources/WidgetReloader.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(reloader.contains("WidgetID.all"))
        XCTAssertFalse(reloader.contains("WidgetID.nextClass"))
        let extra = try String(
            contentsOf: root.appendingPathComponent("ClassdayWidget/Sources/ExtraWidgets.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(extra.contains("kind: WidgetID.fanStack"))
        XCTAssertTrue(extra.contains("kind: WidgetID.weekBoard"))
        XCTAssertTrue(extra.contains("kind: WidgetID.lockScreen"))
        XCTAssertFalse(extra.contains("kind: \"FanStackWidget\""))
        XCTAssertFalse(extra.contains("kind: \"WeekBoardWidget\""))
        XCTAssertFalse(extra.contains("kind: \"LockNextWidget\""))
        let intent = extra.split(separator: "struct NextFanCardIntent").first.map(String.init) ?? extra
        XCTAssertTrue(intent.contains("WidgetID.all"))
        XCTAssertTrue(intent.contains("reloadTimelines"))
    }
}
