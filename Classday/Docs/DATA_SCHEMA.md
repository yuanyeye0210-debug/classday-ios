# Classday store schema

Schema version integer: **1** (`StoreDocument.currentSchema`). That number did not move when grades, holidays, and the timetable library were added. Older files omit the newer keys and still decode. A file saved by 2.7 writes the keys it has. The on-disk file is UTF-8 JSON, pretty-printed with sorted keys. `StoreCodec` in ClassdayCore is the validator the app uses on import. `classday-store.schema.json` matches the Codable shape so a current export can be checked without the app. An example generated from the demo seed is `demo-store.json`.

Import replaces the whole timetable. Overlapping courses are allowed only after you confirm the warning. Invalid JSON, a wrong `schemaVersion`, an empty name, a bad date, a week outside the semester, or a period the semester does not define are rejected and the current file is left unchanged.

There is no account field. Grades in this file are numbers entered on the phone. They are not a campus grade query.

`additionalProperties` is false on every object. A key the schema does not list fails validation. Keys the decoder loads with `decodeIfPresent` are optional below, so an older file that omits them still imports. The encoder writes every non-optional stored property, so a current file includes `activeTimetableID`, `appearance`, `subscribedICSURL`, and the arrays `weekRules`, `overrides`, `exams`, `homework`, `personalEvents`, `rooms`, `library`, `holidays`, and `cancellations` even when those arrays are empty. Nil optionals (`grade`, `gradeScheme`, `reminderLeadMinutes`, room coordinates, `courseID` on a whole-day cancellation, and the unused override fields) are omitted, not written as `null`.

## Document

| Field | Type | Notes |
| --- | --- | --- |
| schemaVersion | number | Must be 1 |
| origin | string | `demo` or `user` |
| semester | object | See below |
| courses | array | May be empty |
| weekRules | array | Optional. Odd/even week filters. See below |
| overrides | array | Optional. One-week cancel, move, or delay |
| exams | array | Optional |
| homework | array | Optional |
| personalEvents | array | Optional. Personal plans, not courses |
| rooms | array | Optional. Named places, with coordinates when set |
| library | array | Optional. Other saved timetables. Does not include `personalEvents`, `appearance`, or `subscribedICSURL` |
| activeTimetableID | string | Optional UUID. Omitted files decode as `00000000-0000-0000-0000-0000000000aa` |
| appearance | object | Optional. `{ "themeID": "neon", "performance": "balanced" }`. `performance` is `high`, `balanced`, or `saver`. Unknown theme ids are stored and draw as neon |
| subscribedICSURL | string | Optional. Empty when no calendar subscription is saved |

## Semester

| Field | Type | Notes |
| --- | --- | --- |
| name | string | Required |
| shortName | string | Required |
| startDate | string | `yyyy-MM-dd`, a civil date in the device timezone |
| totalWeeks | number | 1...30. Week 1 is the Monday-start week that contains `startDate` |
| periods | array | Indexes must be 1, 2, 3, ... with no gaps. `StoreCodec` checks the gaps; the JSON Schema checks each index is an integer |
| defaultReminderMinutes | number | 0...180. Used when a course omits `reminderLeadMinutes` |
| holidays | array | Optional. Missing on files saved before holidays existed |
| cancellations | array | Optional. One cancelled session or a whole cancelled day |

Period: `{ "index": 1, "start": "08:00", "end": "08:45" }`. `end` must be later than `start` on the same day.

Holiday: `{ "id": "<uuid>", "name": "国庆", "startDate": "2026-10-01", "endDate": "2026-10-07" }`. Both dates are inclusive civil dates, and `startDate` must not be after `endDate`.

Cancellation: `{ "id": "<uuid>", "date": "2026-11-12", "courseID": "<uuid>", "courseName": "高等数学", "scope": "am", "reason": "" }`. `courseID` is omitted when the whole day is off. `scope` is `day` (whole day), `all` (every session of that course that day), `am` (starts before noon), or `pm` (starts at or after noon).

## Course

| Field | Type | Notes |
| --- | --- | --- |
| id | string | UUID |
| name | string | Required after trimming |
| teacher, location | string | May be empty |
| department, note, kind | string | Optional on decode. `kind` defaults to 必修课. Current exports write all three |
| colorID | string | `blue`, `orange`, `green`, `purple`, `pink`, `sage`. Unknown values draw as blue |
| weeks | number array | 1-based weeks inside the semester |
| meetings | array | At least one |
| reminderLeadMinutes | number or omitted | 0 turns the reminder off. Omit to use the semester default |
| credits | number or omitted | Defaults to 0 |
| grade | number or omitted | Percent-scale total used for GPA. Omitted when unset |
| gradeScheme | object or omitted | Per-course scoring rule. The normalized result is what the app copies into `grade` |

Meeting: `{ "id": "<uuid>", "weekday": 1, "startPeriod": 1, "endPeriod": 2 }`. Weekday 1 is Monday and 7 is Sunday. `startPeriod` must be less than or equal to `endPeriod`, and both indexes must exist.

Grade scheme: `scale` is the raw full mark (20 or 100 are the ones the editor offers). `components` is `[{ "id": "p", "name": "P" }]`. `scores` maps a component id to a number. `branches` is a list of candidate formulas; each formula is `[{ "componentID": "p", "weight": 0.25 }]`. The total is the highest complete branch. `grade` stores that total converted to a percentage (`final / scale * 100`).

Two meetings conflict when the weekday matches, the period ranges overlap, and the week sets overlap. Adjacent periods do not overlap. Odd/even rules (`weekRules`) and one-week overrides participate in that check. A conflicting drag is rejected and the file is not changed.

## Week rule

`{ "meetingID": "<uuid>", "parity": "odd" }`. `parity` is `any`, `odd`, or `even`. `any` is the default and is omitted from `weekRules`.

## Override

One change for one week of one meeting. The rest of the term stays as the meeting says.

| Field | Type | Notes |
| --- | --- | --- |
| id, courseID, meetingID | string | UUIDs |
| week | number | 1-based week |
| kind | string | `cancelled`, `moved`, or `delayed` |
| weekday, startPeriod, endPeriod | number or omitted | Set when `kind` is `moved` |
| delayMinutes | number or omitted | Set when `kind` is `delayed` |

## Exam, homework, personal event, room

Exam: `{ "id", "courseName", "location", "startISO", "endISO", "note" }`.

Homework: `{ "id", "courseName", "title", "dueISO", "done", "note" }`. `done` is a boolean.

Personal event: `{ "id", "title", "note", "startISO", "endISO" }`.

`startISO`, `endISO`, and `dueISO` are civil local stamps `yyyy-MM-ddTHH:mm` with no seconds and no timezone suffix (`CivilStamp`).

Room: `{ "id", "name", "query", "latitude", "longitude" }`. `latitude` and `longitude` are omitted until a coordinate is saved.

## Library entry

A saved timetable: `{ "id", "name", "semester", "courses", "weekRules", "overrides", "exams", "homework", "rooms" }`. Switching timetables keeps personal events, appearance, and the subscription URL on the document.

## Export

我的 → 导出 JSON writes this document. 导入 JSON reads it back. `ClassdayCore` tests encode a current document and check it against `classday-store.schema.json`, including holidays, cancellations, grades, personal events, and the library.
