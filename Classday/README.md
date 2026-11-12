# 课曜 / Heptara

Native SwiftUI iPhone app and WidgetKit extension for a local weekly timetable. The product name is 课曜 / Heptara. It is an independent design. It is not the official「超级课程表」app and does not aim for feature parity with it.

There is no campus account, grade query, or school server. Courses live in a JSON file on the phone and, when signing is set up, in an App Group the widgets can read.

## Open it on a Mac

Requirements: Xcode 16 or newer, iOS 17 or newer. A free Apple ID is enough for a personal team on a simulator or your own iPhone. This repository was prepared on Linux, so the iOS compile and the simulator were **not** run here. Do not treat this tree as an installable IPA.

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

See [Docs/SIGNING.md](Docs/SIGNING.md). Both targets declare the App Group `group.com.classday.shared`. A free Apple ID resign may grant a different id under your team. The app and the widget pick that granted id together. Until a shared group can be opened, the timetable stays in Application Support, 我的 explains the Sideloadly setting, and the widgets show 读不到课表.

Bundle IDs in the project:

- App: `com.classday.app`
- Widget: `com.classday.app.widget`

The entitlements and `AppGroup.identifier` stay on `group.com.classday.shared`. You do not have to edit that string when Sideloadly rewrites the group for a free Apple ID.

## Run on iPhone

1. Select your Team for **Classday** and **ClassdayWidget**.
2. Let Xcode register the App Group, or create `group.com.classday.shared` in the developer portal and enable it on both App IDs.
3. Choose an iPhone or simulator and Run.
4. The first launch writes clearly marked demo courses (2026 秋季学期, week of 2–8 November 2026 is week 10). The timetable shows a 演示数据 badge. 我的 can restore that demo or clear every course.
5. On the Home Screen, long-press, tap +, and search 课曜 (or Heptara when the phone language is English). Add **下一节** (small) and **今日课程** (medium).

Deep links use `classday://course/<uuid>?meeting=<uuid>`. Notification taps and widget taps open the course detail.

## What V1 does

- Create, edit, and delete courses: name, teacher, location, department, note, kind, color, weeks, one or more weekday/period meetings, reminder lead time.
- Semester name, start date, week count, and the ten default period clocks. Overlap is detected by weekday, period span, and shared weeks.
- Week grid and day list. Swipe or use the arrows to change week or day. 回本周 returns to today. Reduced Motion turns the spring animation off.
- Tap a block to expand into course detail and shrink back. Sheets use a spring presentation and a light material blur.
- Press feedback and haptics on pickup, save, and a rejected drop.
- Long-press a week-grid block to drag it. A conflicting or out-of-range drop is cancelled. A successful drop can be undone for a few seconds. VoiceOver uses 调整时间 instead of the drag.
- Current class progress and a next-class countdown.
- Small next-class widget and medium today widget. They read the App Group file, follow the device timezone, show an empty state, and deep-link into the course. Edits reload timelines. The timeline itself moves at class boundaries so the app does not poll WidgetKit.
- Local notification reminders, requested only when a reminder is turned on. Status is shown in 我的. At most 64 pending reminders, nearest first.
- JSON import and export, schema version 1. See [Docs/DATA_SCHEMA.md](Docs/DATA_SCHEMA.md).
- Dynamic Type, VoiceOver labels, portrait iPhone layout, light and dark appearance.
- Demo seed with reset and clear.

The approved week grid and the detail mock disagree about 高等数学 on Wednesday (the grid places it in periods 3–4, the detail text says periods 1–2 on both days). The stored demo follows the grid and the Monday widget times. Detail copy lists each meeting with its own period and clock.

## Tests without Xcode

Logic that does not need SwiftUI lives in `ClassdayCore` and runs on Linux or Mac:

```bash
cd Classday/ClassdayCore
swift test
python3 ../Tools/check_project.py
```

Or `Tools/linux-check.sh`. Covered areas: week dates, overlap and drag validation, JSON persistence and import, next class and widget selection, notification plans, version-bump snapshots, and the check that a skipped snapshot fails.

Xcode build, simulator, and device runs were not executed in the environment that added this tree. There is no IPA here.

## Version backups

The version number lives in `Classday/VERSION`. Change it with one command:

```bash
Classday/Tools/bump-version.sh 1.1.0
```

The command archives the last commit into `VersionArchive/previous`, then writes the new version. It keeps that immediate previous snapshot and deletes older directories inside `VersionArchive` only. A normal commit does not take a snapshot. V1 is `1.0.0` and has no `previous/` folder. Details: [Docs/VERSION_BACKUPS.md](Docs/VERSION_BACKUPS.md). Pull requests run `.github/workflows/classday-version-snapshot.yml`, which fails if a version change did not archive the committed version it replaced.

## Limits

- No school login, roster sync, grades, or attendance.
- Portrait iPhone. iPad is not a separate target.
- Chinese interface only.
- Widgets need a shared App Group in the profile Sideloadly or Xcode installs. The id in that profile may differ from `group.com.classday.shared`. WidgetKit may still delay a reload; the timeline covers the next 36 hours of class boundaries.
- Reminders are local notifications, capped at 60.
- Drag-and-drop rescheduling is on the week grid. The day list uses 调整时间.
- Overlap is based on period numbers, not on clock times that a custom period table might make overlap.
