package com.classday.app.core

data class MeetingDraft(
    val weekday: Int,
    val startMinutes: Int? = null,
    val endMinutes: Int? = null,
    val startPeriod: Int? = null,
    val endPeriod: Int? = null,
    val location: String = "",
    val parity: WeekParity = WeekParity.any,
    /** True when the source states the periods itself instead of the parser guessing them. */
    val explicitPeriod: Boolean = false,
)

data class CourseDraft(
    val name: String,
    val teacher: String = "",
    val location: String = "",
    val weeks: List<Int> = (1..16).toList(),
    val meetings: List<MeetingDraft> = emptyList(),
    val parity: WeekParity = WeekParity.any,
    /** 班级/教学班（源文件提供时才填）。 */
    val className: String = "",
)

/** notes：已导入但做过替换、需要让用户知道的说明（例如源节次本学期不存在、改按时间导入）。 */
data class DraftImport(val drafts: List<CourseDraft>, val unparsed: List<String>, val notes: List<String> = emptyList())

object ScheduleTextImporter {
    /** Local mail-body import. Ambiguous prose stays unparsed, never defaults to period 1. */
    fun parseMail(text: String): DraftImport {
        val normalized = text.removePrefix("\uFEFF").replace("\r\n", "\n").replace('\r', '\n')
        val notices = listOf("停课", "取消", "调课", "补课", "延期", "改为")
        val (noticeLines, courseLines) = normalized.lines().partition { line -> notices.any { it in line } }
        // Email clients copy HTML tables as tab-separated plain text. Quote every cell
        // before reusing CSV parsing so commas and quotes in course names survive.
        val tableText = courseLines.joinToString("\n") { line ->
            if ('\t' in line) line.split('\t').joinToString(",") { cell ->
                "\"" + cell.replace("\"", "\"\"") + "\""
            } else line
        }
        val table = parseCsv(tableText)
        if (table.drafts.isNotEmpty()) return table.copy(unparsed = table.unparsed + noticeLines)
        val drafts = mutableListOf<CourseDraft>()
        val unparsed = mutableListOf<String>()
        for (line in normalized.lines().map { it.trim() }.filter { it.isNotEmpty() }) {
            val clocks = Regex("(?<!\\d)\\d{1,2}:\\d{2}(?!\\d)").findAll(line).map { it.value }.toList()
            val minutes = clocks.map { parseClockMinutes(it) }
            val name = line.substringBefore("星期").substringBefore("周").trim()
            val ambiguous = notices.any { it in line }
            if (ambiguous || weekdayOf(line) == null || name == line || name.isBlank() ||
                minutes.size != 2 || minutes.any { it == null } || minutes[0]!! >= minutes[1]!!) {
                unparsed += line
                continue
            }
            val parsed = parseText(line)
            drafts += parsed.drafts
            unparsed += parsed.unparsed
        }
        return DraftImport(drafts, unparsed)
    }

    private data class CsvCourseKey(
        val name: String,
        val weeks: List<Int>,
        val teacher: String,
        val location: String,
    )

