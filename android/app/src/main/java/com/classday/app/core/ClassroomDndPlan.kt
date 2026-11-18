package com.classday.app.core

import java.time.Instant

data class ClassroomDndPlan(val active: Boolean, val nextBoundary: Long?) {
    companion object {
        fun make(now: Instant, document: StoreDocument, calendar: CivilCalendar,
                 consent: Boolean, policyAccess: Boolean, exactAccess: Boolean, readable: Boolean = true): ClassroomDndPlan {
            if (!consent || !policyAccess || !exactAccess || !readable || document.origin == DataOrigin.demo)
                return ClassroomDndPlan(false, null)
            val intervals = (1..document.semester.totalWeeks).flatMap { week ->
                ScheduleEngine.occurrences(week, document.courses, document.semester, calendar, document.scheduleContext)
            }.filter { it.endEpochMillis > it.startEpochMillis }.sortedBy { it.startEpochMillis }
            val merged = mutableListOf<Pair<Long, Long>>()
            for (item in intervals) {
                val previous = merged.lastOrNull()
                if (previous != null && item.startEpochMillis <= previous.second) {
                    merged[merged.lastIndex] = previous.first to maxOf(previous.second, item.endEpochMillis)
                } else merged += item.startEpochMillis to item.endEpochMillis
            }
            val millis = now.toEpochMilli()
            val next = merged.firstOrNull { it.second > millis } ?: return ClassroomDndPlan(false, null)
            return if (next.first <= millis) ClassroomDndPlan(true, next.second)
                else ClassroomDndPlan(false, next.first)
        }
    }
}
