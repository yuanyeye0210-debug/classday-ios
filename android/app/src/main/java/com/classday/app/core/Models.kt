package com.classday.app.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.UUID

val StoreJson: Json = Json {
    encodeDefaults = true
    explicitNulls = false
    ignoreUnknownKeys = true
    coerceInputValues = true
    prettyPrint = true
}

val ShareJson: Json = Json {
    encodeDefaults = true
    explicitNulls = false
    ignoreUnknownKeys = true
    coerceInputValues = true
    prettyPrint = false
}

fun newId(): String = UUID.randomUUID().toString().uppercase()

fun normId(raw: String?): String? = raw?.trim()?.takeIf { it.isNotEmpty() }?.uppercase()

enum class DataOrigin { demo, user }

enum class WeekParity {
    any, odd, even;

    val title: String
        get() = when (this) {
            any -> "每周"
            odd -> "单周"
            even -> "双周"
        }

    fun contains(week: Int): Boolean = when (this) {
        any -> true
        odd -> week % 2 == 1
        even -> week % 2 == 0
    }
}

enum class OverrideKind { cancelled, moved, delayed }

enum class PerformanceTier {
    high, balanced, saver;

    val title: String
        get() = when (this) {
            high -> "高性能"
            balanced -> "平衡"
            saver -> "省电"
        }

    val detail: String
        get() = when (this) {
            high -> "着色器、视差和粒子都打开"
            balanced -> "保留动效，小组件用静态皮肤"
            saver -> "关闭着色器、陀螺仪和粒子"
        }
}

@Serializable
data class ClockTime(val hour: Int, val minute: Int) : Comparable<ClockTime> {
    val totalMinutes: Int get() = hour * 60 + minute
    val hhmm: String get() = "%02d:%02d".format(hour, minute)

    override fun compareTo(other: ClockTime): Int = totalMinutes.compareTo(other.totalMinutes)

    companion object {
        fun parse(raw: String): ClockTime? {
            val parts = raw.trim().split(":")
            if (parts.size != 2) return null
            val hour = parts[0].toIntOrNull() ?: return null
            val minute = parts[1].toIntOrNull() ?: return null
            if (hour !in 0..23 || minute !in 0..59) return null
            return ClockTime(hour, minute)
        }
    }
}

@Serializable
data class PeriodTemplate(val index: Int, val start: String, val end: String)

@Serializable
data class Meeting(
    val id: String,
    val weekday: Int,
    val startPeriod: Int,
    val endPeriod: Int,
    // 2.10：教室下沉到单次课。留空表示沿用课程教室（旧数据与单教室课程都是这种情况）。
    val location: String = "",
) {
    val periodCount: Int get() = endPeriod - startPeriod + 1
}

@Serializable
data class GradeComponent(val id: String, val name: String)

@Serializable
data class GradeTerm(val componentID: String, val weight: Double)

@Serializable
data class GradeScheme(
    val scale: Double = 100.0,
    val components: List<GradeComponent> = emptyList(),
    val scores: Map<String, Double> = emptyMap(),
    val branches: List<List<GradeTerm>> = emptyList(),
    /** 每个分项的最低分要求：达不到即这门课直接不合格（例如「考试需 8/20」）。 */
    val minimums: Map<String, Double> = emptyMap(),
) {
    fun value(branch: List<GradeTerm>): Double? {
        if (branch.isEmpty()) return null
        var total = 0.0
        for (term in branch) {
            val score = scores[term.componentID] ?: return null
            total += term.weight * score
        }
        return total
    }

    val bestBranchIndex: Int?
        get() {
            var best: Int? = null
            var bestValue = Double.NEGATIVE_INFINITY
            branches.forEachIndexed { index, branch ->
                val value = value(branch) ?: return@forEachIndexed
                if (value > bestValue) {
                    bestValue = value
                    best = index
                }
            }
            return best
        }

    val finalGrade: Double?
        get() {
            val index = bestBranchIndex ?: return null
            return value(branches[index])
        }

    val normalizedFinal: Double?
        get() {
            val final = finalGrade ?: return null
            if (scale <= 0) return null
            return final / scale * 100.0
        }

    /** 已录入成绩低于最低分要求的分项，用来在界面上提示「直接不合格」。 */
    val minimumWarnings: List<String>
        get() = components.mapNotNull { component ->
            val min = minimums[component.id] ?: return@mapNotNull null
            val score = scores[component.id] ?: return@mapNotNull null
            if (score + 1e-9 >= min) null
            else component.name + " 只有 " + score + " 分，低于最低要求 " + min + " 分"
        }
}

@Serializable
data class Course(
    val id: String,
    val name: String,
    val teacher: String,
    val location: String,
    val department: String = "",
    val note: String = "",
    val colorID: String,
    val kind: String = "必修课",
    val weeks: List<Int>,
    val meetings: List<Meeting>,
    val reminderLeadMinutes: Int? = null,
    val credits: Double = 0.0,
    val grade: Double? = null,
    val gradeScheme: GradeScheme? = null,
    /** 班级/教学班，列表里显示在课程名下面；可为空。 */
    val className: String = "",
) {
    fun normalized(): Course = copy(id = id.uppercase(), weeks = weeks.toSet().sorted(), meetings = meetings.map { it.copy(id = it.id.uppercase()) })
}

@Serializable
data class PersonalEvent(
    val id: String,
    val title: String,
    val note: String = "",
    val startISO: String,
    val endISO: String,
)

@Serializable
data class HolidayPeriod(
    val id: String,
    val name: String,
    val startDate: String,
    val endDate: String,
)

