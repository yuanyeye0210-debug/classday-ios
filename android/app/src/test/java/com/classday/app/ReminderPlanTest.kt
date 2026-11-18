package com.classday.app

import com.classday.app.core.CivilCalendar
import com.classday.app.core.Course
import com.classday.app.core.DemoData
import com.classday.app.core.ExamEvent
import com.classday.app.core.HomeworkTask
import com.classday.app.core.Meeting
import com.classday.app.core.ReminderKind
import com.classday.app.core.ReminderPlan
import com.classday.app.core.ScheduleEngine
import com.classday.app.core.StoreDocument
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 2.9.7：提醒排期。口径对齐 iOS NotificationPlan：
 * 课程自己的提前量优先于学期默认，0 明确关闭，考试与作业用学期默认，只排 7 天内，最多 60 条。
 */
class ReminderPlanTest {
    private val calendar = CivilCalendar(ZoneId.of("UTC"))
    private val base = DemoData.makeDocument()
    private val monday = calendar.semesterMonday(base.semester)!!.atStartOfDay(calendar.zone).toInstant()
    private val now = monday.toEpochMilli()

    private fun document(
        courses: List<Course>,
        defaultLead: Int = 10,
        exams: List<ExamEvent> = emptyList(),
        homework: List<HomeworkTask> = emptyList(),
    ): StoreDocument = base.copy(
        semester = base.semester.copy(
            defaultReminderMinutes = defaultLead,
            holidays = emptyList(),
            cancellations = emptyList(),
        ),
        courses = courses,
        weekRules = emptyList(),
        overrides = emptyList(),
        exams = exams,
        homework = homework,
        personalEvents = emptyList(),
    )

    private fun course(
        id: String = "c1",
        lead: Int? = null,
        meetings: List<Meeting> = listOf(Meeting("m1", 1, 1, 2)),
    ): Course = Course(
        id = id,
        name = "高等数学",
        teacher = "王老师",
        location = "教学楼 A101",
        colorID = "blue",
        weeks = (1..16).toList(),
        meetings = meetings,
        reminderLeadMinutes = lead,
    )

    private fun firstStart(document: StoreDocument): Long =
        ScheduleEngine.occurrences(1, document.courses, document.semester, calendar, document.scheduleContext)
            .first().startEpochMillis

    @Test
    fun courseLeadOverridesSemesterDefault() {
        val doc = document(listOf(course(lead = 30)), defaultLead = 10)
        val plan = ReminderPlan.build(doc, calendar, now)
        assertEquals(1, plan.size)
        assertEquals(firstStart(doc) - 30L * 60_000L, plan.first().triggerAtMillis)
        assertEquals(ReminderKind.CLASS, plan.first().kind)
    }

    @Test
    fun semesterDefaultAppliesWhenCourseIsSilent() {
        val doc = document(listOf(course(lead = null)), defaultLead = 10)
        val plan = ReminderPlan.build(doc, calendar, now)
        assertEquals(1, plan.size)
        assertEquals(firstStart(doc) - 10L * 60_000L, plan.first().triggerAtMillis)
    }

    @Test
    fun zeroCourseLeadDisablesEvenWithSemesterDefault() {
        val doc = document(listOf(course(lead = 0)), defaultLead = 10)
        assertTrue(ReminderPlan.build(doc, calendar, now).isEmpty())
    }

    @Test
    fun zeroSemesterDefaultSilencesClassesAndExams() {
        val exam = ExamEvent(courseName = "高等数学", location = "A101", startISO = "2026-09-02T09:00", endISO = "2026-09-02T11:00")
        val doc = document(listOf(course(lead = null)), defaultLead = 0, exams = listOf(exam))
        assertTrue(ReminderPlan.build(doc, calendar, now).isEmpty())
    }

    @Test
    fun startedClassIsNotRemindedAgainButLaterWeeksStillAre() {
        val doc = document(listOf(course(lead = 10)))
        val start = firstStart(doc)
        val afterStart = start + 60_000L
        val plan = ReminderPlan.build(doc, calendar, afterStart)
        assertTrue(plan.none { it.triggerAtMillis == start - 10L * 60_000L })
        assertTrue(plan.all { it.triggerAtMillis > afterStart })
    }

    @Test
    fun outOfHorizonIsSkipped() {
        val doc = document(listOf(course(lead = 10)))
        val monthBefore = now - 30L * 24 * 60 * 60 * 1000
        assertTrue(ReminderPlan.build(doc, calendar, monthBefore).isEmpty())
    }

    @Test
    fun examReminderUsesDefaultLeadAndKeepsPercentRoomName() {
        val exam = ExamEvent(
            courseName = "高等数学",
            location = "100% 报告厅",
            startISO = "2026-09-02T09:00",
            endISO = "2026-09-02T11:00",
        )
        val doc = document(emptyList(), defaultLead = 10, exams = listOf(exam))
        val plan = ReminderPlan.build(doc, calendar, now)
        assertEquals(1, plan.size)
        assertEquals(ReminderKind.EXAM, plan.first().kind)
        assertTrue(plan.first().body.contains("100% 报告厅"))
    }

    @Test
    fun finishedHomeworkIsSkipped() {
        val open = HomeworkTask(courseName = "高等数学", title = "习题三", dueISO = "2026-09-02T20:00")
        val done = HomeworkTask(courseName = "高等数学", title = "习题二", dueISO = "2026-09-01T20:00", done = true)
        val doc = document(emptyList(), defaultLead = 10, homework = listOf(open, done))
        val plan = ReminderPlan.build(doc, calendar, now)
        assertEquals(1, plan.size)
        assertEquals(ReminderKind.HOMEWORK, plan.first().kind)
        assertTrue(plan.first().title.contains("习题三"))
    }

    @Test
    fun invalidDatesAreSkipped() {
        val exam = ExamEvent(courseName = "高等数学", location = "A101", startISO = "not-a-date", endISO = "")
        val hw = HomeworkTask(courseName = "高等数学", title = "习题", dueISO = "20")
        val doc = document(emptyList(), exams = listOf(exam), homework = listOf(hw))
        assertTrue(ReminderPlan.build(doc, calendar, now).isEmpty())
    }

    @Test
    fun planIsCappedAndKeysAreStable() {
        val many = (1..9).map { index ->
            course(
                id = "c$index",
                lead = 10,
                meetings = (1..7).map { day -> Meeting("m$index-$day", day, 1, 2) },
            )
        }
        val doc = document(many, defaultLead = 10)
        val plan = ReminderPlan.build(doc, calendar, now)
        assertEquals(ReminderPlan.maxReminders, plan.size)
        assertEquals(plan.map { it.key }.distinct().size, plan.size)
        assertEquals(plan.map { it.key }, ReminderPlan.build(doc, calendar, now).map { it.key })
        assertEquals(plan.map { it.triggerAtMillis }.sorted(), plan.map { it.triggerAtMillis })
        assertFalse(plan.any { it.triggerAtMillis <= now })
    }
}
