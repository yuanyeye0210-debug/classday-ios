package com.classday.app

import com.classday.app.core.ScheduleTextImporter
import org.junit.Assert.*
import org.junit.Test

class MailImportTest {
    private val customSemester = com.classday.app.core.DemoData.makeDocument().semester.copy(periods = listOf(
        com.classday.app.core.PeriodTemplate(3, "09:00", "09:30"),
        com.classday.app.core.PeriodTemplate(4, "09:30", "10:00"),
        com.classday.app.core.PeriodTemplate(5, "10:00", "10:30"),
    ))

    @Test fun clockMappingRejectsAmbiguousEndpointsGapsAndReversedIndexes() {
        val periods = customSemester.periods
        val invalidSchedules = listOf(
            emptyList(),
            periods + periods.first().copy(index = 2), // Duplicate start clock.
            periods + periods.last().copy(index = 6), // Duplicate end clock.
            listOf(periods.first(), periods.last()), // Missing middle period.
            periods.map { it.copy(index = 8 - it.index) }, // Clocks increase but indexes decrease.
        )
        val drafts = ScheduleTextImporter.parseMail("数学 周一 09:00-10:30").drafts
        for (schedule in invalidSchedules) {
            val semester = customSemester.copy(periods = schedule)
            val checked = ScheduleTextImporter.validateDrafts(drafts, semester)
            assertTrue("Must reject $schedule", checked.drafts.isEmpty())
            assertEquals(1, checked.unparsed.size)
            assertTrue(ScheduleTextImporter.toCourses(drafts, semester).first.isEmpty())
        }
        // List order must not affect mapping by period index.
        val semester = customSemester.copy(periods = periods.reversed())
        val meeting = ScheduleTextImporter.toCourses(drafts, semester).first.single().meetings.single()
        assertEquals(3, meeting.startPeriod)
        assertEquals(5, meeting.endPeriod)
    }

    @Test fun partialClockNeverFallsBackToParserPeriodGuess() {
        val valid = com.classday.app.core.MeetingDraft(1, 540, 600, 1, 2)
        val invalid = listOf(
            valid.copy(startMinutes = null), valid.copy(endMinutes = null),
            valid.copy(endMinutes = 540), valid.copy(endMinutes = 539),
            com.classday.app.core.MeetingDraft(1),
        )
        for (meeting in invalid) {
            val drafts = listOf(com.classday.app.core.CourseDraft("数学", meetings = listOf(meeting)))
            val checked = ScheduleTextImporter.validateDrafts(drafts, customSemester)
            assertTrue(checked.drafts.isEmpty())
            assertEquals(1, checked.unparsed.size)
        }
    }

    @Test fun mixedMeetingsKeepValidCourseMetadataAndReportRejectedArrangement() {
        val good = com.classday.app.core.MeetingDraft(2, 540, 600, 1, 2,
            parity = com.classday.app.core.WeekParity.odd)
        val draft = com.classday.app.core.CourseDraft("数学", teacher = "王老师", location = "A301",
            weeks = listOf(2, 4, 6), meetings = listOf(good, good.copy(startMinutes = 545)))
        val checked = ScheduleTextImporter.validateDrafts(listOf(draft), customSemester)
        assertEquals(listOf(draft.copy(meetings = listOf(good.copy(startPeriod = 3, endPeriod = 4)))), checked.drafts)
        assertEquals(1, checked.unparsed.size)
        assertTrue(checked.unparsed.single().contains("数学"))
        val (courses, parities) = ScheduleTextImporter.toCourses(checked.drafts, customSemester)
        val course = courses.single()
        assertEquals("王老师", course.teacher)
        assertEquals("A301", course.location)
        assertEquals(listOf(2, 4, 6), course.weeks)
        assertEquals(2, course.meetings.single().weekday)
        assertEquals(com.classday.app.core.WeekParity.odd, parities.toMap()[course.meetings.single().id])
    }

