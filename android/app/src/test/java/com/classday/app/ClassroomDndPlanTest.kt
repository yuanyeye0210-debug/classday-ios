package com.classday.app

import com.classday.app.core.*
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class ClassroomDndPlanTest {
    private val calendar = CivilCalendar(ZoneId.of("UTC"))
    private val document = DemoData.makeDocument().copy(origin = DataOrigin.user)
    private val monday = calendar.semesterMonday(document.semester)!!.atStartOfDay(calendar.zone).toInstant()
    private val today = ScheduleEngine.occurrencesOn(monday, document.courses, document.semester, calendar, document.scheduleContext)
        .sortedBy { it.startEpochMillis }
    private fun plan(now: Instant, doc: StoreDocument = document) =
        ClassroomDndPlan.make(now, doc, calendar, true, true, true)

    @Test fun consentBothPermissionsReadableStoreAndRealDataAreRequired() {
        val now = Instant.ofEpochMilli(today.first().startEpochMillis)
        assertTrue(plan(now).active)
        assertEquals(ClassroomDndPlan(false, null), ClassroomDndPlan.make(now, document, calendar, false, true, true))
        assertEquals(ClassroomDndPlan(false, null), ClassroomDndPlan.make(now, document, calendar, true, false, true))
        assertEquals(ClassroomDndPlan(false, null), ClassroomDndPlan.make(now, document, calendar, true, true, false))
        assertEquals(ClassroomDndPlan(false, null), ClassroomDndPlan.make(now, document, calendar, true, true, true, false))
        assertEquals(ClassroomDndPlan(false, null), plan(now, document.copy(origin = DataOrigin.demo)))
    }

    @Test fun exactStartAndEndScheduleTheirOppositeBoundary() {
        val first = today.first()
        assertEquals(ClassroomDndPlan(false, first.startEpochMillis), plan(Instant.ofEpochMilli(first.startEpochMillis - 1)))
        assertEquals(ClassroomDndPlan(true, first.endEpochMillis), plan(Instant.ofEpochMilli(first.startEpochMillis)))
        assertFalse(plan(Instant.ofEpochMilli(first.endEpochMillis)).active)
        assertEquals(today[1].startEpochMillis, plan(Instant.ofEpochMilli(first.endEpochMillis)).nextBoundary)
    }

    @Test fun overlappingCoursesHoldUntilFinalEnd() {
        val course = document.courses.first()
        val meeting = course.meetings.first()
        val second = meeting.copy(id = newId(), startPeriod = meeting.endPeriod, endPeriod = meeting.endPeriod + 1)
        val source = document.copy(courses = listOf(course.copy(meetings = listOf(meeting)),
            course.copy(id = newId(), meetings = listOf(second))))
        val items = ScheduleEngine.occurrencesOn(monday, source.courses, source.semester, calendar, source.scheduleContext)
            .sortedBy { it.startEpochMillis }
        val state = plan(Instant.ofEpochMilli(items.first().startEpochMillis), source)
        assertTrue(state.active)
        assertEquals(items.maxOf { it.endEpochMillis }, state.nextBoundary)
        assertTrue(plan(Instant.ofEpochMilli(items.first().endEpochMillis), source).active)
    }

    @Test fun holidaysAndCancelledMeetingsNeverRequestDnd() {
        val first = today.first()
        val date = monday.atZone(calendar.zone).toLocalDate().toString()
        val holiday = document.copy(semester = document.semester.copy(holidays = listOf(HolidayPeriod(newId(), "放假", date, date))))
        assertFalse(plan(Instant.ofEpochMilli(first.startEpochMillis), holiday).active)
        val cancelled = document.copy(overrides = listOf(OccurrenceOverride(courseID = first.courseID,
            meetingID = first.meetingID, week = first.weekIndex, kind = OverrideKind.cancelled)))
        assertFalse(plan(Instant.ofEpochMilli(first.startEpochMillis), cancelled).active)
    }

    @Test fun delayedMeetingMovesBothBoundaries() {
        val first = today.first()
        val delayed = document.copy(overrides = listOf(OccurrenceOverride(courseID = first.courseID,
            meetingID = first.meetingID, week = first.weekIndex, kind = OverrideKind.delayed, delayMinutes = 10)))
        assertEquals(ClassroomDndPlan(false, first.startEpochMillis + 600_000), plan(Instant.ofEpochMilli(first.startEpochMillis), delayed))
        assertEquals(ClassroomDndPlan(true, first.endEpochMillis + 600_000), plan(Instant.ofEpochMilli(first.startEpochMillis + 600_000), delayed))
    }

    @Test fun afterSemesterAndEmptyScheduleHaveNoAlarm() {
        val end = calendar.semesterMonday(document.semester)!!.plusWeeks(document.semester.totalWeeks.toLong() + 1)
            .atStartOfDay(calendar.zone).toInstant()
        assertEquals(ClassroomDndPlan(false, null), plan(end))
        assertEquals(ClassroomDndPlan(false, null), plan(monday, document.copy(courses = emptyList())))
    }
}
