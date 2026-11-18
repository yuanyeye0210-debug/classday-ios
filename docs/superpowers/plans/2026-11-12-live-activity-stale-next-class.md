# Live Activity “下一节” stale fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The lock-screen Live Activity must stop showing a class that already ended today; it must flip to the current/next class at class boundaries, with or without the app being opened.

**Architecture:** Pure boundary math lives in ClassdayCore (`NextClassSnapshot.nextBoundary`, testable with `swift test` on Linux). The app layer (AppModel) refreshes the activity through a diff gate whenever the app becomes active and once a minute while active. A BGAppRefreshTask scheduled at the next boundary covers the case where the app is never opened. The CI workflow gains a `pull_request` trigger so this PR itself runs the full suite.

**Tech Stack:** Swift 5.0, SwiftUI, ActivityKit, BackgroundTasks (BGAppRefreshTask), WidgetKit (unchanged), GitHub Actions (classday-ios-ipa.yml).

**Spec:** Chat-agreed design, 2026-11-12 12:23 (this chat) + `~/MEMORY.md` entry “Live Activity ‘下一节’ bug”. Root cause, verified against the 2.7.1 code: `NextClassActivity.sync` runs only on document save (`AppModel.swift:860`) and on `reloadFromDiskIfChanged` (`AppModel.swift:528`), which early-returns when the store file is unchanged — so opening the app does not refresh the activity either. There is no timer, no unconditional foreground sync, and no background refresh (no `BGTaskScheduler` anywhere in the repo). The activity renders `Text(context.state.endsAt, style: .timer)`; with `endsAt` = 10:00 in the past, the timer counts UP — 12:19:22 − 10:00:00 = 2:19:22, exactly the reported value. `ScheduleEngine.currentOccurrence` / `nextOccurrence` are correct (the in-app Today view recomputes every 60s via `TimelineView(.periodic)` and shows the right class); only the activity update path is broken.

## Global Constraints

- Eric has no Mac; all verification runs on GitHub Actions CI, never locally. This Linux VM has no Swift/Xcode toolchain, so never claim a Swift/iOS test passed locally.
- Do NOT run `Classday/Tools/generate_xcodeproj.py` (its absolute-path xid seed rewrites all pbxproj IDs — deferred item D-6 from the 2.8.0 review).
- Do NOT bump the version: `Classday/VERSION` stays `2.7.1`; the version bump happens via the existing release flow, not in this fix.
- No new user-visible copy: phase labels “下一节” / “上课中” and all strings stay unchanged; no Chinese strings in the Core data model.
- Do not change the SideStore / LocalDevPN distribution or update flow.
- Keep shared logic platform-agnostic for the Android sync rule: the new Core function must be pure Swift with no iOS-only APIs; ActivityKit and BackgroundTasks stay in the App layer only.
- Do not push, merge, open a PR, or release. The coordinator finishes with a reviewed local branch; the parent handles push / draft PR / CI / merge.
- Every task ends with its own commit on branch `fix/live-activity-stale-next-class`.

## Review Focus

- A BG task that runs late (or never) leaves the stale activity up until the next foreground; the Core boundary must be exact so a late run still produces the right snapshot. Test: Task 1 boundary tests.
- Two classes back-to-back (one ends exactly when the next starts): the snapshot must flip phase at that instant, never show the ended class as “下一节”. Test: Task 1 custom-document test.
- The last class of the day ends: the snapshot becomes nil and the activity must be ENDED, not left showing the last class. Test: Task 1 nil-snapshot test + diff-predicate test.
- A rest day (Sunday): the snapshot is nil and the next boundary is Monday 08:00; a BG refresh must not be scheduled more than 36h out (same horizon as `WidgetProjection.horizon`). Test: Task 1 horizon test.
- iOS throttles Live Activity updates: identical content must never be re-pushed. Test: Task 1 diff-predicate test (same value → no update).

---

### Task 1: Core boundary math + regression tests

**Files:**
- Modify: `Classday/ClassdayCore/Sources/ClassdayCore/ActivityBridge.swift`
- Test: `Classday/ClassdayCore/Tests/ClassdayCoreTests/ActivitySnapshotTests.swift` (new file)

