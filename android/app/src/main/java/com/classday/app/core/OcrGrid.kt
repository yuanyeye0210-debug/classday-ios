package com.classday.app.core

/** OCR 识别出的一行文字及其中心点，用于按几何位置重建表格。 */
data class OcrLine(val text: String, val cx: Float, val cy: Float)

/**
 * 把「教务系统导出的网格课表 PDF」经 OCR 得到的带坐标文本还原成课程草稿。
 *
 * 思路：先用表头「星期一…星期日」的 x 中心定出列，再用同一列里按 y 聚类的行
 * 把文字归到「第几节 × 星期几」的格子里，最后逐格解析
 * `课程名(课程号) / (1-2节)1-8周 / 校区:xx / 地点:C120 / 教师:张三 / 学分:3.0`。
 *
 * 表头找不到时返回 null，调用方回落到原有的纯文本解析。
 */
object OcrGridParser {
    private val weekdayNames = mapOf(
        "星期一" to 1, "周一" to 1, "礼拜一" to 1,
        "星期二" to 2, "周二" to 2, "礼拜二" to 2,
        "星期三" to 3, "周三" to 3, "礼拜三" to 3,
        "星期四" to 4, "周四" to 4, "礼拜四" to 4,
        "星期五" to 5, "周五" to 5, "礼拜五" to 5,
        "星期六" to 6, "周六" to 6, "礼拜六" to 6,
        "星期日" to 7, "星期天" to 7, "周日" to 7, "周天" to 7, "礼拜日" to 7, "礼拜天" to 7,
    )
    private val timeHeaderWords = setOf("时间", "节次", "时段", "时间/节次")

    private val periodRange = Regex("""[（(]\s*(\d{1,2})\s*[-~—–至]\s*(\d{1,2})\s*节?\s*[)）]""")
    private val weeksRange = Regex("""(\d{1,2})\s*[-~—–至]\s*(\d{1,2})\s*周""")
    private val weeksList = Regex("""((?:\d{1,2}\s*[,，、]\s*)+\d{1,2})\s*周""")
    private val locationField = Regex("""(?:地点|教室|上课地点)\s*[:：]\s*([^/／\n]+)""")
    private val teacherField = Regex("""(?:教师|老师|任课教师)\s*[:：]\s*([^/／\n选课学分备注周次]+)""")
    private val classField = Regex("""(?:班级|教学班|行政班|上课班级)\s*[:：]\s*([^/／\n]+)""")
    private val courseCode = Regex("""[（(]\s*[A-Za-z0-9]{5,16}\s*[)）]""")

    fun parse(lines: List<OcrLine>): DraftImport? {
        val usable = lines.mapNotNull { line ->
            val text = line.text.trim()
            if (text.isEmpty()) null else OcrLine(text, line.cx, line.cy)
        }
        if (usable.size < 8) return null

        // 1) 表头：星期几 → 列
        val headerLines = usable.filter { weekdayNames.containsKey(it.text.replace(" ", "")) }
        val columns = headerLines
            .mapNotNull { line -> weekdayNames[line.text.replace(" ", "")]?.let { day -> day to line.cx } }
            .distinctBy { it.second }
            .sortedBy { it.second }
        if (columns.size < 3) return null

        // 列边界：相邻列中心的中点；第一个列边界左侧是节次标签列
        val firstColumnLeft = columns.first().second
        val previousGap = if (columns.size >= 2) columns[1].second - columns[0].second else 200f
        val labelLimit = firstColumnLeft - previousGap / 2f
        val bounds = columns.zipWithNext { a, b -> (a.second + b.second) / 2f }
        val headerY = headerLines.minOf { it.cy }

        fun columnOf(cx: Float): Int? {
            if (cx < labelLimit) return null
            var index = 0
            while (index < bounds.size && cx > bounds[index]) index++
            return columns.getOrNull(index)?.first
        }

        // 2) 行：按 y 聚类成行带
        val body = usable.filter { it.cy > headerY + 1f }
        if (body.isEmpty()) return null
        val sortedY = body.map { it.cy }.sorted()
        val tolerance = ((sortedY.last() - sortedY.first()) / maxOf(8, body.size / 4).toFloat()).coerceIn(8f, 48f)
        val rowCenters = mutableListOf<Float>()
        for (y in sortedY) {
            if (rowCenters.isEmpty() || y - rowCenters.last() > tolerance) rowCenters += y
        }
        fun rowOf(cy: Float): Int {
            var best = 0
            var bestDistance = Float.MAX_VALUE
            rowCenters.forEachIndexed { index, center ->
                val distance = kotlin.math.abs(center - cy)
                if (distance < bestDistance) { bestDistance = distance; best = index }
            }
            return best
        }

        // 3) 归格：先按「列 + 行」收集，再按列顺序累积合并。
        // 同一格里的课程名与「(1-2节)…」常常被识别成两行，行的 y 聚类不一定把它们并在一起，
        // 所以按列从上到下累积，遇到含节次的行才收口成一个格子。
        val byColumn = linkedMapOf<Int, MutableList<Pair<Float, List<String>>>>()
        for (line in body) {
            val day = columnOf(line.cx) ?: continue
            val rowIndex = rowOf(line.cy)
            val rowY = rowCenters.getOrElse(rowIndex) { line.cy }
            byColumn.getOrPut(day) { mutableListOf() }.add(rowY to listOf(line.text))
        }
        val cells = linkedMapOf<Pair<Int, Int>, MutableList<String>>()
        var cellOrdinal = 0
        for ((day, entries) in byColumn) {
            val sorted = entries.sortedBy { it.first }
            var buffer = mutableListOf<String>()
            for ((_, texts) in sorted) {
                buffer += texts
                if (periodRange.containsMatchIn(buffer.joinToString(" "))) {
                    cells[day to cellOrdinal++] = buffer
                    buffer = mutableListOf()
                }
            }
            if (buffer.isNotEmpty()) cells[day to cellOrdinal++] = buffer
        }
        if (cells.isEmpty()) return null

        // 4) 逐格解析
        val grouped = linkedMapOf<String, CourseDraft>()
        for ((key, texts) in cells) {
            val day = key.first
            val joined = texts.joinToString(" ")
            if (timeHeaderWords.any { joined.trim() == it }) continue
            val name = courseName(texts) ?: continue
            val periods = periodRange.find(joined)
            val start = periods?.groupValues?.getOrNull(1)?.toIntOrNull()
            val end = periods?.groupValues?.getOrNull(2)?.toIntOrNull() ?: start
            if (start == null || end == null) continue
            val weeks = parseWeeks(joined)
            val location = locationField.find(joined)?.groupValues?.getOrNull(1)?.trim().orEmpty()
            val teacher = teacherField.find(joined)?.groupValues?.getOrNull(1)?.trim().orEmpty()
            val className = classField.find(joined)?.groupValues?.getOrNull(1)?.trim().orEmpty()
            val meeting = MeetingDraft(
                weekday = day,
                startPeriod = start,
                endPeriod = end,
                location = location,
                explicitPeriod = true,
            )
            val existing = grouped[name]
            grouped[name] = if (existing == null) {
                CourseDraft(name = name, teacher = teacher, location = location, weeks = weeks, meetings = listOf(meeting), className = className)
            } else {
                existing.copy(
                    location = listOf(existing.location, location).filter { it.isNotBlank() }.distinct().joinToString(" / "),
                    weeks = (existing.weeks + weeks).distinct().sorted(),
                    // 同课同一天同一节重复出现（OCR 把一格拆成两块）时只保留一条。
                    meetings = (existing.meetings + meeting).distinctBy {
                        listOf(it.weekday, it.startPeriod, it.endPeriod, it.location).joinToString("|")
                    },
                )
            }
        }
        if (grouped.isEmpty()) return null
        return DraftImport(grouped.values.toList(), emptyList())
    }

