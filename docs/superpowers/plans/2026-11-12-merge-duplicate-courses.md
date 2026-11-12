# 同名课程自动合并 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Same-named courses are detected, confirmed once by the user, and merged into one Course record so a grade is entered once and GPA/credits are counted once.

**Architecture:** Pure Core logic in a new `CourseMerger.swift` (normalize → group → merge → remap), covered by `CourseMergerTests.swift` run in CI `swift test`; a thin App layer (`MergeReviewView`, entry in the all-courses page, post-import banner, `AppModel.applyCourseMerge` with backup + persist). No schema change.

**Tech Stack:** Swift, SwiftUI, XCTest (`swift test` in CI only — this Linux VM has no Swift/Xcode, never claim local Swift runs).

**Spec:** `docs/superpowers/specs/2026-11-12-merge-duplicate-courses-design.md` (approved 2026-11-12 16:30, all six decisions as recommended). The spec is the authority; the plan argues from it. Executors read both.

## Global Constraints

- Schema stays v1. No new fields, no schema bump, no version-number change in this batch (release 2.9.0 is a separate decision, not this batch).
- D1 merge key: normalized name only — strip leading/trailing whitespace, delete ALL whitespace characters (including U+3000 fullwidth space), lowercase ASCII letters, fullwidth ASCII → halfwidth. No simplified/traditional conversion. Never add teacher/room/weeks to the key.
- D2 merge mode: auto-detect + one confirmation, never silent auto-merge. The confirm page lists each group's members (teacher/location/periods/grade status), supports per-group merge, merge-all, and excluding a member from a group.
- D3 grade conflict: when two members both have a grade and the values differ, the user picks one (two-choice). Never silently overwrite.
- D4 post-import prompt: after any `importCalendar`, if duplicate groups exist, show a banner leading to the confirm page. Keep the OCR "已有同名课" badge; do not block imports and do not unify the three parsers' grouping keys.
- D5 version: 2.9.0 later; this batch changes no version strings.
- D6 teacher mismatch: warn only ("老师不一致，请确认是同一门课"), never block a group from merging.
- Core is pure functions: no disk I/O, no UserDefaults in `ClassdayCore`.
- Keep shared logic, data schema, and behaviour platform-agnostic (Android sync rule).
- Never run `Classday/Tools/bump-version.sh` (needs Swift) and never run `Classday/Tools/generate_xcodeproj.py` (rewrites all pbxproj IDs, D-6).
- New App-layer Swift files must be hand-added to `project.pbxproj` following the existing `GeminiClient.swift` pattern. New Core files need no pbxproj edit (SPM auto-includes).
- Do not push, open a PR, merge, or release. Implementation + review only; the controller pushes.

## Review Focus

1. Same name, different teachers in one term must land in ONE group with the teacher-mismatch warning — not silently split, not silently merged. Test in Task 1 (grouping) + Task 4 (warning shown).
2. Names that differ only by folding must group: trailing space, U+3000 fullwidth space, uppercase ASCII, fullwidth ASCII (Ａ→A). Test in Task 1.
3. Grade conflict where one side has a grade but no scheme and the other has both: the user's pick must carry grade AND scheme together, never mix one side's grade with the other's scheme. Test in Task 2.
4. Merged meetings must not duplicate: two members sharing the same (weekday, startPeriod, endPeriod) produce ONE meeting in the merged course. Test in Task 2.
5. A Live Activity / notification / override pointing at a deleted course id must not crash anything: overrides and cancellations are remapped, reminders and Live Activity recompute from the new document on persist. Test in Task 3 (remap) + Task 5 (persist path recomputes).

---

## File Structure

