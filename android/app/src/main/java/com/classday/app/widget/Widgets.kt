package com.classday.app.widget

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.classday.app.MainActivity
import com.classday.app.R
import com.classday.app.core.CivilCalendar
import com.classday.app.core.CountdownCopy
import com.classday.app.core.Occurrence
import com.classday.app.core.OverrideKind
import com.classday.app.core.ScheduleCopy
import com.classday.app.core.ScheduleEngine
import com.classday.app.core.StoreDocument
import com.classday.app.core.TimetableLibrary
import com.classday.app.platform.ClassdayStore
import java.time.Instant
import java.time.ZoneId

private data class WidgetSnapshot(val document: StoreDocument, val current: Occurrence?, val next: Occurrence?, val week: Int, val loadFailed: Boolean = false)

@Composable
private fun StoreFailureContent(context: Context) {
    Column(modifier = GlanceModifier.fillMaxWidth().padding(12.dp)
        .background(ColorProvider(Color.White)).cornerRadius(18.dp)
        .clickable(actionStartActivity(Intent(context, MainActivity::class.java)))) {
        Text("课表读取失败", style = TextStyle(color = ColorProvider(Color.Black), fontSize = 16.sp, fontWeight = FontWeight.Bold))
        Text("打开课曜查看详情，原文件已保留", style = TextStyle(color = ColorProvider(Color.DarkGray), fontSize = 12.sp))
    }
}

private fun snapshot(context: Context): WidgetSnapshot {
    val loaded = ClassdayStore.loadWithStatus(context)
    val document = loaded.document
    if (loaded.error != null) return WidgetSnapshot(document, null, null, 1, loadFailed = true)
    val calendar = CivilCalendar(ZoneId.systemDefault())
    val now = Instant.now()
    val week = calendar.weekIndex(now, document.semester) ?: 1
    return WidgetSnapshot(
        document,
        ScheduleEngine.current(now, document.courses, document.semester, calendar, document.scheduleContext),
        ScheduleEngine.next(now, document.courses, document.semester, calendar, document.scheduleContext),
        week,
    )
}

class NextClassWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snap = snapshot(context)
        provideContent { NextClassContent(context, snap) }
    }
}

class TodayWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snap = snapshot(context)
        provideContent { TodayContent(context, snap) }
    }
}

class WeekBoardWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snap = snapshot(context)
        provideContent { WeekContent(context, snap) }
    }
}

class NextClassReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NextClassWidget()
}

class TodayReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayWidget()
}

class WeekBoardReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = WeekBoardWidget()
}

class MarkArrivedCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: androidx.glance.action.ActionParameters) {
        context.getSharedPreferences("classday", Context.MODE_PRIVATE)
            .edit().putLong("arrived", System.currentTimeMillis()).apply()
        WeekBoardWidget().updateAll(context)
    }
}

class DelayClassCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: androidx.glance.action.ActionParameters) {
        val loaded = ClassdayStore.loadWithStatus(context)
        if (loaded.error != null) return
        val document = loaded.document
        val calendar = CivilCalendar(ZoneId.systemDefault())
        val now = Instant.now()
        val target = ScheduleEngine.next(now, document.courses, document.semester, calendar, document.scheduleContext)
            ?: ScheduleEngine.current(now, document.courses, document.semester, calendar, document.scheduleContext)
            ?: return
        val updated = TimetableLibrary.overriding(
            document,
            com.classday.app.core.OccurrenceOverride(
                courseID = target.courseID,
                meetingID = target.meetingID,
                week = target.weekIndex,
                kind = OverrideKind.delayed,
                delayMinutes = 10,
            ),
        )
        try {
            ClassdayStore.save(context, updated)
        } catch (_: Exception) {
            return
        }
        com.classday.app.ClassAlerts.refresh(context, updated)
    }
}

@Composable
private fun NextClassContent(context: Context, snap: WidgetSnapshot) {
    if (snap.loadFailed) { StoreFailureContent(context); return }
    val theme = snap.document.appearance.theme
    val item = snap.current ?: snap.next
    val now = System.currentTimeMillis()
    Column(
        modifier = GlanceModifier.fillMaxWidth().padding(12.dp).background(ColorProvider(Color(theme.background.r, theme.background.g, theme.background.b))).cornerRadius(20.dp).clickable(actionStartActivity(openIntent(item))),
    ) {
        Text("课曜", style = TextStyle(color = ColorProvider(Color(theme.secondary.r, theme.secondary.g, theme.secondary.b)), fontSize = 11.sp))
        Spacer(GlanceModifier.height(4.dp))
        if (item == null) {
            Text("今天没有课", style = TextStyle(color = ColorProvider(Color(theme.ink.r, theme.ink.g, theme.ink.b)), fontSize = 16.sp, fontWeight = FontWeight.Bold))
        } else {
            val phase = if (snap.current != null) "上课中" else "待上课"
            val until = if (snap.current != null) item.endEpochMillis else item.startEpochMillis
            Text(item.name, style = TextStyle(color = ColorProvider(Color(theme.ink.r, theme.ink.g, theme.ink.b)), fontSize = 16.sp, fontWeight = FontWeight.Bold), maxLines = 2)
            Text("${item.locationShort.ifEmpty { item.location }} · $phase", style = TextStyle(color = ColorProvider(Color(theme.accent.r, theme.accent.g, theme.accent.b)), fontSize = 12.sp), maxLines = 1)
            if (until > now) {
                val remote = RemoteViews(context.packageName, R.layout.widget_chrono).apply {
                    setChronometer(R.id.chrono, SystemClockElapsed(until), null, true)
                    setChronometerCountDown(R.id.chrono, true)
                    setTextColor(R.id.chrono, android.graphics.Color.rgb(theme.ink.r, theme.ink.g, theme.ink.b))
                }
                AndroidRemoteViews(remote)
            } else {
                Text("已结束，打开课曜查看下一节", style = TextStyle(color = ColorProvider(Color(theme.ink.r, theme.ink.g, theme.ink.b)), fontSize = 12.sp), maxLines = 2)
            }
        }
    }
}

