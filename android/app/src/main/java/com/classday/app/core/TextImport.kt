package com.classday.app.core

data class MeetingDraft(
    val weekday: Int,
    val startMinutes: Int? = null,
    val endMinutes: Int? = null,
    val startPeriod: Int? = null,
    val endPeriod: Int? = null,
    val location: String = "",
    val parity: WeekParity = WeekParity.any,
)

data class CourseDraft(
    val name: String,
    val teacher: String = "",
    val location: String = "",
    val weeks: List<Int> = (1..16).toList(),
    val meetings: List<MeetingDraft> = emptyList(),
    val parity: WeekParity = WeekParity.any,
)

data class DraftImport(val drafts: List<CourseDraft>, val unparsed: List<String>)

object ScheduleTextImporter {
    fun parseCsv(text: String): DraftImport {
        val lines = text.removePrefix("\uFEFF").replace("\r\n", "\n").replace('\r', '\n').lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        if (lines.isEmpty()) return DraftImport(emptyList(), emptyList())
        // Score real headers, not the title/notes that Excel exports may prepend.
        val candidates = listOf(',', ';').flatMap { delimiter ->
            val rows = lines.take(6).map { splitCsv(it, delimiter) }
            rows.mapIndexedNotNull { index, row ->
                val columns = mapColumns(row.map { it.trim() })
                if (row.size > 1 && columns["name"] != null && columns["weekday"] != null &&
                    columns["name"] != columns["weekday"] &&
                    (columns["period"] != null || columns["start"] != null)) {
                    Triple(delimiter, index, columns)
                } else null
            }
        }
        val best = candidates.maxByOrNull { it.third.size }
        val delimiter = best?.first ?: if (lines.first().contains(';') && !lines.first().contains(',')) ';' else ','
        val rows = lines.map { splitCsv(it, delimiter) }
        if (rows.first().count { weekdayOf(it) != null } >= 3) return parseGrid(rows)
        if (best == null) return DraftImport(emptyList(), lines)
        val columns = best.third
        val grouped = linkedMapOf<String, CourseDraft>()
        val unparsed = mutableListOf<String>()
        var lastName = ""
        for (row in rows.drop(best.second + 1)) {
            val explicitName = cell(row, columns["name"]).trim().replace(Regex("^\\d+[.、．]?\\s+"), "")
            if (explicitName.isNotEmpty()) lastName = explicitName
            val name = explicitName.ifEmpty { lastName }
            if (name.isEmpty()) {
                unparsed += row.joinToString(delimiter.toString())
                continue
            }
            val weekday = weekdayOf(cell(row, columns["weekday"]))
            val period = parsePeriodSpan(cell(row, columns["period"]))
            val start = parseClockMinutes(cell(row, columns["start"]))
            val end = parseClockMinutes(cell(row, columns["end"]))
            val (weeks, parity) = parseWeeks(cell(row, columns["weeks"]))
            val teacher = cell(row, columns["teacher"])
            val location = cell(row, columns["location"]).ifEmpty { cell(row, columns["place"]) }
            if (weekday == null || (period == null && start == null)) {
                unparsed += row.joinToString(delimiter.toString())
                continue
            }
            val meeting = MeetingDraft(
                weekday = weekday,
                startMinutes = start,
                endMinutes = end,
                startPeriod = period?.first ?: start?.let { ICSImporter.periodGuess(it) },
                endPeriod = period?.second ?: end?.let { ICSImporter.periodGuess((it - 1).coerceAtLeast(0)) }?.let { guessed ->
                    maxOf(period?.first ?: guessed, guessed)
                },
                location = location,
                parity = parity,
            )
            val existing = grouped[name]
            if (existing == null) {
                grouped[name] = CourseDraft(name, teacher, location, weeks, listOf(meeting), parity)
            } else {
                grouped[name] = existing.copy(
                    teacher = existing.teacher.ifEmpty { teacher },
                    location = existing.location.ifEmpty { location },
                    meetings = existing.meetings + meeting,
                    weeks = if (weeks.isNotEmpty()) weeks else existing.weeks,
                )
            }
        }
        return DraftImport(grouped.values.toList(), unparsed)
    }