- Create: `Classday/ClassdayCore/Sources/ClassdayCore/CourseMerger.swift` — pure merge logic.
- Create: `Classday/ClassdayCore/Tests/ClassdayCoreTests/CourseMergerTests.swift` — Core tests.
- Create: `Classday/ClassdayApp/Sources/MergeReviewView.swift` — confirm page UI (+ pbxproj entries by hand).
- Modify: `Classday/ClassdayApp/Sources/AppModel.swift` — `applyCourseMerge`, duplicate-group state for entry/banner, post-import hook in `importCalendar`.
- Modify: `Classday/ClassdayApp/Sources/RootView.swift` — "全部课程" page entry + banner + navigation to the confirm page.
- Modify: `Classday/Docs/DATA_SCHEMA.md` — one-line note; `Classday/Docs/REGRESSION_CHECKLIST.md` — one new item.
- Read-only anchors (do not modify unless a task says so): `Classday/ClassdayCore/Sources/ClassdayCore/Models.swift` (`Course` :236, `ClassCancellation` :351), `Classday/ClassdayCore/Sources/ClassdayCore/ScheduleExtras.swift` (`OccurrenceOverride` :46, `StoredTimetable` :132), `Classday/ClassdayApp/Sources/AppModel.swift` (`setCourseGrade` :844, `importCalendar` :926, `duplicateTimetable(named:)` :759).

---

### Task 1: Core — name normalization + duplicate grouping

**Files:**
- Create: `Classday/ClassdayCore/Sources/ClassdayCore/CourseMerger.swift`
- Test: `Classday/ClassdayCore/Tests/ClassdayCoreTests/CourseMergerTests.swift`

**Interfaces:**
- Consumes: `Course` (`Models.swift:236`: `id: UUID`, `name: String`, `teacher: String`, `location: String`, `weeks: [Int]`, `meetings: [Meeting]`, `grade: Double?`, `gradeScheme: GradeScheme?`).
- Produces: `public func normalizeCourseName(_ name: String) -> String`; `public struct DuplicateGroup: Sendable, Equatable { public let normalizedName: String; public let courses: [Course] }` (courses in document order); `public func findDuplicateGroups(courses: [Course]) -> [DuplicateGroup]` (only groups with 2+ members, in document order of first appearance).

- [ ] **Step 1: Write the failing tests** in `CourseMergerTests.swift`:
```swift
func testNormalizeTrimsAndRemovesAllWhitespace() // "  高等数学 " + U+3000 → "高等数学"
func testNormalizeLowercasesASCIIAndFoldsFullwidth() // "ＡBC" → "abc"
func testNormalizeDoesNotConvertTraditional() // "發" stays "發"
func testFindGroupsSameNameDifferentTeachers() // two courses, same name, different teachers → one group of 2
func testFindGroupsIgnoresUniqueNames() // no duplicates → []
func testFindGroupsKeepsDocumentOrder() // groups ordered by first appearance
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Classday/ClassdayCore && swift test --filter CourseMergerTests` (CI only; this VM has no Swift — record that the run must happen on CI and do not claim a local run)
Expected: FAIL (type/function not defined)

- [ ] **Step 3: Implement `normalizeCourseName` and `findDuplicateGroups` in `CourseMerger.swift`**

Normalize: strip leading/trailing whitespace, delete every whitespace character (including U+3000), lowercase ASCII A–Z, map fullwidth ASCII (U+FF01–U+FF5E) to halfwidth. Group by normalized name; keep only groups with 2+ courses; preserve document order inside each group and order groups by first appearance.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Classday/ClassdayCore && swift test --filter CourseMergerTests` (CI only)
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Classday/ClassdayCore/Sources/ClassdayCore/CourseMerger.swift Classday/ClassdayCore/Tests/ClassdayCoreTests/CourseMergerTests.swift
git commit -m "feat(core): normalize course names and find duplicate groups"
```

---

### Task 2: Core — merge + grade conflict model

**Files:**
- Modify: `Classday/ClassdayCore/Sources/ClassdayCore/CourseMerger.swift`
- Test: `Classday/ClassdayCore/Tests/ClassdayCoreTests/CourseMergerTests.swift`

**Interfaces:**
- Consumes: Task 1's `DuplicateGroup`, `normalizeCourseName`, `findDuplicateGroups`.
- Produces: `public typealias CourseIDRemap = [UUID: UUID]` (deleted course id → survivor id); `public func mergeDuplicateGroup(_ group: DuplicateGroup, gradeSourceID: UUID?) -> (course: Course, remap: CourseIDRemap)`.