    fun parseCsv(text: String): DraftImport {
        val lines = text.removePrefix("\uFEFF").replace("\r\n", "\n").replace('\r', '\n').lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        if (lines.isEmpty()) return DraftImport(emptyList(), emptyList())
        val gridHeader = listOf(',', ';').flatMap { delimiter ->
            lines.take(6).mapIndexedNotNull { index, line ->
                val cells = splitCsv(line, delimiter)
                // A grid starts with a time/period label, followed by weekday columns.
                // Numeric data rows such as 1,2,3 must not become headers.
                val days = if (weekdayOf(cells.first()) == null) {
                    cells.drop(1).mapNotNull { weekdayOf(it) }.distinct().size
                } else 0
                if (days >= 3) Triple(delimiter, index, days) else null
            }
        }.maxByOrNull { it.third }
        if (gridHeader != null) {
            return parseGrid(lines.drop(gridHeader.second).map { splitCsv(it, gridHeader.first) })
        }
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
        if (best == null) return DraftImport(emptyList(), lines)
        val columns = best.third
        val grouped = linkedMapOf<CsvCourseKey, CourseDraft>()
        val unparsed = mutableListOf<String>()
        var lastName = ""
        var lastWeeks: Pair<List<Int>, WeekParity>? = null
        for (row in rows.drop(best.second + 1)) {
            val explicitName = cell(row, columns["name"]).trim().replace(Regex("^\\d+[.、．]?\\s+"), "")
            if (explicitName.isNotEmpty() && explicitName != lastName) lastWeeks = null
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
            val rawWeeks = cell(row, columns["weeks"])
            val weekRule = if (rawWeeks.isBlank()) lastWeeks ?: parseWeeks("") else parseWeeks(rawWeeks)
            val (weeks, parity) = weekRule
            val teacher = cell(row, columns["teacher"])
            val location = cell(row, columns["location"]).ifEmpty { cell(row, columns["place"]) }
            if (weekday == null || (period == null && start == null)) {
                unparsed += row.joinToString(delimiter.toString())
                continue
            }
            lastWeeks = weekRule
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
                explicitPeriod = period != null,
            )
            // A course has only one teacher/location. Keep distinct metadata separate,
            // including unknown values, rather than assigning one row's room to another.
            val key = CsvCourseKey(name, weeks, teacher, location)
            val existing = grouped[key]
            if (existing == null) {
                grouped[key] = CourseDraft(name, teacher, location, weeks, listOf(meeting), parity)
            } else {
                grouped[key] = existing.copy(
                    teacher = existing.teacher.ifEmpty { teacher },
                    location = existing.location.ifEmpty { location },
                    meetings = existing.meetings + meeting,
                    // Each meeting owns its rule; a mixed course must not supply an odd/even fallback.
                    parity = if (existing.parity == parity) parity else WeekParity.any,
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
            val period = explicitPeriodIn(line)
            val name = line.substringBefore("周").substringBefore("星期").trim().ifEmpty { line.take(12) }
            if (weekday == null || name.isEmpty()) {
                unparsed += line
                continue
            }
            // A period stated by the source stays authoritative even when the line also
            // carries clocks. Half a clock range cannot confirm it, so it is dropped.
            val keepClock = period == null || clock.getOrNull(1) != null
            drafts += CourseDraft(
                name = name,
                meetings = listOf(
                    MeetingDraft(
                        weekday = weekday,
                        startMinutes = clock.getOrNull(0).takeIf { keepClock },
                        endMinutes = clock.getOrNull(1),
                        startPeriod = period?.first ?: clock.getOrNull(0)?.let { ICSImporter.periodGuess(it) } ?: 1,
                        endPeriod = period?.second ?: clock.getOrNull(1)?.let { ICSImporter.periodGuess((it - 1).coerceAtLeast(0)) } ?: clock.getOrNull(0)?.let { ICSImporter.periodGuess(it) } ?: 1,
                        explicitPeriod = period != null,
                    ),
                ),
            )
        }
        return DraftImport(drafts, unparsed)
    }

    fun validateDrafts(drafts: List<CourseDraft>, semester: Semester): DraftImport {
        val indexes = semester.periods.map { it.index }.toSet()
        val rejected = mutableListOf<String>()
        val notes = mutableListOf<String>()
        val valid = drafts.mapNotNull { draft ->
            val meetings = draft.meetings.mapNotNull { original ->
                val meeting = resolveMeeting(original, draft.name, semester, indexes, rejected, notes) ?: return@mapNotNull null
                val start = meeting.startPeriod ?: 0
                val end = meeting.endPeriod ?: start
                val acceptable = meeting.weekday in 1..7 && start <= end && start in indexes && end in indexes &&
                    (start..end).all { it in indexes }
                if (!acceptable) rejected += "${draft.name}：星期或节次超出当前学期范围"
                if (acceptable) meeting else null
            }
            if (meetings.isEmpty()) null else draft.copy(meetings = meetings)
        }
        return DraftImport(valid, rejected, notes)
    }

    /** 「第 3 节」或「第 3–5 节」。 */
    fun periodSpanLabel(start: Int?, end: Int?): String {
        val first = start ?: return "第 ? 节"
        val last = end ?: first
        return if (last == first) "第 $first 节" else "第 $first–$last 节"
    }

    /** 按本学期作息给出起止时间，如「09:00–10:30」；节次不在作息里时为 null。 */
    fun periodClockLabel(start: Int?, end: Int?, semester: Semester): String? {
        val first = semester.periods.singleOrNull { it.index == start } ?: return null
        val last = semester.periods.singleOrNull { it.index == (end ?: start) } ?: return null
        return "${first.start}–${last.end}"
    }

    private fun clockLabel(minutes: Int): String =
        String.format(java.util.Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)

    /**
     * Resolve one arrangement against the current semester. Parse-time guesses may be
     * replaced by the stated clock time, but periods stated by the source stay
     * authoritative: a contradictory clock is reported instead of silently winning.
     * A period this semester cannot represent falls back to a complete clock.
     */
    private fun resolveMeeting(
        original: MeetingDraft,
        courseName: String,
        semester: Semester,
        indexes: Set<Int>,
        rejected: MutableList<String>,
        notes: MutableList<String>,
    ): MeetingDraft? {
        val hasClock = original.startMinutes != null || original.endMinutes != null
        if (original.explicitPeriod) {
            val periodStart = original.startPeriod
            val periodEnd = original.endPeriod ?: periodStart
            if (periodStart != null && periodEnd != null && periodStart <= periodEnd &&
                periodStart in indexes && periodEnd in indexes &&
                (periodStart..periodEnd).all { it in indexes }) {
                // Only a complete clock can confirm or contradict the stated period;
                // half a range is too weak to override it.
                if (original.startMinutes != null && original.endMinutes != null) {
                    val first = semester.periods.singleOrNull { it.index == periodStart }
                    val last = semester.periods.singleOrNull { it.index == periodEnd }
                    val startMatches = first?.let { ClockTime.parse(it.start)?.totalMinutes } == original.startMinutes
                    val endMatches = last?.let { ClockTime.parse(it.end)?.totalMinutes } == original.endMinutes
                    if (!startMatches || !endMatches) {
                        rejected += "${courseName}：源文件的节次与上课/下课时间不一致，请核对节次设置"
                        return null
                    }
                }
                return original
            }
            // A period this semester cannot represent is unusable, but a complete
            // clock may still describe the class exactly; import by clock instead.
            if (!hasClock) return original
        } else if (!hasClock) {
            return original
        }
        // Clock-based imports must use this semester, never the parser's generic guess.
        val start = original.startMinutes
        val end = original.endMinutes
        val first = semester.periods.singleOrNull { ClockTime.parse(it.start)?.totalMinutes == start }
        val last = semester.periods.singleOrNull { ClockTime.parse(it.end)?.totalMinutes == end }
        if (start == null || end == null || start >= end || first == null || last == null) {
            val subject = if (original.explicitPeriod) "节次和上课/下课时间都无法匹配" else "上课/下课时间无法匹配"
            rejected += "${courseName}：${subject}当前学期作息，请核对节次设置"
            return null
        }
        if (original.explicitPeriod) {
            // 源节次被替换时必须说明，避免时间列被错读却悄悄排到别的时段。
            notes += "${courseName}：${periodSpanLabel(original.startPeriod, original.endPeriod)}本学期不存在，" +
                "已按 ${clockLabel(start)}–${clockLabel(end)}（${periodSpanLabel(first.index, last.index)}）导入"
        }
        return original.copy(startPeriod = first.index, endPeriod = last.index)
    }

    /** 时钟字符串加减分钟，给「添加一节」按上一节自动推算时间用。 */
    fun addMinutesToClock(clock: String, minutes: Int): String? {
        val match = Regex("""^(\d{1,2}):(\d{2})$""").find(clock.trim()) ?: return null
        val hour = match.groupValues[1].toIntOrNull() ?: return null
        val minute = match.groupValues[2].toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        val day = 24 * 60
        val total = (((hour * 60 + minute + minutes) % day) + day) % day
        return "%02d:%02d".format(total / 60, total % 60)
    }
    fun toCourses(drafts: List<CourseDraft>, semester: Semester): Pair<List<Course>, List<Pair<String, WeekParity>>> {
        val courses = mutableListOf<Course>()
        val parities = mutableListOf<Pair<String, WeekParity>>()
        validateDrafts(drafts, semester).drafts.forEachIndexed { index, draft ->
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
                className = draft.className.trim(),
            )
        }
        return courses to parities
    }

