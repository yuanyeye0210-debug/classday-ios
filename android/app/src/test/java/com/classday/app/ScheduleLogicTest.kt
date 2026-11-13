package com.classday.app

import com.classday.app.core.CivilCalendar
import com.classday.app.core.ClassdayThemes
import com.classday.app.core.DemoData
import com.classday.app.core.FenixCalendar
import com.classday.app.core.ICSImporter
import com.classday.app.core.OccurrenceOverride
import com.classday.app.core.OverrideKind
import com.classday.app.core.PerformanceTier
import com.classday.app.core.ScheduleEngine
import com.classday.app.core.ScheduleTextImporter
import com.classday.app.core.ShareCodec
import com.classday.app.core.StoreCodec
import com.classday.app.core.TimetableLibrary
import com.classday.app.core.WeekParity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class ScheduleLogicTest {
    private val calendar = CivilCalendar(ZoneId.of("Asia/Shanghai"))

    @Test
    fun themesAndSaverDowngrade() {
        assertEquals(8, ClassdayThemes.all.size)
        assertEquals(8, ClassdayThemes.all.map { it.id }.toSet().size)
        assertEquals("neon", ClassdayThemes.theme("missing").id)
        assertEquals(PerformanceTier.saver, ClassdayThemes.effectiveTier(PerformanceTier.high, lowPower = true, reduceMotion = false))
        assertEquals(PerformanceTier.saver, ClassdayThemes.effectiveTier(PerformanceTier.high, lowPower = false, reduceMotion = true))
        assertEquals(PerformanceTier.balanced, ClassdayThemes.effectiveTier(PerformanceTier.balanced, lowPower = false, reduceMotion = false))
        assertEquals(PerformanceTier.saver, ClassdayThemes.effectiveTier(PerformanceTier.saver, lowPower = false, reduceMotion = false))
        assertEquals(PerformanceTier.saver, ClassdayThemes.effectiveTier(PerformanceTier.balanced, lowPower = true, reduceMotion = false))
        assertFalse(ClassdayThemes.all.any { it.name.contains("Watch") })
        val seen = mutableSetOf<String>()
        var id = "neon"
        repeat(8) {
            seen += id
            id = ClassdayThemes.cycle(id)
        }
        assertEquals(ClassdayThemes.all.map { it.id }.toSet(), seen)
        assertEquals("neon", id)
    }

    @Test
    fun oddWeekCancellationAndDelay() {
        var document = DemoData.makeDocument()
        document = TimetableLibrary.settingParity(document, DemoData.ID.calculusMonday, WeekParity.odd)
        val odd = ScheduleEngine.occurrences(9, document.courses, document.semester, calendar, document.scheduleContext)
        assertTrue(odd.any { it.meetingID == DemoData.ID.calculusMonday && it.parityLabel == "单周" })
        val even = ScheduleEngine.occurrences(10, document.courses, document.semester, calendar, document.scheduleContext)
        assertFalse(even.any { it.meetingID == DemoData.ID.calculusMonday })
        document = TimetableLibrary.overriding(
            document,
            OccurrenceOverride(courseID = DemoData.ID.english, meetingID = DemoData.ID.englishMonday, week = 9, kind = OverrideKind.cancelled),
        )
        val cancelled = ScheduleEngine.occurrences(9, document.courses, document.semester, calendar, document.scheduleContext)
        assertFalse(cancelled.any { it.meetingID == DemoData.ID.englishMonday })
        assertTrue(cancelled.any { it.meetingID == DemoData.ID.englishThursday })
        val restored = TimetableLibrary.clearingOverride(document, DemoData.ID.english, DemoData.ID.englishMonday, 9)
        assertTrue(
            ScheduleEngine.occurrences(9, restored.courses, restored.semester, calendar, restored.scheduleContext)
                .any { it.meetingID == DemoData.ID.englishMonday },
        )

        var delayedDoc = DemoData.makeDocument()
        delayedDoc = TimetableLibrary.overriding(
            delayedDoc,
            OccurrenceOverride(courseID = DemoData.ID.calculus, meetingID = DemoData.ID.calculusMonday, week = 10, kind = OverrideKind.delayed, delayMinutes = 10),
        )
        val delayed = ScheduleEngine.occurrences(10, delayedDoc.courses, delayedDoc.semester, calendar, delayedDoc.scheduleContext)
            .first { it.meetingID == DemoData.ID.calculusMonday }
        val other = ScheduleEngine.occurrences(11, delayedDoc.courses, delayedDoc.semester, calendar, delayedDoc.scheduleContext)
            .first { it.meetingID == DemoData.ID.calculusMonday }
        assertEquals(10, Instant.ofEpochMilli(delayed.startEpochMillis).atZone(calendar.zone).minute)
        assertEquals(0, Instant.ofEpochMilli(other.startEpochMillis).atZone(calendar.zone).minute)
        assertTrue(other.startEpochMillis > delayed.startEpochMillis)
    }

    @Test
    fun movedWeekDoesNotRewriteTheTerm() {
        var document = DemoData.makeDocument()
        document = TimetableLibrary.overriding(
            document,
            OccurrenceOverride(
                courseID = DemoData.ID.calculus,
                meetingID = DemoData.ID.calculusMonday,
                week = 10,
                kind = OverrideKind.moved,
                weekday = 2,
                startPeriod = 3,
                endPeriod = 4,
            ),
        )
        val moved = ScheduleEngine.occurrences(10, document.courses, document.semester, calendar, document.scheduleContext)
            .first { it.meetingID == DemoData.ID.calculusMonday }
        val later = ScheduleEngine.occurrences(11, document.courses, document.semester, calendar, document.scheduleContext)
            .first { it.meetingID == DemoData.ID.calculusMonday }
        assertEquals(2, moved.weekday)
        assertEquals(3, moved.startPeriod)
        assertEquals(1, later.weekday)
        assertEquals(1, later.startPeriod)
    }

    @Test
    fun icsAndFenixImport() {
        val ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            SUMMARY:高等数学
            LOCATION:教学楼 A · 301
            DTSTART:20261102T080000
            DTEND:20261102T094000
            RRULE:FREQ=WEEKLY;BYDAY=MO,WE
            END:VEVENT
            BEGIN:VEVENT
            SUMMARY:高等数学考试
            LOCATION:教学楼 A · 301
            DTSTART:20270112T090000
            DTEND:20270112T110000
            END:VEVENT
            BEGIN:VEVENT
            SUMMARY:作业：习题
            DTSTART:20261120T180000
            DTEND:20261120T180000
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()
        val imported = ICSImporter.parse(ics, calendar)
        assertEquals(listOf("高等数学"), imported.courses.map { it.name })
        assertEquals(1, imported.exams.size)
        assertEquals(1, imported.homework.size)
        assertEquals(listOf(1, 3), imported.courses.first().meetings.map { it.weekday })

        val classes = """[{"course":{"name":"程序设计"},"location":{"name":"机房 2"},"start":"2026-11-02T14:00:00","end":"2026-11-02T15:40:00"}]"""
        val evaluations = """[{"name":"Exame","type":"EXAM","start":"2027-01-15T09:00:00","end":"2027-01-15T11:00:00","courses":[{"name":"程序设计"}],"rooms":[{"name":"机房 2"}]}]"""
        val decoded = FenixCalendar.decodeClasses(classes)
        assertEquals(listOf("程序设计"), decoded.map { it.courseName })
        assertEquals(listOf("程序设计"), FenixCalendar.courses(decoded, calendar).map { it.name })
        assertEquals(1, FenixCalendar.exams(FenixCalendar.decodeEvaluations(evaluations), calendar).size)
    }

    @Test
    fun shareRoundTripAndTimetableSwitch() {
        val document = DemoData.makeDocument()
        val payload = ShareCodec.decode(ShareCodec.encode(document))
        assertNotNull(payload)
        assertEquals(document.courses.size, payload!!.courses.size)
        assertEquals(document.semester.shortName, payload.semester.shortName)
        assertTrue(ShareCodec.url(document).startsWith("classday://timetable?d="))
        val again = ShareCodec.decode(ShareCodec.tokenFromUrl(ShareCodec.url(document))!!)
        assertEquals(document.courses.map { it.name }, again?.courses?.map { it.name })

        val backupId = "00000000-0000-0000-0000-0000000000BB"
        var library = TimetableLibrary.storingCurrent(document, "备份", backupId)
        library = library.copy(semester = library.semester.copy(shortName = "当前"))
        val switched = TimetableLibrary.switching(library, backupId)
        assertEquals(backupId, switched?.activeTimetableID)
        assertEquals(document.semester.shortName, switched?.semester?.shortName)
        assertEquals(listOf("当前"), switched?.library?.map { it.name })
    }

    @Test
    fun oldStoreStillDecodes() {
        val legacy = """
            {"courses":[],"origin":"user","schemaVersion":1,"semester":{"defaultReminderMinutes":10,"name":"学期","periods":[{"end":"08:45","index":1,"start":"08:00"}],"shortName":"秋","startDate":"2026-08-31","totalWeeks":16}}
        """.trimIndent()
        val outcome = StoreCodec.importing(legacy, calendar)
        val document = outcome.document
        assertNotNull(document)
        assertTrue(document!!.courses.isEmpty())
        assertEquals("neon", document.appearance.themeID)
        assertEquals(TimetableLibrary.implicitId, document.activeTimetableID)
        assertTrue(outcome.errors.isEmpty())
    }

    @Test
    fun excelUtf8CsvPreservesQuotedCellsAndReportsInvalidRows() {
        val csv = "\uFEFF课程名称,星期,节次,教室,教师,周次\r\n\"数学,进阶\",周一,1-2,A301,陈老师,1-16周\r\n未安排课程,,,,,\r\n"
        val parsed = ScheduleTextImporter.parseCsv(csv)
        assertEquals(1, parsed.drafts.size)
        assertEquals("数学,进阶", parsed.drafts.single().name)
        assertEquals(1, parsed.drafts.single().meetings.single().weekday)
        assertEquals(1, parsed.drafts.single().meetings.single().startPeriod)
        assertEquals(2, parsed.drafts.single().meetings.single().endPeriod)
        assertEquals(1, parsed.unparsed.size)
        assertTrue(ScheduleTextImporter.parseCsv("\uFEFF").drafts.isEmpty())
    }

    @Test
    fun csvParsesMeetingsParityAndGrid() {
        val csv = """
            课程名称,星期,开始时间,结束时间,教室,教师,周次
            高等数学,周一,08:00,09:40,教学楼A301,陈老师,1-16周
            高等数学,周三,10:10,11:50,教学楼A301,陈老师,1-16周
            大学英语,星期四,08:00,09:40,教学楼B205,林老师,1-16周
        """.trimIndent()
        val parsed = ScheduleTextImporter.parseCsv(csv)
        assertEquals(2, parsed.drafts.size)
        assertTrue(parsed.unparsed.isEmpty())
        val math = parsed.drafts.first { it.name == "高等数学" }
        assertEquals(2, math.meetings.size)
        assertEquals(1, math.meetings.first().weekday)
        assertEquals(480, math.meetings.first().startMinutes)
        assertEquals(580, math.meetings.first().endMinutes)
        assertEquals("陈老师", math.teacher)
        assertEquals(1, math.weeks.first())
        assertEquals(16, math.weeks.last())

        val odd = ScheduleTextImporter.parseCsv("课程;星期;节次;地点;周次\n程序设计;周五;5-6;实验楼机房3;1-15周 单周")
        val draft = odd.drafts.first()
        assertEquals(5, draft.meetings.first().startPeriod)
        assertEquals(6, draft.meetings.first().endPeriod)
        assertEquals("实验楼机房3", draft.meetings.first().location)
        assertEquals(WeekParity.odd, draft.meetings.first().parity)
        assertEquals(15, draft.weeks.last())

        val blank = ScheduleTextImporter.parseCsv("a,b,c\n1,2,3")
        assertTrue(blank.drafts.isEmpty())
        assertEquals(2, blank.unparsed.size)

        val grid = """
            节次/时间,周一,周二,周三,周四,周五
            08:00-09:40,高等数学 教学楼A301,,大学英语 教学楼B205,
            10:10-11:50,,程序设计 实验楼机房3,,
        """.trimIndent()
        val gridResult = ScheduleTextImporter.parseCsv(grid)
        assertEquals(setOf("高等数学", "大学英语", "程序设计"), gridResult.drafts.map { it.name }.toSet())
        assertEquals(1, gridResult.drafts.first { it.name == "高等数学" }.meetings.first().weekday)
        assertEquals(480, gridResult.drafts.first { it.name == "高等数学" }.meetings.first().startMinutes)
        assertEquals(3, gridResult.drafts.first { it.name == "大学英语" }.meetings.first().weekday)
    }
}