    fun parseText(text: String): DraftImport {
        if (text.contains("BEGIN:VCALENDAR")) return DraftImport(emptyList(), emptyList())
        val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.firstOrNull()?.contains(',') == true || lines.firstOrNull()?.contains(';') == true) {
            val csv = parseCsv(text)
            if (csv.drafts.isNotEmpty()) return csv
        }
        val drafts = mutableListOf<CourseDraft>()
        val unparsed = mutableListOf<String>()
        for (line in lines) {
            val weekday = weekdayOf(line)
            val clock = Regex("(\\d{1,2}:\\d{2})").findAll(line).map { parseClockMinutes(it.value) }.filterNotNull().toList()
            val name = line.substringBefore("周").substringBefore("星期").trim().ifEmpty { line.take(12) }
            if (weekday == null || name.isEmpty()) {
                unparsed += line
                continue
            }
            drafts += CourseDraft(
                name = name,
                meetings = listOf(
                    MeetingDraft(
                        weekday = weekday,
                        startMinutes = clock.getOrNull(0),
                        endMinutes = clock.getOrNull(1),
                        startPeriod = clock.getOrNull(0)?.let { ICSImporter.periodGuess(it) } ?: 1,
                        endPeriod = clock.getOrNull(1)?.let { ICSImporter.periodGuess((it - 1).coerceAtLeast(0)) } ?: clock.getOrNull(0)?.let { ICSImporter.periodGuess(it) } ?: 1,
                    ),
                ),
            )
        }
        return DraftImport(drafts, unparsed)
    }

    fun toCourses(drafts: List<CourseDraft>, semester: Semester): Pair<List<Course>, List<Pair<String, WeekParity>>> {
        val courses = mutableListOf<Course>()
        val parities = mutableListOf<Pair<String, WeekParity>>()
        drafts.forEachIndexed { index, draft ->
            if (draft.name.isBlank() || draft.meetings.isEmpty()) return@forEachIndexed
            val meetings = draft.meetings.map { meeting ->
                val start = meeting.startPeriod ?: 1
                val end = meeting.endPeriod ?: start
                val id = newId()
                val parity = if (meeting.parity != WeekParity.any) meeting.parity else draft.parity
                if (parity != WeekParity.any) parities += id to parity
                Meeting(id, meeting.weekday.coerceIn(1, 7), start, end)
            }
            val weeks = draft.weeks.filter { it in 1..semester.totalWeeks }.ifEmpty { (1..semester.totalWeeks).toList() }
            courses += Course(
                id = newId(),
                name = draft.name.trim(),
                teacher = draft.teacher,
                location = draft.location.ifEmpty { draft.meetings.firstOrNull()?.location.orEmpty() },
                colorID = CourseColors.all[index % CourseColors.all.size],
                weeks = weeks,
                meetings = meetings,
            )
        }
        return courses to parities
    }

    private fun parseGrid(rows: List<List<String>>): DraftImport {
        val header = rows.first()
        val dayColumns = header.mapIndexedNotNull { index, title -> weekdayOf(title)?.let { it to index } }
        if (dayColumns.size < 3) return DraftImport(emptyList(), rows.map { it.joinToString(",") })
        val grouped = linkedMapOf<String, CourseDraft>()
        for (row in rows.drop(1)) {
            val span = parseClockRange(row.firstOrNull().orEmpty())
            for ((weekday, column) in dayColumns) {
                val cell = row.getOrNull(column)?.trim().orEmpty()
                if (cell.isEmpty()) continue
                val parts = cell.split(Regex("\\s+"), limit = 2)
                val name = parts[0]
                val location = parts.getOrElse(1) { "" }
                val meeting = MeetingDraft(
                    weekday = weekday,
                    startMinutes = span?.first,
                    endMinutes = span?.second,
                    startPeriod = span?.first?.let { ICSImporter.periodGuess(it) },
                    endPeriod = span?.second?.let { ICSImporter.periodGuess((it - 1).coerceAtLeast(0)) },
                    location = location,
                )
                val existing = grouped[name]
                grouped[name] = if (existing == null) CourseDraft(name, location = location, meetings = listOf(meeting))
                else existing.copy(meetings = existing.meetings + meeting, location = existing.location.ifEmpty { location })
            }
        }
        return DraftImport(grouped.values.toList(), emptyList())
    }

    private fun mapColumns(header: List<String>): Map<String, Int> {
        fun find(names: List<String>): Int? = header.indexOfFirst { cell -> names.any { cell.contains(it, ignoreCase = true) } }.takeIf { it >= 0 }
        return mapOf(
            "name" to (find(listOf("课程名称", "课程名", "课程", "name", "course")) ?: -1),
            "weekday" to (find(listOf("星期", "周几", "weekday", "day")) ?: -1),
            "start" to (find(listOf("开始时间", "开始", "start")) ?: -1),
            "end" to (find(listOf("结束时间", "结束", "end")) ?: -1),
            "period" to (find(listOf("节次", "节", "period")) ?: -1),
            "location" to (find(listOf("教室", "地点", "location", "room")) ?: -1),
            "place" to (find(listOf("地点")) ?: -1),
            "teacher" to (find(listOf("教师", "老师", "teacher")) ?: -1),
            "weeks" to (find(listOf("周次", "周数", "上课周次", "起止周", "上课周", "weeks", "week")) ?: -1),
        ).filterValues { it >= 0 }
    }

    private fun cell(row: List<String>, index: Int?): String = if (index == null || index !in row.indices) "" else row[index].trim()

    fun weekdayOf(raw: String): Int? {
        val text = raw.trim()
        if (text.isEmpty()) return null
        val numbered = Regex("[1-7]").find(text)?.value?.toInt()
        val table = listOf("一" to 1, "二" to 2, "三" to 3, "四" to 4, "五" to 5, "六" to 6, "日" to 7, "天" to 7)
        if (text.contains("周") || text.contains("星期")) {
            table.firstOrNull { text.contains(it.first) }?.let { return it.second }
        }
        val lower = text.lowercase()
        val english = listOf("mon" to 1, "tue" to 2, "wed" to 3, "thu" to 4, "fri" to 5, "sat" to 6, "sun" to 7)
        english.firstOrNull { lower.contains(it.first) }?.let { return it.second }
        if (text.length <= 2) return numbered?.takeIf { it in 1..7 }
        return null
    }

    fun parseWeeks(raw: String, total: Int = 16): Pair<List<Int>, WeekParity> {
        val parity = when {
            raw.contains("单") -> WeekParity.odd
            raw.contains("双") -> WeekParity.even
            else -> WeekParity.any
        }
        val numbers = Regex("\\d+").findAll(raw).map { it.value.toInt() }.toList()
        val weeks = when {
            numbers.size >= 2 && (raw.contains("-") || raw.contains("–") || raw.contains("~") || raw.contains("到")) ->
                (numbers[0]..numbers[1]).toList()
            numbers.isNotEmpty() -> numbers
            else -> (1..total).toList()
        }
        return weeks to parity
    }

    private fun parsePeriodSpan(raw: String): Pair<Int, Int>? {
        val numbers = Regex("\\d+").findAll(raw).map { it.value.toInt() }.toList()
        if (numbers.isEmpty()) return null
        val start = numbers[0]
        val end = numbers.getOrElse(1) { start }
        if (start !in 1..20 || end !in 1..20) return null
        return start to end
    }

    private fun parseClockMinutes(raw: String): Int? {
        val clock = ClockTime.parse(raw.trim().take(5).let { if (it.count { ch -> ch == ':' } == 1 && it.length >= 4) it else raw.trim() }) ?: return null
        return clock.totalMinutes
    }

    private fun parseClockRange(raw: String): Pair<Int, Int>? {
        val clocks = Regex("(\\d{1,2}:\\d{2})").findAll(raw).mapNotNull { parseClockMinutes(it.value) }.toList()
        if (clocks.size < 2) return null
        return clocks[0] to clocks[1]
    }

    private fun splitCsv(line: String, delimiter: Char): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        var quoted = false
        for (char in line) {
            when {
                char == '"' -> quoted = !quoted
                char == delimiter && !quoted -> {
                    result += current.toString()
                    current.clear()
                }
                else -> current.append(char)
            }
        }
        result += current.toString()
        return result
    }
}

