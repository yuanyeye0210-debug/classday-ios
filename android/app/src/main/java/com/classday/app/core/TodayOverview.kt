package com.classday.app.core

import java.time.Instant

data class TodayOverview(val courses: List<Occurrence>, val focus: Occurrence?, val inProgress: Boolean) {
    // App-only presentation state; this never claims the system DND switch is on.
    val classroomCourse: Occurrence? get() = if (inProgress) focus else null
    fun displayedCourses(showAll: Boolean): List<Occurrence> =
        if (!showAll && classroomCourse != null) listOfNotNull(classroomCourse) else courses
}

object TodayProjection {
    fun make(now: Instant, document: StoreDocument, calendar: CivilCalendar, readable: Boolean = true): TodayOverview {
        if (!readable) return TodayOverview(emptyList(), null, false)
        val today = ScheduleEngine.occurrencesOn(now, document.courses, document.semester, calendar, document.scheduleContext)
            .sortedBy { it.startEpochMillis }
        val current = today.firstOrNull { it.startEpochMillis <= now.toEpochMilli() && now.toEpochMilli() < it.endEpochMillis }
        // 当天有课但都上完了 → 不再把明天的课顶上来；当天本来没课才回落下一节。
        val focus = current
            ?: if (today.isEmpty()) ScheduleEngine.next(now, document.courses, document.semester, calendar, document.scheduleContext) else null
        return TodayOverview(today, focus, current != null)
    }
}