Merge rules (from the spec, implement exactly):
- Survivor = first course in the group's document order. Survivor keeps its own `id` (never generate a new one).
- `meetings` = union of all members' meetings, deduped by `(weekday, startPeriod, endPeriod)`; every meeting keeps its original `id`.
- `weeks` = union of all members' weeks, deduped and sorted.
- `teacher` / `location` / `department` / `note` / `colorID` / `kind` / `credits` = survivor's. `reminderLeadMinutes` = survivor's, else the first non-nil among members in document order.
- Grade: if no member has a grade → `grade` nil, `gradeScheme` nil. If exactly one distinct grade value exists among members → keep that member's grade AND scheme together (if the same grade value appears with different schemes, take the scheme of the earliest member in document order with that grade). If two or more distinct grade values exist → conflict: `gradeSourceID` must be the id of a member that has a grade, and that member's grade AND scheme win; if `gradeSourceID` is nil or not a graded member in a conflict, the function must not silently pick — it traps (precondition failure) so the caller can never merge a conflicted group without a choice.
- `remap`: every non-survivor member id → survivor id.

- [ ] **Step 1: Write the failing tests** in `CourseMergerTests.swift`:
```swift
func testMergeKeepsSurvivorIDAndUnionsMeetings() // two members sharing one (weekday, startPeriod, endPeriod) → merged meetings deduped, meeting ids kept
func testMergeUnionsWeeksSorted() // weeks [1,2] + [2,3] → [1,2,3]
func testMergeKeepsSingleGrade() // only one member graded → its grade + scheme kept
func testMergeSameGradeKeepsEarliestScheme() // same grade, different schemes → earliest member's scheme
func testMergeNoGradeStaysNil() // nobody graded → nil, nil
func testMergeGradeConflictRequiresChoice() // two different grades, gradeSourceID nil → traps; with a graded member's id → that grade + scheme win
func testMergeRemapMapsDeletedIDsToSurvivor() // remap has both deleted ids → survivor id
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Classday/ClassdayCore && swift test --filter CourseMergerTests` (CI only)
Expected: FAIL (function not defined)

- [ ] **Step 3: Implement `mergeDuplicateGroup` and `CourseIDRemap` in `CourseMerger.swift`**

Per the merge rules above. Pure function, no I/O.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Classday/ClassdayCore && swift test --filter CourseMergerTests` (CI only)
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Classday/ClassdayCore/Sources/ClassdayCore/CourseMerger.swift Classday/ClassdayCore/Tests/ClassdayCoreTests/CourseMergerTests.swift
git commit -m "feat(core): merge duplicate course groups with grade conflict choice"
```

---

### Task 3: Core — remap overrides and cancellations

**Files:**
- Modify: `Classday/ClassdayCore/Sources/ClassdayCore/CourseMerger.swift`
- Test: `Classday/ClassdayCore/Tests/ClassdayCoreTests/CourseMergerTests.swift`

**Interfaces:**
- Consumes: Task 2's `CourseIDRemap`; `OccurrenceOverride` (`ScheduleExtras.swift:46`: fields include `courseID`, `meetingID`, `week`, `kind` — confirm exact field names from the file); `ClassCancellation` (`Models.swift:351`: anchored by `courseID`, nil = whole-day record — confirm exact field name from the file).
- Produces: `public func remapOccurrenceOverrides(_ overrides: [OccurrenceOverride], remap: CourseIDRemap) -> [OccurrenceOverride]`; `public func remapClassCancellations(_ cancellations: [ClassCancellation], remap: CourseIDRemap) -> [ClassCancellation]`.

Remap rules: for each record whose `courseID` is a key in `remap`, replace it with the mapped survivor id; leave `meetingID` untouched; leave records whose `courseID` is nil or not in the map untouched. Order and all other fields unchanged.

- [ ] **Step 1: Write the failing tests** in `CourseMergerTests.swift`:
```swift
func testRemapOverridesRewritesDeletedCourseIDs() // override on deleted id → survivor id, meetingID unchanged
func testRemapOverridesLeavesUnmappedUntouched() // override on survivor/other id → identical
func testRemapCancellationsRewritesDeletedCourseIDs() // cancellation on deleted id → survivor id
func testRemapCancellationsLeavesNilCourseIDUntouched() // whole-day cancellation (nil courseID) → identical
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Classday/ClassdayCore && swift test --filter CourseMergerTests` (CI only)
Expected: FAIL (functions not defined)

