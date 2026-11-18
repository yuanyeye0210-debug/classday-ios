package com.classday.app

import com.classday.app.core.*
import org.junit.Assert.*
import org.junit.Test

class GridDragTest {
    @Test fun snapsToNearestDayAndPeriod() {
        assertEquals(GridDropTarget(3, 4), GridDragTarget.resolve(2, 2, 3, 12, 100f, 88f, 100f, 44f))
        assertEquals(GridDropTarget(2, 2), GridDragTarget.resolve(2, 2, 3, 12, 49f, 21f, 100f, 44f))
        assertEquals(GridDropTarget(1, 1), GridDragTarget.resolve(2, 2, 3, 12, -100f, -44f, 100f, 44f))
    }

    @Test fun refusesOffBoardAndSpanOverflow() {
        assertNull(GridDragTarget.resolve(7, 2, 3, 12, 100f, 0f, 100f, 44f))
        assertNull(GridDragTarget.resolve(1, 2, 3, 12, -100f, 0f, 100f, 44f))
        assertNull(GridDragTarget.resolve(2, 11, 12, 12, 0f, 44f, 100f, 44f))
        assertNull(GridDragTarget.resolve(2, 1, 2, 12, 0f, -44f, 100f, 44f))
        assertEquals(GridDropTarget(2, 11), GridDragTarget.resolve(2, 10, 11, 12, 0f, 44f, 100f, 44f))
    }

    @Test fun refusesMissingOrInvalidGeometry() {
        for (bad in listOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            assertNull(GridDragTarget.resolve(2, 2, 3, 12, 0f, 0f, bad, 44f))
        }
        assertNull(GridDragTarget.resolve(2, 2, 3, 12, Float.NaN, 0f, 100f, 44f))
        assertNull(GridDragTarget.resolve(2, 2, 3, 12, Float.MAX_VALUE, 0f, 100f, 44f))
    }

    @Test fun dropUsesConflictGuardAndKeepsIdsAndDuration() {
        val document = DemoData.makeDocument()
        val course = document.courses.first()
        val meeting = course.meetings.first()
        val target = GridDragTarget.resolve(meeting.weekday, meeting.startPeriod, meeting.endPeriod,
            document.semester.periods.size, (7 - meeting.weekday) * 100f, 0f, 100f, 44f)!!
        val result = ScheduleEngine.validateMove(course.id, meeting.id, target.weekday, target.startPeriod,
            document.courses, document.semester, document.scheduleContext)
        assertTrue(result is MoveValidation.Ok)
        val moved = (result as MoveValidation.Ok).courses.first { it.id == course.id }.meetings.first { it.id == meeting.id }
        assertEquals(7, moved.weekday)
        assertEquals(meeting.endPeriod - meeting.startPeriod, moved.endPeriod - moved.startPeriod)
        val duplicate = course.copy(id = "another-course", meetings = listOf(meeting.copy(id = "another-meeting", weekday = 7)))
        assertTrue(ScheduleEngine.validateMove(course.id, meeting.id, 7, meeting.startPeriod,
            document.courses + duplicate, document.semester, document.scheduleContext) is MoveValidation.Conflict)
        assertEquals(meeting, document.courses.first().meetings.first())
    }
}