**Interfaces:**
- Consumes: `ScheduleEngine.currentOccurrence(at:courses:semester:calendar:context:)`, `ScheduleEngine.nextOccurrence(after:courses:semester:calendar:context:)`, `NextClassSnapshot.Value` (Equatable), `DemoData.makeDocument()`, `TestSupport.date` / `TestSupport.calendar()` (Asia/Shanghai).
- Produces: `NextClassSnapshot.nextBoundary(after:document:calendar:horizon:) -> Date?` and `NextClassSnapshot.shouldUpdate(previous:current:) -> Bool`, used by Tasks 2 and 4.

- [ ] **Step 1: Write the failing tests in `ActivitySnapshotTests.swift`**

```swift
func testSnapshotFlipsToNextClassAfterOneEnds() {
    let at0950 = TestSupport.date(2026, 11, 9, 9, 50, calendar: calendar)
    let snapshot = NextClassSnapshot.make(document: document, now: at0950, calendar: calendar)
    XCTAssertEqual(snapshot?.title, "大学英语")
    XCTAssertEqual(snapshot?.phase, "下一节")
    XCTAssertEqual(snapshot?.startsAt, TestSupport.date(2026, 11, 9, 10, 10, calendar: calendar))
    XCTAssertEqual(snapshot?.endsAt, TestSupport.date(2026, 11, 9, 10, 10, calendar: calendar))
}

func testSnapshotDuringClassIsInProgress() {
    let at0830 = TestSupport.date(2026, 11, 9, 8, 30, calendar: calendar)
    let snapshot = NextClassSnapshot.make(document: document, now: at0830, calendar: calendar)
    XCTAssertEqual(snapshot?.title, "高等数学")
    XCTAssertEqual(snapshot?.phase, "上课中")
    XCTAssertEqual(snapshot?.endsAt, TestSupport.date(2026, 11, 9, 9, 40, calendar: calendar))
}

func testSnapshotIsNilAfterLastClassOfDay() {
    let at1600 = TestSupport.date(2026, 11, 9, 16, 0, calendar: calendar)
    XCTAssertNil(NextClassSnapshot.make(document: document, now: at1600, calendar: calendar))
}

func testNextBoundary() {
    XCTAssertEqual(
        NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), document: document, calendar: calendar),
        TestSupport.date(2026, 11, 9, 8, 0, calendar: calendar))
    XCTAssertEqual(
        NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 8, 30, calendar: calendar), document: document, calendar: calendar),
        TestSupport.date(2026, 11, 9, 9, 40, calendar: calendar))
    XCTAssertEqual(
        NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 9, 50, calendar: calendar), document: document, calendar: calendar),
        TestSupport.date(2026, 11, 9, 10, 10, calendar: calendar))
    XCTAssertEqual(
        NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 12, 0, calendar: calendar), document: document, calendar: calendar),
        TestSupport.date(2026, 11, 9, 14, 0, calendar: calendar))
}

func testNextBoundaryOnRestDayAndHorizon() {
    XCTAssertEqual(
        NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 8, 12, 0, calendar: calendar), document: document, calendar: calendar),
        TestSupport.date(2026, 11, 9, 8, 0, calendar: calendar))
    var empty = document
    empty.courses = []
    XCTAssertNil(NextClassSnapshot.nextBoundary(after: TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar), document: empty, calendar: calendar))
}

func testBackToBackClassesFlipAtBoundary() {
    // Build a minimal document following DemoData.makeDocument's construction:
    // Monday 2026-11-09, course A 08:00–09:40, course B 09:40–11:20 (same weekday, adjacent periods).
    let at0940 = TestSupport.date(2026, 11, 9, 9, 40, calendar: calendar)
    let snapshot = NextClassSnapshot.make(document: backToBack, now: at0940, calendar: calendar)
    XCTAssertEqual(snapshot?.title, "B")
    XCTAssertEqual(snapshot?.phase, "上课中")
}

func testShouldUpdateDiffGate() {
    let at0830 = TestSupport.date(2026, 11, 9, 8, 30, calendar: calendar)
    let value = NextClassSnapshot.make(document: document, now: at0830, calendar: calendar)
    XCTAssertTrue(NextClassSnapshot.shouldUpdate(previous: nil, current: value))
    XCTAssertFalse(NextClassSnapshot.shouldUpdate(previous: value, current: value))
    XCTAssertTrue(NextClassSnapshot.shouldUpdate(previous: value, current: nil))
    let at0959 = TestSupport.date(2026, 11, 9, 9, 59, calendar: calendar)
    let before = NextClassSnapshot.make(document: document, now: at0959, calendar: calendar)
    let at1000 = TestSupport.date(2026, 11, 9, 10, 0, calendar: calendar)
    let during = NextClassSnapshot.make(document: document, now: at1000, calendar: calendar)
    XCTAssertTrue(NextClassSnapshot.shouldUpdate(previous: before, current: during))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Classday/ClassdayCore && swift test --filter ActivitySnapshotTests`
