package com.classday.app

import com.classday.app.core.CivilCalendar
import com.classday.app.core.DemoData
import com.classday.app.core.StoreLoadResult
import com.classday.app.core.tilePresentation
import com.classday.app.core.widgetLoadState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class WidgetLoadPolicyTest {
    private val calendar = CivilCalendar(ZoneId.of("Asia/Shanghai"))

    // 2026-11-13 is Friday of week 11; the demo timetable has 程序设计 in periods 5–6.
    private val duringDemoClass = Instant.parse("2026-11-13T06:30:00Z")

    @Test
    fun unreadableTimetableShowsFailureInsteadOfFallbackSchedule() {
        val demoDocument = DemoData.makeDocument()

        val state = widgetLoadState(StoreLoadResult(demoDocument, "原课表无法读取"), duringDemoClass, calendar)

        assertTrue(state.loadFailed)
        assertNull(state.current)
        assertNull(state.next)
        assertEquals(1, state.week)
        assertSame(demoDocument, state.document)
    }

    @Test
    fun readableTimetableStillShowsTheCurrentLessonAndWeek() {
        val document = DemoData.makeDocument()

        val state = widgetLoadState(StoreLoadResult(document), duringDemoClass, calendar)

        assertFalse(state.loadFailed)
        assertEquals("程序设计", state.current?.name)
        assertEquals(11, state.week)
        assertSame(document, state.document)
    }

    @Test
    fun unreadableTimetableTileIsInactiveAndPointsAtTheApp() {
        val presentation = tilePresentation(StoreLoadResult(DemoData.makeDocument(), "原课表无法读取"), duringDemoClass, calendar)

        assertEquals("课表读取失败", presentation.label)
        assertEquals("打开课曜查看详情", presentation.subtitle)
        assertFalse(presentation.active)
    }

    @Test
    fun readableTimetableTileKeepsTheLessonName() {
        val presentation = tilePresentation(StoreLoadResult(DemoData.makeDocument()), duringDemoClass, calendar)

        assertEquals("下一节", presentation.label)
        assertEquals("程序设计", presentation.subtitle)
        assertTrue(presentation.active)
    }

    @Test
    fun readableTimetableTileFallsBackToTheNextLessonBetweenClasses() {
        val betweenClasses = Instant.parse("2026-11-13T04:00:00Z") // 周五 12:00，下一节是 14:00 的程序设计

        val presentation = tilePresentation(StoreLoadResult(DemoData.makeDocument()), betweenClasses, calendar)

        assertEquals("下一节", presentation.label)
        assertEquals("程序设计", presentation.subtitle)
        assertTrue(presentation.active)
    }
}