    @Test fun copiedTablePreservesQuotedNamesAndWeeks() {
        val result = ScheduleTextImporter.parseMail("本学期课表\r\n课程名称\t星期\t节次\t周次\r\n数学,基础\t周一\t1-2\t2-8")
        assertEquals(1, result.drafts.size)
        assertEquals("数学,基础", result.drafts.single().name)
        assertEquals((2..8).toList(), result.drafts.single().weeks)
        assertEquals(2, result.drafts.single().meetings.single().endPeriod)
    }

    @Test fun proseNeedsNameDayAndValidTimeRange() {
        val result = ScheduleTextImporter.parseMail("同学们好\n高等数学 周一 08:00-09:40\n周二开会\n大学英语 周三\n物理 周四 10:00-09:00\n化学 周五 25:00-26:00")
        assertEquals(listOf("高等数学"), result.drafts.map { it.name })
        assertEquals(5, result.unparsed.size)
        assertEquals(480, result.drafts.single().meetings.single().startMinutes)
    }

    @Test fun cancellationAndReschedulingNeverBecomeNewCourses() {
        val result = ScheduleTextImporter.parseMail("高数 周一 08:00-09:40 停课\n英语 周二 08:00-09:40 改为线上\n物理 周三 08:00-09:40 调课")
        assertTrue(result.drafts.isEmpty())
        assertEquals(3, result.unparsed.size)
        val table = ScheduleTextImporter.parseMail("课程名称,星期,节次,备注\n高数,周一,1-2,停课\n英语,周二,3-4,正常")
        assertEquals(listOf("英语"), table.drafts.map { it.name })
        assertEquals(1, table.unparsed.size)
    }

    @Test fun csvWithMailPreambleAndEmptyInput() {
        val result = ScheduleTextImporter.parseMail("同学们好\n课程名称,星期,节次,教室\n物理,周二,3-4,A301")
        assertEquals("A301", result.drafts.single().location)
        assertTrue(ScheduleTextImporter.parseMail("  ").drafts.isEmpty())
    }
    @Test fun clockImportUsesCustomSemesterAndRejectsUnrepresentableTimes() {
        val semester = com.classday.app.core.DemoData.makeDocument().semester.copy(periods = listOf(
            com.classday.app.core.PeriodTemplate(1, "08:00", "08:30"),
            com.classday.app.core.PeriodTemplate(2, "08:30", "09:00"),
            com.classday.app.core.PeriodTemplate(3, "09:00", "09:30"),
            com.classday.app.core.PeriodTemplate(4, "09:30", "10:00"),
        ))
        val parsed = ScheduleTextImporter.parseMail("数学 周一 09:00-10:00")
        val checked = ScheduleTextImporter.validateDrafts(parsed.drafts, semester)
        assertTrue(checked.unparsed.isEmpty())
        val meeting = ScheduleTextImporter.toCourses(checked.drafts, semester).first.single().meetings.single()
        assertEquals(3, meeting.startPeriod)
        assertEquals(4, meeting.endPeriod)
        for (time in listOf("09:05-10:00", "09:00-09:55", "09:00-08:30")) {
            val drafts = ScheduleTextImporter.parseText("数学 周一 $time").drafts
            assertTrue(ScheduleTextImporter.toCourses(drafts, semester).first.isEmpty())
            assertEquals(1, ScheduleTextImporter.validateDrafts(drafts, semester).unparsed.size)
        }
        val explicit = ScheduleTextImporter.parseCsv("课程,星期,节次\n数学,周一,2-3")
        assertEquals(2, ScheduleTextImporter.toCourses(explicit.drafts, semester).first.single().meetings.single().startPeriod)
    }