@Composable
private fun TodayContent(context: Context, snap: WidgetSnapshot) {
    if (snap.loadFailed) { StoreFailureContent(context); return }
    val theme = snap.document.appearance.theme
    val calendar = CivilCalendar(ZoneId.systemDefault())
    val today = ScheduleEngine.occurrencesOn(Instant.now(), snap.document.courses, snap.document.semester, calendar, snap.document.scheduleContext)
    Column(
        modifier = GlanceModifier.fillMaxWidth().padding(12.dp).background(ColorProvider(Color(theme.card.r, theme.card.g, theme.card.b))).cornerRadius(18.dp).clickable(actionStartActivity(Intent(context, MainActivity::class.java))),
    ) {
        Text("今日 ${today.size} 节", style = TextStyle(color = ColorProvider(Color(theme.ink.r, theme.ink.g, theme.ink.b)), fontSize = 14.sp, fontWeight = FontWeight.Bold))
        if (today.isEmpty()) {
            Text("今天没有课", style = TextStyle(color = ColorProvider(Color(theme.secondary.r, theme.secondary.g, theme.secondary.b)), fontSize = 12.sp))
        }
        today.take(3).forEach { item ->
            Text("${item.timeText}  ${item.name}", style = TextStyle(color = ColorProvider(Color(theme.ink.r, theme.ink.g, theme.ink.b)), fontSize = 12.sp), maxLines = 1)
        }
    }
}

@Composable
private fun WeekContent(context: Context, snap: WidgetSnapshot) {
    if (snap.loadFailed) { StoreFailureContent(context); return }
    val theme = snap.document.appearance.theme
    val calendar = CivilCalendar(ZoneId.systemDefault())
    val items = ScheduleEngine.occurrences(snap.week, snap.document.courses, snap.document.semester, calendar, snap.document.scheduleContext)
    val arrived = context.getSharedPreferences("classday", Context.MODE_PRIVATE).getLong("arrived", 0L)
    val arrivedLabel = if (System.currentTimeMillis() - arrived < 3 * 60 * 60 * 1000 && arrived > 0) "已记录到教室" else ""
    Column(
        modifier = GlanceModifier.fillMaxWidth().padding(12.dp).background(ColorProvider(Color(theme.background.r, theme.background.g, theme.background.b))).cornerRadius(18.dp),
    ) {
        Text("第 ${snap.week} 周  ${theme.name}", style = TextStyle(color = ColorProvider(Color(theme.ink.r, theme.ink.g, theme.ink.b)), fontSize = 14.sp, fontWeight = FontWeight.Bold))
        if (arrivedLabel.isNotEmpty()) {
            Text(arrivedLabel, style = TextStyle(color = ColorProvider(Color(theme.accent.r, theme.accent.g, theme.accent.b)), fontSize = 11.sp))
        }
        for (weekday in 1..7) {
            val names = items.filter { it.weekday == weekday }.joinToString(" · ") { it.name }
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(ScheduleCopy.weekdayName(weekday), style = TextStyle(color = ColorProvider(Color(theme.secondary.r, theme.secondary.g, theme.secondary.b)), fontSize = 11.sp))
                Text("  ${names.ifEmpty { "—" }}", style = TextStyle(color = ColorProvider(Color(theme.ink.r, theme.ink.g, theme.ink.b)), fontSize = 11.sp), maxLines = 1)
            }
        }
        Spacer(GlanceModifier.height(6.dp))
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            androidx.glance.Button(text = "已到教室", onClick = actionRunCallback<MarkArrivedCallback>())
            androidx.glance.Button(text = "推迟 10 分钟", onClick = actionRunCallback<DelayClassCallback>())
        }
    }
}

private fun openIntent(item: Occurrence?): Intent {
    val intent = Intent(Intent.ACTION_VIEW)
    if (item != null) intent.data = android.net.Uri.parse("classday://course/${item.courseID}?meeting=${item.meetingID}")
    intent.setClassName("com.classday.app", "com.classday.app.MainActivity")
    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    return intent
}

private fun SystemClockElapsed(targetWall: Long): Long {
    val delta = targetWall - System.currentTimeMillis()
    return android.os.SystemClock.elapsedRealtime() + delta
}
