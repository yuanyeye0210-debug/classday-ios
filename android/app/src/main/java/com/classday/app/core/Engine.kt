package com.classday.app.core

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

class CivilCalendar(val zone: ZoneId) {
    fun parseCivil(raw: String): LocalDate? {
        val parts = raw.trim().split("-")
        if (parts.size != 3 || parts[0].length != 4 || parts[1].length != 2 || parts[2].length != 2) return null
        val year = parts[0].toIntOrNull() ?: return null
        val month = parts[1].toIntOrNull() ?: return null
        val day = parts[2].toIntOrNull() ?: return null
        return try {
            val date = LocalDate.of(year, month, day)
            if (date.year != year || date.monthValue != month || date.dayOfMonth != day) null else date
        } catch (_: RuntimeException) {
            null
        }
    }

    fun formatCivil(date: LocalDate): String = "%04d-%02d-%02d".format(date.year, date.monthValue, date.dayOfMonth)

    fun isoWeekday(date: LocalDate): Int = date.dayOfWeek.value

    fun mondayOnOrBefore(date: LocalDate): LocalDate = date.minusDays((isoWeekday(date) - 1).toLong())

    fun semesterMonday(semester: Semester): LocalDate? {
        val start = parseCivil(semester.startDate) ?: return null
        return mondayOnOrBefore(start)
    }

    fun weekIndex(date: LocalDate, semester: Semester): Int? {
        val startMonday = semesterMonday(semester) ?: return null
        val thisMonday = mondayOnOrBefore(date)
        val days = ChronoUnit.DAYS.between(startMonday, thisMonday)
        if (days < 0) return null
        val week = (days / 7).toInt() + 1
        if (week !in 1..semester.totalWeeks) return null
        return week
    }

    fun weekIndex(instant: Instant, semester: Semester): Int? =
        weekIndex(instant.atZone(zone).toLocalDate(), semester)

    fun datesInWeek(week: Int, semester: Semester): List<LocalDate> {
        if (week !in 1..semester.totalWeeks) return emptyList()
        val startMonday = semesterMonday(semester) ?: return emptyList()
        val monday = startMonday.plusDays(((week - 1) * 7).toLong())
        return (0 until 7).map { monday.plusDays(it.toLong()) }
    }

    fun dateTime(week: Int, weekday: Int, time: ClockTime, semester: Semester): ZonedDateTime? {
        val days = datesInWeek(week, semester)
        if (weekday !in 1..days.size) return null
        val day = days[weekday - 1]
        return ZonedDateTime.of(day, LocalTime.of(time.hour, time.minute), zone)
    }

    fun weekRangeLabel(week: Int, semester: Semester): String {
        val days = datesInWeek(week, semester)
        val first = days.firstOrNull() ?: return ""
        val last = days.lastOrNull() ?: return ""
        return "%02d.%02d – %02d.%02d".format(first.monthValue, first.dayOfMonth, last.monthValue, last.dayOfMonth)
    }

    fun weekRangeMonthDayLabel(week: Int, semester: Semester): String {
        val days = datesInWeek(week, semester)
        val first = days.firstOrNull() ?: return ""
        val last = days.lastOrNull() ?: return ""
        return "${first.monthValue}月${first.dayOfMonth}日 – ${last.monthValue}月${last.dayOfMonth}日"
    }


    fun holiday(on: ZonedDateTime, semester: Semester): HolidayPeriod? {
        val civil = formatCivil(on.toLocalDate())
        return semester.holidays.firstOrNull { it.startDate <= civil && civil <= it.endDate }
    }

    fun cancellation(on: ZonedDateTime, courseId: String, semester: Semester): ClassCancellation? {
        val civil = formatCivil(on.toLocalDate())
        val hour = on.hour
        return semester.cancellations.firstOrNull { entry ->
            if (entry.date != civil) return@firstOrNull false
            val entryCourse = entry.courseID
            if (entryCourse != null && !entryCourse.equals(courseId, ignoreCase = true)) return@firstOrNull false
            when (entry.scope) {
                "day", "all" -> true
                "am" -> hour < 12
                "pm" -> hour >= 12
                else -> true
            }
        }
    }

    fun endDate(semester: Semester): LocalDate? {
        val monday = semesterMonday(semester) ?: return null
        return monday.plusDays((semester.totalWeeks * 7 - 1).toLong())
    }

    fun zoned(instant: Instant): ZonedDateTime = instant.atZone(zone)

