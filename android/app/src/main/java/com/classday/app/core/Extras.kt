package com.classday.app.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Base64
import kotlin.math.abs

object TimetableLibrary {
    const val implicitId = "00000000-0000-0000-0000-0000000000AA"

    fun snapshot(document: StoreDocument, id: String, name: String): StoredTimetable = StoredTimetable(
        id = id.uppercase(),
        name = name,
        semester = document.semester,
        courses = document.courses,
        weekRules = document.weekRules,
        overrides = document.overrides,
        exams = document.exams,
        homework = document.homework,
        rooms = document.rooms,
    )

    fun applying(stored: StoredTimetable, document: StoreDocument): StoreDocument = document.copy(
        activeTimetableID = stored.id.uppercase(),
        semester = stored.semester,
        courses = stored.courses,
        weekRules = stored.weekRules,
        overrides = stored.overrides,
        exams = stored.exams,
        homework = stored.homework,
        rooms = stored.rooms,
    )

    fun switching(document: StoreDocument, to: String): StoreDocument? {
        val targetId = to.uppercase()
        if (document.activeTimetableID.equals(targetId, ignoreCase = true)) return document
        val target = document.library.firstOrNull { it.id.equals(targetId, ignoreCase = true) } ?: return null
        val library = document.library
            .filter { !it.id.equals(document.activeTimetableID, ignoreCase = true) && !it.id.equals(targetId, ignoreCase = true) }
            .toMutableList()
        library += snapshot(document, document.activeTimetableID, document.semester.shortName)
        library.sortBy { it.name }
        return applying(target, document).copy(library = library)
    }

    fun storingCurrent(document: StoreDocument, name: String, id: String = newId()): StoreDocument {
        val storedId = id.uppercase()
        val library = document.library.filter { !it.id.equals(storedId, ignoreCase = true) }.toMutableList()
        library += snapshot(document, storedId, name)
        library.sortBy { it.name }
        return document.copy(library = library)
    }

    fun settingParity(document: StoreDocument, meetingId: String, parity: WeekParity): StoreDocument {
        val rules = document.weekRules.filter { !it.meetingID.equals(meetingId, ignoreCase = true) }.toMutableList()
        if (parity != WeekParity.any) rules += MeetingWeekRule(meetingId.uppercase(), parity)
        return document.copy(weekRules = rules)
    }

    fun overriding(document: StoreDocument, override: OccurrenceOverride): StoreDocument {
        val kept = document.overrides.filterNot {
            it.courseID.equals(override.courseID, ignoreCase = true) &&
                it.meetingID.equals(override.meetingID, ignoreCase = true) &&
                it.week == override.week
        }
        return document.copy(overrides = kept + override.copy(courseID = override.courseID.uppercase(), meetingID = override.meetingID.uppercase()))
    }

    fun clearingOverride(document: StoreDocument, courseId: String, meetingId: String, week: Int): StoreDocument =
        document.copy(
            overrides = document.overrides.filterNot {
                it.courseID.equals(courseId, ignoreCase = true) &&
                    it.meetingID.equals(meetingId, ignoreCase = true) &&
                    it.week == week
            },
        )
}

data class ImportedCalendar(
    val courses: List<Course>,
    val exams: List<ExamEvent>,
    val homework: List<HomeworkTask>,
    val warnings: List<String>,
)

