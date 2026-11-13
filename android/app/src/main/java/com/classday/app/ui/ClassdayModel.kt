package com.classday.app.ui

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.lifecycle.AndroidViewModel
import com.classday.app.ClassAlerts
import com.classday.app.core.CivilCalendar
import com.classday.app.core.ClassdayThemes
import com.classday.app.core.Course
import com.classday.app.core.CourseDraft
import com.classday.app.core.DataOrigin
import com.classday.app.core.DemoData
import com.classday.app.core.DuplicateGroup
import com.classday.app.core.ExamEvent
import com.classday.app.core.HomeworkTask
import com.classday.app.core.Meeting
import com.classday.app.core.Occurrence
import com.classday.app.core.OccurrenceOverride
import com.classday.app.core.OverrideKind
import com.classday.app.core.PerformanceTier
import com.classday.app.core.ScheduleEngine
import com.classday.app.core.ScheduleTextImporter
import com.classday.app.core.Semester
import com.classday.app.core.ShareCodec
import com.classday.app.core.StoreCodec
import com.classday.app.core.StoreDocument
import com.classday.app.core.TimetableLibrary
import com.classday.app.core.WeekParity
import com.classday.app.core.applyMerge
import com.classday.app.core.findDuplicateGroups
import com.classday.app.core.newId
import com.classday.app.platform.ClassdayStore
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

sealed class Screen {
    data object Week : Screen()
    data object Countdown : Screen()
    data object Settings : Screen()
    data object Periods : Screen()
    data object SemesterEdit : Screen()
    data object Holidays : Screen()
    data object Reminders : Screen()
    data object DataPage : Screen()
    data object About : Screen()
    data object ImportReview : Screen()
    data object Merge : Screen()
    data class Detail(val courseId: String, val meetingId: String?, val week: Int) : Screen()
    data class Editor(val courseId: String?) : Screen()
}

class ClassdayModel(app: Application) : AndroidViewModel(app) {
    private val initialLoad = ClassdayStore.loadWithStatus(app)
    private var lastSavedDocument = initialLoad.document
    var document by mutableStateOf(initialLoad.document)
        private set
    var banner by mutableStateOf(initialLoad.error)
    var weekShift by mutableStateOf(0)
    var screen by mutableStateOf<Screen>(Screen.Week)
    var reminderDraft by mutableStateOf<Int?>(null)
    var semesterDraft by mutableStateOf<Semester?>(null)
    var importDrafts by mutableStateOf<List<CourseDraft>>(emptyList())
    var importNote by mutableStateOf("")
    private val history = ArrayDeque<Screen>()
    private var undoDocument: StoreDocument? = null
    val calendar = CivilCalendar(ZoneId.systemDefault())

