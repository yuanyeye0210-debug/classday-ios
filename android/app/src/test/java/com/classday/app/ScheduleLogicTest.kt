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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class ScheduleLogicTest {
    @Test
    fun csvNumericDataRowsAreNotGridHeaders() {
        for (separator in listOf(",", ";")) {
            for (values in listOf(listOf("1", "2", "3"), listOf("1", "2", "3", "4"))) {
                val header = listOf("a", "b", "c", "d").take(values.size).joinToString(separator)
                val row = values.joinToString(separator)
                val result = ScheduleTextImporter.parseCsv("$header\n$row")
                assertTrue(result.drafts.isEmpty())
                assertEquals(listOf(header, row), result.unparsed)
            }
        }
    }

    @Test
    fun csvGridFindsWeekdayHeaderAfterTitlesWithEitherDelimiter() {
        for (separator in listOf(",", ";")) {
            val csv = listOf(
                "2026秋季学期课表",
                "班级：软件工程",
                listOf("节次", "周一", "周二", "周三").joinToString(separator),
                listOf("1-2", "数学", "", "英语").joinToString(separator),
                listOf("3-4", "", "物理", "").joinToString(separator),
            ).joinToString("\n")
            val result = ScheduleTextImporter.parseCsv(csv)
            assertTrue(result.unparsed.isEmpty())
            assertEquals(setOf("数学", "英语", "物理"), result.drafts.map { it.name }.toSet())
            val math = result.drafts.single { it.name == "数学" }.meetings.single()
            assertEquals(1, math.weekday)
            assertEquals(1, math.startPeriod)
            assertEquals(2, math.endPeriod)
            val physics = result.drafts.single { it.name == "物理" }.meetings.single()
            assertEquals(2, physics.weekday)
            assertEquals(3, physics.startPeriod)
            assertEquals(4, physics.endPeriod)
        }
    }

    @Test
    fun csvNumericTitleBeforeGridHeaderDoesNotStealDetection() {
        // The numeric row is a title/export artifact, not a header: it must not win over
        // the weekday header that appears on the last line the detector scans.
        val csv = listOf(
            "2026秋季学期课表",
            "班级：软件工程",
            "课表说明：以教务系统为准",
            "导出时间：2026-09-01",
            "1,2,3",
            "节次;周一;周二;周三",
            "1-2;数学;;英语",
            "3-4;;物理;",
        ).joinToString("\n")
        val result = ScheduleTextImporter.parseCsv(csv)
        assertTrue(result.unparsed.isEmpty())
        assertEquals(setOf("数学", "英语", "物理"), result.drafts.map { it.name }.toSet())
        val math = result.drafts.single { it.name == "数学" }.meetings.single()
        assertEquals(1, math.weekday)
        assertEquals(1, math.startPeriod)
        assertEquals(2, math.endPeriod)
        assertEquals(3, result.drafts.single { it.name == "英语" }.meetings.single().weekday)
        assertEquals(2, result.drafts.single { it.name == "物理" }.meetings.single().weekday)
    }

    @Test
    fun mergeGradeConflictNeedsChoiceUntilConflictIsGone() {
        val template = DemoData.makeDocument()
        val original = template.courses.first()
        val first = original.copy(id = "grade-80", grade = 80.0)
        val second = original.copy(id = "grade-90", grade = 90.0, meetings = original.meetings.map { it.copy(id = "second-${it.id}") })
        val ungraded = original.copy(id = "ungraded", meetings = original.meetings.map { it.copy(id = "ungraded-${it.id}") })
        val document = template.copy(courses = listOf(first, second, ungraded), weekRules = emptyList())
        val group = com.classday.app.core.DuplicateGroup("same", listOf(first, second, ungraded))

        assertNull(com.classday.app.core.mergeDuplicateGroup(group, null))
        assertNull(com.classday.app.core.applyMerge(document, group, null))
        assertEquals(90.0, com.classday.app.core.mergeDuplicateGroup(group, second.id)!!.first.grade)

        // Excluding the conflicting member removes the conflict, so no chip choice is needed.
        val withoutSecond = com.classday.app.core.selectedMergeGroup(group, setOf(second.id))
        assertTrue(com.classday.app.core.canSubmitCourseMerge(withoutSecond, null, document))
        assertEquals(80.0, com.classday.app.core.mergeDuplicateGroup(withoutSecond, null)!!.first.grade)

        val sameGrade = com.classday.app.core.DuplicateGroup("same", listOf(first, second.copy(grade = 80.0), ungraded))
        assertTrue(com.classday.app.core.canSubmitCourseMerge(sameGrade, null, document))
        assertEquals(80.0, com.classday.app.core.mergeDuplicateGroup(sameGrade, null)!!.first.grade)
    }

    @Test
    fun mergeSelectionChecksParityExclusionsAndGradeChoice() {
        val template = DemoData.makeDocument()
        val original = template.courses.first()
        val a = original.copy(id = "a", grade = 80.0)
        val b = original.copy(id = "b", grade = 90.0, meetings = original.meetings.map { it.copy(id = "b-${it.id}") })
        val c = original.copy(id = "c", meetings = original.meetings.map { it.copy(id = "c-${it.id}") })
        val document = template.copy(courses = listOf(a, b, c), weekRules =
            a.meetings.map { com.classday.app.core.MeetingWeekRule(it.id, WeekParity.odd) } +
            b.meetings.map { com.classday.app.core.MeetingWeekRule(it.id, WeekParity.odd) } +
            c.meetings.map { com.classday.app.core.MeetingWeekRule(it.id, WeekParity.even) })
        val group = com.classday.app.core.DuplicateGroup("same", listOf(a, b, c))
        assertFalse(com.classday.app.core.canSubmitCourseMerge(group, a.id, document))
        val selected = com.classday.app.core.selectedMergeGroup(group, setOf(c.id))
        assertEquals(listOf(a, b), selected.courses)
        assertFalse(com.classday.app.core.canSubmitCourseMerge(selected, null, document))
        assertFalse(com.classday.app.core.canSubmitCourseMerge(selected, c.id, document))
        assertTrue(com.classday.app.core.canSubmitCourseMerge(selected, b.id, document))
        val merged = com.classday.app.core.applyMerge(document, selected, b.id)!!
        assertEquals(c, merged.courses.first { it.id == c.id })
        assertEquals(90.0, merged.courses.first { it.id == a.id }.grade)
        val single = com.classday.app.core.selectedMergeGroup(group, setOf(b.id, c.id))
        assertFalse(com.classday.app.core.canSubmitCourseMerge(single, a.id, document))
    }
    @Test
    fun mergeEntryCountsGroupsWithCompatiblePairs() {
        val document = DemoData.makeDocument()
        val base = document.courses.first().copy(name = "数学", weeks = (1..8).toList())
        val copy = base.copy(id = "copy", meetings = base.meetings.map { it.copy(id = "copy-${it.id}") })
        val otherRoom = copy.copy(id = "other", location = "不同教室")
        fun eligible(courses: List<com.classday.app.core.Course>) =
            com.classday.app.core.mergeableScheduleGroups(document.copy(courses = courses, weekRules = emptyList()))
        assertTrue(eligible(listOf(base, otherRoom)).isEmpty())
        assertTrue(eligible(listOf(base)).isEmpty())
        assertEquals(1, eligible(listOf(base, copy)).size)
        // The review page can exclude the incompatible member before applying the merge.
        assertEquals(1, eligible(listOf(base, copy, otherRoom)).size)
        val source = document.copy(courses = listOf(base, copy, otherRoom), weekRules = emptyList())
        val selected = com.classday.app.core.DuplicateGroup("数学", listOf(base, copy))
        val merged = com.classday.app.core.applyMerge(source, selected, base.id)!!
        assertEquals(2, merged.courses.size)
        assertEquals(otherRoom, merged.courses.first { it.id == otherRoom.id })
        assertEquals(base.weeks, merged.courses.first { it.id == base.id }.weeks)
        assertEquals(base.location, merged.courses.first { it.id == base.id }.location)
        val english = base.copy(id = "english", name = "英语")
        val englishCopy = english.copy(id = "english-copy")
        val groups = eligible(listOf(base, otherRoom, english, englishCopy))
        assertEquals(1, groups.size)
        assertEquals(listOf("english", "english-copy"), groups.single().courses.map { it.id })
    }
    @Test
    fun mergeRejectsIncompatibleSchedulesBeforeChangingDocument() {
        val document = DemoData.makeDocument()
        val base = document.courses.first().copy(weeks = (1..8).toList())
        val duplicate = base.copy(id = "duplicate-course", meetings = base.meetings.map { it.copy(id = "copy-${it.id}") })
        fun group(other: com.classday.app.core.Course) = com.classday.app.core.DuplicateGroup("same", listOf(base, other))
        val current = document.copy(courses = listOf(base, duplicate), weekRules = emptyList())
        assertTrue(com.classday.app.core.canMergeCourseSchedules(listOf(base, duplicate), current))
        assertNotNull(com.classday.app.core.applyMerge(current, group(duplicate), base.id))
        // 2.9.9：同名课分不同周次、不同教室、单双周不同，都要能合并（不能再因为"安排不一致"拒绝）。
        for (other in listOf(duplicate.copy(weeks = (9..16).toList()), duplicate.copy(location = "另一间教室"))) {
            val source = current.copy(courses = listOf(base, other))
            val merged = com.classday.app.core.applyMerge(source, group(other), base.id)
            assertNotNull(merged)
            assertEquals(1, merged!!.courses.size)
            assertEquals((base.weeks + other.weeks).toSet().sorted(), merged.courses.first().weeks)
        }
        val odd = com.classday.app.core.MeetingWeekRule(base.meetings.first().id, WeekParity.odd)
        val even = com.classday.app.core.MeetingWeekRule(duplicate.meetings.first().id, WeekParity.even)
        val conflicting = current.copy(weekRules = listOf(odd, even))
        assertNotNull(com.classday.app.core.applyMerge(conflicting, group(duplicate), base.id))
    }
    @Test
    fun perMeetingRoomWinsAndEmptyFallsBackToCourse() {
        val doc = DemoData.makeDocument()
        val base = doc.courses.first()
        val withRooms = base.copy(
            location = "教学楼 A · 301",
            meetings = listOf(
                base.meetings[0].copy(id = "m-own", location = "实验楼 B · 205"),
                base.meetings[1].copy(id = "m-fallback", location = ""),
            ),
        )
        val custom = doc.copy(courses = listOf(withRooms), weekRules = emptyList(), overrides = emptyList())
        val occ = ScheduleEngine.occurrences(2, custom.courses, custom.semester, calendar, custom.scheduleContext)
        val own = occ.firstOrNull { it.meetingID == "m-own" }
        val fallback = occ.firstOrNull { it.meetingID == "m-fallback" }
        assertNotNull(own)
        assertNotNull(fallback)
        assertEquals("实验楼 B · 205", own!!.location)
        assertEquals("教学楼 A · 301", fallback!!.location)
    }

    @Test
    fun mergingKeepsRoomOfEachSession() {
        val doc = DemoData.makeDocument()
        val first = doc.courses.first()
        val a = first.copy(id = "merge-a", location = "Room C9", meetings = listOf(com.classday.app.core.Meeting("ma1", 1, 1, 2)))
        val b = first.copy(id = "merge-b", location = "Room V1.17", meetings = listOf(com.classday.app.core.Meeting("mb1", 3, 1, 2)))
        val merged = com.classday.app.core.autoMergeDuplicateCourses(
            doc.copy(courses = listOf(a, b), weekRules = emptyList(), overrides = emptyList()),
        )
        assertEquals(1, merged.document.courses.size)
        val course = merged.document.courses.first()
        val rooms = course.meetings.associate { it.id to it.location }
        assertEquals("Room C9", rooms["ma1"])
        assertEquals("Room V1.17", rooms["mb1"])
        val occ = ScheduleEngine.occurrences(2, merged.document.courses, merged.document.semester, calendar, merged.document.scheduleContext)
        assertEquals(setOf("Room C9", "Room V1.17"), occ.map { it.location }.toSet())
    }
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
        repeat(ClassdayThemes.all.size) {
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
        // 2.10：v1 文档读入后升级到 currentSchema，并给出升级提示
        assertEquals(com.classday.app.core.StoreDocument.currentSchema, document.schemaVersion)
        assertTrue(outcome.warnings.any { it.contains("升级") })
    }

    @Test
    fun csvDifferentRoomsOrTeachersKeepSeparateCoursesAndParity() {
        val rows = listOf(
            "数学,周一,1-2,1-9周 单周,张老师,实验楼",
            "数学,周三,3-4,1-9周 双周,张老师,教学楼",
            "数学,周五,5-6,1-9周 双周,李老师,实验楼",
            "数学,周二,7-8,1-9周 单周,张老师,实验楼",
        )
        for (ordered in listOf(rows, rows.reversed())) {
            val parsed = ScheduleTextImporter.parseCsv(
                "课程,星期,节次,周次,教师,教室\n" + ordered.joinToString("\n")
            )
            assertTrue(parsed.unparsed.isEmpty())
            assertEquals(3, parsed.drafts.size)
            val (courses, parities) = ScheduleTextImporter.toCourses(parsed.drafts, DemoData.makeDocument().semester)
            assertEquals(3, courses.size)
            val rules = parities.toMap()
            val lab = courses.single { it.teacher == "张老师" && it.location == "实验楼" }
            assertEquals(setOf(1, 2), lab.meetings.map { it.weekday }.toSet())
            assertTrue(lab.meetings.all { rules[it.id] == WeekParity.odd })
            for (course in courses.filter { it.id != lab.id }) {
                assertEquals(1, course.meetings.size)
                assertEquals(WeekParity.even, rules[course.meetings.single().id])
            }
            assertTrue(courses.all { it.weeks == (1..9).toList() })
        }
    }

    @Test
    fun csvUnknownRoomDoesNotInheritAnotherMeetingsRoom() {
        val parsed = ScheduleTextImporter.parseCsv("""
            课程,星期,节次,周次,教师,教室
            数学,周一,1-2,1-9周 单周,张老师,
            数学,周三,3-4,1-9周 双周,张老师,实验楼
        """.trimIndent())
        val (courses, _) = ScheduleTextImporter.toCourses(parsed.drafts, DemoData.makeDocument().semester)
        assertEquals(2, courses.size)
        assertEquals("", courses.single { it.meetings.single().weekday == 1 }.location)
        assertEquals("实验楼", courses.single { it.meetings.single().weekday == 3 }.location)
    }

    @Test
    fun csvSameWeeksKeepOddEvenAndEveryWeekMeetingsInOneCourse() {
        for (rules in listOf(
            listOf("1-9周 单周", "1-9周 双周", "1-9周"),
            listOf("1-9周", "1-9周 单周", "1-9周 双周"),
        )) {
            val parsed = ScheduleTextImporter.parseCsv("""
                课程,星期,节次,周次
                数学,周一,1-2,${rules[0]}
                数学,周三,3-4,${rules[1]}
                数学,周五,5-6,${rules[2]}
            """.trimIndent())
            assertTrue(parsed.unparsed.isEmpty())
            val draft = parsed.drafts.single()
            assertEquals((1..9).toList(), draft.weeks)
            assertEquals(WeekParity.any, draft.parity)
            val expected = if (rules[0].contains("单周")) {
                listOf(WeekParity.odd, WeekParity.even, WeekParity.any)
            } else {
                listOf(WeekParity.any, WeekParity.odd, WeekParity.even)
            }
            assertEquals(expected, draft.meetings.map { it.parity })
            val (courses, parities) = ScheduleTextImporter.toCourses(listOf(draft), DemoData.makeDocument().semester)
            val course = courses.single()
            assertEquals((1..9).toList(), course.weeks)
            assertEquals(listOf(1, 3, 5), course.meetings.map { it.weekday })
            val rulesByMeeting = parities.toMap()
            assertEquals(2, rulesByMeeting.size)
            assertEquals(expected, course.meetings.map { rulesByMeeting[it.id] ?: WeekParity.any })
        }
    }

    @Test
    fun csvContinuationInheritsWeeksAndKeepsDistinctWeekRanges() {
        val parsed = ScheduleTextImporter.parseCsv("""
            课程,星期,节次,周次
            数学,周一,1-2,1-8周 单周
            ,周三,3-4,
            数学,周五,5-6,9-16周
            ,周二,7-8,
            英语,周四,1-2,
        """.trimIndent())
        assertTrue(parsed.unparsed.isEmpty())
        assertEquals(3, parsed.drafts.size)
        val early = parsed.drafts[0]
        assertEquals((1..8).toList(), early.weeks)
        assertEquals(WeekParity.odd, early.parity)
        assertEquals(listOf(1, 3), early.meetings.map { it.weekday })
        assertTrue(early.meetings.all { it.parity == WeekParity.odd })
        val late = parsed.drafts[1]
        assertEquals((9..16).toList(), late.weeks)
        assertEquals(WeekParity.any, late.parity)
        assertEquals(listOf(5, 2), late.meetings.map { it.weekday })
        assertEquals((1..16).toList(), parsed.drafts[2].weeks)
        assertEquals(WeekParity.any, parsed.drafts[2].parity)
        val courses = ScheduleTextImporter.toCourses(parsed.drafts, DemoData.makeDocument().semester).first
        assertEquals((1..8).toList(), courses[0].weeks)
        assertEquals(listOf(1, 3), courses[0].meetings.map { it.weekday })
        assertEquals((9..16).toList(), courses[1].weeks)
        assertEquals(listOf(5, 2), courses[1].meetings.map { it.weekday })
    }

    @Test
    fun csvImportRejectsPeriodsOutsideSemesterBeforeWriting() {
        val document = DemoData.makeDocument()
        val drafts = ScheduleTextImporter.parseCsv("""
            节次,周一,周二,周三
            1-2,数学,,
            11-12,数学,夜课,
        """.trimIndent()).drafts
        val checked = ScheduleTextImporter.validateDrafts(drafts, document.semester)
        assertEquals(2, checked.unparsed.size)
        assertEquals(listOf("数学"), checked.drafts.map { it.name })
        assertEquals(1, checked.drafts.single().meetings.size)
        val (courses, _) = ScheduleTextImporter.toCourses(drafts, document.semester)
        assertEquals(1, courses.size)
        assertEquals(2, courses.single().meetings.single().endPeriod)
        val saved = document.copy(courses = document.courses + courses)
        assertTrue(StoreCodec.validate(saved, calendar).isAcceptable)
        assertNotNull(StoreCodec.importing(StoreCodec.exporting(saved)).document)
        val onlyInvalid = ScheduleTextImporter.parseCsv("课程,星期,节次\n夜课,周一,11-12").drafts
        assertTrue(ScheduleTextImporter.toCourses(onlyInvalid, document.semester).first.isEmpty())
        val shorter = document.semester.copy(periods = document.semester.periods.take(1))
        assertTrue(ScheduleTextImporter.toCourses(drafts, shorter).first.isEmpty())
    }

    @Test
    fun csvGridKeepsPeriodRangesAndRejectsUnknownTimes() {
        val parsed = ScheduleTextImporter.parseCsv("""
            节次,周一,周二,周三
            1-2,数学,,
            3-4节,,英语,
            第5节,,,物理
            未定,待安排,,
            6-3,倒序,,
            21-22,越界,,
            08:00,缺少结束时间,,
            09:40-08:00,倒序时间,,
        """.trimIndent())
        assertEquals(listOf("数学", "英语", "物理"), parsed.drafts.map { it.name })
        assertEquals(listOf(1, 3, 5), parsed.drafts.map { it.meetings.single().startPeriod })
        assertEquals(listOf(2, 4, 5), parsed.drafts.map { it.meetings.single().endPeriod })
        assertEquals(5, parsed.unparsed.size)
        val courses = ScheduleTextImporter.toCourses(parsed.drafts, DemoData.makeDocument().semester).first
        assertEquals(listOf(1, 3, 5), courses.map { it.meetings.single().startPeriod })
        assertEquals(listOf(2, 4, 5), courses.map { it.meetings.single().endPeriod })
    }

    @Test
    fun csvFindsHeaderAfterTitleAndKeepsMergedNameContinuations() {
        for (separator in listOf(',', ';')) {
            val csv = listOf(
                "2026秋课表",
                "课程说明：以教务安排为准",
                "课程名称,星期,节次,教室,教师,周次",
                ",周一,1-2,A301,陈老师,1-16周",
                "1 高等数学,周一,1-2,A301,陈老师,1-16周",
                ",周三,3-4,A302,,1-16周",
                "2 大学英语,周五,5-6,B205,林老师,1-16周",
            ).joinToString("\n") { it.replace(',', separator) }
            val parsed = ScheduleTextImporter.parseCsv(csv)
            // Continuation rows inherit the name, but a different classroom or a blank
            // teacher stays a separate draft so one row cannot take another's room.
            assertEquals(3, parsed.drafts.size)
            assertEquals(listOf("高等数学", "高等数学", "大学英语"), parsed.drafts.map { it.name })
            assertEquals(listOf(1), parsed.drafts[0].meetings.map { it.weekday })
            assertEquals("陈老师", parsed.drafts[0].teacher)
            assertEquals("A301", parsed.drafts[0].location)
            assertEquals(listOf(3), parsed.drafts[1].meetings.map { it.weekday })
            assertEquals("", parsed.drafts[1].teacher)
            assertEquals("A302", parsed.drafts[1].location)
            assertEquals(3, parsed.drafts[1].meetings.single().startPeriod)
            assertEquals(1, parsed.unparsed.size)
        }
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

    @Test
    fun sundayNov15InDemoSemesterIsWeek11AndResetsStaleWeekShift() {
        val semester = DemoData.makeDocument().semester
        val mondayNov9 = java.time.LocalDate.of(2026, 11, 9)
        val sundayNov15 = java.time.LocalDate.of(2026, 11, 15)

        for (offset in 0L..6L) {
            val day = mondayNov9.plusDays(offset)
            assertEquals(11, calendar.weekIndex(day, semester))
        }
        assertEquals("11.09 – 11.15", calendar.weekRangeLabel(11, semester))
        assertEquals("11月9日 – 11月15日", calendar.weekRangeMonthDayLabel(11, semester))
        val week11Days = calendar.datesInWeek(11, semester)
        assertEquals(mondayNov9, week11Days.first())
        assertEquals(sundayNov15, week11Days.last())

        // Reproduces the emulator 2026-11-15 stale weekShift (-1 from an earlier day or session):
        var nav = com.classday.app.core.WeekNavigator()
        val saturdayNov14 = java.time.LocalDate.of(2026, 11, 14)
        nav = nav.shifted(-1, saturdayNov14, semester, calendar)
        assertEquals(10, nav.currentWeek(saturdayNov14, semester, calendar))

        // Crossing into 2026-11-15 or resetting on tab entry must show Week 11 (11.09 – 11.15), not Week 10:
        assertEquals(11, nav.currentWeek(sundayNov15, semester, calendar))
        assertEquals(0, nav.synced(sundayNov15, semester).shift)

        val shiftedOnSunday = nav.shifted(-1, sundayNov15, semester, calendar)
        assertEquals(10, shiftedOnSunday.currentWeek(sundayNov15, semester, calendar))
        val afterTabReset = shiftedOnSunday.reset(sundayNov15, semester)
        assertEquals(11, afterTabReset.currentWeek(sundayNov15, semester, calendar))
    }

    @Test
    fun navigationPreservesSameDaySelectionButResetsForSemesterChanges() {
        val semester = DemoData.makeDocument().semester
        val day = java.time.LocalDate.of(2026, 11, 15)
        val nav = com.classday.app.core.WeekNavigator().shifted(-2, day, semester, calendar)
        assertEquals(9, nav.synced(day, semester).currentWeek(day, semester, calendar))
        val movedStart = semester.copy(startDate = "2026-09-07")
        assertEquals(10, nav.currentWeek(day, movedStart, calendar))
        assertEquals(0, nav.synced(day, movedStart).shift)
        val shorter = semester.copy(totalWeeks = 8)
        assertEquals(0, nav.synced(day, shorter).shift)
        assertEquals(1, nav.currentWeek(day, shorter, calendar))
    }

    @Test
    fun navigationClampsBothEndsAndReversesImmediately() {
        val semester = DemoData.makeDocument().semester
        val day = java.time.LocalDate.of(2026, 11, 15)
        val first = com.classday.app.core.WeekNavigator().shifted(-100, day, semester, calendar)
        assertEquals(1, first.currentWeek(day, semester, calendar))
        assertEquals(2, first.shifted(1, day, semester, calendar).currentWeek(day, semester, calendar))
        val last = first.shifted(100, day, semester, calendar)
        assertEquals(semester.totalWeeks, last.currentWeek(day, semester, calendar))
        assertEquals(semester.totalWeeks - 1, last.shifted(-1, day, semester, calendar).currentWeek(day, semester, calendar))
        assertEquals(11, last.reset(day, semester).currentWeek(day, semester, calendar))
        assertEquals(12, last.currentWeek(day.plusDays(1), semester, calendar))
    }

    @Test
    fun civilWeeksRemainStableAcrossLondonClockChanges() {
        val london = com.classday.app.core.CivilCalendar(java.time.ZoneId.of("Europe/London"))
        for (start in listOf("2026-03-23", "2026-10-19", "2028-02-28", "2026-12-28")) {
            val semester = DemoData.makeDocument().semester.copy(startDate = start, totalWeeks = 3)
            val monday = java.time.LocalDate.parse(start)
            assertNull(london.weekIndex(monday.minusDays(1), semester))
            for (offset in 0L..20L) {
                val day = monday.plusDays(offset)
                val expected = (offset / 7 + 1).toInt()
                assertEquals(expected, london.weekIndex(day.atTime(23, 59).atZone(london.zone).toInstant(), semester))
                assertTrue(london.datesInWeek(expected, semester).contains(day))
            }
            assertNull(london.weekIndex(monday.plusDays(21), semester))
            assertEquals("", london.weekRangeMonthDayLabel(0, semester))
            assertEquals("", london.weekRangeMonthDayLabel(4, semester))
        }
    }

    @Test
    fun iosDesignTokensAndCourseColorPairsMatchSpec() {
        assertEquals(com.classday.app.core.Rgb(58, 107, 255), com.classday.app.core.ClassdayDesignTokens.accent)
        assertEquals(com.classday.app.core.Rgb(27, 36, 51), com.classday.app.core.ClassdayDesignTokens.lightInk)
        assertEquals(com.classday.app.core.Rgb(244, 246, 251), com.classday.app.core.ClassdayDesignTokens.darkInk)
        assertEquals(6, com.classday.app.core.ClassdayDesignTokens.coursePairs.size)
        val blue = com.classday.app.core.ClassdayDesignTokens.coursePair("blue")
        assertEquals(com.classday.app.core.Rgb(228, 236, 255), blue.bg(dark = false))
        assertEquals(com.classday.app.core.Rgb(42, 87, 214), blue.ink(dark = false))
        val orange = com.classday.app.core.ClassdayDesignTokens.coursePair("orange")
        assertEquals(com.classday.app.core.Rgb(255, 232, 212), orange.bg(dark = false))
        assertEquals(com.classday.app.core.Rgb(212, 106, 44), orange.ink(dark = false))
        assertEquals(26, com.classday.app.core.ClassdayDesignTokens.HERO_CARD_RADIUS_DP)
        assertEquals(28, com.classday.app.core.ClassdayDesignTokens.SHEET_TOP_RADIUS_DP)
    }
}
