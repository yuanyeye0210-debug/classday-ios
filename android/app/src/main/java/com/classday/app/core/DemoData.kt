package com.classday.app.core

object DemoData {
    object ID {
        const val calculus = "10000000-0000-0000-0000-000000000001"
        const val english = "10000000-0000-0000-0000-000000000002"
        const val programming = "10000000-0000-0000-0000-000000000003"
        const val physics = "10000000-0000-0000-0000-000000000004"
        const val linear = "10000000-0000-0000-0000-000000000005"
        const val pe = "10000000-0000-0000-0000-000000000006"
        const val calculusMonday = "20000000-0000-0000-0000-000000000001"
        const val calculusWednesday = "20000000-0000-0000-0000-000000000002"
        const val englishMonday = "20000000-0000-0000-0000-000000000003"
        const val englishThursday = "20000000-0000-0000-0000-000000000004"
        const val programmingMonday = "20000000-0000-0000-0000-000000000005"
        const val programmingFriday = "20000000-0000-0000-0000-000000000006"
        const val physicsTuesday = "20000000-0000-0000-0000-000000000007"
        const val physicsThursday = "20000000-0000-0000-0000-000000000008"
        const val linearTuesday = "20000000-0000-0000-0000-000000000009"
        const val peTuesday = "20000000-0000-0000-0000-00000000000A"
        const val examCalculus = "30000000-0000-0000-0000-000000000001"
        const val examPhysics = "30000000-0000-0000-0000-000000000002"
        const val examEnglish = "30000000-0000-0000-0000-000000000003"
        const val examProgramming = "30000000-0000-0000-0000-000000000004"
        const val homeworkCalculus = "40000000-0000-0000-0000-000000000001"
        const val homeworkProgramming = "40000000-0000-0000-0000-000000000002"
        const val eventGym = "60000000-0000-0000-0000-000000000001"
        const val eventLab = "60000000-0000-0000-0000-000000000002"
    }

    fun makeSemester(): Semester = Semester(
        name = "2026-2027 学年 · 第一学期",
        shortName = "2026 秋季学期",
        startDate = "2026-08-31",
        totalWeeks = 16,
        periods = listOf(
            PeriodTemplate(1, "08:00", "08:45"),
            PeriodTemplate(2, "08:55", "09:40"),
            PeriodTemplate(3, "10:10", "10:55"),
            PeriodTemplate(4, "11:05", "11:50"),
            PeriodTemplate(5, "14:00", "14:45"),
            PeriodTemplate(6, "14:55", "15:40"),
            PeriodTemplate(7, "16:10", "16:55"),
            PeriodTemplate(8, "17:05", "17:50"),
            PeriodTemplate(9, "19:00", "19:45"),
            PeriodTemplate(10, "19:55", "20:40"),
        ),
        defaultReminderMinutes = 10,
    )

    /** 演示课程的 id 段：10000000-… 开头，用来区分「案例数据」和用户自己的课。 */
    fun isDemoCourse(id: String): Boolean = id.startsWith("10000000-", ignoreCase = true)
    fun makeCourses(): List<Course> {
        val weeks = (1..16).toList()
        return listOf(
            Course(ID.calculus, "高等数学", "陈老师", "教学楼 A · 301", "数学与统计学院", "请提前 5 分钟到达教室", "blue", "必修课", weeks, listOf(Meeting(ID.calculusMonday, 1, 1, 2), Meeting(ID.calculusWednesday, 3, 3, 4)), 10, 4.0),
            Course(ID.english, "大学英语", "林老师", "教学楼 B · 205", "外国语学院", "", "green", "必修课", weeks, listOf(Meeting(ID.englishMonday, 1, 3, 4), Meeting(ID.englishThursday, 4, 1, 2)), null, 2.0),
            Course(ID.programming, "程序设计", "周老师", "机房 2", "计算机学院", "", "purple", "必修课", weeks, listOf(Meeting(ID.programmingMonday, 1, 5, 6), Meeting(ID.programmingFriday, 5, 5, 6)), null, 3.0),
            Course(ID.physics, "大学物理", "赵老师", "教学楼 A · 206", "物理学院", "", "orange", "必修课", weeks, listOf(Meeting(ID.physicsTuesday, 2, 1, 2), Meeting(ID.physicsThursday, 4, 3, 4)), null, 3.0, 92.0),
            Course(ID.linear, "线性代数", "吴老师", "教学楼 A · 302", "数学与统计学院", "", "pink", "必修课", weeks, listOf(Meeting(ID.linearTuesday, 2, 5, 6)), null, 3.0, 85.0),
            Course(ID.pe, "大学体育", "孙老师", "体育馆", "体育部", "", "sage", "实践", weeks, listOf(Meeting(ID.peTuesday, 2, 7, 8)), null, 1.0),
        )
    }

