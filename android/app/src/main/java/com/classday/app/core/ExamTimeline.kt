package com.classday.app.core

/**
 * 把考试按「正在考 / 还没考 / 已结束」分开。
 *
 * 以前今日页和学习页按开始时间排序后直接取第一场当「最近一场」，再把负数天数压成 0：
 * 只要留着一场历史考试，它就会顶掉真正的下一场，显示「0 天后开考」。
 * 这里以结束时间判断是否已结束；时间读不出来的考试不丢弃，排在待考最后。
 */
object ExamTimeline {
    private const val DAY_MILLIS = 86_400_000L

    data class Buckets(
        /** 已开始、未结束，按结束时间先后。 */
        val ongoing: List<ExamEvent>,
        /** 还没开始，按开始时间先后；时间无法解析的排最后。 */
        val upcoming: List<ExamEvent>,
        /** 已结束，最近结束的在前。 */
        val past: List<ExamEvent>,
    ) {
        /** 主卡片该显示的考试：正在考的优先，其次是下一场；都没有时为 null。 */
        val focus: ExamEvent? get() = ongoing.firstOrNull() ?: upcoming.firstOrNull()

        /** 主卡片之外仍待考的考试。 */
        val laterPending: List<ExamEvent> get() = (ongoing + upcoming).drop(1)
    }

    fun classify(
        exams: List<ExamEvent>,
        nowMillis: Long,
        millisOf: (String) -> Long?,
    ): Buckets {
        val ongoing = mutableListOf<Pair<ExamEvent, Long>>()
        val upcoming = mutableListOf<Pair<ExamEvent, Long>>()
        val past = mutableListOf<Pair<ExamEvent, Long>>()
        for (exam in exams) {
            val start = millisOf(exam.startISO)
            val end = millisOf(exam.endISO) ?: start
            when {
                end != null && end <= nowMillis -> past += exam to end
                start != null && start <= nowMillis -> ongoing += exam to (end ?: Long.MAX_VALUE)
                else -> upcoming += exam to (start ?: Long.MAX_VALUE)
            }
        }
        return Buckets(
            ongoing = ongoing.sortedWith(compareBy({ it.second }, { it.first.startISO })).map { it.first },
            upcoming = upcoming.sortedWith(compareBy({ it.second }, { it.first.startISO })).map { it.first },
            past = past.sortedWith(compareByDescending<Pair<ExamEvent, Long>> { it.second }.thenBy { it.first.startISO }).map { it.first },
        )
    }

    /** 距离开考的整天数（不足一天为 0）；已开考返回 null，避免把过去的时间压成 0。 */
    fun daysUntilStart(startMillis: Long?, nowMillis: Long): Long? {
        if (startMillis == null || startMillis <= nowMillis) return null
        return (startMillis - nowMillis) / DAY_MILLIS
    }
}
