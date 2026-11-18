import Foundation
import XCTest
import ClassdayCore

/// Fixture: verbatim copy of the live `latest.json` shape read 2026-11-12 14:05
/// (schema_version 1, ios latest 2.7.1, android null). Single source for both
/// the Data fixture and the dictionary fixture below.
private let liveManifestJSONString = """
{
    "channels": {
        "android": null,
        "ios": {
            "latest": "2.7.1",
            "mandatory": false,
            "min_supported_version": "2.7.0",
            "previous": "2.7.0",
            "releases": [
                {
                    "download_url": "https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/Classday-v2.7.1.ipa",
                    "file": "Classday-v2.7.1.ipa",
                    "published_at": "2026-11-11T16:41:55Z",
                    "sha256": "279da1ee71cb9f5cc9dd8bb44331c5d0b81030012e396101fe797505a7e1f603",
                    "size": 3965332,
                    "version": "2.7.1"
                },
                {
                    "download_url": "https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/Classday-v2.7.0.ipa",
                    "file": "Classday-v2.7.0.ipa",
                    "published_at": "2026-11-11T15:52:18Z",
                    "sha256": "7feb8ccafb198fb8a43b63ce58cb7fcbc1d018340f7210b0d37756a372460d99",
                    "size": 3968446,
                    "version": "2.7.0"
                }
            ]
        }
    },
    "schema_version": 1,
    "updated_at": "2026-11-12T09:34:21Z"
}
"""

private var liveManifestFixture: Data {
    Data(liveManifestJSONString.utf8)
}

private var liveManifestJSON: [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: liveManifestFixture),
          let json = object as? [String: Any] else {
        // A broken fixture must fail the test, not crash the test process.
        XCTFail("live manifest fixture is not a JSON object")
        return [:]
    }
    return json
}

final class UpdateManifestTests: XCTestCase {
    /// Unwraps a nested fixture dictionary, failing the test (not crashing
    /// the process) when the fixture structure has drifted.
    private func channelsDictionary(from json: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(json["channels"] as? [String: Any], "fixture channels must be a dictionary")
    }

    private func iosDictionary(from channels: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(channels["ios"] as? [String: Any], "fixture ios channel must be a dictionary")
    }

    private func releasesArray(from ios: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(ios["releases"] as? [[String: Any]], "fixture ios releases must be an array")
    }