Expected: FAIL — `nextBoundary` and `shouldUpdate` do not exist. (No Swift toolchain on this VM; the failure is observed on CI, or the step is recorded as pending CI. Do not claim a local pass.)

- [ ] **Step 3: Implement in `ActivityBridge.swift`**

Add to `NextClassSnapshot`:
```swift
public static func nextBoundary(after date: Date, document: StoreDocument, calendar: Calendar, horizon: TimeInterval = 36 * 60 * 60) -> Date?
public static func shouldUpdate(previous: Value?, current: Value?) -> Bool
```
`nextBoundary` returns the earliest of `current?.end` and `next?.start` that is strictly after `date` and within `horizon`; `nil` when there is none. `shouldUpdate` returns `previous != current`. Keep the existing `make` untouched.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Classday/ClassdayCore && swift test --filter ActivitySnapshotTests`
Expected: PASS (verified on CI; do not claim a local pass).

- [ ] **Step 5: Commit**

```bash
git add Classday/ClassdayCore/Sources/ClassdayCore/ActivityBridge.swift Classday/ClassdayCore/Tests/ClassdayCoreTests/ActivitySnapshotTests.swift
git commit -m "fix: add NextClassSnapshot.nextBoundary and update diff gate with regression tests"
```

### Task 2: AppModel diff-gated refresh + unconditional foreground sync (A1)

**Files:**
- Modify: `Classday/ClassdayApp/Sources/AppModel.swift` (add `lastLiveActivitySnapshot` + `refreshLiveActivityIfNeeded(now:)`; replace the two direct `NextClassActivity.sync(document:calendar:)` calls — in `reloadFromDiskIfChanged` and after `StoreFile.save` — with `refreshLiveActivityIfNeeded()`)
- Modify: `Classday/ClassdayApp/Sources/ClassdayApp.swift` (in `.onChange(of: scenePhase)`, when `phase == .active`, call `model.refreshLiveActivityIfNeeded()` in addition to `model.reloadFromDiskIfChanged()`)

**Interfaces:**
- Consumes: `NextClassSnapshot.make(document:now:calendar:)`, `NextClassSnapshot.shouldUpdate(previous:current:)` from Task 1; `NextClassActivity.sync(document:calendar:)`.
- Produces: `AppModel.refreshLiveActivityIfNeeded(now: Date = Date())`, used by Tasks 3 and 4.

- [ ] **Step 1: Add `refreshLiveActivityIfNeeded` to `AppModel`**

```swift
func refreshLiveActivityIfNeeded(now: Date = Date()) {
    let snapshot = NextClassSnapshot.make(document: document, now: now, calendar: calendar)
    guard NextClassSnapshot.shouldUpdate(previous: lastLiveActivitySnapshot, current: snapshot) else { return }
    lastLiveActivitySnapshot = snapshot
    NextClassActivity.sync(document: document, calendar: calendar)
}
```
Store `lastLiveActivitySnapshot: NextClassSnapshot.Value?` on the model. The two existing direct `sync` call sites must go through this method so the stored snapshot never goes stale.

- [ ] **Step 2: Wire the unconditional foreground call in `ClassdayApp.swift`**

In the existing `.onChange(of: scenePhase)` handler, after `model.reloadFromDiskIfChanged()`, add `model.refreshLiveActivityIfNeeded()`. Do not change the `reloadFromDiskIfChanged` early-return behaviour itself.

- [ ] **Step 3: Verify by build**

Run: the CI `xcodebuild` step (or note as pending CI). No Linux test covers the App target; correctness is pinned by Task 1's Core tests plus the final review. Do not claim a local pass.

- [ ] **Step 4: Commit**

```bash
git add Classday/ClassdayApp/Sources/AppModel.swift Classday/ClassdayApp/Sources/ClassdayApp.swift
git commit -m "fix: refresh Live Activity on foreground through diff gate"
```

### Task 3: 60-second foreground timer (A2)

**Files:**
- Modify: `Classday/ClassdayApp/Sources/AppModel.swift`

**Interfaces:**
- Consumes: `refreshLiveActivityIfNeeded(now:)` from Task 2.
- Produces: a timer owned by `AppModel` that calls `refreshLiveActivityIfNeeded()` every 60s while the app is active.

- [ ] **Step 1: Add the timer to `AppModel`**

In `init`, subscribe a `Timer.publish(every: 60, on: .main, in: .common).autoconnect()` sink (weak self) that calls `refreshLiveActivityIfNeeded()`; hold the cancellable on the model. The timer does nothing while the app is suspended in the background; that case belongs to Task 4. No new API surface beyond the timer itself.

- [ ] **Step 2: Verify by build**

Run: the CI `xcodebuild` step (or note as pending CI). Do not claim a local pass.

- [ ] **Step 3: Commit**

```bash
git add Classday/ClassdayApp/Sources/AppModel.swift
git commit -m "fix: re-sync Live Activity every minute while the app is active"
```

### Task 4: Background refresh at the next boundary (B)

**Files:**
- Modify: `Classday/ClassdayApp/Sources/AppDelegate.swift` (register the task in `application(_:didFinishLaunchingWithOptions:)`; add the handler)
- Modify: `Classday/ClassdayApp/Sources/NextClassActivity.swift` (add `backgroundTaskID` + `scheduleBackgroundRefresh(document:calendar:)`)
- Modify: `Classday/ClassdayApp/Sources/AppModel.swift` (call `scheduleBackgroundRefresh` from `refreshLiveActivityIfNeeded` on every invocation, outside the diff gate — not only after a successful sync)
- Modify: `Classday/Config/Classday-Info.plist` (add the two keys below; no pbxproj or entitlements change — background fetch is a plist key, not an entitlement)

**Interfaces:**
- Consumes: `NextClassSnapshot.nextBoundary(after:document:calendar:)` from Task 1 (default 36h horizon); `SharedWidgetStore.load()` (the same shared-store read the widget extension uses in `ExtraWidgets.swift`) for the background handler's document.
- Produces: `NextClassActivity.backgroundTaskID` and `NextClassActivity.scheduleBackgroundRefresh(document:calendar:)`.

- [ ] **Step 1: Add the plist keys to `Classday/Config/Classday-Info.plist`**

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.classday.app.refresh-next-class</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

- [ ] **Step 2: Add scheduling to `NextClassActivity.swift`**

```swift
static let backgroundTaskID = "com.classday.app.refresh-next-class"

