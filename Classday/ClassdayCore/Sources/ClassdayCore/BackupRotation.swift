import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct BackupRotationReport: Equatable, Sendable {
    public var mode: String
    public var copiedFileCount: Int
    public var removedRelativePaths: [String]
    public var previousRelativePath: String

    public init(mode: String, copiedFileCount: Int, removedRelativePaths: [String], previousRelativePath: String) {
        self.mode = mode
        self.copiedFileCount = copiedFileCount
        self.removedRelativePaths = removedRelativePaths
        self.previousRelativePath = previousRelativePath
    }
}

public enum BackupRotationError: Error, Equatable, CustomStringConvertible {
    case archiveDirectoryName(expected: String, actual: String)
    case missingMarker
    case invalidMarker
    case sourceInsideArchive
    case identicalPaths
    case notADirectory(String)
    case escapedPath(String)
    case copyFailed(String)

    public var description: String {
        switch self {
        case let .archiveDirectoryName(expected, actual):
            return "备份目录名必须是 \(expected)，实际是 \(actual)。此工具只操作名为 VersionArchive 的托管目录。"
        case .missingMarker:
            return "VersionArchive 缺少标记文件 .classday-backup-root，已拒绝操作。"
        case .invalidMarker:
            return "VersionArchive 标记内容不正确，已拒绝操作。"
        case .sourceInsideArchive:
            return "源目录位于备份目录内部。为避免把备份再次备份，已拒绝操作。"
        case .identicalPaths:
            return "源目录和备份目录不能是同一路径。"
        case let .notADirectory(path):
            return "路径不是目录：\(path)"
        case let .escapedPath(path):
            return "路径逃出了 VersionArchive，已拒绝删除：\(path)"
        case let .copyFailed(message):
            return "备份复制失败：\(message)"
        }
    }
}

/// Copies the given source tree into `VersionArchive/previous` and deletes older version directories
/// inside that archive only. Version bumps must pass the last committed tree via `VersionBump`, not a working tree that already has the new version.
public enum BackupRotator {
    public static let managedDirectoryName = "VersionArchive"
    public static let markerFileName = ".classday-backup-root"
    public static let markerContents = "classday-version-archive-v1\n"
    public static let previousDirectoryName = "previous"
    public static let excludedDirectoryNames: Set<String> = [
        "VersionArchive",
        ".git",
        ".build",
        ".swiftpm",
        "DerivedData",
        "xcuserdata",
        "__pycache__",
    ]

    public static func inspect(
        source: URL,
        archive: URL,
        fileManager: FileManager = .default
    ) throws -> BackupRotationReport {
        let context = try Context(source: source, archive: archive, fileManager: fileManager)
        return BackupRotationReport(
            mode: "inspect",
            copiedFileCount: try context.countCopyableFiles(),
            removedRelativePaths: try context.removalCandidates(),
            previousRelativePath: previousDirectoryName
        )
    }

