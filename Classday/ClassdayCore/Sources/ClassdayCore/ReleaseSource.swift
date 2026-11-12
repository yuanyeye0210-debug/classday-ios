import CoreFoundation
import Foundation

public struct SideStoreAppVersion: Equatable, Sendable {
    public var version: String
    public var buildVersion: String?
    public var date: String?
    public var localizedDescription: String?
    public var downloadURL: URL
    public var size: Int?
    public var minOSVersion: String?

    public init(
        version: String,
        buildVersion: String?,
        date: String?,
        localizedDescription: String?,
        downloadURL: URL,
        size: Int?,
        minOSVersion: String?
    ) {
        self.version = version
        self.buildVersion = buildVersion
        self.date = date
        self.localizedDescription = localizedDescription
        self.downloadURL = downloadURL
        self.size = size
        self.minOSVersion = minOSVersion
    }
}

public struct SideStoreListedApp: Equatable, Sendable {
    public var name: String
    public var bundleIdentifier: String
    public var versions: [SideStoreAppVersion]

    public init(name: String, bundleIdentifier: String, versions: [SideStoreAppVersion]) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.versions = versions
    }
}

public struct SideStoreSource: Equatable, Sendable {
    public var name: String
    public var apps: [SideStoreListedApp]

    public init(name: String, apps: [SideStoreListedApp]) {
        self.name = name
        self.apps = apps
    }
}

public struct UpdateOffer: Equatable, Sendable {
    public var version: String
    public var buildVersion: String?
    public var notes: String?
    public var ipaURL: URL
    public var sideStoreURL: URL

    public init(version: String, buildVersion: String?, notes: String?, ipaURL: URL, sideStoreURL: URL) {
        self.version = version
        self.buildVersion = buildVersion
        self.notes = notes
        self.ipaURL = ipaURL
        self.sideStoreURL = sideStoreURL
    }
}

public enum ReleaseSourceError: Error, Equatable, CustomStringConvertible {
    case malformed
    case missingApp(String)

    public var description: String {
        switch self {
        case .malformed:
            return "The SideStore source is not a usable apps.json."
        case let .missingApp(bundleIdentifier):
            return "The SideStore source has no app \(bundleIdentifier)."
        }
    }
}

/// Marketing-version and build-number comparison used by the in-app update check.
/// Numeric dot components match the previous Settings comparison: a non-numeric piece counts as 0.
public enum ReleaseVersion {
    public static func isNewer(_ marketing: String, than other: String) -> Bool {
        let left = components(marketing)
        let right = components(other)
        for index in 0..<max(left.count, right.count) {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    /// Newer marketing version wins. Equal marketing versions compare `CFBundleVersion` when both are present.
    public static func isNewer(_ marketing: String, build: String?, than other: String, build otherBuild: String?) -> Bool {
        if isNewer(marketing, than: other) { return true }
        if isNewer(other, than: marketing) { return false }
        guard let build, let otherBuild else { return false }
        return isNewer(build, than: otherBuild)
    }

    private static func components(_ value: String) -> [Int] {
        value.split(separator: ".").map { Int($0) ?? 0 }
    }
}

public enum ReleaseChannel {
    public static let bundleIdentifier = "com.classday.app"
    public static let sourceURL = URL(string: "https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/apps.json")!

    /// `sidestore://source?url=...` adds or opens the Classday source. SideStore documents this scheme.
    public static func sideStoreSourceURL(source: URL = sourceURL) -> URL? {
        var components = URLComponents()
        components.scheme = "sidestore"
        components.host = "source"
        components.queryItems = [URLQueryItem(name: "url", value: source.absoluteString)]
        return components.url
    }

    public static func parse(_ data: Data) throws -> SideStoreSource {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReleaseSourceError.malformed
        }
        guard let name = string(root["name"]), let rawApps = root["apps"] as? [Any] else {
            throw ReleaseSourceError.malformed
        }
        var apps: [SideStoreListedApp] = []
        for item in rawApps {
            guard let object = item as? [String: Any] else { throw ReleaseSourceError.malformed }
            guard let appName = string(object["name"]), let bundle = string(object["bundleIdentifier"]) else {
                throw ReleaseSourceError.malformed
            }
            let versions = (object["versions"] as? [Any] ?? []).compactMap(parseVersion)
            apps.append(SideStoreListedApp(name: appName, bundleIdentifier: bundle, versions: versions))
        }
        return SideStoreSource(name: name, apps: apps)
    }

    /// The newest installable version that is newer than the installed app, or nil when nothing newer is offered.
    /// Versions whose `minOSVersion` is above `deviceOS` are skipped. A nil `deviceOS` does not filter.
    /// SideStore treats the first listed version as latest; this comparison uses the version numbers so a
    /// mis-ordered source still offers the newer build. The publisher still writes newest first.
    public static func updateOffer(
        in source: SideStoreSource,
        bundleIdentifier: String = bundleIdentifier,
        currentMarketing: String,
        currentBuild: String? = nil,
        deviceOS: String? = nil,
        sourceURL: URL = sourceURL
    ) throws -> UpdateOffer? {
        guard let app = source.apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            throw ReleaseSourceError.missingApp(bundleIdentifier)
        }
        var best: SideStoreAppVersion?
        for version in app.versions {
            guard compatible(version, deviceOS: deviceOS) else { continue }
            if let current = best {
                if ReleaseVersion.isNewer(version.version, build: version.buildVersion, than: current.version, build: current.buildVersion) {
                    best = version
                }
            } else {
                best = version
            }
        }
        guard let best,
              ReleaseVersion.isNewer(best.version, build: best.buildVersion, than: currentMarketing, build: currentBuild),
              let sideStoreURL = sideStoreSourceURL(source: sourceURL) else {
            return nil
        }
        return UpdateOffer(
            version: best.version,
            buildVersion: best.buildVersion,
            notes: best.localizedDescription,
            ipaURL: best.downloadURL,
            sideStoreURL: sideStoreURL
        )
    }

    private static func compatible(_ version: SideStoreAppVersion, deviceOS: String?) -> Bool {
        guard let deviceOS, let minimum = version.minOSVersion else { return true }
        return !ReleaseVersion.isNewer(minimum, than: deviceOS)
    }

    private static func parseVersion(_ value: Any) -> SideStoreAppVersion? {
        guard let object = value as? [String: Any],
              let version = string(object["version"]),
              let download = string(object["downloadURL"]),
              let downloadURL = URL(string: download) else {
            return nil
        }
        return SideStoreAppVersion(
            version: version,
            buildVersion: string(object["buildVersion"]),
            date: string(object["date"]),
            localizedDescription: string(object["localizedDescription"]),
            downloadURL: downloadURL,
            size: int(object["size"]),
            minOSVersion: string(object["minOSVersion"])
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber, !isJSONBool(number) {
            return number.stringValue
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, !isJSONBool(number) {
            return number.intValue
        }
        if let text = value as? String, let parsed = Int(text) {
            return parsed
        }
        return nil
    }

    /// JSON `true`/`false` bridge to NSNumber. A real number must still be accepted.
    private static func isJSONBool(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
