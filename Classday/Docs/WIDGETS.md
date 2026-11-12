# Widgets

`ClassdayWidgetBundle` registers every widget below. They share the App Group JSON file. The home-screen and lock-screen widgets use one `ClassdayProvider` timeline. The Live Activity and the iOS 18 control do not.

| Kind | Family | Name | Shows |
| --- | --- | --- | --- |
| `NextClassWidget` | systemSmall | 下一节 | Next class, or the class in progress, with a countdown |
| `TodayCoursesWidget` | systemMedium | 今日课程 | Up to three of today's courses and the day's total |
| `FanStackWidget` | systemMedium | 卡片叠放 | Today's courses as a small stack. 下一张 advances the card |
| `WeekBoardWidget` | systemLarge | 本周课表 | The week that contains the timeline date, one line per day |
| `LockNextWidget` | accessoryCircular, accessoryRectangular, accessoryInline | 锁屏下一节 | Next class title, place, and a timer on the Lock Screen |
| `NextClassActivityWidget` | Live Activity | — | Lock Screen banner and Dynamic Island for the current or next class |
| `NextClassControl` | Control Center, iOS 18 | 下一节 | Opens the app. The bundle omits it on iOS 17 |

`WidgetID` in ClassdayCore names only `NextClassWidget` and `TodayCoursesWidget`. The other kinds are the string literals in `ClassdayWidget/Sources/ExtraWidgets.swift`.

The app calls `WidgetCenter.reloadTimelines` only after a save, import, reset, or clear. It does not reload on a timer. The Live Activity is updated from the app with `pushType: nil`, so it moves while the app is running and is not a remote push.

## Timeline

`WidgetProjection.timelinePlan` builds entries from the current instant, each class start and end, and local midnights inside a 36-hour horizon. The count is capped at 40. The reload policy is `.after` the last entry, and never sooner than 15 minutes when the horizon is empty. That is how the widget moves from 待上课 to 上课中 without another budgeted reload.

WidgetKit still decides whether a reload request runs. A burst of edits can be coalesced. The on-disk JSON is the source of truth the next time a timeline is built.

`FanStackWidget` and `WeekBoardWidget` use that timeline for the entry date, then read the shared store again inside the view. 卡片叠放 also reads a small integer in the App Group defaults so 下一张 can change cards without a new timeline. 本周课表 shows the week index of the entry date.

The app and the widget resolve one App Group at runtime (`AppGroupResolver`). The preferred id is `group.com.classday.shared`. A free-account resign often grants a different id; both targets read `embedded.mobileprovision` and use the first id that both profiles contain and that the process can actually open. If that file is missing, the widget shows 读不到课表 and tells you to open 课曜 or reinstall with the widget extension kept. The gallery placeholder uses the demo timetable at 2 November 2026 07:40 so the add-widget sheet is not blank. That placeholder is sample data, not a live capture.

## Deep links

The small widget opens `classday://course/<id>?meeting=<id>` via `widgetURL`. Each chip on 今日课程 is a `Link` to the same URL. 卡片叠放, 本周课表, 锁屏下一节, the Live Activity, and the control do not attach that URL. The control and 下一节在哪上课 open the app instead.

## Buttons and Shortcuts

These write the shared store or the App Group defaults. They are the same actions the widget buttons run:

| Intent | What it does |
| --- | --- |
| 已到教室 | Stores a timestamp in the App Group defaults |
| 推迟 10 分钟 | Writes a `delayed` override on the current or next class |
| 下一张 | Advances the 卡片叠放 index |
| 下一节在哪上课 | Opens the app and speaks the next class and its place |
| 打开下一节 | Opens the app from the control |

## Date

Calendars are Gregorian with the device timezone (`ClassdayCalendar.make()`). Stored dates such as the semester start are civil `yyyy-MM-dd` values interpreted in that timezone, so a timezone change does not shift the calendar day by itself. Class clocks use the period table in local time.
