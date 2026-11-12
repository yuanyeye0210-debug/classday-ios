import XCTest
import ClassdayCore

final class ReleaseSourceTests: XCTestCase {
    func testMarketingComparisonMatchesThePreviousRules() {
        XCTAssertTrue(ReleaseVersion.isNewer("2.7.1", than: "2.7.0"))
        XCTAssertFalse(ReleaseVersion.isNewer("2.7.1", than: "2.7.1"))
        XCTAssertFalse(ReleaseVersion.isNewer("2.7.0", than: "2.7.1"))
        XCTAssertTrue(ReleaseVersion.isNewer("2.10.0", than: "2.9.0"))
        XCTAssertTrue(ReleaseVersion.isNewer("1.2.1", than: "1.2"))
        XCTAssertFalse(ReleaseVersion.isNewer("1.2", than: "1.2.0"))
        XCTAssertTrue(ReleaseVersion.isNewer("10", than: "2"))
    }

    func testEqualMarketingVersionUsesBuildNumber() {
        XCTAssertTrue(ReleaseVersion.isNewer("2.7.1", build: "2", than: "2.7.1", build: "1"))
        XCTAssertFalse(ReleaseVersion.isNewer("2.7.1", build: "1", than: "2.7.1", build: "1"))
        XCTAssertFalse(ReleaseVersion.isNewer("2.7.1", build: "1", than: "2.7.1", build: "2"))
        XCTAssertFalse(ReleaseVersion.isNewer("2.7.1", build: nil, than: "2.7.1", build: "9"))
        XCTAssertTrue(ReleaseVersion.isNewer("2.8.0", build: "1", than: "2.7.9", build: "99"))
    }

    func testParsesSourceAndOffersTheNewerVersion() throws {
        let source = try ReleaseChannel.parse(Data(sampleJSON.utf8))
        XCTAssertEqual(source.name, "课曜")
        let offer = try ReleaseChannel.updateOffer(
            in: source,
            currentMarketing: "2.7.0",
            currentBuild: "1",
            deviceOS: "17.5"
        )
        XCTAssertEqual(offer?.version, "2.7.1")
        XCTAssertEqual(offer?.buildVersion, "1")
        XCTAssertEqual(offer?.ipaURL.absoluteString, "https://example.com/Classday-v2.7.1.ipa")
        XCTAssertEqual(offer?.notes, "课程页滑动修复")
        let components = URLComponents(url: try XCTUnwrap(offer?.sideStoreURL), resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.scheme, "sidestore")
        XCTAssertEqual(components?.host, "source")
        XCTAssertEqual(components?.queryItems?.first?.name, "url")
        XCTAssertEqual(components?.queryItems?.first?.value, ReleaseChannel.sourceURL.absoluteString)
    }

    func testNewestWinsEvenWhenListedSecond() throws {
        let json = """
        {"name":"课曜","apps":[{"name":"课曜","bundleIdentifier":"com.classday.app","versions":[
          {"version":"2.7.0","buildVersion":"1","downloadURL":"https://example.com/old.ipa","size":10,"minOSVersion":"17.0"},
          {"version":"2.7.1","buildVersion":"2","downloadURL":"https://example.com/new.ipa","size":11,"minOSVersion":"17.0"}
        ]}]}
        """
        let source = try ReleaseChannel.parse(Data(json.utf8))
        let offer = try ReleaseChannel.updateOffer(in: source, currentMarketing: "2.7.0", currentBuild: "1")
        XCTAssertEqual(offer?.version, "2.7.1")
        XCTAssertEqual(offer?.buildVersion, "2")
    }

