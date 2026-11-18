package com.classday.app

import com.classday.app.core.*
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class TodayOverviewTest {
    private val calendar = CivilCalendar(ZoneId.of("UTC"))
    private val document = DemoData.makeDocument()
    private val monday = calendar.semesterMonday(document.semester)!!.atStartOfDay(calendar.zone).toInstant()

    @Test fun currentCourseIncludesStartButExcludesEnd() {
        val first = TodayProjection.make(monday, document, calendar).courses.first()
        assertFalse(TodayProjection.make(Instant.ofEpochMilli(first.startEpochMillis - 1), document, calendar).inProgress)
        val atStart = TodayProjection.make(Instant.ofEpochMilli(first.startEpochMillis), document, calendar)
        assertTrue(atStart.inProgress)
        assertEquals(first.id, atStart.focus!!.id)
        val atEnd = TodayProjection.make(Instant.ofEpochMilli(first.endEpochMillis), document, calendar)
        assertNotEquals(first.id, atEnd.focus?.id)
    }

    @Test fun unreadableAndEmptyStoreDoNotInventCourses() {
        val unreadable = TodayProjection.make(monday, document, calendar, readable = false)
        assertTrue(unreadable.courses.isEmpty())
        assertNull(unreadable.focus)
        val empty = TodayProjection.make(monday, document.copy(courses = emptyList()), calendar)
        assertTrue(empty.courses.isEmpty())
        assertNull(empty.focus)
    }

    @Test fun todayUsesClockDateAndStopsAfterLastClass() {
        val firstDay = TodayProjection.make(monday, document, calendar)
        assertTrue(firstDay.courses.all { Instant.ofEpochMilli(it.startEpochMillis).atZone(calendar.zone).toLocalDate() == monday.atZone(calendar.zone).toLocalDate() })
        // 2.10.4：当天课上完以后不再把明天的课顶上来（用户要求「当天显示当天的课」）。
        val late = TodayProjection.make(monday.plusSeconds(23 * 3600), document, calendar)
        assertFalse(late.inProgress)
        assertNull(late.focus)
        assertEquals(firstDay.courses, late.courses)
    }

    @Test fun emptyDayStillFallsBackToNextClass() {
        // 当天本来就没有课（周末/假期）时，仍应给出下一节。
        val sunday = monday.plusSeconds(6 * 24 * 3600)
        val day = TodayProjection.make(sunday, document, calendar)
        assertTrue(day.courses.isEmpty())
        assertNotNull(day.focus)
    }

    @Test fun classroomFocusEntersAtStartRestoresAtEndAndCanRevealOtherCourses() {
        val first = TodayProjection.make(monday, document, calendar).courses.first()
        val before = TodayProjection.make(Instant.ofEpochMilli(first.startEpochMillis - 1), document, calendar)
        assertNull(before.classroomCourse)
        assertEquals(before.courses, before.displayedCourses(false))
        val active = TodayProjection.make(Instant.ofEpochMilli(first.startEpochMillis), document, calendar)
        assertEquals(first.id, active.classroomCourse?.id)
        assertEquals(listOf(first), active.displayedCourses(false))
        assertEquals(active.courses, active.displayedCourses(true))
        val ended = TodayProjection.make(Instant.ofEpochMilli(first.endEpochMillis), document, calendar)
        assertNull(ended.classroomCourse)
        assertEquals(ended.courses, ended.displayedCourses(false))
    }

    @Test fun holidayAndUnreadableStoreNeverActivateClassroomFocus() {
        val first = TodayProjection.make(monday, document, calendar).courses.first()
        val now = Instant.ofEpochMilli(first.startEpochMillis)
        val date = now.atZone(calendar.zone).toLocalDate().toString()
        val holiday = document.copy(semester = document.semester.copy(
            holidays = listOf(HolidayPeriod(newId(), "放假", date, date))))
        assertNull(TodayProjection.make(now, holiday, calendar).classroomCourse)
        assertNull(TodayProjection.make(now, document, calendar, readable = false).classroomCourse)
    }

    @Test fun cancellationAndDelayChangeFocusWithoutEditingOtherWeeks() {
        val first = TodayProjection.make(monday, document, calendar).courses.first()
        val now = Instant.ofEpochMilli(first.startEpochMillis)
        val cancellation = OccurrenceOverride(courseID = first.courseID, meetingID = first.meetingID,
            week = first.weekIndex, kind = OverrideKind.cancelled)
        val cancelled = document.copy(overrides = listOf(cancellation))
        assertNull(TodayProjection.make(now, cancelled, calendar).classroomCourse)
        val delayed = document.copy(overrides = listOf(cancellation.copy(kind = OverrideKind.delayed, delayMinutes = 10)))
        assertNull(TodayProjection.make(now, delayed, calendar).classroomCourse)
        assertEquals(first.courseID, TodayProjection.make(now.plusSeconds(600), delayed, calendar).classroomCourse?.courseID)
        assertNotNull(TodayProjection.make(now.plusSeconds(7 * 24 * 3600), cancelled, calendar).classroomCourse)
    }
}
