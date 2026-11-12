import XCTest
import ClassdayCore

final class StoreTests: XCTestCase {
    func testDemoRoundTripAndClearRestore() throws {
        let directory = try TestSupport.temporaryDirectory()
        let url = directory.appendingPathComponent("classday-store.json")
        let demo = DemoData.makeDocument()
        let report = StoreCodec.validate(demo)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: " | "))
        XCTAssertTrue(report.warnings.isEmpty, report.warnings.joined(separator: " | "))
        try StoreFile.save(demo, to: url)
        let loaded = try StoreFile.load(from: url)
        XCTAssertEqual(loaded, StoreCodec.normalized(demo))
        XCTAssertEqual(loaded.origin, .demo)

        let cleared = StoreEditing.cleared(loaded)
        XCTAssertEqual(cleared.origin, .user)
        XCTAssertTrue(cleared.courses.isEmpty)
        try StoreFile.save(cleared, to: url)
        XCTAssertEqual(try StoreFile.load(from: url).courses, [])

        let restored = StoreEditing.restoredDemo()
        XCTAssertEqual(restored.origin, .demo)
        XCTAssertEqual(restored.courses.count, 6)
    }

    func testImportRejectsMalformedAndAcceptsOverlapWithWarning() throws {
        let bad = StoreCodec.importing(Data("{}".utf8))
        XCTAssertNil(bad.document)
        XCTAssertEqual(bad.errors, ["无法解析 JSON"])

        var invalid = DemoData.makeDocument()
        invalid.schemaVersion = 2
        let wrongSchema = StoreCodec.importing(try StoreCodec.encode(invalid))
        XCTAssertNil(wrongSchema.document)
        XCTAssertTrue(wrongSchema.errors.contains("schemaVersion 必须为 1"))

        invalid = DemoData.makeDocument()
        invalid.semester.startDate = "2026-02-31"
        let badDate = StoreCodec.importing(try JSONEncoder().encode(invalid))
        XCTAssertTrue(badDate.errors.contains("学期开始日期无效"))

        invalid = DemoData.makeDocument()
        invalid.courses[0].name = "  "
        let emptyName = StoreCodec.importing(try JSONEncoder().encode(invalid))
        XCTAssertTrue(emptyName.errors.contains("第 1 门课程的名称不能为空"))

        var overlap = DemoData.makeDocument()
        overlap.courses[1].meetings[0] = Meeting(
            id: DemoData.ID.englishMonday, weekday: 1, startPeriod: 1, endPeriod: 2
        )
        let imported = StoreCodec.importing(try StoreCodec.encode(overlap))
        XCTAssertNotNil(imported.document)
        XCTAssertTrue(imported.errors.isEmpty)
        XCTAssertTrue(imported.warnings.contains { $0.contains("高等数学") && $0.contains("大学英语") && $0.contains("重叠") })

        let directory = try TestSupport.temporaryDirectory()
        let url = directory.appendingPathComponent("bad.json")
        var unsaveable = DemoData.makeDocument()
        unsaveable.semester.totalWeeks = 0
        XCTAssertThrowsError(try StoreFile.save(unsaveable, to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFallbackCopiesIntoEmptyGroupWithoutOverwriting() throws {
        let root = try TestSupport.temporaryDirectory()
        let fallback = root.appendingPathComponent("fallback.json")
        let group = root.appendingPathComponent("group/classday-store.json")
        try Data("fallback".utf8).write(to: fallback)
        let resolved = try StoreLocator.resolve(groupURL: group, fallbackURL: fallback)
        XCTAssertEqual(resolved, group)
        XCTAssertEqual(try String(contentsOf: group), "fallback")

        try Data("group".utf8).write(to: group)
        try Data("other".utf8).write(to: fallback)
        _ = try StoreLocator.resolve(groupURL: group, fallbackURL: fallback)
        XCTAssertEqual(try String(contentsOf: group), "group")
        XCTAssertEqual(try StoreLocator.resolve(groupURL: nil, fallbackURL: fallback), fallback)
    }

    func testCommittedDemoFixtureMatchesGenerator() throws {
        let url = TestSupport.repositoryClassdayRoot().appendingPathComponent("Docs/demo-store.json")
        let outcome = StoreCodec.importing(try Data(contentsOf: url))
        XCTAssertEqual(outcome.document, StoreCodec.normalized(DemoData.makeDocument()))
        XCTAssertTrue(outcome.errors.isEmpty)
        XCTAssertTrue(outcome.warnings.isEmpty)
    }

    func testUnreadableStoreIsCopiedAndDemoIsNotWrittenOverIt() throws {
        let directory = try TestSupport.temporaryDirectory()
        let url = directory.appendingPathComponent("classday-store.json")
        let original = Data("this is not a timetable".utf8)
        try original.write(to: url)

        let read = StoreFile.read(from: url, stamp: "unit")
        guard case let .unreadable(preservedCopy, errors) = read else {
            return XCTFail("expected unreadable, got \(read)")
        }
        XCTAssertFalse(errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
        let backup = try XCTUnwrap(preservedCopy)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertNotEqual(backup, url)
        XCTAssertTrue(StoreSafety.blocksDemoOverwrite(origin: .demo, fileWasUnreadable: true))
        XCTAssertFalse(StoreSafety.blocksDemoOverwrite(origin: .user, fileWasUnreadable: true))
        XCTAssertFalse(StoreSafety.blocksDemoOverwrite(origin: .demo, fileWasUnreadable: false))
    }

    func testJSONImportReplaceKeepsThePreviousTimetable() throws {
        let current = DemoData.makeDocument()
        var incoming = DemoData.makeDocument()
        incoming.courses = [incoming.courses[0]]
        incoming.courses[0].name = "导入的课"
        incoming.semester.name = "导入学期"
        let backupID = UUID(uuidString: "00000000-0000-0000-0000-0000000000cc")!
        let replaced = StoreImport.replaceKeepingBackup(current, with: incoming, backupID: backupID)
        XCTAssertEqual(replaced.courses.map(\.name), ["导入的课"])
        XCTAssertEqual(replaced.semester.name, "导入学期")
        XCTAssertEqual(replaced.origin, .user)
        XCTAssertEqual(replaced.activeTimetableID, current.activeTimetableID)
        let saved = try XCTUnwrap(replaced.library.first { $0.id == backupID })
        XCTAssertEqual(saved.name, "导入前备份")
        XCTAssertTrue(saved.courses.contains { $0.name == "高等数学" })
    }

    func testAppImportDoesNotReplaceBeforeConfirmation() throws {
        let source = try String(
            contentsOf: TestSupport.repositoryClassdayRoot().appendingPathComponent("ClassdayApp/Sources/AppModel.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("replace(with: document)"))
        XCTAssertTrue(source.contains("StoreImport.replaceKeepingBackup"))
        XCTAssertTrue(source.contains("StoreFile.read"))
        XCTAssertTrue(source.contains("blocksDemoOverwrite"))
    }

    func testDeepLinksRoundTrip() {
        let url = ClassdayLink.course(DemoData.ID.calculus, meeting: DemoData.ID.calculusMonday)
        XCTAssertEqual(url.scheme, "classday")
        let parsed = ClassdayLink.parse(url)
        XCTAssertEqual(parsed?.courseID, DemoData.ID.calculus)
        XCTAssertEqual(parsed?.meetingID, DemoData.ID.calculusMonday)
        XCTAssertNil(ClassdayLink.parse(URL(string: "https://example.com/course")!))
        XCTAssertEqual(AppGroup.identifier, "group.com.classday.shared")
        XCTAssertEqual(WidgetID.nextClass, "NextClassWidget")
        XCTAssertEqual(WidgetID.todayCourses, "TodayCoursesWidget")
    }
}
