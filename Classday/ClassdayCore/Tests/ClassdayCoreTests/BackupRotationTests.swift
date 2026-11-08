import XCTest
import ClassdayCore

final class BackupRotationTests: XCTestCase {
    func testRotateKeepsOnlyPreviousAndDoesNotEscapeArchive() throws {
        let root = try TestSupport.temporaryDirectory()
        let source = root.appendingPathComponent("Classday", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let archive = source.appendingPathComponent("VersionArchive", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive.appendingPathComponent("older/nested", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive.appendingPathComponent("previous", isDirectory: true), withIntermediateDirectories: true)
        try Data("keep-me".utf8).write(to: archive.appendingPathComponent("KEEP.txt"))
        try Data("stale".utf8).write(to: archive.appendingPathComponent("older/nested/old.txt"))
        try Data("old-prev".utf8).write(to: archive.appendingPathComponent("previous/old.txt"))
        try Data(BackupRotator.markerContents.utf8).write(to: archive.appendingPathComponent(BackupRotator.markerFileName))
        try Data("hello".utf8).write(to: source.appendingPathComponent("hello.txt"))
        try FileManager.default.createDirectory(at: source.appendingPathComponent(".build", isDirectory: true), withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: source.appendingPathComponent(".build/junk.txt"))
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        let secret = outside.appendingPathComponent("secret.txt")
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("linked-secret"),
            withDestinationURL: secret
        )
        try FileManager.default.createSymbolicLink(
            at: archive.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        let sibling = root.appendingPathComponent("do-not-touch.txt")
        try Data("safe".utf8).write(to: sibling)

        let preview = try BackupRotator.inspect(source: source, archive: archive)
        XCTAssertEqual(preview.mode, "inspect")
        XCTAssertEqual(preview.copiedFileCount, 1)
        XCTAssertEqual(preview.removedRelativePaths, ["escape", "older", "previous"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.appendingPathComponent("older/nested/old.txt").path))

        let report = try BackupRotator.rotate(source: source, archive: archive)
        XCTAssertEqual(report.mode, "rotate")
        XCTAssertEqual(report.copiedFileCount, 1)
        XCTAssertEqual(report.removedRelativePaths, ["escape", "older", "previous"])

        let snapshot = archive.appendingPathComponent("previous/hello.txt")
        XCTAssertEqual(try String(contentsOf: snapshot), "hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("previous/.build/junk.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("previous/VersionArchive").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("previous/linked-secret").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("older").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("escape").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("previous/old.txt").path))
        XCTAssertEqual(try String(contentsOf: archive.appendingPathComponent("KEEP.txt")), "keep-me")
        XCTAssertEqual(try String(contentsOf: secret), "secret")
        XCTAssertEqual(try String(contentsOf: sibling), "safe")
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("hello.txt")), "hello")

        try Data("second".utf8).write(to: source.appendingPathComponent("hello.txt"))
        _ = try BackupRotator.rotate(source: source, archive: archive)
        XCTAssertEqual(try String(contentsOf: archive.appendingPathComponent("previous/hello.txt")), "second")
        let children = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil)
        let directories = children.filter { url in
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return isDirectory.boolValue && !url.lastPathComponent.hasPrefix(".")
        }.map(\.lastPathComponent).sorted()
        XCTAssertEqual(directories, ["previous"])
        XCTAssertEqual(try String(contentsOf: secret), "secret")
    }

    func testSafetyChecksDoNotDelete() throws {
        let root = try TestSupport.temporaryDirectory()
        let source = root.appendingPathComponent("Classday", isDirectory: true)
        let archive = root.appendingPathComponent("NotTheArchive", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive.appendingPathComponent("older", isDirectory: true), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source.appendingPathComponent("hello.txt"))
        try Data("stay".utf8).write(to: archive.appendingPathComponent("older/stay.txt"))
        try Data(BackupRotator.markerContents.utf8).write(to: archive.appendingPathComponent(BackupRotator.markerFileName))

        XCTAssertThrowsError(try BackupRotator.rotate(source: source, archive: archive)) { error in
            guard case BackupRotationError.archiveDirectoryName = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: archive.appendingPathComponent("older/stay.txt")), "stay")

        let realArchive = source.appendingPathComponent("VersionArchive", isDirectory: true)
        try FileManager.default.createDirectory(at: realArchive.appendingPathComponent("older", isDirectory: true), withIntermediateDirectories: true)
        try Data("stay".utf8).write(to: realArchive.appendingPathComponent("older/stay.txt"))
        XCTAssertThrowsError(try BackupRotator.rotate(source: source, archive: realArchive))
        XCTAssertEqual(try String(contentsOf: realArchive.appendingPathComponent("older/stay.txt")), "stay")

        try Data("wrong".utf8).write(to: realArchive.appendingPathComponent(BackupRotator.markerFileName))
        XCTAssertThrowsError(try BackupRotator.rotate(source: source, archive: realArchive)) { error in
            guard case BackupRotationError.invalidMarker = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: realArchive.appendingPathComponent("older/stay.txt")), "stay")

        let nestedSource = realArchive.appendingPathComponent("previous", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedSource, withIntermediateDirectories: true)
        try Data(BackupRotator.markerContents.utf8).write(to: realArchive.appendingPathComponent(BackupRotator.markerFileName))
        XCTAssertThrowsError(try BackupRotator.rotate(source: nestedSource, archive: realArchive)) { error in
            guard case BackupRotationError.sourceInsideArchive = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: realArchive.appendingPathComponent("older/stay.txt")), "stay")
        XCTAssertThrowsError(try BackupRotator.rotate(source: realArchive, archive: realArchive))
    }

    func testRepositoryArchiveHasNoFabricatedPreviousVersion() throws {
        let archive = TestSupport.repositoryClassdayRoot().appendingPathComponent("VersionArchive")
        let marker = archive.appendingPathComponent(BackupRotator.markerFileName)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), BackupRotator.markerContents)
        let children = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil)
        XCTAssertFalse(children.contains { $0.lastPathComponent == "previous" })
        XCTAssertFalse(children.contains { $0.lastPathComponent == "older" || $0.lastPathComponent == "v1" })
        let before = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).map(\.lastPathComponent).sorted()
        _ = try BackupRotator.inspect(source: TestSupport.repositoryClassdayRoot(), archive: archive)
        let after = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).map(\.lastPathComponent).sorted()
        XCTAssertEqual(before, after)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("previous").path))
    }
}
