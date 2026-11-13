package com.classday.app.platform

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import com.classday.app.core.CivilCalendar
import com.classday.app.core.ScheduleEngine
import com.classday.app.core.StoreCodec
import com.classday.app.core.StoreDocument
import com.classday.app.core.DemoData
import java.io.File
import java.time.ZoneId

object ClassdayStore {
    private const val fileName = "classday-store.json"

    fun file(context: Context): File = File(context.filesDir, fileName)

    fun load(context: Context): StoreDocument {
        val file = file(context)
        if (!file.exists()) {
            val demo = DemoData.makeDocument()
            file.writeText(StoreCodec.exporting(demo))
            return demo
        }
        val outcome = StoreCodec.importing(file.readText())
        return outcome.document ?: DemoData.makeDocument()
    }

    fun save(context: Context, document: StoreDocument) {
        val file = file(context)
        file.parentFile?.mkdirs()
        val backupDir = File(context.filesDir, "backups")
        backupDir.mkdirs()
        if (file.exists()) {
            val stamp = System.currentTimeMillis()
            file.copyTo(File(backupDir, "classday-$stamp.json"), overwrite = true)
            backupDir.listFiles()?.sortedByDescending { it.lastModified() }?.drop(3)?.forEach { it.delete() }
        }
        file.writeText(StoreCodec.exporting(document))
    }
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
    fun intent(location: String, latitude: Double? = null, longitude: Double? = null): Intent {
        val uri = if (latitude != null && longitude != null) {
            Uri.parse("geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encode(location)})")
        } else {
            Uri.parse("geo:0,0?q=${Uri.encode(location)}")
        }
        return Intent(Intent.ACTION_VIEW, uri)
    }
}
