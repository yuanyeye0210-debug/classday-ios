package com.classday.app.core

/** Validates editable study entries without changing the source document. */
object StudyEntryEditor {
    fun homework(existing: HomeworkTask?, course: String, title: String, due: String, calendar: CivilCalendar): HomeworkTask? {
        val cleanTitle = title.trim()
        val cleanDue = due.trim()
        if (cleanTitle.isEmpty() || CivilStamp.instant(cleanDue, calendar) == null) return null
        return (existing ?: HomeworkTask(courseName = "", title = "", dueISO = cleanDue))
            .copy(courseName = course.trim(), title = cleanTitle, dueISO = cleanDue)
    }

    fun exam(existing: ExamEvent?, name: String, start: String, end: String, place: String, calendar: CivilCalendar): ExamEvent? {
        val cleanName = name.trim()
        val cleanStart = start.trim()
        val cleanEnd = end.trim()
        val from = CivilStamp.instant(cleanStart, calendar) ?: return null
        val until = CivilStamp.instant(cleanEnd, calendar) ?: return null
        if (cleanName.isEmpty() || !until.isAfter(from)) return null
        return (existing ?: ExamEvent(courseName = "", location = "", startISO = cleanStart, endISO = cleanEnd))
            .copy(courseName = cleanName, location = place.trim(), startISO = cleanStart, endISO = cleanEnd)
    }
}