    val theme get() = ClassdayThemes.theme(document.appearance.themeID)
    val tier: PerformanceTier
        get() {
            val power = (getApplication<Application>().getSystemService(android.os.PowerManager::class.java))?.isPowerSaveMode == true
            val scale = android.provider.Settings.Global.getFloat(getApplication<Application>().contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
            return ClassdayThemes.effectiveTier(document.appearance.performance, power, scale == 0f)
        }

    fun weekIndex(): Int {
        val today = LocalDate.now(calendar.zone)
        val base = calendar.weekIndex(today, document.semester) ?: 1
        return (base + weekShift).coerceIn(1, document.semester.totalWeeks)
    }

    fun open(next: Screen) {
        history.addLast(screen)
        screen = next
    }

    fun back() {
        screen = if (history.isEmpty()) Screen.Week else history.removeLast()
    }

    fun goHome(tab: Screen) {
        history.clear()
        screen = tab
    }

    fun occurrences(): List<Occurrence> =
        ScheduleEngine.occurrences(weekIndex(), document.courses, document.semester, calendar, document.scheduleContext)

    fun cycleTheme() {
        val next = ClassdayThemes.cycle(document.appearance.themeID)
        document = document.copy(appearance = document.appearance.copy(themeID = next))
        haptic(ClassdayThemes.theme(next).haptic)
        persist(markUser = false)
        banner = ClassdayThemes.theme(next).name
    }

    fun setTheme(id: String) {
        document = document.copy(appearance = document.appearance.copy(themeID = ClassdayThemes.theme(id).id))
        haptic(theme.haptic)
        persist(markUser = false)
    }

    fun setTier(tier: PerformanceTier) {
        document = document.copy(appearance = document.appearance.copy(performance = tier))
        persist(markUser = false)
    }

    fun shiftWeek(delta: Int) {
        val today = LocalDate.now(calendar.zone)
        val base = calendar.weekIndex(today, document.semester) ?: 1
        val target = (base + weekShift + delta).coerceIn(1, document.semester.totalWeeks)
        weekShift = target - base
    }

    fun backToThisWeek() {
        weekShift = 0
    }

    fun cancelThisWeek(item: Occurrence) {
        document = TimetableLibrary.overriding(document, OccurrenceOverride(courseID = item.courseID, meetingID = item.meetingID, week = item.weekIndex, kind = OverrideKind.cancelled))
        banner = "已取消本周这一节，其他周不变"
        persist(markUser = true)
    }

    fun delayThisWeek(item: Occurrence, minutes: Int = 10) {
        document = TimetableLibrary.overriding(document, OccurrenceOverride(courseID = item.courseID, meetingID = item.meetingID, week = item.weekIndex, kind = OverrideKind.delayed, delayMinutes = minutes))
        banner = "本周这一节推迟 $minutes 分钟"
        persist(markUser = true)
    }

    fun moveThisWeek(item: Occurrence, weekday: Int, startPeriod: Int) {
        val duration = item.endPeriod - item.startPeriod + 1
        val end = startPeriod + duration - 1
        val max = document.semester.periods.maxOfOrNull { it.index } ?: 0
        if (weekday !in 1..7 || startPeriod < 1 || end > max) {
            haptic("reject")
            banner = "调出范围了"
            return
        }
        document = TimetableLibrary.overriding(
            document,
            OccurrenceOverride(courseID = item.courseID, meetingID = item.meetingID, week = item.weekIndex, kind = OverrideKind.moved, weekday = weekday, startPeriod = startPeriod, endPeriod = end),
        )
        banner = "只改了本周这一节"
        persist(markUser = true)
    }

    fun clearThisWeek(item: Occurrence) {
        document = TimetableLibrary.clearingOverride(document, item.courseID, item.meetingID, item.weekIndex)
        banner = "本周改动已撤销"
        persist(markUser = true)
    }

    fun setParity(meetingId: String, parity: WeekParity) {
        document = TimetableLibrary.settingParity(document, meetingId, parity)
        persist(markUser = true)
    }

    fun moveMeeting(courseId: String, meetingId: String, weekday: Int, startPeriod: Int) {
        when (val result = ScheduleEngine.validateMove(courseId, meetingId, weekday, startPeriod, document.courses, document.semester, document.scheduleContext)) {
            is com.classday.app.core.MoveValidation.Unchanged -> Unit
            is com.classday.app.core.MoveValidation.Ok -> {
                undoDocument = document
                document = document.copy(courses = result.courses, origin = DataOrigin.user)
                haptic(theme.haptic)
                banner = "已调整时间，可撤销"
                persist(markUser = true)
            }
            is com.classday.app.core.MoveValidation.Conflict -> {
                haptic("reject")
                banner = "和${result.conflicts.firstOrNull()?.otherCourseName ?: "其他课"}冲突，没有放下"
            }
            com.classday.app.core.MoveValidation.OutOfBounds -> {
                haptic("reject")
                banner = "放不下"
            }
            com.classday.app.core.MoveValidation.Missing -> banner = "找不到这节课"
        }
    }

    fun undo() {
        val previous = undoDocument ?: return
        document = previous
        undoDocument = null
        banner = "已撤销"
        persist(markUser = true)
    }

    fun saveCourse(course: Course) {
        val cleaned = course.normalized().copy(name = course.name.trim())
        if (cleaned.name.isEmpty() || cleaned.meetings.isEmpty() || cleaned.weeks.isEmpty()) {
            banner = "名称、周次和上课时间都要有"
            haptic("reject")
            return
        }
        val others = document.courses.filter { !it.id.equals(cleaned.id, ignoreCase = true) }
        document = document.copy(courses = others + cleaned, origin = DataOrigin.user)
        banner = "已保存"
        haptic(theme.haptic)
        persist(markUser = true)
        back()
    }

    fun deleteCourse(id: String) {
        document = document.copy(courses = document.courses.filter { !it.id.equals(id, ignoreCase = true) }, origin = DataOrigin.user)
        banner = "已删除"
        persist(markUser = true)
        back()
    }

    fun saveSemester(semester: Semester) {
        val report = StoreCodec.validate(document.copy(semester = semester), calendar)
        if (!report.isAcceptable) {
            banner = report.errors.firstOrNull() ?: "学期无效"
            return
        }
        document = document.copy(semester = semester, origin = DataOrigin.user)
        semesterDraft = semester
        banner = "学期已保存"
        persist(markUser = true)
    }

    fun ensureReminderDraft() {
        if (reminderDraft == null) reminderDraft = document.semester.defaultReminderMinutes
    }

    fun saveReminderDraft() {
        val minutes = reminderDraft ?: return
        if (minutes !in 0..180) {
            banner = "提醒分钟数要在 0 到 180"
            return
        }
        document = document.copy(semester = document.semester.copy(defaultReminderMinutes = minutes), origin = DataOrigin.user)
        banner = "提醒已保存"
        persist(markUser = true)
    }

    fun addExam(name: String, whenIso: String, location: String) {
        document = document.copy(exams = document.exams + ExamEvent(courseName = name, location = location, startISO = whenIso, endISO = whenIso), origin = DataOrigin.user)
        persist(markUser = true)
    }

    fun addHomework(course: String, title: String, due: String) {
        document = document.copy(homework = document.homework + HomeworkTask(courseName = course, title = title, dueISO = due), origin = DataOrigin.user)
        persist(markUser = true)
    }

    fun toggleHomework(id: String) {
        document = document.copy(homework = document.homework.map { if (it.id == id) it.copy(done = !it.done) else it })
        persist(markUser = true)
    }

    fun deleteExam(id: String) {
        document = document.copy(exams = document.exams.filter { it.id != id })
        persist(markUser = true)
    }

    fun importDocument(raw: String, replace: Boolean) {
        val outcome = StoreCodec.importing(raw, calendar)
        val imported = outcome.document
        if (imported == null) {
            banner = outcome.errors.firstOrNull() ?: "无法解析"
            return
        }
        document = if (replace) imported.copy(origin = DataOrigin.user) else document.copy(
            courses = document.courses + imported.courses,
            exams = document.exams + imported.exams,
            homework = document.homework + imported.homework,
            weekRules = document.weekRules + imported.weekRules,
            origin = DataOrigin.user,
        )
        banner = if (outcome.warnings.isEmpty()) "已导入" else outcome.warnings.first()
        if (findDuplicateGroups(document.courses).isNotEmpty()) banner = "导入后有同名课程，可以去合并"
        persist(markUser = true)
    }

    fun importShare(raw: String) {
        val token = ShareCodec.tokenFromUrl(raw) ?: raw.trim()
        val payload = ShareCodec.decode(token)
        if (payload == null) {
            banner = "这份分享读不出来"
            return
        }
        document = document.copy(
            semester = payload.semester,
            courses = payload.courses,
            weekRules = payload.weekRules,
            overrides = payload.overrides,
            exams = payload.exams,
            homework = payload.homework,
            origin = DataOrigin.user,
        )
        banner = "已导入分享的课表"
        persist(markUser = true)
    }

    fun importCalendar(courses: List<Course>, exams: List<com.classday.app.core.ExamEvent>, homework: List<HomeworkTask>, subscribe: String? = null) {
        document = document.copy(
            courses = document.courses + courses,
            exams = document.exams + exams,
            homework = document.homework + homework,
            subscribedICSURL = subscribe ?: document.subscribedICSURL,
            origin = DataOrigin.user,
        )
        banner = "导入 ${courses.size} 门课、${exams.size} 场考试、${homework.size} 项作业"
        if (findDuplicateGroups(document.courses).isNotEmpty()) banner = "导入后有同名课程，可以去合并"
        persist(markUser = true)
    }

    fun stageDrafts(text: String, csv: Boolean = false) {
        val parsed = if (csv) ScheduleTextImporter.parseCsv(text) else ScheduleTextImporter.parseText(text)
        val checked = ScheduleTextImporter.validateDrafts(parsed.drafts, document.semester)
        importDrafts = checked.drafts
        importNote = if (importDrafts.isEmpty()) "没有可导入的课程" else "认出 ${importDrafts.size} 门，确认后才写入"
        if (parsed.unparsed.isNotEmpty()) importNote += "；${parsed.unparsed.size} 行未识别，请检查源文件"
        if (checked.unparsed.isNotEmpty()) importNote += "；已跳过 ${checked.unparsed.size} 项星期或节次超出当前学期范围的安排，请检查学期节次设置"
        if (importDrafts.isNotEmpty()) open(Screen.ImportReview)
        else banner = importNote
    }

    fun confirmDrafts() {
        val (courses, parities) = ScheduleTextImporter.toCourses(importDrafts, document.semester)
        if (courses.isEmpty()) {
            banner = "没有可导入的课程，请检查当前学期的节次设置"
            return
        }
        document = document.copy(courses = document.courses + courses, origin = DataOrigin.user)
        parities.forEach { (meeting, parity) -> document = TimetableLibrary.settingParity(document, meeting, parity) }
        importDrafts = emptyList()
        banner = "已添加 ${courses.size} 门课"
        persist(markUser = true)
        back()
    }

    fun duplicates(): List<DuplicateGroup> = findDuplicateGroups(document.courses)

    fun merge(group: DuplicateGroup, gradeSource: String?) {
        if (!com.classday.app.core.canMergeCourseSchedules(group.courses, document)) {
            banner = "周次、教室或同一时段单双周不同，已保持独立课程"
            return
        }
        val backup = TimetableLibrary.storingCurrent(document, document.semester.shortName.ifBlank { "合并前" })
        val merged = applyMerge(backup, group, gradeSource)
        if (merged == null) {
            banner = "这几门课的成绩不一样，先选一个保留"
            return
        }
        document = merged.copy(origin = DataOrigin.user)
        banner = "已合并，合并前的课表留在课表库"
        persist(markUser = true)
    }

    fun storeLibrary(name: String) {
        document = TimetableLibrary.storingCurrent(document, name)
        banner = "已存入课表库"
        persist(markUser = true)
    }

    fun switchLibrary(id: String) {
        val next = TimetableLibrary.switching(document, id)
        if (next == null) {
            banner = "找不到这套课表"
            return
        }
        document = next
        banner = "已切换到 ${document.semester.shortName}"
        persist(markUser = true)
    }

    fun resetDemo() {
        document = DemoData.makeDocument()
        banner = "已恢复演示数据"
        persist(markUser = false)
    }

    fun clearAll() {
        document = document.copy(courses = emptyList(), exams = emptyList(), homework = emptyList(), weekRules = emptyList(), overrides = emptyList(), origin = DataOrigin.user)
        banner = "课程已清空"
        persist(markUser = true)
    }

    fun exportJson(): String = StoreCodec.exporting(document)

    fun blankCourse(): Course = Course(
        id = newId(),
        name = "",
        teacher = "",
        location = "",
        colorID = "blue",
        weeks = (1..document.semester.totalWeeks).toList(),
        meetings = listOf(Meeting(newId(), 1, 1, 2)),
    )

    fun haptic(kind: String) {
        if (tier == PerformanceTier.saver && kind != "reject") return
        val context = getApplication<Application>()
        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        } ?: return
        val effect = effectFor(kind)
        vibrator.vibrate(effect)
    }