object ICSImporter {
    fun parse(text: String, calendar: CivilCalendar, totalWeeks: Int = 16): ImportedCalendar {
        val events = unfold(text).split("BEGIN:VEVENT").drop(1).map { block ->
            val fields = linkedMapOf<String, String>()
            for (line in block.split('\n', '\r')) {
                val raw = line.trimEnd()
                if (raw.startsWith("END:VEVENT")) break
                val colon = raw.indexOf(':')
                if (colon < 0) continue
                val key = raw.substring(0, colon).substringBefore(';').uppercase()
                fields[key] = raw.substring(colon + 1)
            }
            fields
        }
        val courses = linkedMapOf<String, Course>()
        val exams = mutableListOf<ExamEvent>()
        val homework = mutableListOf<HomeworkTask>()
        val warnings = mutableListOf<String>()
        for (event in events) {
            val summary = event["SUMMARY"] ?: continue
            if (summary.isEmpty()) continue
            val location = event["LOCATION"].orEmpty()
            val start = event["DTSTART"]?.let { parseIcsDate(it, calendar) }
            val end = event["DTEND"]?.let { parseIcsDate(it, calendar) }
            val kind = classify(summary)
            val rawStart = event["DTSTART"]
            if (rawStart != null && rawStart.count { it.isDigit() } == 8) {
                warnings += "跳过全天事件「$summary」"
                continue
            }
            if (kind == Kind.EXAM && start != null) {
                val endInstant = end ?: start.plusSeconds(3600)
                exams += ExamEvent(
                    courseName = summary,
                    location = location,
                    startISO = CivilStamp.string(start, calendar),
                    endISO = CivilStamp.string(endInstant, calendar),
                )
                continue
            }
            if (kind == Kind.HOMEWORK && start != null) {
                homework += HomeworkTask(
                    courseName = summary,
                    title = summary,
                    dueISO = CivilStamp.string(start, calendar),
                    note = location,
                )
                continue
            }
            if (start == null || end == null || !end.isAfter(start)) {
                warnings += "跳过没有时间的事件「$summary」"
                continue
            }
            val zone = calendar.zone
            val startZoned = start.atZone(zone)
            val endZoned = end.atZone(zone)
            val weekday = startZoned.dayOfWeek.value
            val startClock = ClockTime(startZoned.hour, startZoned.minute)
            val endClock = ClockTime(endZoned.hour, endZoned.minute)
            val key = "$summary|$location"
            var course = courses[key] ?: Course(
                id = stableUuid(key),
                name = summary,
                teacher = "",
                location = location,
                colorID = CourseColors.all[colorIndex(key)],
                weeks = (1..maxOf(1, totalWeeks)).toList(),
                meetings = emptyList(),
            )
            val days = rruleWeekdays(event["RRULE"]) ?: listOf(weekday)
            for (meetingWeekday in days) {
                val meetingKey = "$key|$meetingWeekday|${startClock.hhmm}|${endClock.hhmm}"
                val meetingId = stableUuid(meetingKey)
                if (course.meetings.none { it.id == meetingId }) {
                    val endForGuess = if (endClock.totalMinutes == startClock.totalMinutes) {
                        endClock
                    } else {
                        ClockTime(endClock.hour, maxOf(0, endClock.minute - 1))
                    }
                    course = course.copy(
                        meetings = course.meetings + Meeting(
                            id = meetingId,
                            weekday = meetingWeekday,
                            startPeriod = periodGuess(startClock.totalMinutes),
                            endPeriod = maxOf(periodGuess(startClock.totalMinutes), periodGuess(endForGuess.totalMinutes)),
                        ),
                    )
                }
            }
            courses[key] = course
        }
        return ImportedCalendar(
            courses = courses.values.sortedBy { it.name },
            exams = exams,
            homework = homework,
            warnings = warnings,
        )
    }

    fun parseIcsDate(raw: String, calendar: CivilCalendar): Instant? {
        val digits = raw.filter { it.isDigit() }
        if (digits.length < 8) return null
        val year = digits.substring(0, 4).toInt()
        val month = digits.substring(4, 6).toInt()
        val day = digits.substring(6, 8).toInt()
        val date = try {
            LocalDate.of(year, month, day)
        } catch (_: RuntimeException) {
            return null
        }
        val zone = if (raw.trim().endsWith("Z")) ZoneOffset.UTC else calendar.zone
        if (digits.length < 12) return date.atStartOfDay(zone).toInstant()
        val hour = digits.substring(8, 10).toInt()
        val minute = digits.substring(10, 12).toInt()
        return date.atTime(hour, minute).atZone(zone).toInstant()
    }

