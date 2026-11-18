package com.classday.app.core

/**
 * 从停课通知里认出「哪天、哪门课不上」。
 * 支持 2026-11-20 / 2026/11/20 / 2026年11月20日 三种日期写法；
 * 课程名按现有课表里的名字做包含匹配，认不出就记成当天全天停课，交给用户改。
 */
object CancellationParser {
    private val datePattern = Regex("""(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})""")
    private val keywords = listOf("停课", "取消", "暂停", "不上课", "停上一次", "改为线上", "调课", "顺延")

    fun parse(text: String, courses: List<Course>): List<ClassCancellation> {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return emptyList()
        val dates = datePattern.findAll(trimmed).mapNotNull { match ->
            val year = match.groupValues[1].toIntOrNull() ?: return@mapNotNull null
            val month = match.groupValues[2].toIntOrNull() ?: return@mapNotNull null
            val day = match.groupValues[3].toIntOrNull() ?: return@mapNotNull null
            if (month !in 1..12 || day !in 1..31) null else "%04d-%02d-%02d".format(year, month, day)
        }.distinct().toList()
        val matched = courses.filter { course ->
            val name = course.name.trim()
            name.length >= 2 && trimmed.contains(name)
        }
        val reason = keywords.firstOrNull { trimmed.contains(it) } ?: "停课通知"
        val dayList = dates.ifEmpty { listOf("") }
        val targets: List<Course?> = matched.ifEmpty { listOf(null) }
        return dayList.flatMap { date ->
            targets.map { course ->
                ClassCancellation(
                    id = newId(),
                    date = date,
                    courseID = course?.id,
                    courseName = course?.name.orEmpty(),
                    scope = if (course == null) "all" else "course",
                    reason = reason,
                )
            }
        }
    }
}