    @Test fun explicitPeriodSurvivesPartialClockAndRejectsContradictions() {
        // An explicitly stated period is valid on its own; half a clock range must
        // neither drop the arrangement nor be silently replaced by a guess.
        val partial = ScheduleTextImporter.parseCsv("课程,星期,节次,开始时间\n数学,周一,4-5,09:30")
        val kept = ScheduleTextImporter.validateDrafts(partial.drafts, customSemester)
        assertTrue(kept.unparsed.isEmpty())
        val meeting = ScheduleTextImporter.toCourses(kept.drafts, customSemester).first.single().meetings.single()
        assertEquals(4, meeting.startPeriod)
        assertEquals(5, meeting.endPeriod)

        // Half a clock range cannot contradict a stated period; it is simply ignored.
        val halfConflict = ScheduleTextImporter.parseCsv("课程,星期,节次,开始时间\n数学,周一,4-5,09:00")
        val halfChecked = ScheduleTextImporter.validateDrafts(halfConflict.drafts, customSemester)
        assertTrue(halfChecked.unparsed.isEmpty())
        val halfMeeting = ScheduleTextImporter.toCourses(halfChecked.drafts, customSemester)
            .first.single().meetings.single()
        assertEquals(4, halfMeeting.startPeriod)
        assertEquals(5, halfMeeting.endPeriod)

        // The end half is equally weak: it cannot contradict the stated period either.
        val endOnly = ScheduleTextImporter.parseCsv("课程,星期,节次,结束时间\n数学,周一,4-5,10:30")
        val endChecked = ScheduleTextImporter.validateDrafts(endOnly.drafts, customSemester)
        assertTrue(endChecked.unparsed.isEmpty())
        val endMeeting = ScheduleTextImporter.toCourses(endChecked.drafts, customSemester)
            .first.single().meetings.single()
        assertEquals(4, endMeeting.startPeriod)
        assertEquals(5, endMeeting.endPeriod)

        val matching = ScheduleTextImporter.parseCsv("课程,星期,节次,开始时间,结束时间\n数学,周一,4-5,09:30,10:30")
        val agreeing = ScheduleTextImporter.toCourses(matching.drafts, customSemester).first.single().meetings.single()
        assertEquals(4, agreeing.startPeriod)
        assertEquals(5, agreeing.endPeriod)

        val conflicting = ScheduleTextImporter.parseCsv("课程,星期,节次,开始时间,结束时间\n数学,周一,4-5,09:00,10:00")
        val rejected = ScheduleTextImporter.validateDrafts(conflicting.drafts, customSemester)
        assertTrue(rejected.drafts.isEmpty())
        assertTrue(rejected.unparsed.single().contains("不一致"))
        assertTrue(ScheduleTextImporter.toCourses(conflicting.drafts, customSemester).first.isEmpty())

        val outOfRange = ScheduleTextImporter.parseCsv("课程,星期,节次\n数学,周一,8-9")
        assertTrue(ScheduleTextImporter.validateDrafts(outOfRange.drafts, customSemester)
            .unparsed.single().contains("超出"))

        // A period this semester does not have must not hide a complete, usable clock.
        val fallback = ScheduleTextImporter.parseCsv("课程,星期,节次,开始时间,结束时间\n数学,周一,8-9,09:00,10:30")
        val fallbackMeeting = ScheduleTextImporter.toCourses(fallback.drafts, customSemester).first.single().meetings.single()
        assertEquals(3, fallbackMeeting.startPeriod)
        assertEquals(5, fallbackMeeting.endPeriod)
        // 替换必须说明：源节次、采用的时间与对应的新节次都写进提示。
        val fallbackChecked = ScheduleTextImporter.validateDrafts(fallback.drafts, customSemester)
        assertTrue(fallbackChecked.unparsed.isEmpty())
        assertEquals(listOf("数学：第 8–9 节本学期不存在，已按 09:00–10:30（第 3–5 节）导入"), fallbackChecked.notes)
        // 本学期节次可用时不产生替换说明。
        val inRange = ScheduleTextImporter.parseCsv("课程,星期,节次,开始时间,结束时间\n数学,周一,3-5,09:00,10:30")
        assertTrue(ScheduleTextImporter.validateDrafts(inRange.drafts, customSemester).notes.isEmpty())
        // 未写节次、只按时间导入也不算替换。
        val clockOnly = ScheduleTextImporter.parseCsv("课程,星期,开始时间,结束时间\n数学,周一,09:00,10:30")
        assertTrue(ScheduleTextImporter.validateDrafts(clockOnly.drafts, customSemester).notes.isEmpty())

        // Half a clock cannot stand in for a period this semester cannot represent.
        val halfOutOfRange = ScheduleTextImporter.parseCsv("课程,星期,节次,开始时间\n数学,周一,8-9,09:00")
        val halfOutRejected = ScheduleTextImporter.validateDrafts(halfOutOfRange.drafts, customSemester)
        assertTrue(halfOutRejected.drafts.isEmpty())
        assertTrue(halfOutRejected.unparsed.single().contains("都无法匹配"))
        assertTrue(ScheduleTextImporter.toCourses(halfOutOfRange.drafts, customSemester).first.isEmpty())
    }

