import Foundation

/// One reporting event for version-distribution reporting, per the
/// classday-releases README contract. The wire name is `rawValue`;
/// `downloadFailed` is the only case that carries an `error` string in the
/// payload, and it is a human-readable reason with no user data.
public enum UpdateReportEvent: Equatable, Sendable {
    case updateCheck
    case downloadStarted
    case downloadSucceeded
    case downloadFailed(reason: String)
    case installed

    public var rawValue: String {
        switch self {
        case .updateCheck: return "update_check"
        case .downloadStarted: return "download_started"
        case .downloadSucceeded: return "download_succeeded"
        case .downloadFailed: return "download_failed"
        case .installed: return "installed"
        }
    }
}

/// The version-distribution reporting payload: exactly the README fields —
/// `app_version`, `platform` (`"ios"`), `build`, `event`, `error` (only for
/// `download_failed`), `timestamp` (UTC ISO `YYYY-MM-DDTHH:MM:SSZ`). No
/// device identifier, no user data, ever.
///
/// Pure value type in Core — the actual network sender is the App layer
/// (Task 6); this type only builds the payload, gates on the endpoint, and
/// detects an install. Sending is disabled by default: there is no
/// collector endpoint yet, so `isEnabled` is false until one is configured.
public struct UpdateReport: Equatable, Sendable {
    public let event: UpdateReportEvent
    public let appVersion: String
    public let build: String
    public let timestamp: Date

    public init(event: UpdateReportEvent, appVersion: String, build: String, timestamp: Date = Date()) {
        self.event = event
        self.appVersion = appVersion
        self.build = build
        self.timestamp = timestamp
    }

    /// The payload dictionary, ready for `JSONSerialization`. Exactly the
    /// README fields; `error` is present only for `.downloadFailed`.
    public var json: [String: Any] {
        var payload: [String: Any] = [
            "app_version": appVersion,
            "platform": "ios",
            "build": build,
            "event": event.rawValue,
            "timestamp": Self.formatTimestamp(timestamp),
        ]
        if case let .downloadFailed(reason) = event {
            payload["error"] = reason
        }
        return payload
    }

    /// Whether reporting is enabled for `endpoint`: false when no endpoint
    /// is configured (nil or empty). There is no collector yet, so this is
    /// false by default; enabling it later is filling in one constant.
    public static func isEnabled(endpoint: String?) -> Bool {
        guard let endpoint else { return false }
        return !endpoint.isEmpty
    }

    /// The `.installed` event for launch, or nil when no install should be
    /// reported: `storedVersion` is nil on first launch (nothing to compare
    /// against — the stored version is persisted after this check), and
    /// equal versions mean the app was not newly installed. Any difference
    /// — upgrade or downgrade — fires, per the design ("stored last-reported
    /// version differs from the current version").
    public static func installedEventIfNeeded(storedVersion: String?, currentVersion: String) -> UpdateReportEvent? {
        guard let storedVersion, storedVersion != currentVersion else { return nil }
        return .installed
    }

    /// UTC `YYYY-MM-DDTHH:MM:SSZ`, no fractional seconds. A fresh formatter
    /// per call (reporting is infrequent) so no shared mutable formatter
    /// state is involved; `en_US_POSIX` + explicit UTC keep the output
    /// identical regardless of the device locale or time zone.
    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }
}
