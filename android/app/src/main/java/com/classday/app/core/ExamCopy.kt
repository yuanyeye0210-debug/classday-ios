package com.classday.app.core

import java.util.Locale

/**
 * 考试页的时间与考场文案。
 *
 * 考场名来自用户输入，只能作为普通文本拼接，不能先插入格式模板再整体 format：
 * 名称里的「%」会被当成格式指令，抛出异常并让考试页崩溃（例如「100% 报告厅」）。
 */
object ExamCopy {
    private const val FALLBACK_LOCATION = "考场待定"

    /** 考场名去掉首尾空白后为空时给明确提示，不静默显示空白。 */
    fun locationLabel(location: String): String = location.trim().ifBlank { FALLBACK_LOCATION }

    /** 最近一场考试：8月31日 周一 09:00–11:00 · 考场。 */
    fun nearestLine(
        month: Int,
        day: Int,
        weekday: Int,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        location: String,
    ): String {
        val start = clock(startHour, startMinute)
        val end = clock(endHour, endMinute)
        return "${month}月${day}日 ${ScheduleCopy.weekdayName(weekday)} $start–$end · ${locationLabel(location)}"
    }

    /** 后续考试：8月31日 09:00 · 考场。 */
    fun upcomingLine(
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        location: String,
    ): String = "${month}月${day}日 ${clock(hour, minute)} · ${locationLabel(location)}"

    /** 只在固定模板上格式化纯数字，用户文本永远不进入模板。 */
    private fun clock(hour: Int, minute: Int): String =
        String.format(Locale.ROOT, "%02d:%02d", hour, minute)
}
