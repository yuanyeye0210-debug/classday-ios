package com.classday.app

import com.classday.app.core.WeekDaySelection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WeekDaySelectionTest {
    @Test
    fun currentWeekStartsOnTodayOtherWeeksOnMonday() {
        assertEquals(3, WeekDaySelection.initial(week = 11, todayWeek = 11, todayWeekday = 3))
        assertEquals(1, WeekDaySelection.initial(week = 12, todayWeek = 11, todayWeekday = 3))
        assertEquals(1, WeekDaySelection.initial(week = 1, todayWeek = null, todayWeekday = 3))
    }

    @Test
    fun tappingAnotherDayInCurrentWeekChangesSelection() {
        val start = WeekDaySelection.initial(week = 11, todayWeek = 11, todayWeekday = 3)
        assertEquals(5, WeekDaySelection.select(start, 5))
        assertEquals(3, WeekDaySelection.select(5, 3))
    }

    @Test
    fun outOfRangeTapKeepsSelection() {
        assertEquals(2, WeekDaySelection.select(2, 0))
        assertEquals(2, WeekDaySelection.select(2, 8))
    }

    @Test
    fun todayMarkIsIndependentOfSelection() {
        assertTrue(WeekDaySelection.isToday(week = 11, day = 3, todayWeek = 11, todayWeekday = 3))
        assertFalse(WeekDaySelection.isToday(week = 12, day = 3, todayWeek = 11, todayWeekday = 3))
        assertFalse(WeekDaySelection.isToday(week = 11, day = 4, todayWeek = 11, todayWeekday = 3))
    }
}