static func scheduleBackgroundRefresh(document: StoreDocument, calendar: Calendar, now: Date = Date()) {
    guard let boundary = NextClassSnapshot.nextBoundary(after: now, document: document, calendar: calendar) else { return }
    let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
    request.earliestBeginDate = boundary
    try? BGTaskScheduler.shared.submit(request)
}
```
`nextBoundary` already applies the 36h horizon, so no separate cap check is needed here.

- [ ] **Step 3: Register and handle the task in `AppDelegate.swift`**

In `application(_:didFinishLaunchingWithOptions:)`, register the identifier with `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)`; the handler must call `task.setTaskCompleted(success:)` in all paths. The handler loads the document with `SharedWidgetStore.load()`; if it returns nil, complete the task without scheduling. Otherwise call `NextClassActivity.sync(document:calendar:)` and then `scheduleBackgroundRefresh(document:calendar:)` to queue the following boundary.

- [ ] **Step 4: Call `scheduleBackgroundRefresh` from `AppModel.refreshLiveActivityIfNeeded` on every invocation, outside the diff gate**

- [ ] **Step 5: Verify by build**

Run: the CI `xcodebuild` step (or note as pending CI). Background execution itself cannot be verified on CI or this VM; the PR description must list the real-device check for Eric (open the app in the morning, lock the phone, confirm the lock-screen activity flips at the next class start/end without opening the app). Do not claim a local pass.

- [ ] **Step 6: Commit**

```bash
git add Classday/ClassdayApp/Sources/AppDelegate.swift Classday/ClassdayApp/Sources/NextClassActivity.swift Classday/ClassdayApp/Sources/AppModel.swift Classday/Config/Classday-Info.plist
git commit -m "fix: schedule a background refresh at the next class boundary"
```

### Task 5: CI workflow runs on pull requests (C)

**Files:**
- Modify: `.github/workflows/classday-ios-ipa.yml`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the `classday-ios-ipa` workflow runs on pull requests to `main`, so this PR itself gets the `swift test` + `xcodebuild` signal the main rule requires before merging.

- [ ] **Step 1: Add the `pull_request` trigger, keeping the existing `push` block unchanged**

```yaml
on:
  push:
    branches:
      - cursor/shared-app-group-92bb
      - cursor/classday-2-themes-92bb
      - main
  pull_request:
    branches:
      - main