    private enum class Kind { COURSE, EXAM, HOMEWORK }

    private fun classify(summary: String): Kind {
        val folded = summary.lowercase()
        if (folded.contains("exam") || folded.contains("teste") || folded.contains("exame") || summary.contains("考试") || summary.contains("测验")) {
            return Kind.EXAM
        }
        if (folded.contains("assignment") || folded.contains("trabalho") || folded.contains("homework") || summary.contains("作业")) {
            return Kind.HOMEWORK
        }
        return Kind.COURSE
    }

    private fun rruleWeekdays(rrule: String?): List<Int>? {
        if (rrule == null || !rrule.uppercase().contains("FREQ=WEEKLY")) return null
        val byday = rrule.split(';').firstOrNull { it.uppercase().startsWith("BYDAY=") } ?: return null
        val map = mapOf("MO" to 1, "TU" to 2, "WE" to 3, "TH" to 4, "FR" to 5, "SA" to 6, "SU" to 7)
        val days = byday.drop(6).split(',').mapNotNull { token ->
            map[token.filter { it.isLetter() }.uppercase()]
        }
        return days.toSet().sorted().ifEmpty { null }
    }

    private fun unfold(text: String): String = text
        .replace("\r\n ", "")
        .replace("\n ", "")
        .replace("\r\n\t", "")
        .replace("\n\t", "")

    fun periodGuess(totalMinutes: Int): Int {
        val table = listOf(
            1 to 8 * 60,
            2 to 8 * 60 + 55,
            3 to 10 * 60 + 10,
            4 to 11 * 60 + 5,
            5 to 14 * 60,
            6 to 14 * 60 + 55,
            7 to 16 * 60 + 10,
            8 to 17 * 60 + 5,
            9 to 19 * 60,
            10 to 19 * 60 + 55,
        )
        return table.minBy { abs(it.second - totalMinutes) }.first
    }

    fun stableUuid(key: String): String = stableBytes(key).toUuidString()

    fun colorIndex(key: String): Int = stableBytes(key)[0].toInt().and(0xff) % CourseColors.all.size

    private fun stableBytes(key: String): ByteArray {
        var hash = 1469598103934665603uL
        for (byte in key.encodeToByteArray()) {
            hash = hash xor byte.toUByte().toULong()
            hash *= 1099511628211uL
        }
        val bytes = ByteArray(16)
        for (index in 0 until 8) bytes[index] = ((hash shr (8 * index)) and 0xffu).toByte()
        val hash2 = hash * 0x9E3779B185EBCA87uL
        for (index in 0 until 8) bytes[8 + index] = ((hash2 shr (8 * index)) and 0xffu).toByte()
        bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x40).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
        return bytes
    }
}

data class FenixClass(val courseName: String, val location: String, val start: Instant, val end: Instant)

data class FenixEvaluation(
    val name: String,
    val courseName: String,
    val location: String,
    val start: Instant?,
    val end: Instant?,
    val isExam: Boolean,
)

@kotlinx.serialization.Serializable
private data class FenixNamed(val name: String? = null)

@kotlinx.serialization.Serializable
private data class FenixClassRow(
    val course: FenixNamed? = null,
    val courseName: String? = null,
    val location: FenixNamed? = null,
    val rooms: List<FenixNamed>? = null,
    val start: String? = null,
    val end: String? = null,
)

@kotlinx.serialization.Serializable
private data class FenixEvaluationRow(
    val name: String? = null,
    val type: String? = null,
    val courses: List<FenixNamed>? = null,
    val rooms: List<FenixNamed>? = null,
    val start: String? = null,
    val end: String? = null,
)