    companion object {
        fun system(): CivilCalendar = CivilCalendar(ZoneId.systemDefault())
        private val isoMinute: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")
    }
}

object ScheduleCopy {
    val weekdayNames = listOf("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")

    fun weekdayName(weekday: Int): String = weekdayNames.getOrElse(weekday) { "" }

    fun weekdayShort(weekday: Int): String = weekdayName(weekday).drop(1)

    fun periodSpan(start: Int, end: Int): String =
        if (start == end) "第 $start 节" else "第 $start–$end 节"

    fun timeRange(start: ClockTime, end: ClockTime): String = "${start.hhmm}–${end.hhmm}"

    fun weekList(weeks: List<Int>): String {
        val sorted = weeks.toSet().sorted()
        val first = sorted.firstOrNull() ?: return "未设置周次"
        val last = sorted.last()
        if (sorted.size == 1) return "第${first}周"
        if (sorted == (first..last).toList()) return "第$first–${last}周"
        if (sorted.all { it % 2 == 1 } && sorted == (first..last step 2).toList()) return "单周"
        if (sorted.all { it % 2 == 0 } && sorted == (first..last step 2).toList()) return "双周"
        if (sorted.size <= 4) return "第" + sorted.joinToString("、") + "周"
        return "自定义 ${sorted.size} 周"
    }

    fun clocks(meeting: Meeting, semester: Semester): Pair<ClockTime, ClockTime>? {
        val map = semester.periods.associateBy { it.index }
        val startPeriod = map[meeting.startPeriod] ?: return null
        val endPeriod = map[meeting.endPeriod] ?: return null
        val start = ClockTime.parse(startPeriod.start) ?: return null
        val end = ClockTime.parse(endPeriod.end) ?: return null
        return start to end
    }
}

object ScheduleEngine {
    fun occurrences(
        week: Int,
        courses: List<Course>,
        semester: Semester,
        calendar: CivilCalendar,
        context: ScheduleContext = ScheduleContext.empty,
    ): List<Occurrence> {
        if (week !in 1..semester.totalWeeks) return emptyList()
        val built = mutableListOf<Occurrence>()
        for (course in courses) {
            if (week !in course.weeks) continue
            for (meeting in course.meetings) {
                val parity = context.parity(meeting.id)
                if (!parity.contains(week)) continue
                val override = context.override(course.id, meeting.id, week)
                if (override?.kind == OverrideKind.cancelled) continue
                val weekday = if (override?.kind == OverrideKind.moved) override.weekday ?: meeting.weekday else meeting.weekday
                val startPeriod = if (override?.kind == OverrideKind.moved) override.startPeriod ?: meeting.startPeriod else meeting.startPeriod
                val endPeriod = if (override?.kind == OverrideKind.moved) override.endPeriod ?: meeting.endPeriod else meeting.endPeriod
                val placed = Meeting(meeting.id, weekday, startPeriod, endPeriod, meeting.location)
                val clocks = ScheduleCopy.clocks(placed, semester) ?: continue
                var start = calendar.dateTime(week, weekday, clocks.first, semester) ?: continue
                var end = calendar.dateTime(week, weekday, clocks.second, semester) ?: continue
                if (!end.isAfter(start)) continue
                if (override?.kind == OverrideKind.delayed) {
                    val minutes = override.delayMinutes ?: 0
                    start = start.plusMinutes(minutes.toLong())
                    end = end.plusMinutes(minutes.toLong())
                }
                if (calendar.holiday(start, semester) != null) continue
                if (calendar.cancellation(start, course.id, semester) != null) continue
                val parityLabel = if (parity == WeekParity.any) "" else parity.title
                built += Occurrence(
                    id = "${course.id}-${meeting.id}-$week",
                    courseID = course.id,
                    meetingID = meeting.id,
                    name = course.name,
                    teacher = course.teacher,
                    location = meeting.location.ifBlank { course.location },
                    locationShort = LocationText.short(meeting.location.ifBlank { course.location }),
                    department = course.department,
                    note = course.note,
                    colorID = course.colorID,
                    kind = course.kind,
                    weekday = weekday,
                    startPeriod = startPeriod,
                    endPeriod = endPeriod,
                    weekIndex = week,
                    weeks = course.weeks,
                    startEpochMillis = start.toInstant().toEpochMilli(),
                    endEpochMillis = end.toInstant().toEpochMilli(),
                    timeText = ScheduleCopy.timeRange(clocks.first, clocks.second),
                    reminderLeadMinutes = course.reminderLeadMinutes,
                    parityLabel = parityLabel,
                )
            }
        }
        return built.sortedWith(compareBy<Occurrence> { it.weekday }.thenBy { it.startPeriod }.thenBy { it.name })
    }

