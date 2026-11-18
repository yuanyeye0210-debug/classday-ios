package com.classday.app

import com.classday.app.core.*
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class StudyEntryEditorTest {
    private val calendar = CivilCalendar(ZoneId.of("UTC"))

    @Test fun editingCompletedHomeworkPreservesIdentityStateAndNotes() {
        val original = HomeworkTask(id = "work-1", courseName = "旧课程", title = "旧标题", dueISO = "2026-12-01T18:00", done = true, note = "保留备注")
        val result = StudyEntryEditor.homework(original, " 新课程 ", " 新标题 ", "2026-12-02T19:00", calendar)!!
        assertEquals(original.id, result.id)
        assertTrue(result.done)
        assertEquals(original.note, result.note)
        assertEquals("新标题", result.title)
        assertEquals("新课程", result.courseName)
        assertEquals("旧标题", original.title)
    }

    @Test fun invalidHomeworkNeverProducesSavedEntry() {
        assertNull(StudyEntryEditor.homework(null, "", "  ", "2026-12-01T18:00", calendar))
        assertNull(StudyEntryEditor.homework(null, "", "作业", "not-a-date", calendar))
        assertNull(StudyEntryEditor.homework(null, "", "作业", "2026-13-01T18:00", calendar))
    }

    @Test fun newHomeworkIsUnfinishedAndCourseMayBeBlank() {
        val result = StudyEntryEditor.homework(null, "", "作业", "2026-12-01T18:00", calendar)!!
        assertFalse(result.done)
        assertTrue(result.id.isNotBlank())
        assertEquals("", result.courseName)
    }

    @Test fun examRejectsMissingNameBadDateZeroAndNegativeDuration() {
        assertNull(StudyEntryEditor.exam(null, "", "2026-12-01T09:00", "2026-12-01T10:00", "", calendar))
        assertNull(StudyEntryEditor.exam(null, "考试", "bad", "2026-12-01T10:00", "", calendar))
        assertNull(StudyEntryEditor.exam(null, "考试", "2026-12-01T09:00", "bad", "", calendar))
        assertNull(StudyEntryEditor.exam(null, "考试", "2026-12-01T09:00", "2026-12-01T09:00", "", calendar))
        assertNull(StudyEntryEditor.exam(null, "考试", "2026-12-01T10:00", "2026-12-01T09:00", "", calendar))
    }

    @Test fun editingExamPreservesIdentityAndNotesAndSupportsCrossMidnight() {
        val original = ExamEvent(id = "exam-1", courseName = "旧课程", location = "A", startISO = "2026-12-01T09:00", endISO = "2026-12-01T10:00", note = "携带证件")
        val result = StudyEntryEditor.exam(original, " 新课程 ", "2026-12-01T23:00", "2026-12-02T01:00", " B ", calendar)!!
        assertEquals(original.id, result.id)
        assertEquals(original.note, result.note)
        assertEquals("B", result.location)
        assertEquals("新课程", result.courseName)
        assertEquals("A", original.location)
    }
}