    public static func rotate(
        source: URL,
        archive: URL,
        fileManager: FileManager = .default
    ) throws -> BackupRotationReport {
        let context = try Context(source: source, archive: archive, fileManager: fileManager)
        let copied = try context.countCopyableFiles()
        let removed = try context.removalCandidates()
        let staging = context.archive.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try context.copyTree(from: context.source, to: staging)
            let previous = context.archive.appendingPathComponent(previousDirectoryName, isDirectory: true)
            let retiring = context.archive.appendingPathComponent(".retiring-\(UUID().uuidString)", isDirectory: true)
            if context.fileManager.fileExists(atPath: previous.path) {
                try context.fileManager.moveItem(at: previous, to: retiring)
            }
            do {
                try context.fileManager.moveItem(at: staging, to: previous)
            } catch {
                if context.fileManager.fileExists(atPath: retiring.path),
                   !context.fileManager.fileExists(atPath: previous.path) {
                    try? context.fileManager.moveItem(at: retiring, to: previous)
                }
                throw BackupRotationError.copyFailed(error.localizedDescription)
            }
            if context.fileManager.fileExists(atPath: retiring.path) {
                try context.removeTree(retiring)
            }
            try context.sweepExtraDirectories()
        } catch {
            if context.fileManager.fileExists(atPath: staging.path) {
                try? context.removeTree(staging)
            }
            throw error
        }
        return BackupRotationReport(
            mode: "rotate",
            copiedFileCount: copied,
            removedRelativePaths: removed,
            previousRelativePath: previousDirectoryName
        )
    }

    struct Context {
        var source: URL
        var archive: URL
        var sourceReal: String
        var archiveReal: String
        var fileManager: FileManager

        init(source: URL, archive: URL, fileManager: FileManager) throws {
            let sourceURL = source.standardizedFileURL.resolvingSymlinksInPath()
            let archiveURL = archive.standardizedFileURL.resolvingSymlinksInPath()
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw BackupRotationError.notADirectory(sourceURL.path)
            }
            guard fileManager.fileExists(atPath: archiveURL.path) else {
                throw BackupRotationError.notADirectory(archiveURL.path)
            }
            var sourceDir: ObjCBool = false
            var archiveDir: ObjCBool = false
            _ = fileManager.fileExists(atPath: sourceURL.path, isDirectory: &sourceDir)
            _ = fileManager.fileExists(atPath: archiveURL.path, isDirectory: &archiveDir)
            guard sourceDir.boolValue else { throw BackupRotationError.notADirectory(sourceURL.path) }
            guard archiveDir.boolValue else { throw BackupRotationError.notADirectory(archiveURL.path) }
            guard archiveURL.lastPathComponent == BackupRotator.managedDirectoryName else {
                throw BackupRotationError.archiveDirectoryName(
                    expected: BackupRotator.managedDirectoryName,
                    actual: archiveURL.lastPathComponent
                )
            }
            let marker = archiveURL.appendingPathComponent(BackupRotator.markerFileName)
            guard fileManager.fileExists(atPath: marker.path) else {
                throw BackupRotationError.missingMarker
            }
            let payload = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
            guard payload == BackupRotator.markerContents else {
                throw BackupRotationError.invalidMarker
            }
            if sourceURL.path == archiveURL.path {
                throw BackupRotationError.identicalPaths
            }
            if sourceURL.path.hasPrefix(archiveURL.path + "/") {
                throw BackupRotationError.sourceInsideArchive
            }
            self.source = sourceURL
            self.archive = archiveURL
            self.sourceReal = sourceURL.path
            self.archiveReal = archiveURL.path
            self.fileManager = fileManager
        }

        func countCopyableFiles() throws -> Int {
            var count = 0
            try walk(source) { url, isDirectory in
                if !isDirectory { count += 1 }
            }
            return count
        }

        func removalCandidates() throws -> [String] {
            try directChildren().compactMap { child in
                let name = child.lastPathComponent
                if isSymlink(child) { return name }
                if isRealDirectory(child) { return name }
                return nil
            }.sorted()
        }

        func copyTree(from: URL, to: URL) throws {
            try fileManager.createDirectory(at: to, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(
                at: from,
                includingPropertiesForKeys: nil,
                options: []
            )
            for child in children {
                if isSymlink(child) { continue }
                let name = child.lastPathComponent
                if isRealDirectory(child), BackupRotator.excludedDirectoryNames.contains(name) {
                    continue
                }
                let resolved = child.resolvingSymlinksInPath().path
                if resolved == archiveReal || resolved.hasPrefix(archiveReal + "/") {
                    continue
                }
                let destination = to.appendingPathComponent(name, isDirectory: isRealDirectory(child))
                if isRealDirectory(child) {
                    try copyTree(from: child, to: destination)
                } else {
                    do {
                        try fileManager.copyItem(at: child, to: destination)
                    } catch {
                        throw BackupRotationError.copyFailed(error.localizedDescription)
                    }
                }
            }
        }

        func sweepExtraDirectories() throws {
            for child in try directChildren() {
                if isSymlink(child) {
                    try removeSymlink(child)
                    continue
                }
                guard isRealDirectory(child) else { continue }
                if child.lastPathComponent == BackupRotator.previousDirectoryName { continue }
                try removeTree(child)
            }
        }

        func removeTree(_ url: URL) throws {
            try assertLexicalInside(url)
            if isSymlink(url) {
                try removeSymlink(url)
                return
            }
            if isRealDirectory(url) {
                let children = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
                for child in children {
                    try removeTree(child)
                }
                try assertResolvedInside(url)
                try fileManager.removeItem(at: url)
                return
            }
            try assertResolvedInside(url)
            try fileManager.removeItem(at: url)
        }

        func removeSymlink(_ url: URL) throws {
            try assertLexicalInside(url)
            let result = url.path.withCString { unlink($0) }
            if result != 0 {
                throw BackupRotationError.copyFailed("无法删除符号链接 \(url.lastPathComponent)")
            }
        }

        func walk(_ url: URL, visit: (URL, Bool) throws -> Void) throws {
            if isSymlink(url) { return }
            let resolved = url.resolvingSymlinksInPath().path
            if resolved == archiveReal || resolved.hasPrefix(archiveReal + "/") { return }
            let directory = isRealDirectory(url)
            if directory, BackupRotator.excludedDirectoryNames.contains(url.lastPathComponent), url.path != source.path {
                return
            }
            if url.path != source.path {
                try visit(url, directory)
            }
            guard directory else { return }
            let children = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            for child in children {
                try walk(child, visit: visit)
            }
        }

        func directChildren() throws -> [URL] {
            try fileManager.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil, options: [])
        }

        func isSymlink(_ url: URL) -> Bool {
            guard let type = fileType(url) else { return false }
            return type == .typeSymbolicLink
        }

        func isRealDirectory(_ url: URL) -> Bool {
            guard let type = fileType(url) else { return false }
            return type == .typeDirectory
        }

        func fileType(_ url: URL) -> FileAttributeType? {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return attributes?[.type] as? FileAttributeType
        }

        func assertLexicalInside(_ url: URL) throws {
            let path = url.standardizedFileURL.path
            guard path == archive.path || path.hasPrefix(archive.path + "/") else {
                throw BackupRotationError.escapedPath(path)
            }
        }

        func assertResolvedInside(_ url: URL) throws {
            try assertLexicalInside(url)
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved == archiveReal || resolved.hasPrefix(archiveReal + "/") else {
                throw BackupRotationError.escapedPath(resolved)
            }
        }
    }
}
