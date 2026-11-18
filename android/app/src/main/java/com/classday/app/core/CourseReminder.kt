package com.classday.app.core

/**
 * 课前提醒档位。
 *
 * Course.reminderLeadMinutes 为 null 时沿用学期默认值，0 表示这门课明确关闭提醒。
 * 这两种状态必须区分开，不能把 0 当成“继承默认”，否则用户关掉提醒后下次点击会跳过一档。
 */
object CourseReminder {
    val leadOptions: List<Int> = listOf(0, 5, 10, 15, 20, 30)

    /** 当前生效的提前分钟数：课程自身设置优先，null 则取学期默认；负数按关闭处理。 */
    fun effectiveLead(courseLeadMinutes: Int?, defaultLeadMinutes: Int): Int =
        (courseLeadMinutes ?: defaultLeadMinutes).coerceAtLeast(0)

    /** 循环到下一档：关闭(0) → 5 → 10 → … → 30 → 关闭。非标准值取比它大的第一档。 */
    fun nextLead(courseLeadMinutes: Int?, defaultLeadMinutes: Int): Int {
        val current = effectiveLead(courseLeadMinutes, defaultLeadMinutes)
        return leadOptions.firstOrNull { it > current } ?: 0
    }
}