```
For `pull_request` events GitHub uses the workflow file from the merge commit, so this PR will run the full workflow once the trigger lands in it. Do not touch any job, step, or permission.

- [ ] **Step 2: Verify**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/classday-ios-ipa.yml'))"` — if PyYAML is unavailable, verify by reading the file back and confirming the trigger block. The live proof is the draft PR's checks showing the `classday-ios-ipa` run.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/classday-ios-ipa.yml
git commit -m "ci: run classday-ios-ipa on pull requests to main"
```

### Task 6: Final verification pass

**Files:**
- Modify: none (verification only; fix anything it finds in the owning task's style and re-commit there)

- [ ] **Step 1: Run the Python checks from the worktree root**

Run: `python3 Classday/Tools/check_project.py` and `python3 Classday/Tools/check_version_snapshot.py --self-test` and `python3 Classday/Tools/check_version_snapshot.py --base main`
Expected: all pass, exit 0.

- [ ] **Step 2: Confirm the branch contains only the intended changes**

Run: `git status --short` and `git diff --stat main...HEAD`
Expected: only the files listed in Tasks 1–5; `Classday/VERSION` untouched (still `2.7.1`); no `project.pbxproj` changes; no `generate_xcodeproj.py` run.

- [ ] **Step 3: Draft the PR description (do not open the PR)**

Save nothing to the repo; report the text to the parent. It must state: the root cause in one paragraph; what A and B each fix; that `swift test` + `xcodebuild` could not run on this VM and must go green on the PR; and the real-device check for Eric (morning: open the app, lock the phone, confirm the lock-screen activity flips at the next class start/end without opening the app; also confirm the Dynamic Island timer counts DOWN to the next boundary, never up past a class start).

## Self-Review

1. **Spec coverage:** A (foreground) → Tasks 2–3; B (background) → Task 4; C (PR trigger) → Task 5; regression tests for the reported 12:19 case → Task 1 (`testSnapshotFlipsToNextClassAfterOneEnds` is the exact shape: a class ended, the snapshot must already be the next class).
2. **Step scan:** each step names one action and its check; the App-layer steps honestly record that no Linux test covers them instead of pretending otherwise.
3. **Type consistency:** `nextBoundary(after:document:calendar:horizon:)` is defined once in Task 1 and reused verbatim in Task 4; `shouldUpdate(previous:current:)` is defined once and used in Task 2; `backgroundTaskID` is a single constant used by the plist, the scheduler, and the registrar.
4. **Review Focus:** each of the five lines has a test in Task 1 (boundary, back-to-back, nil-after-last-class, rest-day/horizon, diff gate).
5. **Proportion:** the plan is longer than the fix because it pins exact test values, signatures, and the plist keys the implementer cannot guess; no function body is transcribed beyond what the signature and tests leave open.