object FenixCalendar {
    fun courses(classes: List<FenixClass>, calendar: CivilCalendar, totalWeeks: Int = 16): List<Course> {
        val grouped = linkedMapOf<String, Course>()
        for (item in classes) {
            if (!item.end.isAfter(item.start)) continue
            val key = "${item.courseName}|${item.location}"
            var course = grouped[key] ?: Course(
                id = newId(),
                name = item.courseName,
                teacher = "",
                location = item.location,
                colorID = "blue",
                weeks = (1..maxOf(1, totalWeeks)).toList(),
                meetings = emptyList(),
            )
            val startZoned = item.start.atZone(calendar.zone)
            val endZoned = item.end.minusSeconds(60).atZone(calendar.zone)
            val weekday = startZoned.dayOfWeek.value
            val startPeriod = ICSImporter.periodGuess(startZoned.hour * 60 + startZoned.minute)
            val endPeriod = maxOf(startPeriod, ICSImporter.periodGuess(endZoned.hour * 60 + endZoned.minute))
            if (course.meetings.none { it.weekday == weekday && it.startPeriod == startPeriod && it.endPeriod == endPeriod }) {
                course = course.copy(meetings = course.meetings + Meeting(newId(), weekday, startPeriod, endPeriod))
            }
            grouped[key] = course
        }
        return grouped.values.sortedBy { it.name }
    }

    fun exams(evaluations: List<FenixEvaluation>, calendar: CivilCalendar): List<ExamEvent> =
        evaluations.filter { it.isExam }.mapNotNull { item ->
            val start = item.start ?: return@mapNotNull null
            ExamEvent(
                courseName = item.courseName.ifEmpty { item.name },
                location = item.location,
                startISO = CivilStamp.string(start, calendar),
                endISO = CivilStamp.string(item.end ?: start.plusSeconds(7200), calendar),
                note = item.name,
            )
        }

    fun decodeClasses(json: String): List<FenixClass> {
        val rows = try {
            ShareJson.decodeFromString<List<FenixClassRow>>(json)
        } catch (_: RuntimeException) {
            emptyList()
        }
        return rows.mapNotNull { row ->
            val course = row.course?.name ?: row.courseName ?: ""
            val location = row.location?.name ?: row.rooms?.firstOrNull()?.name ?: ""
            val start = iso(row.start) ?: return@mapNotNull null
            val end = iso(row.end) ?: return@mapNotNull null
            if (course.isEmpty()) return@mapNotNull null
            FenixClass(course, location, start, end)
        }
    }

    fun decodeEvaluations(json: String): List<FenixEvaluation> {
        val rows = try {
            ShareJson.decodeFromString<List<FenixEvaluationRow>>(json)
        } catch (_: RuntimeException) {
            emptyList()
        }
        return rows.mapNotNull { row ->
            val name = row.name.orEmpty()
            val course = row.courses?.firstOrNull()?.name.orEmpty()
            val type = row.type.orEmpty().uppercase()
            if (name.isEmpty() && course.isEmpty()) return@mapNotNull null
            val exam = type.contains("EXAM") || type.contains("TEST") || name.lowercase().contains("exame") || name.contains("考试")
            FenixEvaluation(
                name = name,
                courseName = course.ifEmpty { name },
                location = row.rooms?.firstOrNull()?.name.orEmpty(),
                start = iso(row.start),
                end = iso(row.end),
                isExam = exam,
            )
        }
    }