- [ ] **Step 3: Implement both remap functions in `CourseMerger.swift`**

Per the remap rules above. Pure functions, no I/O.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Classday/ClassdayCore && swift test --filter CourseMergerTests` (CI only)
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Classday/ClassdayCore/Sources/ClassdayCore/CourseMerger.swift Classday/ClassdayCore/Tests/ClassdayCoreTests/CourseMergerTests.swift
git commit -m "feat(core): remap overrides and cancellations to merged survivor"
```

---

### Task 4: App — confirm page UI + entry + post-import banner

**Files:**
- Create: `Classday/ClassdayApp/Sources/MergeReviewView.swift`
- Modify: `Classday/ClassdayApp/Sources/RootView.swift` (entry + banner + navigation)
- Modify: `Classday/Classday.xcodeproj/project.pbxproj` (hand-add `MergeReviewView.swift` fileRef + buildFile, following the existing `GeminiClient.swift` pattern; never run `generate_xcodeproj.py`)
- Modify: `Classday/ClassdayApp/Sources/AppModel.swift` (expose the duplicate groups for the entry/banner; hook the post-import check into `importCalendar` :926)

**Interfaces:**
- Consumes: Tasks 1–3 (`findDuplicateGroups`, `DuplicateGroup`, `mergeDuplicateGroup`, remap functions).
- Produces: `MergeReviewView` (SwiftUI view taking the groups and a completion callback); an entry row on the "全部课程" page (`RootView.swift:857` area) shown only when groups exist, labeled with the group count ("发现 N 组同名课程"); a banner shown after an import that produced duplicate groups, leading to the confirm page.

Confirm page behavior (from the spec, implement exactly):
- One card per group: each member's teacher, location, periods, weeks, grade status. A per-member "exclude from this group" control; excluded members stay independent.
- Per-group merge button + a "全部合并" button.
- Teacher mismatch within a group shows the warning "老师不一致，请确认是同一门课" and does not block merging.
- Grade conflict within a group: show both grades as a two-choice picker; the group's merge button is disabled until a choice is made.
- The page does NOT execute the merge itself — it reports the user's decisions (which groups, which exclusions, which grade choices) to `AppModel.applyCourseMerge` (Task 5). Keep the page free of backup/persist logic.

- [ ] **Step 1: Build the page skeleton + entry + banner, then verify by review**

No unit-test target exists for App-layer UI in CI (only `swift test` for Core and `xcodebuild build`); verification is the per-task review + the final `xcodebuild` on CI. Follow the existing patterns in `RootView.swift` and `CourseDetailView.swift` for navigation, banners, and dialogs.

- [ ] **Step 2: Verify the build compiles**

Run: `xcodebuild` via the CI workflow on the draft PR (CI only; this VM has no Xcode — record that verification happens on CI and do not claim a local build)

- [ ] **Step 3: Commit**

```bash
git add Classday/ClassdayApp/Sources/MergeReviewView.swift Classday/ClassdayApp/Sources/RootView.swift Classday/ClassdayApp/Sources/AppModel.swift Classday/Classday.xcodeproj/project.pbxproj
git commit -m "feat(app): merge review page, all-courses entry, post-import banner"
```

---

### Task 5: App — execute merge + backup + persist

**Files:**
- Modify: `Classday/ClassdayApp/Sources/AppModel.swift`

**Interfaces:**
- Consumes: Task 2's `mergeDuplicateGroup` + `CourseIDRemap`; Task 3's remap functions; Task 4's decisions (groups, exclusions, grade choices).
- Produces: `func applyCourseMerge(groups: [DuplicateGroup], exclusions: [String: Set<UUID>], gradeChoices: [String: UUID?])` on `AppModel`. Keys are the group's `normalizedName` (unique per group by construction): `exclusions` holds the course ids to leave out of that group (if fewer than 2 members remain after exclusion, skip the group); `gradeChoices` holds the `gradeSourceID` for that group (nil = no conflict, auto rules apply). The function computes the merges itself via Task 2's `mergeDuplicateGroup`, so the review page stays thin — it reports decisions, never merge results.

