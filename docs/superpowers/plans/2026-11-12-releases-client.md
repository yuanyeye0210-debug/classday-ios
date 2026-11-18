# classday-releases batch 3 — client-side Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app checks for updates against `latest.json` (with fallback to the GitHub Releases API), downloads the IPA in-app with retry + Range resume + SHA-256 verification, and reports version-distribution events per the `classday-releases` README schema — without ever blocking the client.

**Architecture:** Pure logic lives in ClassdayCore (`UpdateManifest`, `UpdateDownloadPlan`, `UpdateReport`, testable with `swift test` on Linux). The app layer (`SettingsView` + a thin `UpdateService`) owns `URLSession` fetching/downloading, CryptoKit hashing, the share sheet, alerts, and the daily auto-check. Reporting has no collector yet, so sending is implemented but disabled by default.

**Tech Stack:** Swift 5.0, SwiftUI, URLSession, CryptoKit, UserDefaults, GitHub Actions (classday-ios-ipa.yml — unchanged).

**Spec:** `docs/superpowers/specs/2026-11-12-releases-client-design.md`, approved by Eric in chat 2026-11-12 14:14. Background verified against live `latest.json` (2026-11-12 14:05) and `SettingsView.checkForUpdate` (lines 726–742) plus the `Link` at lines 333–335. `classday-releases/README.md` (main `e6daa0a`) defines the manifest and reporting contracts.

## Global Constraints

- Eric has no Mac; all verification runs on GitHub Actions CI, never locally. This Linux VM has no Swift/Xcode toolchain, so never claim a Swift/iOS test passed locally.
- Do NOT run `Classday/Tools/generate_xcodeproj.py` (its absolute-path xid seed rewrites all pbxproj IDs — deferred item D-6 from the 2.8.0 review).
- Do NOT bump the version: `Classday/VERSION` stays `2.7.1`.
- Do NOT change any workflow file (`.github/workflows/*`) — this keeps the connector snapshot push working (no 403).
- Do not touch the `classday-2.8.0-foundation` branch or the merged `fix/live-activity-stale-next-class` branch. This branch is `feat/releases-client` from main `676f6ce`.
- Keep shared logic platform-agnostic for the Android sync rule: manifest schema, report payload/events, candidate order, retry policy, resume rules and SHA-256 verification must be pure Swift with no iOS-only APIs. `URLSession`, CryptoKit, SwiftUI and UserDefaults stay in the App layer only.
- New files must be added to the Xcode project the same way the 2.8.0 branch added `AIRecognition.swift` / `GeminiClient.swift` — check that branch's pbxproj diff first. If the project uses filesystem-synchronized groups, confirm new files are picked up automatically; do not assume.
- Do not push, merge, open a PR, or release. The coordinator finishes with a reviewed local branch; the parent handles push / draft PR / CI / merge.
- Every task ends with its own commit on branch `feat/releases-client`.
- Reporting must never throw into a UI path, never retry, never alert, never block. The sender is disabled until a collector endpoint constant is filled in.

## Review Focus

- Manifest failure must not break the old path: any fetch/parse/validation failure falls back to the GitHub Releases API with identical behaviour. Test: Task 1 + Task 5.
- A mandatory alert must only appear when a mandatory update was actually fetched — never on a network error, never on "already latest". Test: Task 2 decision tests + Task 5 review.
- A partial file larger than the manifest `size` is corrupt: discard it, do not resume from it. Test: Task 3.
- SHA-256 is computed over the final file, not the partial; a tampered byte must fail verification even if the size matches. Test: Task 3.
- `installed` must not fire on first launch (no stored version → store the current version silently, do not report). Test: Task 4.
- The sender must do nothing when no endpoint is configured — no request, no log spam, no crash. Test: Task 4.

---

### Task 1: Core manifest model + decoding/validation

**Files:**
- New: `Classday/ClassdayCore/Sources/ClassdayCore/UpdateManifest.swift`
- Test: `Classday/ClassdayCore/Tests/ClassdayCoreTests/UpdateManifestTests.swift` (new file)