    private fun parseGrid(rows: List<List<String>>): DraftImport {
        val header = rows.first()
        val dayColumns = header.mapIndexedNotNull { index, title -> weekdayOf(title)?.let { it to index } }
        if (dayColumns.size < 3) return DraftImport(emptyList(), rows.map { it.joinToString(",") })
        val grouped = linkedMapOf<String, CourseDraft>()
        val unparsed = mutableListOf<String>()
        for (row in rows.drop(1)) {
            val label = row.firstOrNull().orEmpty()
            val span = parseClockRange(label)?.takeIf { it.second > it.first }
            val periods = if (span == null && ':' !in label) {
                parsePeriodSpan(label)?.takeIf { it.second >= it.first }
            } else null
            if (span == null && periods == null) {
                if (dayColumns.any { (_, column) -> !row.getOrNull(column).isNullOrBlank() }) {
                    unparsed += row.joinToString(",")
                }
                continue
            }
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
                    startPeriod = periods?.first ?: span?.first?.let { ICSImporter.periodGuess(it) },
                    endPeriod = periods?.second ?: span?.second?.let { ICSImporter.periodGuess((it - 1).coerceAtLeast(0)) },
                    location = location,
                    explicitPeriod = periods != null,
                )
                val existing = grouped[name]
                grouped[name] = if (existing == null) CourseDraft(name, location = location, meetings = listOf(meeting))
                else existing.copy(meetings = existing.meetings + meeting, location = existing.location.ifEmpty { location })
            }
        }
        return DraftImport(grouped.values.toList(), unparsed)
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

    /** A period written in a free-text line: "第3-4节", "3-4节" or "第3节". */
    private fun explicitPeriodIn(text: String): Pair<Int, Int>? {
        Regex("第?\\s*(\\d{1,2})\\s*[-–—~～至]\\s*(\\d{1,2})\\s*节").find(text)?.let { match ->
            val start = match.groupValues[1].toIntOrNull() ?: return null
            val end = match.groupValues[2].toIntOrNull() ?: return null
            return if (start in 1..20 && end in 1..20 && start <= end) start to end else null
        }
        Regex("第\\s*(\\d{1,2})\\s*节").find(text)?.let { match ->
            val only = match.groupValues[1].toIntOrNull() ?: return null
            return if (only in 1..20) only to only else null
        }
        return null
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
