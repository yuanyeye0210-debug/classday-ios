import XCTest
import ClassdayCore

final class VersionBumpTests: XCTestCase {
    func testTwoSuccessiveBumpsKeepOnlyTheImmediatePrevious() throws {
        let root = try TestSupport.temporaryDirectory()
        let outside = root.appendingPathComponent("do-not-touch.txt")
        try Data("safe".utf8).write(to: outside)
        let working = root.appendingPathComponent("Classday", isDirectory: true)
        try writeApp(working, version: "1.0.0", payload: "alpha")
        try writeArchive(working)
        try FileManager.default.createDirectory(
            at: working.appendingPathComponent("VersionArchive/older", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("stale".utf8).write(to: working.appendingPathComponent("VersionArchive/older/stale.txt"))
        try FileManager.default.createDirectory(
            at: working.appendingPathComponent("VersionArchive/previous", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("ancient".utf8).write(to: working.appendingPathComponent("VersionArchive/previous/ancient.txt"))
        let outsideDir = root.appendingPathComponent("outside-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outsideDir.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(
            at: working.appendingPathComponent("VersionArchive/escape"),
            withDestinationURL: outsideDir
        )

        let committedV1 = root.appendingPathComponent("committed-v1", isDirectory: true)
        try writeApp(committedV1, version: "1.0.0", payload: "alpha")
        try FileManager.default.createDirectory(
            at: committedV1.appendingPathComponent("VersionArchive/previous", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("should-not-nest".utf8).write(to: committedV1.appendingPathComponent("VersionArchive/previous/nested.txt"))

        let first = try VersionBump.apply(committedTree: committedV1, workingTree: working, newVersion: "1.1.0")
        XCTAssertEqual(first.previousVersion, "1.0.0")
        XCTAssertEqual(first.newVersion, "1.1.0")
        XCTAssertEqual(first.previousBuild, 1)
        XCTAssertEqual(first.newBuild, 2)
        XCTAssertEqual(try text(working.appendingPathComponent(VersionBump.buildFileName)), "2\n")
        XCTAssertEqual(VersionBump.readVersion(in: working), "1.1.0")
        XCTAssertEqual(try text(working.appendingPathComponent("payload.txt")), "alpha")
        let previous = working.appendingPathComponent("VersionArchive/previous")
        XCTAssertEqual(try text(previous.appendingPathComponent("payload.txt")), "alpha")
        XCTAssertEqual(try text(previous.appendingPathComponent(VersionBump.versionFileName)), "1.0.0\n")
        XCTAssertEqual(try text(previous.appendingPathComponent(VersionBump.stampFileName)), "1.0.0\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.appendingPathComponent("VersionArchive").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.appendingPathComponent("VersionArchive/older").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.appendingPathComponent("ancient.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.appendingPathComponent("VersionArchive/escape").path))
        XCTAssertEqual(try text(outsideDir.appendingPathComponent("secret.txt")), "secret")
        XCTAssertEqual(try text(outside), "safe")

        try Data("beta".utf8).write(to: working.appendingPathComponent("payload.txt"))
        let committedV11 = root.appendingPathComponent("committed-v1.1", isDirectory: true)
        try writeApp(committedV11, version: "1.1.0", payload: "beta")
        try Data("4\n".utf8).write(to: committedV11.appendingPathComponent(VersionBump.buildFileName))
        let second = try VersionBump.apply(committedTree: committedV11, workingTree: working, newVersion: "1.2.0")
        XCTAssertEqual(second.previousVersion, "1.1.0")
        XCTAssertEqual(second.previousBuild, 4)
        XCTAssertEqual(second.newBuild, 5)
        XCTAssertEqual(try text(working.appendingPathComponent(VersionBump.buildFileName)), "5\n")
        XCTAssertEqual(try text(previous.appendingPathComponent(VersionBump.buildFileName)), "4\n")
        XCTAssertEqual(VersionBump.readVersion(in: working), "1.2.0")
        XCTAssertEqual(try text(previous.appendingPathComponent("payload.txt")), "beta")
        XCTAssertEqual(try text(previous.appendingPathComponent(VersionBump.stampFileName)), "1.1.0\n")
        XCTAssertFalse(try text(previous.appendingPathComponent("payload.txt")).contains("alpha"))
        let directories = try directoryNames(working.appendingPathComponent("VersionArchive"))
        XCTAssertEqual(directories, ["previous"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.appendingPathComponent("VersionArchive").path))
        XCTAssertEqual(try text(outside), "safe")
        XCTAssertEqual(try text(outsideDir.appendingPathComponent("secret.txt")), "secret")
    }

    func testBumpArchivesTheCommittedTreeRatherThanTheDirtyWorkingTree() throws {
        let root = try TestSupport.temporaryDirectory()
        let working = root.appendingPathComponent("Classday", isDirectory: true)
        try writeApp(working, version: "9.9.9", payload: "already-edited")
        try writeArchive(working)
        let committed = root.appendingPathComponent("committed", isDirectory: true)
        try writeApp(committed, version: "1.0.0", payload: "old-commit")

        _ = try VersionBump.apply(committedTree: committed, workingTree: working, newVersion: "1.1.0")
        let previous = working.appendingPathComponent("VersionArchive/previous")
        XCTAssertEqual(try text(previous.appendingPathComponent("payload.txt")), "old-commit")
        XCTAssertEqual(try text(previous.appendingPathComponent(VersionBump.stampFileName)), "1.0.0\n")
        XCTAssertEqual(try text(working.appendingPathComponent("payload.txt")), "already-edited")
        XCTAssertEqual(VersionBump.readVersion(in: working), "1.1.0")
    }

    func testRejectedBumpDoesNotCreateASnapshot() throws {
        let root = try TestSupport.temporaryDirectory()
        let working = root.appendingPathComponent("Classday", isDirectory: true)
        try writeApp(working, version: "1.0.0", payload: "alpha")
        try writeArchive(working)
        let committed = root.appendingPathComponent("committed", isDirectory: true)
        try writeApp(committed, version: "1.0.0", payload: "alpha")

        XCTAssertThrowsError(try VersionBump.apply(committedTree: committed, workingTree: working, newVersion: "1.0.0")) { error in
            guard case VersionBumpError.sameVersion = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertThrowsError(try VersionBump.apply(committedTree: committed, workingTree: working, newVersion: "1.1")) { error in
            guard case VersionBumpError.invalidVersion = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.appendingPathComponent("VersionArchive/previous").path))
        XCTAssertEqual(VersionBump.readVersion(in: working), "1.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.appendingPathComponent(VersionBump.buildFileName).path))

        try Data("nope\n".utf8).write(to: committed.appendingPathComponent(VersionBump.buildFileName))
        XCTAssertThrowsError(try VersionBump.apply(committedTree: committed, workingTree: working, newVersion: "1.1.0")) { error in
            guard case VersionBumpError.invalidBuild = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.appendingPathComponent("VersionArchive/previous").path))
        XCTAssertEqual(VersionBump.readVersion(in: working), "1.0.0")
    }

    private func writeApp(_ root: URL, version: String, payload: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("\(version)\n".utf8).write(to: root.appendingPathComponent("VERSION"))
        try Data(payload.utf8).write(to: root.appendingPathComponent("payload.txt"))
    }

    private func writeArchive(_ root: URL) throws {
        let archive = root.appendingPathComponent("VersionArchive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data(BackupRotator.markerContents.utf8).write(to: archive.appendingPathComponent(BackupRotator.markerFileName))
        try Data("readme".utf8).write(to: archive.appendingPathComponent("README.md"))
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func directoryNames(_ archive: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).compactMap { url in
            let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
            guard type == .typeDirectory else { return nil }
            return url.lastPathComponent
        }.sorted()
    }
}