    func testDecodesLiveManifestShape() throws {
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: liveManifestFixture)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.updatedAt, "2026-11-12T09:34:21Z")
        XCTAssertEqual(manifest.channels.ios?.latest, "2.7.1")
        XCTAssertEqual(manifest.channels.ios?.mandatory, false)
        XCTAssertEqual(manifest.channels.ios?.minSupportedVersion, "2.7.0")
        XCTAssertEqual(manifest.channels.ios?.previous, "2.7.0")
        XCTAssertEqual(manifest.channels.ios?.latestRelease?.file, "Classday-v2.7.1.ipa")
        XCTAssertEqual(
            manifest.channels.ios?.latestRelease?.downloadURL.absoluteString,
            "https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/Classday-v2.7.1.ipa"
        )
        XCTAssertEqual(manifest.channels.ios?.latestRelease?.publishedAt, "2026-11-11T16:41:55Z")
        XCTAssertEqual(manifest.channels.ios?.latestRelease?.sha256, "279da1ee71cb9f5cc9dd8bb44331c5d0b81030012e396101fe797505a7e1f603")
        XCTAssertEqual(manifest.channels.ios?.latestRelease?.size, 3965332)
        XCTAssertNil(manifest.channels.ios?.latestRelease?.mirrors)
        XCTAssertNil(manifest.channels.android)
    }

    func testRejectsWrongSchemaVersion() {
        var json = liveManifestJSON
        json["schema_version"] = 2
        XCTAssertThrowsError(try UpdateManifest.decode(from: json)) { error in
            guard case UpdateManifestError.unsupportedSchemaVersion(2) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRejectsLatestNotInReleases() throws {
        var json = liveManifestJSON
        // [String: Any] has no chained subscripts, so the nested update is
        // written out explicitly; the effect is identical to
        // json["channels"]["ios"]["latest"] = "9.9.9".
        var channels = try channelsDictionary(from: json)
        var ios = try iosDictionary(from: channels)
        ios["latest"] = "9.9.9"
        channels["ios"] = ios
        json["channels"] = channels
        XCTAssertThrowsError(try UpdateManifest.decode(from: json)) { error in
            guard case UpdateManifestError.latestReleaseNotFound("9.9.9") = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRejectsMissingIOSChannel() throws {
        // channels.ios set to null.
        var json = liveManifestJSON
        var channels = try channelsDictionary(from: json)
        channels["ios"] = NSNull()
        json["channels"] = channels
        XCTAssertThrowsError(try UpdateManifest.decode(from: json)) { error in
            guard case UpdateManifestError.missingIOSChannel = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        // channels.ios removed entirely — same rule, same error.
        json = liveManifestJSON
        channels = try channelsDictionary(from: json)
        channels.removeValue(forKey: "ios")
        json["channels"] = channels
        XCTAssertThrowsError(try UpdateManifest.decode(from: json)) { error in
            guard case UpdateManifestError.missingIOSChannel = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testDecodesAndroidChannelWhenPresent() throws {
        var json = liveManifestJSON
        var channels = try channelsDictionary(from: json)
        // Arbitrary fields: AndroidChannel ignores its contents; only its
        // presence is visible to this client.
        channels["android"] = ["latest": "9.9.9", "note": "ignored"]
        json["channels"] = channels
        let manifest = try UpdateManifest.decode(from: json)
        XCTAssertNotNil(manifest.channels.android)
        XCTAssertEqual(manifest.channels.ios?.latest, "2.7.1")
    }

    func testDecodesMirrorsWhenPresent() throws {
        var json = liveManifestJSON
        var channels = try channelsDictionary(from: json)
        var ios = try iosDictionary(from: channels)
        var releases = try releasesArray(from: ios)
        releases[0]["mirrors"] = ["https://mirror.example.com/Classday-v2.7.1.ipa"]
        ios["releases"] = releases
        channels["ios"] = ios
        json["channels"] = channels
        let manifest = try UpdateManifest.decode(from: json)
        XCTAssertEqual(
            manifest.channels.ios?.latestRelease?.mirrors,
            ["https://mirror.example.com/Classday-v2.7.1.ipa"]
        )
    }

    // MARK: - Update decision (Task 2)

    /// The live-shape fixture decoded. `try!` is safe here: the fixture is
    /// verbatim live `latest.json` and every decode test above proves it
    /// decodes; a failure would mean fixture drift, which those tests catch.
    private var manifest: UpdateManifest {
        try! JSONDecoder().decode(UpdateManifest.self, from: liveManifestFixture)
    }

    private func manifest(withMandatory mandatory: Bool) -> UpdateManifest {
        var copy = manifest
        guard var ios = copy.channels.ios else {
            XCTFail("fixture must have an iOS channel")
            return copy
        }
        ios.mandatory = mandatory
        copy.channels.ios = ios
        return copy
    }

    /// Same fixture with `latest` (and its release) renamed to `version`,
    /// so the compare can be exercised beyond the live 2.7.0/2.7.1 pair.
    private func manifest(latest version: String) -> UpdateManifest {
        var copy = manifest
        guard var ios = copy.channels.ios,
              var release = ios.latestRelease,
              let index = ios.releases.firstIndex(where: { $0.version == ios.latest })
        else {
            XCTFail("fixture must have an iOS channel with a latest release")
            return copy
        }
        release.version = version
        ios.releases[index] = release
        ios.latest = version
        copy.channels.ios = ios
        return copy
    }

    func testNoUpdateWhenCurrentEqualsLatest() {
        XCTAssertEqual(decision(manifest: manifest, current: "2.7.1"), .upToDate)
    }

    func testUpdateAvailableWhenCurrentIsOlder() {
        let d = decision(manifest: manifest, current: "2.7.0")
        XCTAssertEqual(d, .updateAvailable(release: manifest.channels.ios!.latestRelease!, mandatory: false))
    }

    func testMandatoryFlagCarriedThrough() {
        let mandatory = manifest(withMandatory: true)
        XCTAssertEqual(decision(manifest: mandatory, current: "2.7.0"), .updateAvailable(release: mandatory.channels.ios!.latestRelease!, mandatory: true))
    }

    func testBelowMinimumSupported() {
        XCTAssertEqual(decision(manifest: manifest, current: "2.6.0"), .belowMinimumSupported(release: manifest.channels.ios!.latestRelease!))
    }

    func testUpToDateWhenCurrentIsNewerThanLatest() {
        XCTAssertEqual(decision(manifest: manifest, current: "2.7.2"), .upToDate)
    }

    func testBelowMinimumSupportedTakesPrecedenceOverMandatory() {
        let mandatory = manifest(withMandatory: true)
        XCTAssertEqual(decision(manifest: mandatory, current: "2.6.0"), .belowMinimumSupported(release: mandatory.channels.ios!.latestRelease!))
    }

    func testCompareIsNumericNotLexicographic() {
        let tenManifest = manifest(latest: "2.7.10")
        XCTAssertEqual(
            decision(manifest: tenManifest, current: "2.7.9"),
            .updateAvailable(release: tenManifest.channels.ios!.latestRelease!, mandatory: false)
        )
        XCTAssertEqual(decision(manifest: tenManifest, current: "2.7.10"), .upToDate)
    }

    func testCompareTreatsMissingAndNonNumericSegmentsAsZero() {
        // "2.7" == "2.7.0": equal to the minimum, so not below-minimum,
        // but still below latest 2.7.1.
        XCTAssertEqual(
            decision(manifest: manifest, current: "2.7"),
            .updateAvailable(release: manifest.channels.ios!.latestRelease!, mandatory: false)
        )
        // Against a 2.7.0 latest, "2.7" is up to date (missing segment
        // counts as 0), and so is "2.7.x" (a non-numeric segment counts
        // as 0).
        let zeroManifest = manifest(latest: "2.7.0")
        XCTAssertEqual(decision(manifest: zeroManifest, current: "2.7"), .upToDate)
        XCTAssertEqual(decision(manifest: zeroManifest, current: "2.7.x"), .upToDate)
    }

    func testRejectsNonPositiveReleaseSize() throws {
        for badSize in [0, -1] {
            var json = liveManifestJSON
            var channels = try channelsDictionary(from: json)
            var ios = try iosDictionary(from: channels)
            var releases = try releasesArray(from: ios)
            releases[0]["size"] = badSize
            ios["releases"] = releases
            channels["ios"] = ios
            json["channels"] = channels
            XCTAssertThrowsError(try UpdateManifest.decode(from: json)) { error in
                guard case let UpdateManifestError.invalidReleaseSize(version, size) = error else {
                    return XCTFail("unexpected error for size \(badSize): \(error)")
                }
                XCTAssertEqual(version, "2.7.1")
                XCTAssertEqual(size, badSize)
            }
        }
    }

    func testRejectsMalformedReleaseSHA256() throws {
        // Wrong length (63 hex chars) and non-hex (64 chars, one 'z').
        let badDigests = [String(repeating: "a", count: 63), String(repeating: "a", count: 63) + "z"]
        for badSHA in badDigests {
            var json = liveManifestJSON
            var channels = try channelsDictionary(from: json)
            var ios = try iosDictionary(from: channels)
            var releases = try releasesArray(from: ios)
            releases[0]["sha256"] = badSHA
            ios["releases"] = releases
            channels["ios"] = ios
            json["channels"] = channels
            XCTAssertThrowsError(try UpdateManifest.decode(from: json)) { error in
                guard case let UpdateManifestError.invalidReleaseSHA256(version, sha256) = error else {
                    return XCTFail("unexpected error for sha256 \(badSHA): \(error)")
                }
                XCTAssertEqual(version, "2.7.1")
                XCTAssertEqual(sha256, badSHA)
            }
        }
    }

    func testUpToDateWhenManifestHasNoIOSChannel() {
        // Hand-built only: decoding rejects a missing iOS channel. A
        // manifest with no channel to compare against means "no update
        // known", never a crash.
        let empty = UpdateManifest(
            schemaVersion: 1,
            updatedAt: "2026-11-12T09:34:21Z",
            channels: UpdateChannels(ios: nil)
        )
        XCTAssertEqual(decision(manifest: empty, current: "2.6.0"), .upToDate)
    }
}
