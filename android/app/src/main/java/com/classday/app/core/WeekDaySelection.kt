package com.classday.app.core

/**
 * 课表页日期条的「选中」与「今天」是两件事：
 * 选中跟随用户点击，今天只是标记。以前选中在本周被今天锁死，点别的日期没有反应。
 */
object WeekDaySelection {
    /** 进入某一周时默认选中的星期（1=周一）：本周选今天，其他周选周一。 */
    fun initial(week: Int, todayWeek: Int?, todayWeekday: Int): Int =
        if (week == todayWeek && todayWeekday in 1..7) todayWeekday else 1

    /** 用户点击后的选中值；越界输入保持原选中。 */
    fun select(current: Int, tapped: Int): Int = if (tapped in 1..7) tapped else current

    /** 这一格是不是今天（只用于标记，不决定选中）。 */
    fun isToday(week: Int, day: Int, todayWeek: Int?, todayWeekday: Int): Boolean =
        week == todayWeek && day == todayWeekday
}
