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

## What 2.9.3 does

- Create, edit, and delete courses: name, teacher, location, department, note, kind, color, weeks, one or more weekday/period meetings, reminder lead time.
- Semester name, start date, week count, and the ten default period clocks. Overlap is detected by weekday, period span, and shared weeks.
- Week grid and day list. Swipe or use the arrows to change week or day. 回本周 returns to today. Reduced Motion turns the spring animation off.
- Tap a block to expand into course detail and shrink back. Sheets use a spring presentation and a light material blur.
- Press feedback and haptics on pickup, save, and a rejected drop.
- Long-press a week-grid block to drag it. A conflicting or out-of-range drop is cancelled. A successful drop can be undone for a few seconds. VoiceOver uses 调整时间 instead of the drag.
- Current class progress and a next-class countdown.
- Small next-class widget and medium today widget. They read the App Group file, follow the device timezone, show an empty state, and deep-link into the course. Edits reload timelines. The timeline itself moves at class boundaries so the app does not poll WidgetKit.
- Local notification reminders, requested only when a reminder is turned on. Status is shown in 我的. At most 60 pending reminders.
- JSON import and export, schema version 1. See [Docs/DATA_SCHEMA.md](Docs/DATA_SCHEMA.md).
- Dynamic Type, VoiceOver labels, portrait iPhone layout, light and dark appearance.
- Demo seed with reset and clear.

### New in 2.4.0–2.9.3

- Per-course grading rules (2.4.0): each course can have its own components (project, quiz, exam…) and weights, and the total is computed automatically. Several candidate formulas can compete and the highest wins, the scale can be 20 or 100 points, and a 20-point total is converted to percent for GPA. A course without a rule keeps direct total entry, and the course detail shows the "total / scale · rule-computed" basis.
- AI grading-rule recognition (2.5.0): photograph a grading-formula screenshot and AI fills the scale, components, and candidate formulas as a draft to check and correct before saving. It uses Gemini vision; the first use asks for a Google AI Studio key, which is then kept in the device keychain.
- School-calendar holidays and no-class periods (2.6.0): classes inside a holiday are skipped and not reminded, and the today and week views mark 假期. Import from a `.ics` calendar file or by photographing the calendar with AI, with a confirmation page to check each item before it is written. Semester settings show the computed end date, and the holiday list can be edited there at any time.
- Email cancellation recognition (2.7.0): when a teacher emails that a class is off, paste the email text or pick a mail screenshot in 我的 › 假期与不上课时段 › 邮件停课识别 and AI identifies the date, course, and sessions (relative dates such as 今天/明天 are converted). It starts as a draft — single-course vs whole-day cancellation, date, course, sessions, and reason can each be checked and changed — and only takes effect on confirm. A cancelled session no longer appears and no longer reminds; later classes that day run as normal. Cancellations are managed together with holidays, and deleting a record restores the class.
- SideStore update installs (2.4.1, 2.7.1): after 检查更新 downloads a new version, install it through SideStore — download the IPA to Files, connect LocalDevVPN, then tap + in SideStore and pick the IPA — so later updates no longer need a computer and Sideloadly. 2.7.1 also fixed course-page scrolling by switching to the system native list (swipe-to-delete kept, still with a confirmation first) and changed the install package to an English registered name with a Chinese display name, so SideStore no longer blocks the install.
- Live Activity and update flow (2.8.0): the lock-screen island now follows the current class — it syncs when the app opens and refreshes in the background instead of freezing on a finished class. 检查更新 reads the update list from classday-releases with a fallback to the GitHub Releases API, downloads the IPA in the app with resume and size + SHA-256 verification, and blocks skipping when an update is mandatory or the installed version is below the minimum supported version.
- Duplicate-course auto-merge (2.9.0): courses with the same name are detected automatically and merged into one course after one confirmation — sessions and weeks are unioned so GPA counts once, conflicting grades are picked by the user instead of being silently overwritten, the timetable is backed up to the timetable library before merging, and an import that creates duplicates shows a banner to go merge.
- Settings navigation (2.9.1): the 我的 page is now a grouped navigation home — two cards (课表 / 通用） with six rows, each opening a dedicated sub-page for 上课时间, 学期, 假期与不上课时段, 提醒, 数据, 关于 — instead of expanding all six sections inline; the reminders page has its own save button, and unsaved drafts survive going back.
- Live Activity background-refresh follow-up (2.9.2): horizon 7 天 + 每天午夜心跳续种，跨周末不断链；午夜翻转 + 首课在 8 小时及更久之后时课前 60 分钟唤醒；过期后显示“已结束，打开课曜查看下一节”，计时器不再往上数；小组件时间线同步 7 天；关于页在后台刷新已关时提示一行。
- App icon and reliability fixes (2.9.3): a new icon (black timetable-and-clock line art on white); imports recognize title rows and carry blank course names and unfinished week ranges forward, keeping different rooms and teachers as separate courses; same-name merges keep schedules with different weeks, rooms, or parity apart and only advertise groups that can actually merge; exams and homework get reminders at the default lead time and open the matching screen, every lock-screen and Home Screen widget reloads after timetable edits, and room search falls back to the room name instead of Beijing.

Earlier releases (2.0.0–2.3.9) added smart import — timetable photos, CSV, Excel, Word, PDF, `.ics`, and pasted text, each course confirmed before it is added — eight themes with tilt-following effects and a different haptic feel per theme, plus exam countdowns, homework, and grade records with GPA.

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

The version number lives in `Classday/VERSION`, the single source of truth. Change it with one command:

```bash
Classday/Tools/bump-version.sh 1.1.0
```

The command archives the last commit into `VersionArchive/previous`, then writes the new version. It keeps that immediate previous snapshot and deletes older directories inside `VersionArchive` only. A normal commit does not take a snapshot. The current version is `2.9.3`. Details: [Docs/VERSION_BACKUPS.md](Docs/VERSION_BACKUPS.md). Pull requests run `.github/workflows/classday-version-snapshot.yml`, which fails if a version change did not archive the committed version it replaced.

## Limits

- No school login, roster sync, school grade query, or attendance.
- Portrait iPhone. iPad is not a separate target.
- Chinese interface only.
- Widgets need a shared App Group in the profile Sideloadly or Xcode installs. The id in that profile may differ from `group.com.classday.shared`. WidgetKit may still delay a reload; the timeline covers the next 36 hours of class boundaries.
- Reminders are local notifications, capped at 60.
- Drag-and-drop rescheduling is on the week grid. The day list uses 调整时间.
- Overlap is based on period numbers, not on clock times that a custom period table might make overlap.
