package com.classday.app.core

import java.time.Instant

/** 提醒来源：上课、考试、作业。点击后分别打开课程、考试、作业对应界面。 */
enum class ReminderKind { CLASS, EXAM, HOMEWORK }

/** 一条到点要弹的提醒。key 稳定，用来做 PendingIntent 的 requestCode 与去重。 */
data class ReminderItem(
    val key: String,
    val triggerAtMillis: Long,
    val kind: ReminderKind,
    val title: String,
    val body: String,
    val courseID: String? = null,
)

/**
 * 2.9.7：把「提前 N 分钟」真正接进调度。
 *
 * 口径与 iOS `NotificationPlan` 一致：
 * - 课程自己的 reminderLeadMinutes 优先，为 null 时用学期 defaultReminderMinutes，0 表示这门课明确关闭；
 * - 考试与作业沿用学期默认提前量，0 表示不提醒；
 * - 已经开始/截止的不再补提醒；只排 7 天内、且距离现在超过 15 秒的；
 * - 总数上限 60 条，超出时保留最近的那些。
 *
 * 纯计算，不碰 Android API，JVM 单测可直接覆盖。
 */
object ReminderPlan {
    const val maxReminders = 60

    private const val MIN_LEAD_MILLIS = 15_000L
    private const val HOUR_MILLIS = 60 * 60 * 1000L

    fun build(
        document: StoreDocument,
        calendar: CivilCalendar,
        nowMillis: Long,
        horizonDays: Int = 7,
    ): List<ReminderItem> {
        val semester = document.semester
        val defaultLead = semester.defaultReminderMinutes.coerceAtLeast(0)
        val horizonEnd = nowMillis + horizonDays.toLong() * 24 * HOUR_MILLIS
        val items = mutableListOf<ReminderItem>()

        items += classReminders(document, calendar, nowMillis, horizonEnd, defaultLead)
        items += examReminders(document, calendar, nowMillis, horizonEnd, defaultLead)
        items += homeworkReminders(document, calendar, nowMillis, horizonEnd, defaultLead)

        return items
            .filter { it.triggerAtMillis > nowMillis + MIN_LEAD_MILLIS && it.triggerAtMillis <= horizonEnd }
            .distinctBy { it.key }
            .sortedWith(compareBy<ReminderItem> { it.triggerAtMillis }.thenBy { it.key })
            .take(maxReminders)
    }

    private fun classReminders(
        document: StoreDocument,
        calendar: CivilCalendar,
        nowMillis: Long,
        horizonEnd: Long,
        defaultLead: Int,
    ): List<ReminderItem> {
        val semester = document.semester
        val today = Instant.ofEpochMilli(nowMillis).atZone(calendar.zone).toLocalDate()
        val currentWeek = calendar.weekIndex(today, semester) ?: 1
        val firstWeek = currentWeek.coerceIn(1, maxOf(semester.totalWeeks, 1))
        val lastWeek = minOf(semester.totalWeeks, firstWeek + 1)
        val horizonEndMillis = minOf(horizonEnd, Long.MAX_VALUE)

        val result = mutableListOf<ReminderItem>()
        for (week in firstWeek..maxOf(firstWeek, lastWeek)) {
            for (occurrence in ScheduleEngine.occurrences(
                week = week,
                courses = document.courses,
                semester = semester,
                calendar = calendar,
                context = document.scheduleContext,
            )) {
                if (occurrence.startEpochMillis > horizonEndMillis) continue
                val lead = CourseReminder.effectiveLead(occurrence.reminderLeadMinutes, defaultLead)
                if (lead <= 0) continue
                result += ReminderItem(
                    key = "class-${occurrence.id}",
                    triggerAtMillis = occurrence.startEpochMillis - lead * 60_000L,
                    kind = ReminderKind.CLASS,
                    title = occurrence.name,
                    body = body(lead, occurrence),
                    courseID = occurrence.courseID,
                )
            }
        }
        return result
    }

    private fun body(lead: Int, occurrence: Occurrence): String {
        val room = occurrence.locationShort.ifEmpty { occurrence.location }.ifBlank { "教室未定" }
        return "$lead 分钟后上课 · $room · ${occurrence.timeText}"
    }

    private fun examReminders(
        document: StoreDocument,
        calendar: CivilCalendar,
        nowMillis: Long,
        horizonEnd: Long,
        defaultLead: Int,
    ): List<ReminderItem> {
        if (defaultLead <= 0) return emptyList()
        val result = mutableListOf<ReminderItem>()
        for (exam in document.exams) {
            val start = CivilStamp.instant(exam.startISO, calendar) ?: continue
            val startMillis = start.toEpochMilli()
            if (startMillis <= nowMillis || startMillis > horizonEnd) continue
            val label = CivilStamp.string(start, calendar).replace('T', ' ')
            result += ReminderItem(
                key = "exam-${exam.id}",
                triggerAtMillis = startMillis - defaultLead * 60_000L,
                kind = ReminderKind.EXAM,
                title = exam.courseName.ifBlank { "考试" },
                // 考场名是用户输入，只做普通拼接，不经 String.format 模板。
                body = "$label · ${ExamCopy.locationLabel(exam.location)}",
            )
        }
        return result
    }

    private fun homeworkReminders(
        document: StoreDocument,
        calendar: CivilCalendar,
        nowMillis: Long,
        horizonEnd: Long,
        defaultLead: Int,
    ): List<ReminderItem> {
        if (defaultLead <= 0) return emptyList()
        val result = mutableListOf<ReminderItem>()
        for (task in document.homework) {
            if (task.done) continue
            val due = CivilStamp.instant(task.dueISO, calendar) ?: continue
            val dueMillis = due.toEpochMilli()
            if (dueMillis <= nowMillis || dueMillis > horizonEnd) continue
            val label = CivilStamp.string(due, calendar).replace('T', ' ')
            val course = task.courseName.ifBlank { "作业" }
            result += ReminderItem(
                key = "homework-${task.id}",
                triggerAtMillis = dueMillis - defaultLead * 60_000L,
                kind = ReminderKind.HOMEWORK,
                title = task.title.ifBlank { course },
                body = "$course · $label 截止",
            )
        }
        return result
    }
}
