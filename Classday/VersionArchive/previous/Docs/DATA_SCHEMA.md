# Classday store schema

Schema version: **1**. The on-disk file is UTF-8 JSON. `StoreCodec` in ClassdayCore is the validator the app uses. A JSON Schema copy is `classday-store.schema.json`. An example generated from the demo seed is `demo-store.json`.

Import replaces the whole timetable. Overlapping courses are allowed only after you confirm the warning. Invalid JSON, a wrong `schemaVersion`, an empty name, a bad date, a week outside the semester, or a period the semester does not define are rejected and the current file is left unchanged.

There is no account field and no grade field.

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

Period: `{ "index": 1, "start": "08:00", "end": "08:45" }`. `end` must be later than `start` on the same day.

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

Meeting: `{ "id": "<uuid>", "weekday": 1, "startPeriod": 1, "endPeriod": 2 }`. Weekday 1 is Monday and 7 is Sunday. `startPeriod` must be less than or equal to `endPeriod`, and both indexes must exist.

Two meetings conflict when the weekday matches, the period ranges overlap, and the week sets overlap. Adjacent periods do not overlap.

## Export

我的 → 导出 JSON writes this document. 导入 JSON reads it back.
