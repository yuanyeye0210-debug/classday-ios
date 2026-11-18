import Foundation
import XCTest
import ClassdayCore

final class UpdateDownloadPlanTests: XCTestCase {
    private let downloadURL = "https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/Classday-v2.7.1.ipa"
    private let mirror1 = "https://mirror1.example.com/Classday-v2.7.1.ipa"
    private let mirror2 = "https://mirror2.example.com/Classday-v2.7.1.ipa"

    private var releaseWithMirrors: ReleaseEntry {
        ReleaseEntry(
            version: "2.7.1",
            file: "Classday-v2.7.1.ipa",
            size: 3_965_332,
            sha256: "279da1ee71cb9f5cc9dd8bb44331c5d0b81030012e396101fe797505a7e1f603",
            downloadURL: URL(string: downloadURL)!,
            publishedAt: "2026-11-11T16:41:55Z",
            mirrors: [mirror1, mirror2]
        )
    }

    private func release(mirrors: [String]?) -> ReleaseEntry {
        var entry = releaseWithMirrors
        entry.mirrors = mirrors
        return entry
    }

    // MARK: - Candidate order (brief Step 1)

    func testCandidateOrderIsDownloadURLThenMirrors() {
        let plan = UpdateDownloadPlan(release: releaseWithMirrors)
        XCTAssertEqual(plan.candidates.map(\.absoluteString), [downloadURL, mirror1, mirror2])
    }

    func testNoMirrorsYieldsOnlyDownloadURL() {
        let plan = UpdateDownloadPlan(release: release(mirrors: nil))
        XCTAssertEqual(plan.candidates.map(\.absoluteString), [downloadURL])
    }

    /// An empty mirrors array takes the same path as `nil`: only the
    /// `download_url` candidate.
    func testEmptyMirrorsYieldsOnlyDownloadURL() {
        let plan = UpdateDownloadPlan(release: release(mirrors: []))
        XCTAssertEqual(plan.candidates.map(\.absoluteString), [downloadURL])
    }

    /// Coordinator decision (brief is silent): a malformed mirror string is
    /// skipped — it must not break the `download_url` candidate or drop a
    /// later valid mirror.
    func testMalformedMirrorIsSkipped() {
        let plan = UpdateDownloadPlan(release: release(mirrors: ["://bad", "mirror.example.com/no-scheme.ipa", mirror2]))
        XCTAssertEqual(plan.candidates.map(\.absoluteString), [downloadURL, mirror2])
    }

    // MARK: - Retry policy (brief Step 1)

    func testBackoffSequence() {
        XCTAssertEqual(UpdateDownloadPlan.backoffSeconds(forAttempt: 1), 1)
        XCTAssertEqual(UpdateDownloadPlan.backoffSeconds(forAttempt: 2), 2)
        XCTAssertEqual(UpdateDownloadPlan.backoffSeconds(forAttempt: 3), 4)
    }

    func testRetryPolicyConstants() {
        XCTAssertEqual(UpdateDownloadPlan.maxAttemptsPerURL, 3)
        XCTAssertEqual(UpdateDownloadPlan.timeoutSeconds, 60)
    }

    // MARK: - Resume (brief Step 1)

    func testResumeOffsetIsPartialFileSize() {
        XCTAssertEqual(UpdateDownloadPlan.resumeOffset(partialSize: 1_000_000, expectedSize: 3_965_332), 1_000_000)
    }

    func testOversizedPartialIsDiscarded() {
        XCTAssertEqual(UpdateDownloadPlan.resumeOffset(partialSize: 9_999_999, expectedSize: 3_965_332), 0)
        XCTAssertTrue(UpdateDownloadPlan.shouldDiscardPartial(partialSize: 9_999_999, expectedSize: 3_965_332))
    }

    func testEmptyPartialResumesFromZero() {
        XCTAssertEqual(UpdateDownloadPlan.resumeOffset(partialSize: 0, expectedSize: 3_965_332), 0)
        XCTAssertFalse(UpdateDownloadPlan.shouldDiscardPartial(partialSize: 0, expectedSize: 3_965_332))
    }

    /// A partial exactly the expected size is complete, not corrupt: resume
    /// at the end (zero bytes remain) and keep the file for hash verification.
    func testCompletePartialIsNotDiscarded() {
        XCTAssertEqual(UpdateDownloadPlan.resumeOffset(partialSize: 3_965_332, expectedSize: 3_965_332), 3_965_332)
        XCTAssertFalse(UpdateDownloadPlan.shouldDiscardPartial(partialSize: 3_965_332, expectedSize: 3_965_332))
    }

    // MARK: - SHA-256 verification (brief Step 1)

    func testSHA256MatchesKnownVector() {
        XCTAssertTrue(UpdateDownloadPlan.sha256Matches(data: Data("abc".utf8), expected: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        XCTAssertFalse(UpdateDownloadPlan.sha256Matches(data: Data("abd".utf8), expected: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    }

    func testSHA256MatchesEmptyInput() {
        XCTAssertTrue(UpdateDownloadPlan.sha256Matches(data: Data(), expected: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
    }

    /// FIPS 180-4 56-byte vector: padding spills into a second block, so this
    /// exercises the multi-block path that "abc" never reaches.
    func testSHA256Matches56ByteVector() {
        let input = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
        XCTAssertEqual(input.count, 56)
        XCTAssertTrue(UpdateDownloadPlan.sha256Matches(data: Data(input.utf8), expected: "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"))
    }

    /// Large-input vector: one million "a" bytes (15,625 blocks),
    /// verified against Python hashlib in the Task 3 report. Exercises
    /// the multi-block path far beyond the 56-byte vector.
    func testSHA256MatchesOneMillionAVector() {
        let input = Data(repeating: 0x61, count: 1_000_000)
        XCTAssertTrue(UpdateDownloadPlan.sha256Matches(data: input, expected: "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"))
    }

    /// Hex comparison is case-insensitive: the digest is the same value
    /// regardless of the manifest's hex casing.
    func testSHA256MatchesIgnoresExpectedHexCase() {
        XCTAssertTrue(UpdateDownloadPlan.sha256Matches(data: Data("abc".utf8), expected: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"))
    }
}
