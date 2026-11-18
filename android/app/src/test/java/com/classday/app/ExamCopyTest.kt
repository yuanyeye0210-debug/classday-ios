package com.classday.app

import com.classday.app.core.ExamCopy
import org.junit.Assert.assertEquals
import org.junit.Test

class ExamCopyTest {
    @Test
    fun nearestLineKeepsLonePercentSignInLocation() {
        assertEquals(
            "8月31日 周一 09:00–11:00 · 100% 报告厅",
            ExamCopy.nearestLine(8, 31, 1, 9, 0, 11, 0, "100% 报告厅"),
        )
    }

    @Test
    fun upcomingLineKeepsFormatSpecifiersInLocation() {
        assertEquals("8月31日 09:00 · %s 教室", ExamCopy.upcomingLine(8, 31, 9, 0, "%s 教室"))
        assertEquals("8月31日 09:00 · %d 楼", ExamCopy.upcomingLine(8, 31, 9, 0, "%d 楼"))
        assertEquals("8月31日 09:00 · 50% 机房", ExamCopy.upcomingLine(8, 31, 9, 0, "50% 机房"))
    }

    @Test
    fun nearestLineAlsoKeepsFormatSpecifiersInLocation() {
        assertEquals(
            "8月31日 周一 09:00–11:00 · %n 阶梯教室",
            ExamCopy.nearestLine(8, 31, 1, 9, 0, 11, 0, "%n 阶梯教室"),
        )
    }

    @Test
    fun blankOrPaddedLocationFallsBackInsteadOfShowingNothing() {
        assertEquals("考场待定", ExamCopy.locationLabel(""))
        assertEquals("考场待定", ExamCopy.locationLabel("   "))
        assertEquals("8月31日 09:00 · 考场待定", ExamCopy.upcomingLine(8, 31, 9, 0, ""))
    }

    @Test
    fun clocksStayZeroPadded() {
        assertEquals(
            "8月31日 周一 09:05–09:30 · A101",
            ExamCopy.nearestLine(8, 31, 1, 9, 5, 9, 30, "A101"),
        )
        assertEquals("12月1日 08:00 · A101", ExamCopy.upcomingLine(12, 1, 8, 0, "A101"))
    }
}
