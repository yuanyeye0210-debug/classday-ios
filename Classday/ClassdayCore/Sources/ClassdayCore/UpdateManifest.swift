import Foundation

/// Errors raised when a `latest.json` manifest is unusable. Any of these means
/// the caller falls back to the GitHub Releases API path.
public enum UpdateManifestError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(Int)
    case missingIOSChannel
    case latestReleaseNotFound(String)
    /// A release entry names a download that can never verify: a
    /// non-positive `size`, or a `sha256` that is not 64 hex characters.
    /// Rejecting at decode time makes the caller fall back to the API
    /// path instead of attempting a futile download.
    case invalidReleaseSize(version: String, size: Int)
    case invalidReleaseSHA256(version: String, sha256: String)

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Unsupported manifest schema_version \(version), expected \(UpdateManifest.supportedSchemaVersion)."
        case .missingIOSChannel:
            return "Manifest has no iOS channel."
        case let .latestReleaseNotFound(version):
            return "Manifest latest version \(version) has no matching release."
        case let .invalidReleaseSize(version, size):
            return "Release \(version) has invalid size \(size), expected a positive byte count."
        case let .invalidReleaseSHA256(version, sha256):
            return "Release \(version) has invalid sha256 \(sha256), expected 64 hex characters."
        }
    }
}

/// One release entry in an iOS channel of `latest.json`.
public struct ReleaseEntry: Decodable, Equatable, Sendable {
    public var version: String
    public var file: String
    public var size: Int
    public var sha256: String
    public var downloadURL: URL
    public var publishedAt: String
    public var mirrors: [String]?

    public init(
        version: String,
        file: String,
        size: Int,
        sha256: String,
        downloadURL: URL,
        publishedAt: String,
        mirrors: [String]? = nil
    ) {
        self.version = version
        self.file = file
        self.size = size
        self.sha256 = sha256
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
        self.mirrors = mirrors
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case file
        case size
        case sha256
        case downloadURL = "download_url"
        case publishedAt = "published_at"
        case mirrors
    }

    /// Decodes one release entry, rejecting at decode time a `size` that
    /// can never verify (`<= 0`) or a `sha256` that is not 64 hex
    /// characters: such a manifest is unusable, so the caller falls back
    /// to the API path instead of attempting a futile download. The
    /// memberwise `init` above stays for hand-built values (tests); only
    /// the decode path enforces the rules.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        file = try container.decode(String.self, forKey: .file)
        size = try container.decode(Int.self, forKey: .size)
        sha256 = try container.decode(String.self, forKey: .sha256)
        downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        mirrors = try container.decodeIfPresent([String].self, forKey: .mirrors)
        guard size > 0 else {
            throw UpdateManifestError.invalidReleaseSize(version: version, size: size)
        }
        guard sha256.count == 64, sha256.allSatisfy(\.isHexDigit) else {
            throw UpdateManifestError.invalidReleaseSHA256(version: version, sha256: sha256)
        }
    }
}

/// The `ios` channel of `latest.json`.
public struct iOSChannel: Decodable, Equatable, Sendable {
    public var latest: String
    public var previous: String?
    public var mandatory: Bool
    public var minSupportedVersion: String
    public var releases: [ReleaseEntry]

    public init(
        latest: String,
        previous: String? = nil,
        mandatory: Bool,
        minSupportedVersion: String,
        releases: [ReleaseEntry]
    ) {
        self.latest = latest
        self.previous = previous
        self.mandatory = mandatory
        self.minSupportedVersion = minSupportedVersion
        self.releases = releases
    }

    /// The release named by `latest`, or nil when `latest` names no release.
    public var latestRelease: ReleaseEntry? {
        releases.first { $0.version == latest }
    }

    private enum CodingKeys: String, CodingKey {
        case latest
        case previous
        case mandatory
        case minSupportedVersion = "min_supported_version"
        case releases
    }
}

/// The `android` channel of `latest.json`. This app does not consume it; the
/// type exists only so its presence or absence is visible. Its contents are
/// intentionally ignored when decoding.
public struct AndroidChannel: Decodable, Equatable, Sendable {
    public init() {}
}

