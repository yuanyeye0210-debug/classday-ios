# Widgets

Two real WidgetKit widgets share one timeline provider and the App Group JSON file.

| Kind | Family | Shows |
| --- | --- | --- |
| `NextClassWidget` | systemSmall | Next class, or the class in progress, with a countdown |
| `TodayCoursesWidget` | systemMedium | Up to three of today's courses and the day's total |

Kinds are `WidgetID` in ClassdayCore. The app calls `WidgetCenter.reloadTimelines` only after a save, import, reset, or clear. It does not reload on a timer.

## Timeline

`WidgetProjection.timelinePlan` builds entries from the current instant, each class start and end, and local midnights inside a 36-hour horizon. The count is capped at 40. The reload policy is `.after` the last entry, and never sooner than 15 minutes when the horizon is empty. That is how the widget moves from 待上课 to 上课中 without another budgeted reload.

WidgetKit still decides whether a reload request runs. A burst of edits can be coalesced. The on-disk JSON is the source of truth the next time a timeline is built.

The app and the widget resolve one App Group at runtime (`AppGroupResolver`). The preferred id is `group.com.classday.shared`. A free-account resign often grants a different id; both targets read `embedded.mobileprovision` and use the first id that both profiles contain and that the process can actually open. If that file is missing, the widget shows 读不到课表 and tells you to open 课间 or reinstall with the widget extension kept. The gallery placeholder uses the demo timetable at 2 November 2026 07:40 so the add-widget sheet is not blank. That placeholder is sample data, not a live capture.

## Deep links

Each course chip and the small widget open `classday://course/<id>?meeting=<id>`.

## Date

Calendars are Gregorian with the device timezone (`ClassdayCalendar.make()`). Stored dates such as the semester start are civil `yyyy-MM-dd` values interpreted in that timezone, so a timezone change does not shift the calendar day by itself. Class clocks use the period table in local time.