    fun occurrencesOn(
        instant: Instant,
        courses: List<Course>,
        semester: Semester,
        calendar: CivilCalendar,
        context: ScheduleContext = ScheduleContext.empty,
    ): List<Occurrence> {
        val date = instant.atZone(calendar.zone).toLocalDate()
        val week = calendar.weekIndex(date, semester) ?: return emptyList()
        val weekday = calendar.isoWeekday(date)
        return occurrences(week, courses, semester, calendar, context).filter { it.weekday == weekday }
    }

    fun current(
        instant: Instant,
        courses: List<Course>,
        semester: Semester,
        calendar: CivilCalendar,
        context: ScheduleContext = ScheduleContext.empty,
    ): Occurrence? {
        val week = calendar.weekIndex(instant, semester) ?: return null
        val millis = instant.toEpochMilli()
        return occurrences(week, courses, semester, calendar, context)
            .firstOrNull { it.startEpochMillis <= millis && millis < it.endEpochMillis }
    }

    fun next(
        instant: Instant,
        courses: List<Course>,
        semester: Semester,
        calendar: CivilCalendar,
        context: ScheduleContext = ScheduleContext.empty,
    ): Occurrence? {
        val startMonday = calendar.semesterMonday(semester) ?: return null
        val date = instant.atZone(calendar.zone).toLocalDate()
        val startWeek = when {
            date.isBefore(startMonday) -> 1
            else -> calendar.weekIndex(date, semester) ?: return null
        }
        val millis = instant.toEpochMilli()
        for (week in startWeek..semester.totalWeeks) {
            val found = occurrences(week, courses, semester, calendar, context)
                .sortedBy { it.startEpochMillis }
                .firstOrNull { it.startEpochMillis > millis }
            if (found != null) return found
        }
        return null
    }

    fun conflicts(courses: List<Course>, context: ScheduleContext = ScheduleContext.empty): List<MeetingConflict> {
        data class Item(val course: Course, val meeting: Meeting)
        val items = courses.flatMap { course -> course.meetings.map { Item(course, it) } }
        if (items.size < 2) return emptyList()
        val result = mutableListOf<MeetingConflict>()
        for (index in 0 until items.lastIndex) {
            for (other in (index + 1) until items.size) {
                val left = items[index]
                val right = items[other]
                if (left.meeting.weekday != right.meeting.weekday) continue
                if (!rangesOverlap(left.meeting.startPeriod, left.meeting.endPeriod, right.meeting.startPeriod, right.meeting.endPeriod)) continue
                val leftParity = context.parity(left.meeting.id)
                val rightParity = context.parity(right.meeting.id)
                val weeks = left.course.weeks.toSet().intersect(right.course.weeks.toSet())
                    .filter { leftParity.contains(it) && rightParity.contains(it) }
                    .sorted()
                if (weeks.isEmpty()) continue
                result += MeetingConflict(
                    courseID = left.course.id,
                    meetingID = left.meeting.id,
                    courseName = left.course.name,
                    otherCourseID = right.course.id,
                    otherMeetingID = right.meeting.id,
                    otherCourseName = right.course.name,
                    weekday = left.meeting.weekday,
                    startPeriod = maxOf(left.meeting.startPeriod, right.meeting.startPeriod),
                    endPeriod = minOf(left.meeting.endPeriod, right.meeting.endPeriod),
                    weeks = weeks,
                )
            }
        }
        return result.sortedWith(compareBy<MeetingConflict> { it.weekday }.thenBy { it.startPeriod }.thenBy { it.courseName })
    }