    /**
     * 课程名：取格子里最像「课程名」的一行。
     * 教务系统的格子常被 OCR 拆成「课程名(课程号)」「(1-2节)9-16周/校区:…/地点:…/教师:…」，
     * 有时字段行还会单独成行，所以字段行、星期行、节次行、纯人名行都要排除。
     */
    private fun courseName(texts: List<String>): String? {
        val fieldMarkers = listOf("校区", "场地", "地点", "教室", "教师", "老师", "学分", "周次", "备注", "选课", "考核")
        val candidates = mutableListOf<String>()
        for (raw in texts) {
            val text = raw.trim()
            if (text.isEmpty()) continue
            if (weekdayNames.containsKey(text.replace(" ", ""))) continue
            if (timeHeaderWords.contains(text)) continue
            if (text.startsWith("(") || text.startsWith("（")) continue
            if (fieldMarkers.any { text.startsWith(it) || text.startsWith("区/$it") }) continue
            if (fieldMarkers.count { it in text } >= 2) continue          // 满行都是字段
            val cleaned = text.replace(courseCode, " ")
                .replace(Regex("""^[区校]?/?\s*(场地|地点|教室)\s*[:：]"""), " ")
                .replace(Regex("""/教师\s*[:：].*$"""), " ")
                .replace(Regex("""/学分\s*[:：].*$"""), " ")
                .replace(Regex("""(选课备注|选課各注|学分).*$"""), " ")
                .replace(Regex("""\s+"""), " ").trim()
            if (cleaned.length < 2 || cleaned.none { it.isLetter() || it.isDigit() }) continue
            candidates += cleaned
        }
        if (candidates.isEmpty()) return null
        // 优先取「不被字段污染、且看起来像课名（含中文或英文单词）」的第一条
        return candidates.firstOrNull { c -> c.length >= 2 && Regex("""[\u4e00-\u9fa5A-Za-z]{2}""").containsMatchIn(c) }
    }

    private fun parseWeeks(text: String): List<Int> {
        weeksRange.find(text)?.let { match ->
            val from = match.groupValues[1].toIntOrNull() ?: return@let
            val to = match.groupValues[2].toIntOrNull() ?: return@let
            if (from in 1..30 && to in from..30) return (from..to).toList()
        }
        // 真实教务系统会把周次写成「3周,7周,11周,15周」，每个数字后面都带「周」。
        val repeated = Regex("""(\d{1,2})\s*周""").findAll(text)
            .mapNotNull { it.groupValues[1].toIntOrNull() }
            .filter { it in 1..30 }
            .toList()
        if (repeated.size >= 2) return repeated.distinct().sorted()
        weeksList.find(text)?.let { match ->
            val weeks = match.groupValues[1].split(',', '，', '、')
                .mapNotNull { it.trim().toIntOrNull() }
                .filter { it in 1..30 }
            if (weeks.isNotEmpty()) return weeks.distinct().sorted()
        }
        return (1..16).toList()
    }
}