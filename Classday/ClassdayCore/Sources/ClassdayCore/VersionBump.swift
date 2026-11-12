import Foundation

public struct VersionBumpReport: Equatable, Sendable {
    public var previousVersion: String
    public var newVersion: String
    public var previousBuild: Int
    public var newBuild: Int
    public var rotation: BackupRotationReport

    public init(previousVersion: String, newVersion: String, previousBuild: Int, newBuild: Int, rotation: BackupRotationReport) {
        self.previousVersion = previousVersion
        self.newVersion = newVersion
        self.previousBuild = previousBuild
        self.newBuild = newBuild
        self.rotation = rotation
    }
}

public enum VersionBumpError: Error, Equatable, CustomStringConvertible {
    case missingCommittedVersion
    case invalidVersion(String)
    case invalidBuild(String)
    case sameVersion(String)
    case prepareFailed(String)

    public var description: String {
        switch self {
        case .missingCommittedVersion:
            return "The committed tree has no VERSION file. Refusing to invent a previous snapshot."
        case let .invalidVersion(value):
            return "Version must look like 1.2.3, got \(value)."
        case let .invalidBuild(value):
            return "BUILD must be a positive integer, got \(value)."
        case let .sameVersion(value):
            return "Refusing to bump: the committed version is already \(value)."
        case let .prepareFailed(message):
            return "Could not prepare the committed snapshot: \(message)"
        }
    }
}

/// Version updates go through `apply`, which archives the committed tree and only then writes the new version.
/// Ordinary edits are not archived. Deletes stay inside `VersionArchive`.
public enum VersionBump {
    public static let versionFileName = "VERSION"
    public static let buildFileName = "BUILD"
    public static let stampFileName = ".classday-snapshot-version"
    /// Trees from before BUILD existed shipped CFBundleVersion 1.
    public static let historicalBuild = 1

    public static func isValid(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }

    public static func readVersion(in tree: URL) -> String? {
        let url = tree.appendingPathComponent(versionFileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard isValid(line) else { return nil }
        return line
    }

    /// Positive integer, or nil when the file is absent or not a canonical integer (`1`, not `01` or `0`).
    public static func readBuild(in tree: URL) -> Int? {
        let url = tree.appendingPathComponent(buildFileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let value = Int(line), value > 0, String(value) == line else { return nil }
        return value
    }

    /// Archives `committedTree` into `workingTree/VersionArchive/previous`, then writes `newVersion` and the next build number.
    /// The committed tree is the source. A dirty working tree is not what gets copied.
    /// A missing BUILD file counts as build 1, which is what every release used before the file existed.
    public static func apply(
        committedTree: URL,
        workingTree: URL,
        newVersion: String,
        fileManager: FileManager = .default
    ) throws -> VersionBumpReport {
        let requested = newVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(requested) else { throw VersionBumpError.invalidVersion(newVersion) }
        guard let previousVersion = readVersion(in: committedTree) else {
            throw VersionBumpError.missingCommittedVersion
        }
        guard previousVersion != requested else { throw VersionBumpError.sameVersion(requested) }
        let previousBuild = try committedBuild(in: committedTree, fileManager: fileManager)

        let preparation = fileManager.temporaryDirectory.appendingPathComponent("classday-bump-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: preparation) }
        do {
            try copyCommittedTree(from: committedTree, to: preparation, fileManager: fileManager)
            let stamp = preparation.appendingPathComponent(stampFileName)
            try Data((previousVersion + "\n").utf8).write(to: stamp)
            let recorded = readVersion(in: preparation)
            guard recorded == previousVersion else {
                throw VersionBumpError.prepareFailed("snapshot VERSION was \(recorded ?? "missing"), expected \(previousVersion)")
            }
        } catch let error as VersionBumpError {
            throw error
        } catch {
            throw VersionBumpError.prepareFailed(error.localizedDescription)
        }

        let archive = workingTree.appendingPathComponent(BackupRotator.managedDirectoryName, isDirectory: true)
        let rotation = try BackupRotator.rotate(source: preparation, archive: archive, fileManager: fileManager)
        let versionURL = workingTree.appendingPathComponent(versionFileName)
        try Data((requested + "\n").utf8).write(to: versionURL)
        let newBuild = previousBuild + 1
        let buildURL = workingTree.appendingPathComponent(buildFileName)
        try Data("\(newBuild)\n".utf8).write(to: buildURL)
        return VersionBumpReport(
            previousVersion: previousVersion,
            newVersion: requested,
            previousBuild: previousBuild,
            newBuild: newBuild,
            rotation: rotation
        )
    }

    private static func committedBuild(in tree: URL, fileManager: FileManager) throws -> Int {
        let url = tree.appendingPathComponent(buildFileName)
        guard fileManager.fileExists(atPath: url.path) else { return historicalBuild }
        guard let value = readBuild(in: tree) else {
            let raw = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw VersionBumpError.invalidBuild(raw)
        }
        return value
    }

    private static func copyCommittedTree(from: URL, to: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: to, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(at: from, includingPropertiesForKeys: nil, options: [])
        for child in children {
            let kind = fileType(child, fileManager)
            if kind == .typeSymbolicLink { continue }
            let name = child.lastPathComponent
            if kind == .typeDirectory, BackupRotator.excludedDirectoryNames.contains(name) { continue }
            let destination = to.appendingPathComponent(name, isDirectory: kind == .typeDirectory)
            if kind == .typeDirectory {
                try copyCommittedTree(from: child, to: destination, fileManager: fileManager)
            } else {
                try fileManager.copyItem(at: child, to: destination)
            }
        }
    }

    private static func fileType(_ url: URL, _ fileManager: FileManager) -> FileAttributeType? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }
}