    fun validateMove(
        courseId: String,
        meetingId: String,
        weekday: Int,
        startPeriod: Int,
        courses: List<Course>,
        semester: Semester,
        context: ScheduleContext = ScheduleContext.empty,
    ): MoveValidation {
        val courseIndex = courses.indexOfFirst { it.id.equals(courseId, ignoreCase = true) }
        if (courseIndex < 0) return MoveValidation.Missing
        val course = courses[courseIndex]
        val meeting = course.meetings.firstOrNull { it.id.equals(meetingId, ignoreCase = true) } ?: return MoveValidation.Missing
        val duration = meeting.endPeriod - meeting.startPeriod + 1
        if (duration < 1) return MoveValidation.OutOfBounds
        val endPeriod = startPeriod + duration - 1
        val maxPeriod = semester.periods.maxOfOrNull { it.index } ?: 0
        if (weekday !in 1..7 || startPeriod < 1 || endPeriod > maxPeriod) return MoveValidation.OutOfBounds
        if (weekday == meeting.weekday && startPeriod == meeting.startPeriod) return MoveValidation.Unchanged
        val moved = course.copy(
            meetings = course.meetings.map { item ->
                if (!item.id.equals(meetingId, ignoreCase = true)) item
                else item.copy(weekday = weekday, startPeriod = startPeriod, endPeriod = endPeriod)
            },
        )
        val updated = courses.toMutableList().also { it[courseIndex] = moved }
        val involved = conflicts(updated, context).filter {
            it.meetingID.equals(meetingId, ignoreCase = true) || it.otherMeetingID.equals(meetingId, ignoreCase = true)
        }
        return if (involved.isEmpty()) MoveValidation.Ok(updated) else MoveValidation.Conflict(involved)
    }

    private fun rangesOverlap(start: Int, end: Int, otherStart: Int, otherEnd: Int): Boolean =
        start <= otherEnd && otherStart <= end
}

object CountdownCopy {
    fun remaining(untilMillis: Long, nowMillis: Long): String {
        val seconds = ((untilMillis - nowMillis) / 1000).toInt()
        if (seconds <= 0) return "已开始"
        val days = seconds / 86_400
        val hours = (seconds % 86_400) / 3600
        val minutes = (seconds % 3600) / 60
        if (days > 0) return "$days 天 $hours 小时"
        if (hours > 0) return "$hours 小时 $minutes 分"
        return "${maxOf(minutes, 1)} 分钟"
    }
}

object CivilStamp {
    fun string(instant: Instant, calendar: CivilCalendar): String {
        val zoned = instant.atZone(calendar.zone)
        return "%04d-%02d-%02dT%02d:%02d".format(
            zoned.year, zoned.monthValue, zoned.dayOfMonth, zoned.hour, zoned.minute,
        )
    }

    fun instant(raw: String, calendar: CivilCalendar): Instant? {
        val trimmed = raw.trim()
        if (trimmed.length < 10) return null
        val day = calendar.parseCivil(trimmed.substring(0, 10)) ?: return null
        if (trimmed.length < 16) return day.atStartOfDay(calendar.zone).toInstant()
        val clock = ClockTime.parse(trimmed.substring(11, 16)) ?: return day.atStartOfDay(calendar.zone).toInstant()
        return ZonedDateTime.of(day, LocalTime.of(clock.hour, clock.minute), calendar.zone).toInstant()
    }
}

data class WeekNavigator(
    val shift: Int = 0,
    val anchorDay: LocalDate? = null,
    val anchorSemesterStart: String? = null,
    val anchorTotalWeeks: Int = 0,
) {
    fun synced(today: LocalDate, semester: Semester): WeekNavigator {
        val maxWeeks = semester.totalWeeks.coerceAtLeast(1)
        return if (anchorDay == today && anchorSemesterStart == semester.startDate && anchorTotalWeeks == maxWeeks) {
            this
        } else {
            WeekNavigator(
                shift = 0,
                anchorDay = today,
                anchorSemesterStart = semester.startDate,
                anchorTotalWeeks = maxWeeks,
            )
        }
    }

    fun currentWeek(today: LocalDate, semester: Semester, calendar: CivilCalendar): Int {
        val maxWeeks = semester.totalWeeks.coerceAtLeast(1)
        val base = calendar.weekIndex(today, semester) ?: 1
        val active = synced(today, semester)
        return (base + active.shift).coerceIn(1, maxWeeks)
    }

    fun shifted(delta: Int, today: LocalDate, semester: Semester, calendar: CivilCalendar): WeekNavigator {
        val maxWeeks = semester.totalWeeks.coerceAtLeast(1)
        val base = calendar.weekIndex(today, semester) ?: 1
        val active = synced(today, semester)
        val target = (base + active.shift + delta).coerceIn(1, maxWeeks)
        return active.copy(shift = target - base)
    }

    fun reset(today: LocalDate, semester: Semester): WeekNavigator =
        WeekNavigator(
            shift = 0,
            anchorDay = today,
            anchorSemesterStart = semester.startDate,
            anchorTotalWeeks = semester.totalWeeks.coerceAtLeast(1),
        )
}

