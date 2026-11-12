# 课曜 / Heptara

Native SwiftUI iPhone app and WidgetKit extension for a local weekly timetable. The product name is 课曜 / Heptara. Marketing version 2.7.1. It is an independent design. It is not the official「超级课程表」app and does not aim for feature parity with it.

Courses, grades, holidays, and the rest of the timetable live in one JSON file on the phone and, when signing is set up, in an App Group the widgets can read. Grades are entered on the device. There is no campus grade server.

## Open it on a Mac

Requirements: Xcode 16 or newer, iOS 17 or newer. A free Apple ID is enough for a personal team on a simulator or your own iPhone. Logic tests run with `swift test` and do not need Xcode. Building the app, the widget, or an IPA does. This tree is not itself an installable IPA.

```bash
cd Classday
open Classday.xcodeproj
```

The shared scheme is **Classday**. It builds the app and embeds `ClassdayWidget.appex`.

Regenerate the project file after adding or removing Swift files:

```bash
python3 Tools/generate_xcodeproj.py
```

`project.yml` is an equivalent spec for [XcodeGen](https://github.com/yonaskolb/XcodeGen). The checked-in `Classday.xcodeproj` is what you open. If you regenerate with XcodeGen, do that instead of mixing the two outputs.

## Signing

See [Docs/SIGNING.md](Docs/SIGNING.md). Install with SideStore and LocalDevVPN. Add this source once; SideStore then offers updates itself:

`https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/apps.json`

Both targets declare the App Group `group.com.classday.shared`. A free Apple ID resign may grant a different id under your team. The app and the widget pick that granted id together. Until a shared group can be opened, the timetable stays in Application Support, 我的 names the group ids the profile actually contained, and the widgets show 读不到课表.

Bundle IDs in the project:

- App: `com.classday.app`
- Widget: `com.classday.app.widget`

The entitlements and `AppGroup.identifier` stay on `group.com.classday.shared`. You do not have to edit that string when SideStore rewrites the group for a free Apple ID.

## Run on iPhone

1. Select your Team for **Classday** and **ClassdayWidget**.
2. Let Xcode register the App Group, or create `group.com.classday.shared` in the developer portal and enable it on both App IDs.
3. Choose an iPhone or simulator and Run.
4. The first launch writes clearly marked demo courses (2026 秋季学期, week of 2–8 November 2026 is week 10). The timetable shows a 演示数据 badge. 我的 can restore that demo or clear every course.
5. On the Home Screen, long-press, tap +, and search 课曜 (or Heptara when the phone language is English). The gallery lists 下一节, 今日课程, 卡片叠放, 本周课表, and 锁屏下一节. See [Docs/WIDGETS.md](Docs/WIDGETS.md).

Deep links use `classday://course/<uuid>?meeting=<uuid>`. Notification taps, the small widget, and the medium widget's course chips open the course detail.

## What 2.7 does

- Four tabs: 今日, 周览, 课程, 我的. There is no fifth tab.
- 周览 switches between 周记 and 网格. 周记 lists each day, including personal events and a 假期 mark. 网格 is the period grid. Long-press a block to drag it. A conflicting or out-of-range drop is cancelled. A successful drop can be undone for a few seconds. VoiceOver uses 调整时间 instead of the drag.
- Create, edit, and delete courses: name, teacher, location, department, note, kind, color, credits, optional grade, optional grade scheme, weeks, one or more weekday/period meetings, reminder lead time. Odd/even weeks and one-week cancel, move, or delay overrides.
- Semester name, start date, week count, period clocks, holidays, and per-session cancellations (including a draft parsed from a pasted email or a screenshot). Overlap is detected by weekday, period span, and shared weeks.
- Today: next class, progress, the day's courses and personal events, exam countdown, homework.
- Course list with weighted average, GPA, and earned credits. Swipe to delete asks first.
- Exams, homework, and personal events.
- A timetable library: save the current table and switch back later.
- JSON import and export. The `schemaVersion` integer is still 1; the document includes the 2.7 fields. See [Docs/DATA_SCHEMA.md](Docs/DATA_SCHEMA.md).
- Smart import from a photo, CSV, Excel, Word, PDF, or calendar file. The result is a draft you confirm before it replaces anything.
- Widgets, a local Live Activity, and an iOS 18 Control Center control. See [Docs/WIDGETS.md](Docs/WIDGETS.md).
- Local notification reminders, requested only when a reminder is turned on. Status is shown in 我的. At most 60 pending reminders.
- Eight themes, with motion and haptics that follow the theme. Dynamic Type, VoiceOver labels, light and dark appearance.
- 我的 → 检查更新 reads the SideStore source above.

## Tests without Xcode

Logic that does not need SwiftUI lives in `ClassdayCore` and runs on Linux or Mac:

```bash
cd Classday/ClassdayCore
swift test
python3 ../Tools/check_project.py
```

Or `Tools/linux-check.sh`. Covered areas: week dates, overlap and drag validation, JSON persistence and import, a current export checked against `Docs/classday-store.schema.json`, next class and widget selection, notification plans, version-bump snapshots, and the check that a skipped snapshot fails.

Xcode build, simulator, and device runs are not part of `swift test`.

## Version backups

The marketing version lives in `Classday/VERSION` (2.7.1). The build number lives in `Classday/BUILD` (`CFBundleVersion`, currently 1). Change them with one command:

```bash
Classday/Tools/bump-version.sh 1.1.0
```

The command archives the last commit into `VersionArchive/previous`, writes the new marketing version, and increments `BUILD`. It then rewrites `project.yml` and `project.pbxproj` from those two files. It keeps that immediate previous snapshot and deletes older directories inside `VersionArchive` only. A normal commit does not take a snapshot. Do not hand-write a snapshot. Details: [Docs/VERSION_BACKUPS.md](Docs/VERSION_BACKUPS.md). Pull requests run `.github/workflows/classday-version-snapshot.yml`, which fails if a version change did not archive the committed version it replaced or did not increase the build number.

## Limits

- No official campus roster or attendance sync. Fénix login and calendar import are optional and stay on the phone.
- iPhone first. The target also includes iPad, using the same layout rather than a separate iPad design.
- Chinese interface. The English home-screen name is Heptara.
- Widgets need a shared App Group in the profile SideStore or Xcode installs. The id in that profile may differ from `group.com.classday.shared`. WidgetKit may still delay a reload; the timeline covers the next 36 hours of class boundaries.
- A free Apple ID can keep 3 sideloaded apps (SideStore and LocalDevVPN count, 课曜 is the third) and can register 10 App IDs every 7 days. The widget extension uses a second App ID.
- Reminders are local notifications, capped at 60.
- Drag-and-drop rescheduling is the 周览 grid. 周记 does not drag. VoiceOver uses 调整时间 on a grid block.
- Overlap is based on period numbers, not on clock times that a custom period table might make overlap.