    func testSameVersionIsNotAnUpdateUnlessTheBuildIsHigher() throws {
        let source = try ReleaseChannel.parse(Data(sampleJSON.utf8))
        XCTAssertNil(try ReleaseChannel.updateOffer(in: source, currentMarketing: "2.7.1", currentBuild: "1"))
        let bumped = """
        {"name":"课曜","apps":[{"name":"课曜","bundleIdentifier":"com.classday.app","versions":[
          {"version":"2.7.1","buildVersion":"3","downloadURL":"https://example.com/b.ipa","size":1}
        ]}]}
        """
        let again = try ReleaseChannel.parse(Data(bumped.utf8))
        XCTAssertEqual(try ReleaseChannel.updateOffer(in: again, currentMarketing: "2.7.1", currentBuild: "2")?.buildVersion, "3")
    }

    func testSkipsAVersionTheDeviceCannotRun() throws {
        let json = """
        {"name":"课曜","apps":[{"name":"课曜","bundleIdentifier":"com.classday.app","versions":[
          {"version":"3.0.0","buildVersion":"8","downloadURL":"https://example.com/future.ipa","size":4,"minOSVersion":"18.0"},
          {"version":"2.7.1","buildVersion":"1","downloadURL":"https://example.com/current.ipa","size":3,"minOSVersion":"17.0"}
        ]}]}
        """
        let source = try ReleaseChannel.parse(Data(json.utf8))
        let offer = try ReleaseChannel.updateOffer(in: source, currentMarketing: "2.7.0", currentBuild: "1", deviceOS: "17.4")
        XCTAssertEqual(offer?.version, "2.7.1")
        XCTAssertNil(try ReleaseChannel.updateOffer(in: source, currentMarketing: "2.7.1", currentBuild: "1", deviceOS: "17.4"))
    }

    func testMissingAppAndMalformedSource() {
        let other = """
        {"name":"Other","apps":[{"name":"Other","bundleIdentifier":"com.example.other","versions":[
          {"version":"1.0.0","downloadURL":"https://example.com/x.ipa"}
        ]}]}
        """
        XCTAssertThrowsError(try ReleaseChannel.updateOffer(in: try ReleaseChannel.parse(Data(other.utf8)), currentMarketing: "1.0.0")) { error in
            guard case ReleaseSourceError.missingApp("com.classday.app") = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertThrowsError(try ReleaseChannel.parse(Data("not-json".utf8))) { error in
            guard case ReleaseSourceError.malformed = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertThrowsError(try ReleaseChannel.parse(Data(#"{"apps":[]}"#.utf8))) { error in
            guard case ReleaseSourceError.malformed = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testAVersionWithoutADownloadURLIsIgnored() throws {
        let json = """
        {"name":"课曜","apps":[{"name":"课曜","bundleIdentifier":"com.classday.app","versions":[
          {"version":"9.0.0"},
          {"version":"2.7.2","buildVersion":"4","downloadURL":"https://example.com/ok.ipa","size":"12"}
        ]}]}
        """
        let source = try ReleaseChannel.parse(Data(json.utf8))
        XCTAssertEqual(source.apps.first?.versions.count, 1)
        let offer = try ReleaseChannel.updateOffer(in: source, currentMarketing: "2.7.1", currentBuild: "1")
        XCTAssertEqual(offer?.version, "2.7.2")
        XCTAssertEqual(offer?.ipaURL.absoluteString, "https://example.com/ok.ipa")
    }

    private let sampleJSON = """
    {
      "name": "课曜",
      "apps": [
        {
          "name": "课曜",
          "bundleIdentifier": "com.classday.app",
          "versions": [
            {
              "version": "2.7.1",
              "buildVersion": "1",
              "date": "2026-11-11",
              "localizedDescription": "课程页滑动修复",
              "downloadURL": "https://example.com/Classday-v2.7.1.ipa",
              "size": 3965332,
              "minOSVersion": "17.0"
            },
            {
              "version": "2.7.0",
              "buildVersion": "1",
              "date": "2026-11-11",
              "localizedDescription": "邮件停课识别",
              "downloadURL": "https://example.com/Classday-v2.7.0.ipa",
              "size": 3968446,
              "minOSVersion": "17.0"
            }
          ]
        }
      ],
      "news": []
    }
    """
}