object HolidayImporter {
    fun parseIcs(text: String, calendar: CivilCalendar): List<HolidayPeriod> {
        val unfolded = text.replace("\r\n", "\n").replace("\n ", "").replace("\n\t", "")
        val periods = mutableListOf<HolidayPeriod>()
        for (block in unfolded.split("BEGIN:VEVENT")) {
            if (!block.contains("END:VEVENT")) continue
            var summary = "假期"
            var startRaw: String? = null
            var endRaw: String? = null
            for (line in block.split('\n')) {
                when {
                    line.startsWith("SUMMARY") -> summary = line.substringAfter(':').trim().ifEmpty { "假期" }
                    line.startsWith("DTSTART") -> startRaw = line.substringAfter(':')
                    line.startsWith("DTEND") -> endRaw = line.substringAfter(':')
                }
            }
            val startInstant = startRaw?.let { ICSImporter.parseIcsDate(it, calendar) } ?: continue
            var endDate = startInstant.atZone(calendar.zone).toLocalDate()
            val startDate = endDate
            if (endRaw != null) {
                val endInstant = ICSImporter.parseIcsDate(endRaw, calendar)
                if (endInstant != null) {
                    var endCivil = endInstant.atZone(calendar.zone).toLocalDate()
                    val exclusive = !endRaw.contains("T") || endRaw.contains("T000000")
                    if (exclusive) endCivil = endCivil.minusDays(1)
                    if (!endCivil.isBefore(startDate)) endDate = endCivil
                }
            }
            periods += HolidayPeriod(newId(), summary, calendar.formatCivil(startDate), calendar.formatCivil(endDate))
        }
        return periods
    }
}