**Interfaces:**
- Consumes: live `latest.json` shape (keep a fixture copy in the test from the 2026-11-12 14:05 read: schema_version 1, ios latest 2.7.1, mandatory false, min_supported_version 2.7.0, releases 2.7.1 + 2.7.0 with file/size/sha256/download_url/published_at; android null).
- Produces: `UpdateManifest` (Decodable), `iOSChannel`, `ReleaseEntry` (with optional `mirrors: [String]`), `latestRelease` selection, validation errors — used by Tasks 2 and 5.

- [ ] **Step 1: Write the failing tests in `UpdateManifestTests.swift`**

```swift
func testDecodesLiveManifestShape() {
    let manifest = try JSONDecoder().decode(UpdateManifest.self, from: liveManifestFixture)
    XCTAssertEqual(manifest.schemaVersion, 1)
    XCTAssertEqual(manifest.channels.ios?.latest, "2.7.1")
    XCTAssertEqual(manifest.channels.ios?.latestRelease?.sha256, "279da1ee71cb9f5cc9dd8bb44331c5d0b81030012e396101fe797505a7e1f603")
    XCTAssertEqual(manifest.channels.ios?.latestRelease?.size, 3965332)
    XCTAssertNil(manifest.channels.ios?.latestRelease?.mirrors)
    XCTAssertNil(manifest.channels.android)
}

func testRejectsWrongSchemaVersion() {
    var json = liveManifestJSON
    json["schema_version"] = 2
    XCTAssertThrowsError(try UpdateManifest.decode(from: json))
}

func testRejectsLatestNotInReleases() {
    var json = liveManifestJSON
    json["channels"]["ios"]["latest"] = "9.9.9"
    XCTAssertThrowsError(try UpdateManifest.decode(from: json))
}
```

- [ ] **Step 2: Run tests to verify they fail (red)**
- [ ] **Step 3: Write minimal implementation in `UpdateManifest.swift`**
- [ ] **Step 4: Run tests to verify they pass (green)**
- [ ] **Step 5: Commit**

---

### Task 2: Core update decision (compare + mandatory + min-supported)

**Files:**
- New or modify: `Classday/ClassdayCore/Sources/ClassdayCore/UpdateManifest.swift` (decision type) — check `VersionBump.swift` first for an existing SemVer compare and reuse it; do not duplicate compare logic. Leave `SettingsView.version(_:isNewerThan:)` alone unless reuse is a safe, review-approved cleanup.
- Test: `Classday/ClassdayCore/Tests/ClassdayCoreTests/UpdateManifestTests.swift` (extend)

**Interfaces:**
- Consumes: `UpdateManifest` from Task 1, current version string (`CFBundleShortVersionString`).
- Produces: `UpdateDecision` (`.upToDate` / `.updateAvailable(release, mandatory: Bool)` / `.belowMinimumSupported(release)`), used by Tasks 5 and 6.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail (red)**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run tests to verify they pass (green)**
- [ ] **Step 5: Commit**

---

### Task 3: Core download plan (candidates, retry, resume, verify)

**Files:**
- New: `Classday/ClassdayCore/Sources/ClassdayCore/UpdateDownloadPlan.swift`
- Test: `Classday/ClassdayCore/Tests/ClassdayCoreTests/UpdateDownloadPlanTests.swift` (new file)

**Interfaces:**
- Consumes: `ReleaseEntry` from Task 1 (download_url, mirrors, size, sha256).
- Produces: ordered candidate URLs, retry policy (3 attempts per URL, backoff 1 s/2 s/4 s, 60 s timeout), resume offset from a partial file's byte count, SHA-256 verification helper — used by Task 6.

- [ ] **Step 1: Write the failing tests**

