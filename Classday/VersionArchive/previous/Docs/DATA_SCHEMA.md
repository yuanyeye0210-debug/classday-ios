# Classday store schema

Schema version: **1**. The on-disk file is UTF-8 JSON. `StoreCodec` in ClassdayCore is the validator the app uses. A JSON Schema copy is `classday-store.schema.json`. An example generated from the demo seed is `demo-store.json`.

Import replaces the whole timetable. Overlapping courses are allowed only after you confirm the warning. Invalid JSON, a wrong `schemaVersion`, an empty name, a bad date, a week outside the semester, or a period the semester does not define are rejected and the current file is left unchanged.

同名课程由 App 合并，schema 本身不禁止同名（现状已如此）。

There is no account field. `Course` has `grade` (the total score, as a number) and an optional `gradeScheme` (the per-course grading rule); see the Course table.

Schema version 1 is frozen: these fields were added without raising the version, and no v2 is planned for them. `Semester.holidays`, `Semester.cancellations`, and `Course.gradeScheme` are all optional — a document saved before they existed has no such keys, and it still loads: the decoder reads them with `decodeIfPresent` and falls back to empty (`holidays` and `cancellations` decode as `[]`, `grade` and `gradeScheme` decode as absent).

## Document

| Field | Type | Notes |
| --- | --- | --- |
| schemaVersion | number | Must be 1 |
| origin | string | `demo` or `user` |
| semester | object | See below |
| courses | array | May be empty |

## Semester

| Field | Type | Notes |
| --- | --- | --- |
| name | string | Required |
| shortName | string | Required |
| startDate | string | `yyyy-MM-dd`, interpreted as a civil date in the device timezone |
| totalWeeks | number | 1...30. Week 1 is the Monday-start week that contains `startDate` |
| periods | array | Indexes must be 1, 2, 3, ... with no gaps |
| defaultReminderMinutes | number | 0...180. Used when a course omits `reminderLeadMinutes` |
| holidays | array | Optional. `[HolidayPeriod]`; omit or leave empty when there are none. Classes inside a holiday are skipped and not reminded |
| cancellations | array | Optional. `[ClassCancellation]`; omit or leave empty when there are none. Cancelled sessions do not appear and do not remind |

Period: `{ "index": 1, "start": "08:00", "end": "08:45" }`. `end` must be later than `start` on the same day.

HolidayPeriod: `{ "id": "<uuid>", "name": "寒假", "startDate": "2026-01-19", "endDate": "2026-02-15" }`. Dates are civil `yyyy-MM-dd` strings, both ends inclusive — the same representation `startDate` uses.

ClassCancellation: `{ "id": "<uuid>", "date": "2026-11-12", "courseID": "<uuid>", "courseName": "高等数学", "scope": "all", "reason": "老师出差" }`. `date` is a civil `yyyy-MM-dd` string. `courseID` omitted (or null) means the whole day is off; otherwise `scope` selects which of that course's sessions that day are cancelled: `"all"`, `"am"` (starts before noon), or `"pm"` (starts at or after noon).

## Course

| Field | Type | Notes |
| --- | --- | --- |
| id | string | UUID |
| name | string | Required after trimming |
| teacher, location, department, note | string | May be empty |
| colorID | string | `blue`, `orange`, `green`, `purple`, `pink`, `sage`. Unknown values draw as blue |
| kind | string | Display text such as 必修课, 选修课, 实践 |
| weeks | number array | 1-based weeks inside the semester |
| meetings | array | At least one |
| reminderLeadMinutes | number or omitted | 0 turns the reminder off. Omit to use the semester default |
| grade | number or omitted | Optional. The total score; when a `gradeScheme` is set, the scheme's computed total converted to percent |
| gradeScheme | object or omitted | Optional. `GradeScheme`: the per-course grading rule — `{ "scale": 100, "components": [...], "scores": {...}, "branches": [[...]] }`. `scale` is the point scale (100, or 20 for a 20-point course); `components` are the weighted items, `scores` maps component id to score, `branches` are the candidate formulas and the highest wins. Missing keys inside a `gradeScheme` fall back to `scale` 100 and empty `components` / `scores` / `branches` |

Meeting: `{ "id": "<uuid>", "weekday": 1, "startPeriod": 1, "endPeriod": 2 }`. Weekday 1 is Monday and 7 is Sunday. `startPeriod` must be less than or equal to `endPeriod`, and both indexes must exist.

Two meetings conflict when the weekday matches, the period ranges overlap, and the week sets overlap. Adjacent periods do not overlap.

## Export

我的 → 导出数据 writes this document. 导入数据 reads it back.