object GradeSchemeParser {
    fun parse(text: String): GradeScheme? {
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        val json = text.substring(start, end + 1)
        val result = try {
            ShareJson.decodeFromString<AiGrade>(json)
        } catch (_: RuntimeException) {
            return null
        }
        val names = result.components.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        if (names.isEmpty()) return null
        val components = names.mapIndexed { index, name -> GradeComponent("ai-$index", name) }
        val idByName = components.associate { it.name to it.id }
        val branches = mutableListOf<List<GradeTerm>>()
        for (raw in result.branches) {
            val known = raw.filter { idByName.containsKey(it.component) }
            val sum = known.sumOf { it.weight }
            val divisor = if (sum > 1.5) 100.0 else 1.0
            val terms = known.mapNotNull { term ->
                val id = idByName[term.component] ?: return@mapNotNull null
                GradeTerm(id, term.weight / divisor)
            }
            if (terms.isNotEmpty()) branches += terms
        }
        if (branches.isEmpty()) {
            branches += components.map { GradeTerm(it.id, 1.0 / components.size) }
        }
        val scale = if (result.scale in 10.0..1000.0) result.scale else 100.0
        return GradeScheme(scale, components, emptyMap(), branches)
    }

    @kotlinx.serialization.Serializable
    private data class AiTerm(val component: String, val weight: Double)

    @kotlinx.serialization.Serializable
    private data class AiGrade(val scale: Double = 100.0, val components: List<String> = emptyList(), val branches: List<List<AiTerm>> = emptyList())
}