/// The `channels` object of `latest.json`.
public struct UpdateChannels: Decodable, Equatable, Sendable {
    public var ios: iOSChannel?
    public var android: AndroidChannel?

    public init(ios: iOSChannel? = nil, android: AndroidChannel? = nil) {
        self.ios = ios
        self.android = android
    }
}

/// The decoded `latest.json` manifest from classday-releases.
/// Validation runs during decoding: an unusable manifest throws
/// `UpdateManifestError` instead of producing a value, so both the
/// `JSONDecoder` path and `decode(from:)` enforce the same rules.
public struct UpdateManifest: Decodable, Equatable, Sendable {
    /// The only schema version this client understands.
    public static let supportedSchemaVersion = 1

    public var schemaVersion: Int
    public var updatedAt: String
    public var channels: UpdateChannels

    public init(schemaVersion: Int, updatedAt: String, channels: UpdateChannels) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.channels = channels
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case channels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw UpdateManifestError.unsupportedSchemaVersion(schemaVersion)
        }
        let updatedAt = try container.decode(String.self, forKey: .updatedAt)
        let channels = try container.decode(UpdateChannels.self, forKey: .channels)
        guard let ios = channels.ios else {
            throw UpdateManifestError.missingIOSChannel
        }
        guard ios.latestRelease != nil else {
            throw UpdateManifestError.latestReleaseNotFound(ios.latest)
        }
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.channels = channels
    }

    /// Decodes a manifest from a JSON dictionary (e.g. produced by
    /// `JSONSerialization`). Validation applies exactly as for `JSONDecoder`.
    public static func decode(from json: [String: Any]) throws -> UpdateManifest {
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        return try JSONDecoder().decode(UpdateManifest.self, from: data)
    }
}

/// The outcome of comparing the installed version against a manifest.
/// Consumed by the update UI (Tasks 5 and 6).
public enum UpdateDecision: Equatable, Sendable {
    case upToDate
    case updateAvailable(release: ReleaseEntry, mandatory: Bool)
    case belowMinimumSupported(release: ReleaseEntry)
}

/// The pure update decision for `manifest` given the installed `current`
/// version (`CFBundleShortVersionString`).
///
/// Rules, in order:
/// 1. Current strictly below the channel's `min_supported_version`:
///    `.belowMinimumSupported` — this takes precedence over the mandatory
///    flag, so a too-old install is always blocking. Equal to the minimum
///    is still supported.
/// 2. Current strictly below `latest`: `.updateAvailable` with the
///    channel's `mandatory` flag carried through.
/// 3. Otherwise (equal to or newer than `latest`): `.upToDate`.
///
/// A manifest with no iOS channel or no latest release cannot happen
/// through decoding (both are validation errors), but a hand-built one
/// is treated as "no update known" rather than crashing the caller.
public func decision(manifest: UpdateManifest, current: String) -> UpdateDecision {
    guard let ios = manifest.channels.ios, let release = ios.latestRelease else {
        return .upToDate
    }
    if compareVersions(current, ios.minSupportedVersion) == .orderedAscending {
        return .belowMinimumSupported(release: release)
    }
    if compareVersions(current, ios.latest) == .orderedAscending {
        return .updateAvailable(release: release, mandatory: ios.mandatory)
    }
    return .upToDate
}

/// Numeric dot-separated version compare, the single compare in the
/// codebase: the App layer's `UpdateService.version(_:isNewerThan:)` (the
/// GitHub Releases API fallback) is implemented on top of this, so the
/// fallback and the manifest decision can never drift apart. Each segment
/// is compared as an integer (so 2.7.10 > 2.7.9), missing segments count
/// as 0, and a non-numeric segment counts as 0.
///
/// `VersionBump` has no compare to reuse — it only validates the `x.y.z`
/// shape (`isValid`).
public func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x > y ? .orderedDescending : .orderedAscending }
    }
    return .orderedSame
}
