package com.classday.app.core

import kotlin.math.roundToInt

data class GridDropTarget(val weekday: Int, val startPeriod: Int)

/** Convert a card's displacement to a grid slot, preserving its whole period span. */
object GridDragTarget {
    fun resolve(weekday: Int, startPeriod: Int, endPeriod: Int, periodCount: Int,
                deltaX: Float, deltaY: Float, dayWidth: Float, rowHeight: Float): GridDropTarget? {
        if (weekday !in 1..7 || startPeriod < 1 || endPeriod < startPeriod || endPeriod > periodCount ||
            !deltaX.isFinite() || !deltaY.isFinite() || !dayWidth.isFinite() || !rowHeight.isFinite() ||
            dayWidth <= 0 || rowHeight <= 0) return null
        val day = weekday + deltaX / dayWidth
        val period = startPeriod + deltaY / rowHeight
        // Check before rounding to avoid clamping a drop outside the timetable.
        if (!day.isFinite() || !period.isFinite() || day < 0.5f || day >= 7.5f ||
            period < 0.5f || period >= periodCount + 0.5f) return null
        val targetDay = day.roundToInt()
        val targetPeriod = period.roundToInt()
        if (targetPeriod + (endPeriod - startPeriod) > periodCount) return null
        return GridDropTarget(targetDay, targetPeriod)
    }
}
