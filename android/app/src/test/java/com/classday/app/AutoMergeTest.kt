package com.classday.app

import com.classday.app.core.Course
import com.classday.app.core.DemoData
import com.classday.app.core.Meeting
import com.classday.app.core.OccurrenceOverride
import com.classday.app.core.OverrideKind
import com.classday.app.core.StoreDocument
import com.classday.app.core.autoMergeDuplicateCourses
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 2.9.8：同名课程自动合并。
 * 规则与手动合并一致：周次/时段取并集，成绩冲突取较高分，引用一并改指幸存者；
 * 安排冲突的分组不合并，留给人工页。
 */
class AutoMergeTest {
    private val base = DemoData.makeDocument()

    private fun course(
        id: String,
        name: String = "高等数学",
        location: String = "教学楼 A101",
        weeks: List<Int> = (1..16).toList(),
        meetings: List<Meeting> = listOf(Meeting("M$id", 1, 1, 2)),
        grade: Double? = null,
    ) = Course(
        id = id,
        name = name,
        teacher = "王老师",
        location = location,
        colorID = "blue",
        weeks = weeks,
        meetings = meetings,
        grade = grade,
    )

    private fun document(courses: List<Course>, overrides: List<OccurrenceOverride> = emptyList()): StoreDocument =
        base.copy(
            courses = courses,
            weekRules = emptyList(),
            overrides = overrides,
            exams = emptyList(),
            homework = emptyList(),
            personalEvents = emptyList(),
        )

    @Test
    fun sameNameSameScheduleIsMergedIntoOne() {
        val doc = document(listOf(course("C1"), course("C2", meetings = listOf(Meeting("M2", 3, 3, 4)))))
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(1, result.mergedGroups)
        assertEquals(1, result.document.courses.size)
        val merged = result.document.courses.first()
        assertEquals("C1", merged.id)
        assertEquals(listOf(1, 3), merged.meetings.map { it.weekday }.sorted())
        assertEquals((1..16).toList(), merged.weeks)
        assertTrue(result.remainingGroups.isEmpty())
    }

    @Test
    fun differentRoomsAreMergedAndEveryRoomIsKept() {
        // 2.9.9：同一门课分在不同教室也必须并成一门，教室全部保留。
        val doc = document(
            listOf(
                course("C1", location = "Room C9"),
                course("C2", location = "Room V1.17"),
            ),
        )
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(1, result.mergedGroups)
        assertEquals(1, result.document.courses.size)
        assertEquals("Room C9 / Room V1.17", result.document.courses.first().location)
        assertTrue(result.remainingGroups.isEmpty())
    }

    @Test
    fun roomSurvivesWhenOnlyOneMemberHasIt() {
        val doc = document(
            listOf(
                course("C1", name = "Power Conversion & Storage   (   ", location = ""),
                course("C2", name = "Power Conversion & Storage", location = "Room EA4"),
            ),
        )
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(1, result.mergedGroups)
        assertEquals("Room EA4", result.document.courses.first().location)
    }
    @Test
    fun trailingJunkInNameStillMerges() {
        // 真实数据："Power Conversion & Storage   (   " 与 "Power Conversion & Storage"
        val doc = document(
            listOf(
                course("C1", name = "Power Conversion & Storage   (   ", location = ""),
                course("C2", name = "Power Conversion & Storage", location = "Room EA4"),
            ),
        )
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(1, result.mergedGroups)
        assertEquals(1, result.document.courses.size)
        assertEquals("Power Conversion & Storage", result.document.courses.first().name.trim())
    }
    @Test
    fun differentWeeksAreMergedIntoUnion() {
        val doc = document(
            listOf(
                course("C1", weeks = (1..8).toList()),
                course("C2", weeks = (9..16).toList(), meetings = listOf(Meeting("M2", 3, 1, 2))),
            ),
        )
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(1, result.mergedGroups)
        assertEquals((1..16).toList(), result.document.courses.first().weeks)
    }

    @Test
    fun gradeConflictKeepsTheHigherScore() {
        val doc = document(listOf(course("C1", grade = 72.0), course("C2", grade = 88.0)))
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(1, result.mergedGroups)
        assertEquals(88.0, result.document.courses.first().grade!!, 0.0001)
    }

    @Test
    fun singleGradeIsKeptWithoutConflict() {
        val doc = document(listOf(course("C1"), course("C2", grade = 91.0)))
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(1, result.mergedGroups)
        assertEquals(91.0, result.document.courses.first().grade!!, 0.0001)
    }

    @Test
    fun overridesFollowTheSurvivor() {
        val override = OccurrenceOverride(
            id = "O1",
            courseID = "C2",
            meetingID = "M2",
            week = 3,
            kind = OverrideKind.cancelled,
        )
        val doc = document(
            listOf(course("C1"), course("C2", meetings = listOf(Meeting("M2", 1, 1, 2)))),
            overrides = listOf(override),
        )
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(1, result.mergedGroups)
        val left = result.document.overrides.single()
        assertEquals("C1", left.courseID)
        assertEquals("MC1", left.meetingID)
    }

    @Test
    fun mergingIsIdempotent() {
        val doc = document(listOf(course("C1"), course("C2")))
        val once = autoMergeDuplicateCourses(doc)
        val twice = autoMergeDuplicateCourses(once.document)
        assertEquals(1, once.mergedGroups)
        assertEquals(0, twice.mergedGroups)
        assertEquals(once.document.courses, twice.document.courses)
    }

    @Test
    fun unrelatedCoursesAreUntouched() {
        val doc = document(listOf(course("C1"), course("C9", name = "大学英语")))
        val result = autoMergeDuplicateCourses(doc)
        assertEquals(0, result.mergedGroups)
        assertEquals(2, result.document.courses.size)
        assertNull(result.document.courses.firstOrNull { it.id == "C9" }?.grade)
    }

    @Test
    fun threeDuplicatesCollapseToOneWithUnionOfSlots() {
        val doc = document(
            listOf(
                course("C1", meetings = listOf(Meeting("M1", 1, 1, 2))),
                course("C2", meetings = listOf(Meeting("M2", 2, 3, 4))),
                course("C3", meetings = listOf(Meeting("M3", 5, 5, 6))),
            ),
        )
        val result = autoMergeDuplicateCourses(doc)
        // 三个同名的课程属于同一个分组，一次就并成一门。
        assertEquals(1, result.mergedGroups)
        assertEquals(1, result.document.courses.size)
        assertEquals(listOf(1, 2, 5), result.document.courses.first().meetings.map { it.weekday }.sorted())
    }
}
