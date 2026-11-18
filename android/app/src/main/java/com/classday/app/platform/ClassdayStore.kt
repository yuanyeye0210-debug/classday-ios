package com.classday.app.platform

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import com.classday.app.core.CivilCalendar
import com.classday.app.core.ScheduleEngine
import com.classday.app.core.StoreDocument
import com.classday.app.core.ProtectedStoreFile
import com.classday.app.core.StoreLoadResult
import java.io.File
import java.time.ZoneId

object ClassdayStore {
    private const val fileName = "classday-store.json"

    fun file(context: Context): File = File(context.filesDir, fileName)

    fun load(context: Context): StoreDocument = loadWithStatus(context).document

    @Synchronized
    fun loadWithStatus(context: Context): StoreLoadResult = ProtectedStoreFile(file(context)).load()

    @Synchronized
    fun save(context: Context, document: StoreDocument) = ProtectedStoreFile(file(context)).save(document)
}

object CalendarSync {
    fun sync(context: Context, document: StoreDocument): String {
        val resolver = context.contentResolver
        val calendarId = ensureCalendar(context) ?: return "没有可用的系统日历，请先允许日历权限"
        val calendar = CivilCalendar(ZoneId.systemDefault())
        val marker = "classday:"
        resolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(CalendarContract.Events._ID, CalendarContract.Events.DESCRIPTION),
            "${CalendarContract.Events.CALENDAR_ID}=?",
            arrayOf(calendarId.toString()),
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(CalendarContract.Events._ID)
            val descCol = cursor.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION)
            while (cursor.moveToNext()) {
                val desc = cursor.getString(descCol).orEmpty()
                if (!desc.startsWith(marker)) continue
                val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, cursor.getLong(idCol))
                resolver.delete(uri, null, null)
            }
        }
        var count = 0
        for (week in 1..document.semester.totalWeeks) {
            val items = ScheduleEngine.occurrences(week, document.courses, document.semester, calendar, document.scheduleContext)
            for (item in items) {
                val values = ContentValues().apply {
                    put(CalendarContract.Events.CALENDAR_ID, calendarId)
                    put(CalendarContract.Events.TITLE, item.name)
                    put(CalendarContract.Events.EVENT_LOCATION, item.location)
                    put(CalendarContract.Events.DESCRIPTION, "$marker${item.courseID} ${item.teacher}")
                    put(CalendarContract.Events.DTSTART, item.startEpochMillis)
                    put(CalendarContract.Events.DTEND, item.endEpochMillis)
                    put(CalendarContract.Events.EVENT_TIMEZONE, ZoneId.systemDefault().id)
                }
                resolver.insert(CalendarContract.Events.CONTENT_URI, values)
                count += 1
            }
        }
        return "已写入系统日历 $count 节。取消或推迟某一周后可以再同步一次。"
    }

    private fun ensureCalendar(context: Context): Long? {
        val resolver = context.contentResolver
        val projection = arrayOf(CalendarContract.Calendars._ID, CalendarContract.Calendars.NAME)
        resolver.query(CalendarContract.Calendars.CONTENT_URI, projection, null, null, null)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
            val nameCol = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.NAME)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameCol) == "课曜") return cursor.getLong(idCol)
            }
            if (cursor.moveToFirst()) return cursor.getLong(idCol)
        }
        val values = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, "课曜")
            put(CalendarContract.Calendars.ACCOUNT_TYPE, "LOCAL")
            put(CalendarContract.Calendars.NAME, "课曜")
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, "课曜")
            put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, "课曜")
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            put(CalendarContract.Calendars.VISIBLE, 1)
        }
        val uri = resolver.insert(CalendarContract.Calendars.CONTENT_URI, values) ?: return null
        return ContentUris.parseId(uri)
    }
}

object Maps {
    private const val prefsName = "classday.map"
    private const val lastChoiceKey = "lastChoice"

    private fun prefs(context: Context) = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    fun lastChoice(context: Context): String? = prefs(context).getString(lastChoiceKey, null)

    fun rememberChoice(context: Context, label: String) {
        prefs(context).edit().putString(lastChoiceKey, label).apply()
    }

    fun resetRememberedChoice(context: Context) {
        prefs(context).edit().remove(lastChoiceKey).apply()
    }

