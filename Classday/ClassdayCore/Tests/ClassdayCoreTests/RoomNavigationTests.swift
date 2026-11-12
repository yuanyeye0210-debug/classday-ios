import XCTest
import ClassdayCore

final class RoomNavigationTests: XCTestCase {
    func testMissingCoordinatesDoNotInventBeijing() {
        let named = RoomNavigation.directions(location: "教学楼 A · 301", pin: nil)
        XCTAssertEqual(named, .search(query: "教学楼 A · 301"))

        let pin = RoomPin(name: "教学楼 A", latitude: nil, longitude: nil, query: "教学楼 A")
        XCTAssertEqual(RoomNavigation.directions(location: "教学楼 A · 301", pin: pin), .search(query: "教学楼 A · 301"))

        let partial = RoomPin(name: "教学楼 A", latitude: 39.9, longitude: nil)
        let partialResult = RoomNavigation.directions(location: "教学楼 A", pin: partial)
        if case let .coordinate(latitude, longitude, _) = partialResult {
            XCTFail("partial pin became \(latitude), \(longitude)")
        }
        XCTAssertEqual(partialResult, .search(query: "教学楼 A"))

        XCTAssertEqual(RoomNavigation.directions(location: "  ", pin: nil), .missing)

        let placed = RoomPin(name: "教学楼 A", latitude: 31.23, longitude: 121.47, query: "教学楼 A")
        XCTAssertEqual(
            RoomNavigation.directions(location: "301", pin: placed),
            .coordinate(latitude: 31.23, longitude: 121.47, name: "教学楼 A")
        )
    }

    func testRoomNavigatorSourceHasNoBeijingFallback() throws {
        let source = try String(
            contentsOf: TestSupport.repositoryClassdayRoot().appendingPathComponent("ClassdayApp/Sources/Experience.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("39.9"))
        XCTAssertFalse(source.contains("116.4"))
        XCTAssertTrue(source.contains("RoomNavigation.directions"))
    }
}