    fun makeDocument(): StoreDocument = StoreDocument(
        schemaVersion = StoreDocument.currentSchema,
        origin = DataOrigin.demo,
        semester = makeSemester(),
        courses = makeCourses(),
        exams = listOf(
            ExamEvent(ID.examCalculus, "高等数学", "教学楼 A · 301", "2026-12-22T09:00", "2026-12-22T11:00", "期末考试"),
            ExamEvent(ID.examPhysics, "大学物理", "教学楼 A · 206", "2026-12-24T14:00", "2026-12-24T16:00", "期末考试"),
            ExamEvent(ID.examEnglish, "大学英语", "教学楼 B · 205", "2026-12-29T10:10", "2026-12-29T12:10", "期末考试"),
            ExamEvent(ID.examProgramming, "程序设计", "机房 2", "2027-01-05T14:00", "2027-01-05T16:00", "期末考试"),
        ),
        homework = listOf(
            HomeworkTask(ID.homeworkCalculus, "高等数学", "第三章习题", "2026-11-11T23:59"),
            HomeworkTask(ID.homeworkProgramming, "程序设计", "实验报告", "2026-11-13T23:59"),
        ),
        personalEvents = listOf(
            PersonalEvent(ID.eventGym, "健身", "VivaGym · 练背 + 有氧", "2026-11-10T18:30", "2026-11-10T20:00"),
            PersonalEvent(ID.eventLab, "实验室组会", "Lab 2 小组 · 讨论报告", "2026-11-10T20:30", "2026-11-10T21:30"),
        ),
    )
}

data class DuplicateGroup(val normalizedName: String, val courses: List<Course>)

private const val NAME_EDGE_JUNK = "()（）[]【】{}—-_.·,、:：/\\|"

/** 比较用的课程名键：去空白、全角转半角、小写、去掉首尾的括号/连字符等杂符。 */
fun normalizeCourseName(name: String): String {
    val built = buildString {
        name.forEach { char ->
            if (char.isWhitespace()) return@forEach
            var value = char.code
            if (value in 0xFF01..0xFF5E) value -= 0xFEE0
            if (value in 0x41..0x5A) value += 32
            append(value.toChar())
        }
    }
    return built.trim { it in NAME_EDGE_JUNK }
}

/** 展示用的课程名：只把首尾的空格与杂符清掉，中间一律不动。 */
fun cleanCourseDisplayName(name: String): String = name.trim().trimEnd(*NAME_EDGE_JUNK.toCharArray()).trim()

fun findDuplicateGroups(courses: List<Course>): List<DuplicateGroup> {
    val order = mutableListOf<String>()
    val grouped = linkedMapOf<String, MutableList<Course>>()
    for (course in courses) {
        val key = normalizeCourseName(course.name)
        if (grouped[key] == null) order += key
        grouped.getOrPut(key) { mutableListOf() } += course
    }
    return order.mapNotNull { key ->
        val members = grouped[key].orEmpty()
        if (members.size < 2) null else DuplicateGroup(key, members)
    }
}

private data class MeetingSlot(val weekday: Int, val startPeriod: Int, val endPeriod: Int)

fun droppedMeetingRemap(group: DuplicateGroup): Map<String, String> {
    val keptBySlot = mutableMapOf<MeetingSlot, String>()
    val remap = linkedMapOf<String, String>()
    for (course in group.courses) {
        for (meeting in course.meetings) {
            val slot = MeetingSlot(meeting.weekday, meeting.startPeriod, meeting.endPeriod)
            val kept = keptBySlot[slot]
            if (kept != null) remap[meeting.id] = kept else keptBySlot[slot] = meeting.id
        }
    }
    return remap
}

fun gradeConflict(group: DuplicateGroup): Boolean =
    group.courses.mapNotNull { it.grade }.toSet().size > 1