    /** 供「教室位置」页复用的校准弹窗。 */
    fun promptRoomQuery(
        context: Context,
        location: String,
        pin: com.classday.app.core.RoomPin?,
        onBindQuery: (String) -> Unit,
    ) = askForRoomQuery(context, location, pin, onBindQuery)
    /**
     * 打开地图。
     * - 已绑定精确搜索词或坐标时：直接给出「步行路线」等导航选项；
     * - 没绑定时：除了搜索，还提供「校准这间教室的位置」，让用户填一次
     *   能搜准的关键词（例如 "IST Pavilhão de Civil PA1"），保存后长期生效。
     */
    fun open(
        context: Context,
        location: String,
        pin: com.classday.app.core.RoomPin?,
        onBindQuery: ((String) -> Unit)? = null,
        onError: (String) -> Unit,
    ) {
        val name = com.classday.app.core.MapLinks.query(location, pin)
        val lat = pin?.latitude
        val lon = pin?.longitude
        val search = com.classday.app.core.MapLinks.search(name, lat, lon)
        if (search == null) { onError("没有教室名称或有效坐标，请先编辑课程填写地点"); return }
        val choices = mutableListOf<Pair<String, Intent>>()
        fun add(label: String, url: String?, packageName: String? = null) {
            if (url == null) return
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            if (packageName != null) intent.setPackage(packageName)
            if (intent.resolveActivity(context.packageManager) != null) choices += label to intent
        }
        add("系统地图搜索", search)
        add("步行路线（系统地图或网页）", com.classday.app.core.MapLinks.directions(name, lat, lon))
        val route = com.classday.app.core.MapLinks.validCoordinates(lat, lon)
        add(if (route) "高德地图步行路线" else "高德地图搜索", com.classday.app.core.MapLinks.amap(name, lat, lon), "com.autonavi.minimap")
        add(if (route) "百度地图步行路线" else "百度地图搜索", com.classday.app.core.MapLinks.baidu(name, lat, lon), "com.baidu.BaiduMap")
        if (choices.isEmpty()) { onError("没有可用的地图应用，请检查手机的地图应用后再试"); return }
        // 2.10.3：记住上次选择后直接跳，不再每次弹框（可在「教室位置」里清除）。
        val remembered = lastChoice(context)
        if (remembered != null) {
            choices.firstOrNull { it.first == remembered }?.let { (_, intent) ->
                if (intent.data?.scheme != "classday") {
                    try { context.startActivity(intent); return } catch (_: Exception) { /* 回落到选择框 */ }
                }
            }
        }
        val precise = com.classday.app.core.MapLinks.hasPreciseQuery(location, pin)
        if (onBindQuery != null && !precise) {
            choices += (if (location.isBlank()) "🏫 填写教室关键词，让搜索更准" else "🏫 校准「$location」的位置") to
                Intent(Intent.ACTION_VIEW, Uri.parse("classday://bind-room"))
        }
        android.app.AlertDialog.Builder(context).setTitle("选择地图 · 请核对目的地")
            .setItems(choices.map { it.first }.toTypedArray()) { _, which ->
                val chosen = choices[which]
                if (chosen.second.data?.scheme == "classday" && onBindQuery != null) {
                    askForRoomQuery(context, location, pin, onBindQuery)
                    return@setItems
                }
                try {
                    rememberChoice(context, chosen.first)
                    context.startActivity(chosen.second)
                } catch (_: Exception) { onError("未能打开所选地图，请重新选择可用地图") }
            }.setNegativeButton("取消", null).show()
    }

    /** 让用户填一次能搜准的教室关键词，存进文档的 rooms（RoomPin.query）。 */
    private fun askForRoomQuery(
        context: Context,
        location: String,
        pin: com.classday.app.core.RoomPin?,
        onBindQuery: (String) -> Unit,
    ) {
        val input = android.widget.EditText(context).apply {
            setText(pin?.query?.takeIf { it.isNotBlank() } ?: location)
            setHint("例如：IST Pavilhão de Civil PA1")
            setSingleLine(true)
        }
        android.app.AlertDialog.Builder(context)
            .setTitle("教室关键词")
            .setMessage("填一个在地图上能直接搜到这间教室的词（楼名 + 房间号最好），以后导航就不用每次找。")
            .setView(input)
            .setPositiveButton("保存") { _, _ ->
                val value = input.text?.toString()?.trim().orEmpty()
                if (value.isNotEmpty()) onBindQuery(value)
            }
            .setNegativeButton("取消", null)
            .show()
    }
}
