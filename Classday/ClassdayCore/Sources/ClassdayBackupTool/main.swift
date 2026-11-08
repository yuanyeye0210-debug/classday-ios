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

        rotate snapshots PATH into PATH's managed VersionArchive/previous and deletes older
        version directories inside that archive only. It never rewrites git history.
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
