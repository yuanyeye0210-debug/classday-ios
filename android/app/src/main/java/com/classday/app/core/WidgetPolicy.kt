package com.classday.app.core

import java.time.Instant

/**
 * Presentation state shared by home-screen widgets and the quick-settings tile.
 *
 * A failed load still returns a usable demo document, so the document alone must
 * never authorize showing a timetable: widgets and the tile render an explicit
 * failure instead of the fallback schedule.
 */
internal data class WidgetLoadState(
    val document: StoreDocument,
    val current: Occurrence?,
    val next: Occurrence?,
    val week: Int,
    val loadFailed: Boolean = false,
)

internal fun widgetLoadState(loaded: StoreLoadResult, now: Instant, calendar: CivilCalendar): WidgetLoadState {
    val document = loaded.document
    if (loaded.error != null) return WidgetLoadState(document, null, null, 1, loadFailed = true)
    val week = calendar.weekIndex(now, document.semester) ?: 1
    return WidgetLoadState(
        document,
        ScheduleEngine.current(now, document.courses, document.semester, calendar, document.scheduleContext),
        ScheduleEngine.next(now, document.courses, document.semester, calendar, document.scheduleContext),
        week,
    )
}

internal data class TilePresentation(val label: String, val subtitle: String, val active: Boolean)

internal fun tilePresentation(loaded: StoreLoadResult, now: Instant, calendar: CivilCalendar): TilePresentation {
    val document = loaded.document
    if (loaded.error != null) return TilePresentation("课表读取失败", "打开课曜查看详情", active = false)
    val item = ScheduleEngine.current(now, document.courses, document.semester, calendar, document.scheduleContext)
        ?: ScheduleEngine.next(now, document.courses, document.semester, calendar, document.scheduleContext)
    return TilePresentation("下一节", item?.name ?: "今天没有课", active = true)
}
