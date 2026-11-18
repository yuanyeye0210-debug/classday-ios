package com.classday.app.core

import kotlinx.serialization.SerializationException

data class StoreValidation(val errors: List<String>, val warnings: List<String>) {
    val isAcceptable: Boolean get() = errors.isEmpty()
}

data class ImportOutcome(val document: StoreDocument?, val errors: List<String>, val warnings: List<String>)

object StoreCodec {
    fun exporting(document: StoreDocument): String = StoreJson.encodeToString(StoreDocument.serializer(), document)

    fun importing(raw: String, calendar: CivilCalendar = CivilCalendar(java.time.ZoneOffset.UTC)): ImportOutcome {
        val document = try {
            StoreJson.decodeFromString(StoreDocument.serializer(), raw)
        } catch (_: SerializationException) {
            return ImportOutcome(null, listOf("无法解析 JSON"), emptyList())
        } catch (_: RuntimeException) {
            return ImportOutcome(null, listOf("无法解析 JSON"), emptyList())
        }
        val report = validate(document, calendar)
        if (!report.isAcceptable) return ImportOutcome(null, report.errors, report.warnings)
        val migrated = normalize(document).copy(schemaVersion = StoreDocument.currentSchema)
        val warnings = if (document.schemaVersion < StoreDocument.currentSchema) {
            report.warnings + listOf("课表已从 schemaVersion ${document.schemaVersion} 升级到 ${StoreDocument.currentSchema}")
        } else {
            report.warnings
        }
        return ImportOutcome(migrated, emptyList(), warnings)
    }

    fun validate(document: StoreDocument, calendar: CivilCalendar): StoreValidation {
        val errors = mutableListOf<String>()
        val warnings = mutableListOf<String>()
        // 2.10：接受旧版本文档（v1 没有 Meeting.location），验证后统一升级到 currentSchema。
        when {
            document.schemaVersion > StoreDocument.currentSchema ->
                errors += "schemaVersion ${document.schemaVersion} 高于本版本支持的 ${StoreDocument.currentSchema}"
            document.schemaVersion < 1 -> errors += "schemaVersion 无效"
        }
        val semester = document.semester
        if (semester.name.isEmpty()) errors += "学期名称不能为空"
        if (semester.shortName.isEmpty()) errors += "学期简称不能为空"
        if (calendar.parseCivil(semester.startDate) == null) errors += "学期开始日期无效"
        if (semester.totalWeeks !in 1..30) errors += "学期周数必须在 1 到 30 之间"
        semester.holidays.forEach { holiday ->
            val start = calendar.parseCivil(holiday.startDate)
            val end = calendar.parseCivil(holiday.endDate)
            if (start == null || end == null || end.isBefore(start)) errors += "假期日期不正确"
        }
        semester.cancellations.forEach { entry ->
            if (calendar.parseCivil(entry.date) == null) errors += "停课日期不正确"
        }
        if (semester.defaultReminderMinutes !in 0..180) errors += "默认提醒分钟数必须在 0 到 180 之间"
        if (semester.periods.isEmpty()) errors += "至少需要 1 个节次"
        val indexes = semester.periods.map { it.index }
        if (indexes != (1..indexes.size).toList()) errors += "节次序号必须从 1 连续编号"
        semester.periods.forEach { period ->
            val start = ClockTime.parse(period.start)
            val end = ClockTime.parse(period.end)
            if (start == null || end == null) errors += "节次 ${period.index} 的时间无效"
            else if (end <= start) errors += "第 ${period.index} 节结束时间必须晚于开始时间"
        }
        val seenCourses = mutableSetOf<String>()
        val seenMeetings = mutableSetOf<String>()
        val maxPeriod = semester.periods.maxOfOrNull { it.index } ?: 0
        document.courses.forEachIndexed { offset, course ->
            val display = course.name.ifBlank { "第 ${offset + 1} 门课程" }
            if (course.name.isBlank()) errors += "第 ${offset + 1} 门课程的名称不能为空"
            if (!seenCourses.add(course.id.uppercase())) errors += "课程 ID 重复"
            if (course.meetings.isEmpty()) errors += "课程「$display」至少要有一个上课时间"
            if (course.weeks.isEmpty()) errors += "课程「$display」至少要有一周"
            if (course.weeks.any { it !in 1..semester.totalWeeks }) errors += "课程「$display」的周次超出学期范围"
            val reminder = course.reminderLeadMinutes
            if (reminder != null && reminder !in 0..180) errors += "课程「$display」的提醒分钟数无效"
            course.meetings.forEach { meeting ->
                if (!seenMeetings.add(meeting.id.uppercase())) errors += "上课时间 ID 重复"
                if (meeting.weekday !in 1..7) errors += "课程「$display」的星期无效"
                if (meeting.startPeriod > meeting.endPeriod) errors += "课程「$display」的开始节次不能晚于结束节次"
                if (meeting.startPeriod !in 1..maxPeriod || meeting.endPeriod !in 1..maxPeriod) {
                    errors += "课程「$display」的节次超出范围"
                }
            }
        }
        if (ScheduleEngine.conflicts(document.courses, document.scheduleContext).isNotEmpty()) {
            warnings += "有课程时间重叠"
        }
        return StoreValidation(errors, warnings)
    }