    private fun persist(markUser: Boolean) {
        if (markUser && document.origin == DataOrigin.demo) {
            document = document.copy(origin = DataOrigin.user)
        }
        try {
            ClassdayStore.save(getApplication(), document)
            lastSavedDocument = document
        } catch (error: Exception) {
            document = lastSavedDocument
            banner = error.message ?: "未能保存课表，已恢复到上次保存的内容"
            return
        }
        ClassAlerts.refreshAsync(getApplication(), document)
    }
}

private fun effectFor(kind: String): VibrationEffect {
    val waveform = when (kind) {
        "electric" -> longArrayOf(0, 14, 18, 22, 16, 36) to intArrayOf(0, 255, 0, 180, 0, 255)
        "soft" -> longArrayOf(0, 24) to intArrayOf(0, 60)
        "tick" -> longArrayOf(0, 12) to intArrayOf(0, 140)
        "particle" -> longArrayOf(0, 10, 16, 10, 16, 18) to intArrayOf(0, 80, 0, 120, 0, 180)
        "metal" -> longArrayOf(0, 28, 20, 40) to intArrayOf(0, 255, 0, 220)
        "glide" -> longArrayOf(0, 18, 30, 22) to intArrayOf(0, 70, 120, 90)
        "glass" -> longArrayOf(0, 16, 12, 28) to intArrayOf(0, 200, 0, 255)
        "reject" -> longArrayOf(0, 20, 30, 20) to intArrayOf(0, 180, 0, 180)
        else -> longArrayOf(0, 18) to intArrayOf(0, 160)
    }
    return if (Build.VERSION.SDK_INT >= 26) {
        VibrationEffect.createWaveform(waveform.first, waveform.second, -1)
    } else {
        @Suppress("DEPRECATION")
        VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE)
    }
}

fun tiltOffset(x: Float, y: Float, enabled: Boolean): Offset =
    if (!enabled) Offset.Zero else Offset(x.coerceIn(-16f, 16f), y.coerceIn(-16f, 16f))