    @Test fun pastedTextKeepsStatedPeriodAlongsideClocks() {
        // A pasted line states the period and may also carry clocks; the period must
        // survive recognition so it can be checked instead of silently guessed away.
        val onlyPeriod = ScheduleTextImporter.parseText("数学 周一 第3-4节").drafts
        val kept = ScheduleTextImporter.toCourses(onlyPeriod, customSemester).first.single().meetings.single()
        assertEquals(3, kept.startPeriod)
        assertEquals(4, kept.endPeriod)

        val agreeing = ScheduleTextImporter.parseText("数学 周一 第3-4节 09:00-10:00").drafts
        val agreed = ScheduleTextImporter.toCourses(agreeing, customSemester).first.single().meetings.single()
        assertEquals(3, agreed.startPeriod)
        assertEquals(4, agreed.endPeriod)

        val conflicting = ScheduleTextImporter.parseText("数学 周一 第4-5节 09:00-10:00").drafts
        val rejected = ScheduleTextImporter.validateDrafts(conflicting, customSemester)
        assertTrue(rejected.drafts.isEmpty())
        assertTrue(rejected.unparsed.single().contains("不一致"))

        // Half a clock range cannot confirm the period, so it is dropped, not guessed.
        val half = ScheduleTextImporter.parseText("数学 周一 第4-5节 09:30").drafts
        assertNull(half.single().meetings.single().startMinutes)
        val halfMeeting = ScheduleTextImporter.toCourses(half, customSemester).first.single().meetings.single()
        assertEquals(4, halfMeeting.startPeriod)
        assertEquals(5, halfMeeting.endPeriod)
    }

    @Test fun calendarImportUsesSemesterClocksWithoutRounding() {
        val calendar = com.classday.app.core.CivilCalendar(java.time.ZoneOffset.UTC)
        fun parse(start: String, end: String) = com.classday.app.core.ICSImporter.parse(
            "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Math\nDTSTART:$start\nDTEND:$end\nEND:VEVENT\nEND:VCALENDAR",
            calendar, periods = customSemester.periods)
        val meeting = parse("20261102T090000", "20261102T100000").courses.single().meetings.single()
        assertEquals(3, meeting.startPeriod)
        assertEquals(4, meeting.endPeriod)
        for ((start, end) in listOf(
            "20261102T090500" to "20261102T100000",
            "20261102T090000" to "20261102T095500",
            "20261102T090001" to "20261102T100000",
            "20261102T090000" to "20261103T100000")) {
            val result = parse(start, end)
            assertTrue(result.courses.isEmpty())
            assertEquals(1, result.warnings.size)
        }
    }

    @Test fun periodLabelsShowSpanAndSemesterClock() {
        assertEquals("第 3 节", ScheduleTextImporter.periodSpanLabel(3, null))
        assertEquals("第 3 节", ScheduleTextImporter.periodSpanLabel(3, 3))
        assertEquals("第 3–5 节", ScheduleTextImporter.periodSpanLabel(3, 5))
        assertEquals("第 ? 节", ScheduleTextImporter.periodSpanLabel(null, 5))
        assertEquals("09:00–10:30", ScheduleTextImporter.periodClockLabel(3, 5, customSemester))
        assertEquals(null, ScheduleTextImporter.periodClockLabel(8, 9, customSemester))
    }
}