fun mergeDuplicateGroup(group: DuplicateGroup, gradeSourceId: String?): Pair<Course, Map<String, String>>? {
    if (group.courses.isEmpty()) return null
    val survivor = group.courses[0]
    val graded = group.courses.filter { it.grade != null }
    val distinct = graded.mapNotNull { it.grade }.toSet()
    val (grade, scheme) = when {
        graded.isEmpty() -> null to null
        distinct.size == 1 -> graded[0].grade to graded[0].gradeScheme
        else -> {
            val chosen = graded.firstOrNull { it.id.equals(gradeSourceId, ignoreCase = true) } ?: return null
            chosen.grade to chosen.gradeScheme
        }
    }
    // 2.9.9：同名课常常分在不同教室（讲座 + 实验），合并时把所有教室都保留下来。
    val rooms = group.courses.map { it.location.trim() }.filter { it.isNotEmpty() }.distinct()
    // 合并后清掉课程名首尾的杂符（真实数据里有 "Power Conversion & Storage   (   " 这种）。
    val merged = survivor.copy(name = cleanCourseDisplayName(survivor.name),
        meetings = dedupedMeetings(group.courses),
        weeks = group.courses.flatMap { it.weeks }.toSet().sorted(),
        reminderLeadMinutes = group.courses.firstNotNullOfOrNull { it.reminderLeadMinutes },
        grade = grade,
        gradeScheme = scheme,
        location = when {
            rooms.size > 1 -> rooms.joinToString(" / ")
            // 只有一个成员填了教室时，就用那一个；不能用幸存者的空值把教室丢掉。
            rooms.size == 1 -> rooms.first()
            else -> survivor.location
        },
    )
    val remap = group.courses.drop(1).associate { it.id to survivor.id }
    return merged to remap
}

fun selectedMergeGroup(group: DuplicateGroup, excluded: Set<String>): DuplicateGroup =
    group.copy(courses = group.courses.filter { it.id !in excluded })

fun canSubmitCourseMerge(group: DuplicateGroup, chosen: String?, document: StoreDocument): Boolean =
    group.courses.size >= 2 && canMergeCourseSchedules(group.courses, document) &&
        (!gradeConflict(group) || group.courses.any { it.id == chosen && it.grade != null })

fun mergeableScheduleGroups(document: StoreDocument): List<DuplicateGroup> =
    findDuplicateGroups(document.courses).filter { group ->
        group.courses.indices.any { index ->
            group.courses.drop(index + 1).any { canMergeCourseSchedules(listOf(group.courses[index], it), document) }
        }
    }

fun canMergeCourseSchedules(courses: List<Course>, document: StoreDocument): Boolean {
    val first = courses.firstOrNull() ?: return true
    if (courses.any { it.weeks.toSet() != first.weeks.toSet() || it.location != first.location }) return false
    val parities = mutableMapOf<MeetingSlot, WeekParity>()
    for (course in courses) for (meeting in course.meetings) {
        val slot = MeetingSlot(meeting.weekday, meeting.startPeriod, meeting.endPeriod)
        val parity = document.scheduleContext.parity(meeting.id)
        if (parities[slot]?.let { it != parity } == true) return false
        parities[slot] = parity
    }
    return true
}

fun applyMerge(document: StoreDocument, group: DuplicateGroup, gradeSourceId: String?): StoreDocument? {
    // 2.9.9：不再要求"周次/教室完全一致"才允许合并——同名课分教室、分周次也要并成一门。
    // 人工合并页仍然用 canSubmitCourseMerge 自己做门槛。
    val merged = mergeDuplicateGroup(group, gradeSourceId) ?: return null
    val (course, remap) = merged
    val meetingRemap = droppedMeetingRemap(group)
    val courses = document.courses.mapNotNull { item ->
        when {
            item.id == course.id -> course
            remap.containsKey(item.id) -> null
            else -> item
        }
    }
    val overrides = document.overrides.map { override ->
        val courseId = remap[override.courseID] ?: override.courseID
        val meetingId = meetingRemap[override.meetingID] ?: override.meetingID
        override.copy(courseID = courseId, meetingID = meetingId)
    }
    val rules = document.weekRules.map { rule ->
        rule.copy(meetingID = meetingRemap[rule.meetingID] ?: rule.meetingID)
    }
    val cancellations = document.semester.cancellations.map { entry ->
        val mapped = entry.courseID?.let { remap[it] }
        if (mapped == null) entry else entry.copy(courseID = mapped)
    }
    return document.copy(
        courses = courses,
        overrides = overrides,
        weekRules = rules,
        semester = document.semester.copy(cancellations = cancellations),
    )
}

private fun dedupedMeetings(courses: List<Course>): List<Meeting> {
    val seen = mutableSetOf<MeetingSlot>()
    val result = mutableListOf<Meeting>()
    for (course in courses) {
        for (meeting in course.meetings) {
            // 2.10：把来源课程自己的教室写到这一次课上，
            // 合并后每周各次课就能显示各自的教室，而不是一串全教室。
            val stamped = if (meeting.location.isBlank()) {
                meeting.copy(location = course.location.trim())
            } else {
                meeting
            }
            val slot = MeetingSlot(meeting.weekday, meeting.startPeriod, meeting.endPeriod)
            if (seen.add(slot)) result += stamped
        }
    }
    return result
}