```swift
func testCandidateOrderIsDownloadURLThenMirrors() {
    let plan = UpdateDownloadPlan(release: releaseWithMirrors)
    XCTAssertEqual(plan.candidates.map(\.absoluteString), [downloadURL, mirror1, mirror2])
}

func testResumeOffsetIsPartialFileSize() {
    XCTAssertEqual(UpdateDownloadPlan.resumeOffset(partialSize: 1_000_000, expectedSize: 3_965_332), 1_000_000)
}

func testOversizedPartialIsDiscarded() {
    XCTAssertEqual(UpdateDownloadPlan.resumeOffset(partialSize: 9_999_999, expectedSize: 3_965_332), 0)
    XCTAssertTrue(UpdateDownloadPlan.shouldDiscardPartial(partialSize: 9_999_999, expectedSize: 3_965_332))
}

func testSHA256MatchesKnownVector() {
    XCTAssertTrue(UpdateDownloadPlan.sha256Matches(data: Data("abc".utf8), expected: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    XCTAssertFalse(UpdateDownloadPlan.sha256Matches(data: Data("abd".utf8), expected: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
}

func testBackoffSequence() {
    XCTAssertEqual(UpdateDownloadPlan.backoffSeconds(forAttempt: 1), 1)
    XCTAssertEqual(UpdateDownloadPlan.backoffSeconds(forAttempt: 2), 2)
    XCTAssertEqual(UpdateDownloadPlan.backoffSeconds(forAttempt: 3), 4)
}
```

- [ ] **Step 2: Run tests to verify they fail (red)**
- [ ] **Step 3: Write minimal implementation** (SHA-256 via CryptoKit where available on Linux CI; if CryptoKit is unavailable in the Linux `swift test` environment, implement the hash check behind the same interface with a portable SHA-256 and note it — do not silently skip verification)
- [ ] **Step 4: Run tests to verify they pass (green)**
- [ ] **Step 5: Commit**

---

### Task 4: Core reporter (payload, events, gate, installed detection)

**Files:**
- New: `Classday/ClassdayCore/Sources/ClassdayCore/UpdateReport.swift`
- Test: `Classday/ClassdayCore/Tests/ClassdayCoreTests/UpdateReportTests.swift` (new file)

**Interfaces:**
- Consumes: README payload contract (`app_version`, `platform`, `build`, `event`, `error?`, `timestamp` UTC ISO `YYYY-MM-DDTHH:MM:SSZ`); events `update_check`, `download_started`, `download_succeeded`, `download_failed`, `installed`.
- Produces: `UpdateReport` payload builder, `UpdateReportEvent` enum, `isEnabled` gate (false when no endpoint is configured), `installedEventIfNeeded(storedVersion:currentVersion:)` — used by Task 6.

- [ ] **Step 1: Write the failing tests**

```swift
func testPayloadHasExactlyTheREADMEFields() {
    let payload = UpdateReport(event: .updateCheck, appVersion: "2.7.1", build: "1", timestamp: fixedDate).json
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
    XCTAssertEqual(payload["event"] as? String, "download_failed")
    XCTAssertEqual(payload["error"] as? String, "timeout")
}

func testInstalledFiresOnlyOnVersionChange() {
    XCTAssertNil(UpdateReport.installedEventIfNeeded(storedVersion: nil, currentVersion: "2.7.1"))
    XCTAssertNil(UpdateReport.installedEventIfNeeded(storedVersion: "2.7.1", currentVersion: "2.7.1"))
    XCTAssertNotNil(UpdateReport.installedEventIfNeeded(storedVersion: "2.7.0", currentVersion: "2.7.1"))
}

func testSenderDisabledWithoutEndpoint() {
    XCTAssertFalse(UpdateReport.isEnabled(endpoint: nil))
}
```

- [ ] **Step 2: Run tests to verify they fail (red)**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run tests to verify they pass (green)**
- [ ] **Step 5: Commit**

---

### Task 5: App manifest fetch + fallback + SettingsView wiring

**Files:**
- Modify: `Classday/ClassdayApp/Sources/SettingsView.swift` (`checkForUpdate`, row at lines ~329–335, `updateNote` / `updateURL` state)
- New (only if a separate type is cleaner than extending SettingsView): `Classday/ClassdayApp/Sources/UpdateService.swift`