@Serializable
data class ClassCancellation(
    val id: String,
    val date: String,
    val courseID: String? = null,
    val courseName: String = "",
    val scope: String = "all",
    val reason: String = "",
)

@Serializable
data class Semester(
    val name: String,
    val shortName: String,
    val startDate: String,
    val totalWeeks: Int,
    val periods: List<PeriodTemplate>,
    val defaultReminderMinutes: Int,
    val holidays: List<HolidayPeriod> = emptyList(),
    val cancellations: List<ClassCancellation> = emptyList(),
)

@Serializable
data class MeetingWeekRule(val meetingID: String, val parity: WeekParity) {
    val id: String get() = meetingID
}

@Serializable
data class OccurrenceOverride(
    val id: String = newId(),
    val courseID: String,
    val meetingID: String,
    val week: Int,
    val kind: OverrideKind,
    val weekday: Int? = null,
    val startPeriod: Int? = null,
    val endPeriod: Int? = null,
    val delayMinutes: Int? = null,
)

@Serializable
data class ExamEvent(
    val id: String = newId(),
    val courseName: String,
    val location: String,
    val startISO: String,
    val endISO: String,
    val note: String = "",
)

@Serializable
data class HomeworkTask(
    val id: String = newId(),
    val courseName: String,
    val title: String,
    val dueISO: String,
    val done: Boolean = false,
    val note: String = "",
)

@Serializable
data class RoomPin(
    val id: String = newId(),
    val name: String,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val query: String = name,
)

@Serializable
data class StoredTimetable(
    val id: String,
    val name: String,
    val semester: Semester,
    val courses: List<Course>,
    val weekRules: List<MeetingWeekRule>,
    val overrides: List<OccurrenceOverride>,
    val exams: List<ExamEvent>,
    val homework: List<HomeworkTask>,
    val rooms: List<RoomPin>,
)

@Serializable
data class AppearanceChoice(
    val themeID: String = ClassdayThemes.fallbackId,
    val performance: PerformanceTier = PerformanceTier.balanced,
) {
    val theme: ClassdayTheme get() = ClassdayThemes.theme(themeID)

    companion object {
        val standard = AppearanceChoice()
    }
}

@Serializable
data class StoreDocument(
    val schemaVersion: Int,
    val origin: DataOrigin,
    val semester: Semester,
    val courses: List<Course>,
    val weekRules: List<MeetingWeekRule> = emptyList(),
    val overrides: List<OccurrenceOverride> = emptyList(),
    val exams: List<ExamEvent> = emptyList(),
    val homework: List<HomeworkTask> = emptyList(),
    val personalEvents: List<PersonalEvent> = emptyList(),
    val rooms: List<RoomPin> = emptyList(),
    val library: List<StoredTimetable> = emptyList(),
    val activeTimetableID: String = TimetableLibrary.implicitId,
    val appearance: AppearanceChoice = AppearanceChoice.standard,
    val subscribedICSURL: String = "",
) {
    val scheduleContext: ScheduleContext get() = ScheduleContext(weekRules, overrides)

    companion object {
        // 2.10：Meeting 增加 location（教室下沉到单次课）。旧文档缺少该字段时按空串读取，行为不变。
        const val currentSchema = 2
    }
}

data class ScheduleContext(
    val weekRules: List<MeetingWeekRule> = emptyList(),
    val overrides: List<OccurrenceOverride> = emptyList(),
) {
    fun parity(meetingId: String): WeekParity =
        weekRules.firstOrNull { it.meetingID.equals(meetingId, ignoreCase = true) }?.parity ?: WeekParity.any

    fun override(courseId: String, meetingId: String, week: Int): OccurrenceOverride? =
        overrides.lastOrNull {
            it.courseID.equals(courseId, ignoreCase = true) &&
                it.meetingID.equals(meetingId, ignoreCase = true) &&
                it.week == week
        }

    companion object {
        val empty = ScheduleContext()
    }
}

data class Occurrence(
    val id: String,
    val courseID: String,
    val meetingID: String,
    val name: String,
    val teacher: String,
    val location: String,
    val locationShort: String,
    val department: String,
    val note: String,
    val colorID: String,
    val kind: String,
    val weekday: Int,
    val startPeriod: Int,
    val endPeriod: Int,
    val weekIndex: Int,
    val weeks: List<Int>,
    val startEpochMillis: Long,
    val endEpochMillis: Long,
    val timeText: String,
    val reminderLeadMinutes: Int?,
    val parityLabel: String,
)

data class MeetingConflict(
    val courseID: String,
    val meetingID: String,
    val courseName: String,
    val otherCourseID: String,
    val otherMeetingID: String,
    val otherCourseName: String,
    val weekday: Int,
    val startPeriod: Int,
    val endPeriod: Int,
    val weeks: List<Int>,
)

sealed class MoveValidation {
    data object Unchanged : MoveValidation()
    data class Ok(val courses: List<Course>) : MoveValidation()
    data object OutOfBounds : MoveValidation()
    data object Missing : MoveValidation()
    data class Conflict(val conflicts: List<MeetingConflict>) : MoveValidation()
}

object LocationText {
    fun short(location: String): String {
        val trimmed = location.trim()
        val marker = "教学楼"
        val index = trimmed.indexOf(marker)
        if (index < 0) return trimmed
        val rest = trimmed.substring(index + marker.length).trim()
        return rest.ifEmpty { trimmed }
    }
}

object CourseColors {
    val all = listOf("blue", "orange", "green", "purple", "pink", "sage")
    fun style(id: String): String = if (id in all) id else "blue"
}
