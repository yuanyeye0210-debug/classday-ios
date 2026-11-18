import Foundation
import XCTest
import ClassdayCore

final class UpdateReportTests: XCTestCase {
    /// 2026-11-12T14:00:00Z, built from UTC components so the test does not
    /// depend on a magic epoch constant.
    private var fixedDate: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 11
        components.day = 12
        components.hour = 14
        components.minute = 0
        components.second = 0
        guard let date = components.date else {
            preconditionFailure("Invalid fixed test date")
        }
        return date
    }

    // MARK: - Payload (brief Step 1)

    func testPayloadHasExactlyTheREADMEFields() {
        let payload = UpdateReport(event: .updateCheck, appVersion: "2.7.1", build: "1", timestamp: fixedDate).json
        XCTAssertEqual(Set(payload.keys), ["app_version", "platform", "build", "event", "timestamp"])
        XCTAssertEqual(payload["app_version"] as? String, "2.7.1")
        XCTAssertEqual(payload["platform"] as? String, "ios")
        XCTAssertEqual(payload["build"] as? String, "1")
        XCTAssertEqual(payload["event"] as? String, "update_check")
        XCTAssertEqual(payload["timestamp"] as? String, "2026-11-12T14:00:00Z")
        XCTAssertNil(payload["error"])
        XCTAssertNil(payload["device_id"])
    }

    func testDownloadFailedCarriesError() {
        let payload = UpdateReport(event: .downloadFailed(reason: "timeout"), appVersion: "2.7.1", build: "1", timestamp: fixedDate).json
        XCTAssertEqual(Set(payload.keys), ["app_version", "platform", "build", "event", "error", "timestamp"])
        XCTAssertEqual(payload["event"] as? String, "download_failed")
        XCTAssertEqual(payload["error"] as? String, "timeout")
    }

    func testNonFailedEventsCarryNoError() {
        for event in [UpdateReportEvent.updateCheck, .downloadStarted, .downloadSucceeded, .installed] as [UpdateReportEvent] {
            let payload = UpdateReport(event: event, appVersion: "2.7.1", build: "1", timestamp: fixedDate).json
            XCTAssertNil(payload["error"], "event \(event) must not carry an error field")
        }
    }

    func testEventRawValuesMatchREADME() {
        XCTAssertEqual(UpdateReportEvent.updateCheck.rawValue, "update_check")
        XCTAssertEqual(UpdateReportEvent.downloadStarted.rawValue, "download_started")
        XCTAssertEqual(UpdateReportEvent.downloadSucceeded.rawValue, "download_succeeded")
        XCTAssertEqual(UpdateReportEvent.installed.rawValue, "installed")
        XCTAssertEqual(UpdateReportEvent.downloadFailed(reason: "x").rawValue, "download_failed")
    }

    func testTimestampIsUTCWithoutFractionalSeconds() {
        // A date with fractional seconds and a non-UTC local zone must still
        // render as UTC seconds precision: the formatter, not the caller,
        // owns the format. The zone is set for real (restored afterwards),
        // not just claimed in this comment.
        let previousDefault = NSTimeZone.default
        NSTimeZone.default = TimeZone(secondsFromGMT: 8 * 3600)!
        defer { NSTimeZone.default = previousDefault }
        let date = fixedDate.addingTimeInterval(0.5)
        let payload = UpdateReport(event: .updateCheck, appVersion: "2.7.1", build: "1", timestamp: date).json
        XCTAssertEqual(payload["timestamp"] as? String, "2026-11-12T14:00:00Z")
    }

    // MARK: - Installed detection (brief Step 1)

    func testInstalledFiresOnlyOnVersionChange() {
        XCTAssertNil(UpdateReport.installedEventIfNeeded(storedVersion: nil, currentVersion: "2.7.1"))
        XCTAssertNil(UpdateReport.installedEventIfNeeded(storedVersion: "2.7.1", currentVersion: "2.7.1"))
        XCTAssertNotNil(UpdateReport.installedEventIfNeeded(storedVersion: "2.7.0", currentVersion: "2.7.1"))
    }

    func testInstalledEventIsInstalled() {
        XCTAssertEqual(
            UpdateReport.installedEventIfNeeded(storedVersion: "2.7.0", currentVersion: "2.7.1"),
            .installed
        )
    }

    func testInstalledFiresOnDowngrade() {
        // Any difference fires, per the design ("stored last-reported
        // version differs from the current version") — a downgrade is
        // still a fresh install of the running version.
        XCTAssertEqual(
            UpdateReport.installedEventIfNeeded(storedVersion: "2.7.1", currentVersion: "2.7.0"),
            .installed
        )
    }

    // MARK: - Enabled gate (brief Step 1)

    func testSenderDisabledWithoutEndpoint() {
        XCTAssertFalse(UpdateReport.isEnabled(endpoint: nil))
    }

    func testSenderDisabledWithEmptyEndpoint() {
        XCTAssertFalse(UpdateReport.isEnabled(endpoint: ""))
    }

    func testSenderEnabledWithEndpoint() {
        XCTAssertTrue(UpdateReport.isEnabled(endpoint: "https://example.com/collect"))
    }
}