    private fun normalize(document: StoreDocument): StoreDocument = document.copy(
        courses = document.courses.map { it.normalized() },
        activeTimetableID = document.activeTimetableID.uppercase(),
        weekRules = document.weekRules.map { it.copy(meetingID = it.meetingID.uppercase()) },
        overrides = document.overrides.map { it.copy(courseID = it.courseID.uppercase(), meetingID = it.meetingID.uppercase(), id = it.id.uppercase()) },
        appearance = document.appearance.copy(themeID = ClassdayThemes.theme(document.appearance.themeID).id),
    )
}

object Versions {
    fun compare(a: String, b: String): Int {
        val pa = a.split('.').map { it.toIntOrNull() ?: 0 }
        val pb = b.split('.').map { it.toIntOrNull() ?: 0 }
        val count = maxOf(pa.size, pb.size)
        for (index in 0 until count) {
            val x = pa.getOrElse(index) { 0 }
            val y = pb.getOrElse(index) { 0 }
            if (x != y) return x.compareTo(y)
        }
        return 0
    }
}

data class ReleaseEntry(
    val version: String,
    val file: String,
    val size: Long,
    val sha256: String,
    val downloadUrl: String,
    val publishedAt: String,
    val mirrors: List<String> = emptyList(),
)

data class UpdateChannel(
    val latest: String,
    val previous: String?,
    val mandatory: Boolean,
    val minSupportedVersion: String,
    val releases: List<ReleaseEntry>,
) {
    val latestRelease: ReleaseEntry? get() = releases.firstOrNull { it.version == latest }
}

sealed class UpdateDecision {
    data object UpToDate : UpdateDecision()
    data class UpdateAvailable(val release: ReleaseEntry, val mandatory: Boolean) : UpdateDecision()
    data class BelowMinimum(val release: ReleaseEntry) : UpdateDecision()
    data object MissingChannel : UpdateDecision()
}

object UpdateManifest {
    const val supportedSchema = 1
    const val manifestUrl = "https://gitlab.com/yuanyeye0210/classday-releases/-/raw/main/latest.json"

    fun parseAndroid(json: String): UpdateChannel? {
        val root = org.json.JSONObject(json)
        val schema = root.optInt("schema_version", -1)
        if (schema != supportedSchema) return null
        val channels = root.optJSONObject("channels") ?: return null
        if (channels.isNull("android")) return null
        val android = channels.optJSONObject("android") ?: return null
        return parseChannel(android)
    }

    fun decision(channel: UpdateChannel?, current: String): UpdateDecision {
        val release = channel?.latestRelease ?: return UpdateDecision.MissingChannel
        if (Versions.compare(current, channel.minSupportedVersion) < 0) return UpdateDecision.BelowMinimum(release)
        if (Versions.compare(current, channel.latest) < 0) return UpdateDecision.UpdateAvailable(release, channel.mandatory)
        return UpdateDecision.UpToDate
    }

    private fun parseChannel(obj: org.json.JSONObject): UpdateChannel? {
        val latest = obj.optString("latest")
        if (latest.isBlank()) return null
        val releasesJson = obj.optJSONArray("releases") ?: return null
        val releases = mutableListOf<ReleaseEntry>()
        for (index in 0 until releasesJson.length()) {
            val row = releasesJson.optJSONObject(index) ?: return null
            val version = row.optString("version")
            val file = row.optString("file")
            val size = row.optLong("size", -1)
            val sha = row.optString("sha256")
            val url = row.optString("download_url")
            val published = row.optString("published_at")
            if (size <= 0) return null
            if (sha.length != 64 || sha.any { it !in '0'..'9' && it !in 'a'..'f' && it !in 'A'..'F' }) return null
            val mirrors = mutableListOf<String>()
            val mirrorArray = row.optJSONArray("mirrors")
            if (mirrorArray != null) {
                for (mirror in 0 until mirrorArray.length()) mirrors += mirrorArray.optString(mirror)
            }
            releases += ReleaseEntry(version, file, size, sha, url, published, mirrors)
        }
        val previous = if (obj.isNull("previous")) null else obj.optString("previous").ifBlank { null }
        return UpdateChannel(
            latest = latest,
            previous = previous,
            mandatory = obj.optBoolean("mandatory", false),
            minSupportedVersion = obj.optString("min_supported_version", "0"),
            releases = releases,
        ).takeIf { it.latestRelease != null }
    }
}