    private fun iso(raw: String?): Instant? {
        if (raw.isNullOrBlank()) return null
        val trimmed = raw.trim()
        val candidates = listOf(
            java.time.format.DateTimeFormatter.ISO_OFFSET_DATE_TIME,
            java.time.format.DateTimeFormatter.ISO_ZONED_DATE_TIME,
            java.time.format.DateTimeFormatter.ISO_LOCAL_DATE_TIME,
        )
        for (formatter in candidates) {
            try {
                return if (formatter == java.time.format.DateTimeFormatter.ISO_LOCAL_DATE_TIME) {
                    java.time.LocalDateTime.parse(trimmed, formatter).atZone(java.time.ZoneId.systemDefault()).toInstant()
                } else {
                    java.time.OffsetDateTime.parse(trimmed, formatter).toInstant()
                }
            } catch (_: RuntimeException) {
                continue
            }
        }
        val patterns = listOf(
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "dd-MM-yyyy HH:mm:ss",
            "dd-MM-yyyy HH:mm",
            "dd-MM-yyyy",
        )
        for (pattern in patterns) {
            try {
                val formatter = java.time.format.DateTimeFormatter.ofPattern(pattern)
                return if (pattern == "dd-MM-yyyy") {
                    LocalDate.parse(trimmed, formatter).atStartOfDay(java.time.ZoneId.systemDefault()).toInstant()
                } else {
                    java.time.LocalDateTime.parse(trimmed, formatter).atZone(java.time.ZoneId.systemDefault()).toInstant()
                }
            } catch (_: RuntimeException) {
                continue
            }
        }
        return null
    }
}

@kotlinx.serialization.Serializable
data class SharePayload(
    val semester: Semester,
    val courses: List<Course>,
    val weekRules: List<MeetingWeekRule> = emptyList(),
    val overrides: List<OccurrenceOverride> = emptyList(),
    val exams: List<ExamEvent> = emptyList(),
    val homework: List<HomeworkTask> = emptyList(),
)

object ShareCodec {
    fun encode(document: StoreDocument): String {
        val payload = SharePayload(
            semester = document.semester,
            courses = document.courses,
            weekRules = document.weekRules,
            overrides = document.overrides,
            exams = document.exams,
            homework = document.homework,
        )
        val data = ShareJson.encodeToString(SharePayload.serializer(), payload).encodeToByteArray()
        return Base64.getUrlEncoder().withoutPadding().encodeToString(data)
    }

    fun decode(token: String): SharePayload? {
        val bytes = decode64(token) ?: return null
        return try {
            ShareJson.decodeFromString(SharePayload.serializer(), bytes.decodeToString())
        } catch (_: RuntimeException) {
            null
        }
    }

    fun url(document: StoreDocument): String = "classday://timetable?d=${encode(document)}"

    fun tokenFromUrl(raw: String): String? {
        val trimmed = raw.trim()
        val marker = "d="
        val index = trimmed.indexOf(marker)
        if (index < 0) return if (trimmed.startsWith("ey") || trimmed.length > 40) trimmed else null
        return trimmed.substring(index + marker.length).substringBefore('&').substringBefore(' ')
    }

    private fun decode64(token: String): ByteArray? {
        var base = token.trim().replace('-', '+').replace('_', '/')
        val padding = (4 - base.length % 4) % 4
        base += "=".repeat(padding)
        return try {
            Base64.getDecoder().decode(base)
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}

object ClassdayLink {
    const val scheme = "classday"

    fun course(id: String, meeting: String? = null): String {
        val base = "classday://course/${id.uppercase()}"
        return if (meeting.isNullOrBlank()) base else "$base?meeting=${meeting.uppercase()}"
    }

    fun parseCourse(raw: String): Pair<String, String?>? {
        val uri = try {
            java.net.URI(raw.trim())
        } catch (_: Exception) {
            return null
        }
        if (!uri.scheme.equals(scheme, ignoreCase = true)) return null
        if (!uri.host.equals("course", ignoreCase = true)) return null
        val id = uri.path.trim('/').uppercase()
        if (id.isEmpty()) return null
        val meeting = uri.query?.split('&')?.firstOrNull { it.startsWith("meeting=") }?.substringAfter('=')?.uppercase()
        return id to meeting?.takeIf { it.isNotEmpty() }
    }
}

private fun ByteArray.toUuidString(): String {
    val hex = joinToString("") { "%02x".format(it.toInt() and 0xff) }
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}".uppercase()
}