**Interfaces:**
- Consumes: `UpdateManifest` + `UpdateDecision` (Tasks 1–2), the existing GitHub Releases API path (kept as fallback), `Bundle.main` version strings.
- Produces: the row shows "新版 X" with the manifest `download_url` when an update exists; "已是最新版" / "检查失败" behaviour unchanged; on manifest failure the old API path runs with identical results.

- [ ] **Step 1: Write the failing tests** — App-layer wiring has no unit-test target in CI; instead write a checklist test in the plan: (a) manifest fetch with 15 s timeout, (b) each failure mode (no network, bad JSON, schema_version 2, ios null) falls back to the API path, (c) row note/URL match the old behaviour on fallback. Verify (a)–(c) by code inspection + review, and by the `xcodebuild` build in Task 7's CI run.
- [ ] **Step 2: Implement the manifest fetch + fallback + decision wiring in `SettingsView` / `UpdateService`**
- [ ] **Step 3: Verify `check_version_snapshot.py --self-test` and `--base main` still pass in the worktree; verify the worktree builds conceptually (no Swift toolchain here — CI covers it)**
- [ ] **Step 4: Commit**

---

### Task 6: App downloader + alerts + auto-check + reporting dispatch

**Files:**
- Modify: `Classday/ClassdayApp/Sources/SettingsView.swift` (progress UI, share sheet, alerts), `Classday/ClassdayApp/Sources/ClassdayApp.swift` or `AppModel.swift` (daily auto-check trigger — pick the existing launch path, do not add a new launch sequence)
- New: download + reporting sender in `UpdateService.swift` (from Task 5) or a focused new file

**Interfaces:**
- Consumes: `UpdateDownloadPlan` (Task 3), `UpdateReport` (Task 4), `UpdateDecision` (Task 2).
- Produces: in-app download with Range resume + progress, SHA-256 verify, share sheet with the finished IPA, Safari fallback on total failure, mandatory / below-minimum blocking alerts, silent daily auto-check, fire-and-forget reporting dispatch (disabled while no endpoint is configured).

- [ ] **Step 1: Confirm the networking shape against the codebase** (manual Range data tasks vs an existing helper; share-sheet presentation pattern already used in the app — find it and reuse it; do not invent a new presentation path)
- [ ] **Step 2: Implement the downloader** (candidates in order, 3 attempts per URL, backoff 1 s/2 s/4 s, 60 s timeout, partial file in caches named by version, 200-instead-of-206 restarts from scratch once, stale partials deleted, size + SHA-256 verification with one re-download on mismatch, progress reporting)
- [ ] **Step 3: Implement the alerts** (mandatory → single-button non-dismissable alert; below-minimum → blocking alert stating the version is no longer supported; neither appears on network error or when already latest)
- [ ] **Step 4: Implement the daily auto-check** (at most once per day, silent, only surfaces UI when an update/mandatory/below-minimum is found; manual tap always checks; last-check date in UserDefaults; never blocks launch)
- [ ] **Step 5: Implement reporting dispatch** (fire-and-forget `Task`, gated by `UpdateReport.isEnabled`; `update_check` after every completed check, download events around the download, `installed` on launch via `installedEventIfNeeded`; all failures swallowed)
- [ ] **Step 6: Commit**

---

### Task 7: Final review + docs + verification

**Files:**
- Review: whole branch diff vs main `676f6ce`
- Docs: check `README.md` (classday-ios) for stale update-flow claims (GitHub Releases API only) and update them if present; no `DATA_SCHEMA.md` change (timetable schema untouched)

**Interfaces:**
- Consumes: the finished branch, the design doc, the coordinator's task reports.

- [ ] **Step 1: Run `check_version_snapshot.py --self-test` and `--base main` in the worktree — both must pass**
- [ ] **Step 2: Confirm no workflow file changed, no version bump, no other branch touched (`git status`, `git diff --stat main...HEAD`)**
- [ ] **Step 3: Independent whole-branch review (fresh reviewer, no fixes by the reviewer) — must be clean of Critical issues before handoff; fix wave if needed, then re-review the wave**
- [ ] **Step 4: Commit any review fixes + the review record; leave the branch ready for the parent to push, open a draft PR, run CI, and merge per the main rule**
