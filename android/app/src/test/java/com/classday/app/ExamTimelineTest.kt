package com.classday.app

import com.classday.app.core.ExamEvent
import com.classday.app.core.ExamTimeline
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExamTimelineTest {
    private val hour = 3_600_000L
    private val now = 1_000L * hour

    /** 用「相对 now 的小时数」当时间戳，便于读用例。 */
    private fun exam(id: String, startH: Long?, endH: Long?) = ExamEvent(
        id = id,
        courseName = id,
        location = "",
        startISO = startH?.let { "h$it" } ?: "bad",
        endISO = endH?.let { "h$it" } ?: "bad",
    )

    private val millisOf: (String) -> Long? = { iso ->
        iso.removePrefix("h").toLongOrNull()?.let { now + it * hour }
    }

    private fun ids(list: List<ExamEvent>) = list.map { it.id }

    @Test
    fun pastExamDoesNotDisplaceNextUpcomingExam() {
        val buckets = ExamTimeline.classify(
            listOf(exam("old", -48, -46), exam("next", 24, 26), exam("later", 72, 74)), now, millisOf,
        )
        assertEquals("next", buckets.focus?.id)
        assertEquals(listOf("later"), ids(buckets.laterPending))
        assertEquals(listOf("old"), ids(buckets.past))
    }

    @Test
    fun allPastExamsLeaveNoFocus() {
        val buckets = ExamTimeline.classify(listOf(exam("a", -72, -70), exam("b", -5, -3)), now, millisOf)
        assertNull(buckets.focus)
        assertTrue(buckets.laterPending.isEmpty())
        assertEquals(listOf("b", "a"), ids(buckets.past))
    }

    @Test
    fun ongoingExamTakesFocusBeforeUpcoming() {
        val buckets = ExamTimeline.classify(listOf(exam("next", 5, 7), exam("now", -1, 1)), now, millisOf)
        assertEquals(listOf("now"), ids(buckets.ongoing))
        assertEquals("now", buckets.focus?.id)
        assertEquals(listOf("next"), ids(buckets.laterPending))
    }

    @Test
    fun examEndingExactlyNowCountsAsPastAndStartingNowAsOngoing() {
        val buckets = ExamTimeline.classify(listOf(exam("ended", -2, 0), exam("started", 0, 2)), now, millisOf)
        assertEquals(listOf("ended"), ids(buckets.past))
        assertEquals(listOf("started"), ids(buckets.ongoing))
    }

    @Test
    fun unreadableTimesStayPendingAndSortLast() {
        val buckets = ExamTimeline.classify(listOf(exam("bad", null, null), exam("soon", 3, 5)), now, millisOf)
        assertEquals(listOf("soon", "bad"), ids(buckets.upcoming))
        assertTrue(buckets.past.isEmpty())
    }

    @Test
    fun missingEndFallsBackToStart() {
        val buckets = ExamTimeline.classify(listOf(exam("noEndPast", -3, null), exam("noEndFuture", 3, null)), now, millisOf)
        assertEquals(listOf("noEndPast"), ids(buckets.past))
        assertEquals(listOf("noEndFuture"), ids(buckets.upcoming))
    }

    @Test
    fun daysUntilStartNeverReportsPastAsZero() {
        assertEquals(1L, ExamTimeline.daysUntilStart(now + 30 * hour, now))
        assertEquals(0L, ExamTimeline.daysUntilStart(now + 2 * hour, now))
        assertNull(ExamTimeline.daysUntilStart(now - hour, now))
        assertNull(ExamTimeline.daysUntilStart(now, now))
        assertNull(ExamTimeline.daysUntilStart(null, now))
    }
}
