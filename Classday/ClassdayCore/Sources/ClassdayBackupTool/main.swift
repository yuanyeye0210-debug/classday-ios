import Foundation
import ClassdayCore

private enum ExitCode: Int32 {
    case ok = 0
    case usage = 2
    case failed = 3
}

private func fail(_ message: String, _ code: ExitCode) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code.rawValue)
}

private func usage() -> Never {
    fail(
        """
        usage:
          classday-backup dump-demo
          classday-backup inspect --source PATH --archive PATH
          classday-backup rotate --source PATH --archive PATH
          classday-backup bump --committed PATH --working PATH --to X.Y.Z

        bump archives the committed tree into working/VersionArchive/previous, then writes
        X.Y.Z to working/VERSION and the next integer to working/BUILD. Version updates
        must use Tools/bump-version.sh so the snapshot is the last commit, taken before
        the version files change.
        rotate and bump delete directories only inside the marked VersionArchive.
        They never rewrite git history.
        """,
        .usage
    )
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch command {
case "dump-demo":
    do {
        let data = try StoreCodec.encode(DemoData.makeDocument())
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        fail(String(describing: error), .failed)
    }
case "bump":
    var committed: String?
    var working: String?
    var newVersion: String?
    var index = 1
    while index < arguments.count {
        let flag = arguments[index]
        guard index + 1 < arguments.count else { usage() }
        let value = arguments[index + 1]
        switch flag {
        case "--committed": committed = value
        case "--working": working = value
        case "--to": newVersion = value
        default: usage()
        }
        index += 2
    }
    guard let committed, let working, let newVersion else { usage() }
    do {
        let report = try VersionBump.apply(
            committedTree: URL(fileURLWithPath: committed),
            workingTree: URL(fileURLWithPath: working),
            newVersion: newVersion
        )
        let removed = report.rotation.removedRelativePaths.isEmpty
            ? "(none)"
            : report.rotation.removedRelativePaths.joined(separator: ", ")
        let message = """
        mode: bump
        previous-version: \(report.previousVersion)
        new-version: \(report.newVersion)
        previous-build: \(report.previousBuild)
        new-build: \(report.newBuild)
        copied: \(report.rotation.copiedFileCount)
        removed: \(removed)
        scope: VersionArchive only
        """
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    } catch let error as VersionBumpError {
        fail(error.description, .failed)
    } catch let error as BackupRotationError {
        fail(error.description, .failed)
    } catch {
        fail(error.localizedDescription, .failed)
    }
case "inspect", "rotate":
    var source: String?
    var archive: String?
    var index = 1
    while index < arguments.count {
        let flag = arguments[index]
        guard index + 1 < arguments.count else { usage() }
        let value = arguments[index + 1]
        switch flag {
        case "--source": source = value
        case "--archive": archive = value
        default: usage()
        }
        index += 2
    }
    guard let source, let archive else { usage() }
    let sourceURL = URL(fileURLWithPath: source)
    let archiveURL = URL(fileURLWithPath: archive)
    do {
        let report: BackupRotationReport
        if command == "inspect" {
            report = try BackupRotator.inspect(source: sourceURL, archive: archiveURL)
        } else {
            report = try BackupRotator.rotate(source: sourceURL, archive: archiveURL)
        }
        let removed = report.removedRelativePaths.isEmpty ? "(none)" : report.removedRelativePaths.joined(separator: ", ")
        let message = """
        mode: \(report.mode)
        copied: \(report.copiedFileCount)
        previous: \(report.previousRelativePath)
        removed: \(removed)
        scope: VersionArchive only
        """
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    } catch let error as BackupRotationError {
        fail(error.description, .failed)
    } catch {
        fail(error.localizedDescription, .failed)
    }
default:
    usage()
}