Apply order (from the spec, implement exactly):
1. Compute all merge results first (pure computation, no mutation): for each group, filter out excluded members, then call `mergeDuplicateGroup` with that group's grade choice.
2. Back up the current document via the existing `duplicateTimetable(named:)` (`AppModel.swift:759`), name like "合并前备份 11-12 16:30" (current date/time at execution).
3. Replace each group's members in `document.courses` with its merged course (survivor position kept).
3. Rewrite `OccurrenceOverride.courseID` and `ClassCancellation.courseID` through the remaps (Task 3 functions).
4. Persist through the existing persist path (the same one `saveCourse`/`importCalendar` use) so reminders, Live Activity, and widgets recompute from the new document. Do not add new notification/Live Activity code.
5. Do not touch exams/homework (name-based, unaffected) and do not touch the OCR badge.

- [ ] **Step 1: Implement `applyCourseMerge` in `AppModel.swift`**

Per the apply order above. No new UI in this task.

- [ ] **Step 2: Verify by review + CI build**

No App-layer unit-test target runs in CI; verification is the per-task review + the final `xcodebuild` on CI. State this in the report.

- [ ] **Step 3: Commit**

```bash
git add Classday/ClassdayApp/Sources/AppModel.swift
git commit -m "feat(app): execute course merge with pre-merge backup and persist"
```

---

### Task 6: Tests + docs

**Files:**
- Modify: `Classday/Docs/DATA_SCHEMA.md` (one-line note)
- Modify: `Classday/Docs/REGRESSION_CHECKLIST.md` (one new item)
- Test: full Core suite via CI

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: docs note + checklist item; a full-suite green expectation.

- [ ] **Step 1: Add the DATA_SCHEMA.md note**

Exact wording: "同名课程由 App 合并，schema 本身不禁止同名（现状已如此）。"

- [ ] **Step 2: Add one regression checklist item**

Wording: "同名课合并后成绩/GPA/提醒正常" (place it with the other course/grade items).

- [ ] **Step 3: Run the local Python checks**

Run: `python3 Classday/Tools/check_project.py` and `python3 Classday/Tools/check_version_snapshot.py --self-test` and `--base main` from the worktree.
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add Classday/Docs/DATA_SCHEMA.md Classday/Docs/REGRESSION_CHECKLIST.md
git commit -m "docs: note duplicate-course merge in schema; add merge regression item"
```

---

### Task 7: Whole-branch review

**Files:** none (review only)

- [ ] **Step 1: Request the whole-branch review** (controller dispatches it; implementers do not review their own work)
- [ ] **Step 2: Fix wave for any Critical/Important findings**, then a scoped re-review of the fix diff
- [ ] **Step 3: Confirm the branch is review-clean and CI-green before the controller reports** (do not push, open a PR, merge, or release — the controller does that)

---

## Self-Review

- Spec coverage: normalization (§1) → Task 1; merge rules + grade conflict (§3) → Task 2; override/cancellation migration (§4 table) → Task 3; confirm page + entry + banner (§5) → Task 4; backup + persist (§6) → Task 5; version (§7) is a non-change (no version strings touched anywhere); docs/testing → Task 6; Android sync (§Architecture) is a constraint on all tasks, not a separate task.
- Step scan: every step names one action with a checkable result; test steps carry exact names and assertions; code steps carry exact signatures and file paths.
- Type consistency: `DuplicateGroup`, `CourseIDRemap`, `mergeDuplicateGroup(_:gradeSourceID:)`, `remapOccurrenceOverrides`, `remapClassCancellations`, `applyCourseMerge(groups:exclusions:gradeChoices:)` use the same names across Tasks 1–5.
- Review Focus: all five input classes have tests pinned (Tasks 1, 2, 3, 4, 5 as listed).
- Proportion: plan is shorter than the spec and carries decisions, not code bodies.
