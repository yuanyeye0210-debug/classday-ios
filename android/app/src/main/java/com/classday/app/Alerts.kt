package com.classday.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import com.classday.app.core.CivilCalendar
import com.classday.app.core.CountdownCopy
import com.classday.app.core.Occurrence
import com.classday.app.core.ScheduleEngine
import com.classday.app.core.StoreDocument
import com.classday.app.core.applyStoredAlarmResult
import com.classday.app.widget.NextClassWidget
import com.classday.app.widget.TodayWidget
import com.classday.app.widget.WeekBoardWidget
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

object ClassAlerts {
    const val channelId = "classday.live"
    private const val notificationId = 2902
    private const val requestCode = 2902
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun refreshStoredAsync(context: Context, done: (() -> Unit)? = null) {
        val app = context.applicationContext
        scope.launch {
            try {
                val loaded = com.classday.app.platform.ClassdayStore.loadWithStatus(app)
                applyStoredAlarmResult(
                    loaded = loaded,
                    refresh = { refresh(app, it) },
                    cancelNotification = {
                        // An unreadable personal timetable must never schedule demo classes.
                        app.getSystemService(NotificationManager::class.java).cancel(notificationId)
                    },
                    cancelAlarm = {
                        val pending = PendingIntent.getBroadcast(
                            app, requestCode, Intent(app, ClassAlarmReceiver::class.java),
                            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
                        )
                        if (pending != null) app.getSystemService(AlarmManager::class.java).cancel(pending)
                    },
                )
            } finally {
                done?.invoke()
            }
        }
    }

    fun refreshAsync(context: Context, document: StoreDocument, done: (() -> Unit)? = null) {
        val app = context.applicationContext
        scope.launch {
            try {
                refresh(app, document)
            } finally {
                done?.invoke()
            }
        }
    }

    suspend fun refresh(context: Context, document: StoreDocument) {
        val calendar = CivilCalendar(ZoneId.systemDefault())
        val now = Instant.now()
        val current = ScheduleEngine.current(now, document.courses, document.semester, calendar, document.scheduleContext)
        val next = ScheduleEngine.next(now, document.courses, document.semester, calendar, document.scheduleContext)
        post(context, current, next, now.toEpochMilli())
        schedule(context, current, next, now.toEpochMilli(), calendar)
        WeekBoardWidget().updateAll(context)
        TodayWidget().updateAll(context)
        com.classday.app.widget.NextClassWidget().updateAll(context)
    }

    private fun post(context: Context, current: Occurrence?, next: Occurrence?, now: Long) {
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(manager)
        val target = current ?: next
        val open = PendingIntent.getActivity(
            context,
            1,
            Intent(context, MainActivity::class.java).apply {
                action = MainActivity.ACTION_OPEN_NEXT
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_class)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setOnlyAlertOnce(true)
            .setOngoing(target != null)
            .setContentIntent(open)
        if (target == null) {
            builder.setContentTitle("课曜")
                .setContentText("已结束，打开课曜查看下一节")
                .setUsesChronometer(false)
                .setOngoing(false)
        } else {
            val countingTo = if (current != null) current.endEpochMillis else target.startEpochMillis
            val phase = if (current != null) "上课中" else "待上课"
            val remain = CountdownCopy.remaining(countingTo, now)
            builder.setContentTitle(target.name)
                .setContentText("$phase · ${target.locationShort.ifEmpty { target.location }} · $remain")
                .setWhen(countingTo)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
            if (countingTo <= now) {
                builder.setContentText("已结束，打开课曜查看下一节")
                    .setUsesChronometer(false)
                    .setOngoing(false)
            }
        }
        manager.notify(notificationId, builder.build())
    }

    private fun schedule(context: Context, current: Occurrence?, next: Occurrence?, now: Long, calendar: CivilCalendar) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val intent = Intent(context, ClassAlarmReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val horizon = now + 7L * 24 * 60 * 60 * 1000
        val candidates = mutableListOf<Long>()
        current?.let { candidates += it.endEpochMillis }
        next?.let {
            candidates += it.startEpochMillis
            candidates += it.endEpochMillis
            if (it.startEpochMillis - now >= 8 * 60 * 60 * 1000) candidates += it.startEpochMillis - 60 * 60 * 1000
        }
        val zone = calendar.zone
        var midnight = LocalDate.now(zone).plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        repeat(7) {
            candidates += midnight
            midnight += 24 * 60 * 60 * 1000
        }
        val trigger = candidates.filter { it > now + 15_000 && it <= horizon }.minOrNull() ?: (now + 6 * 60 * 60 * 1000)
        val canExact = Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()
        if (canExact) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
        else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(channelId, "上课提醒", NotificationManager.IMPORTANCE_LOW).apply {
            description = "锁屏上的下一节课倒计时"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    @Suppress("unused")
    private val elapsed = SystemClock.elapsedRealtime()
}

class ClassAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val pending = goAsync()
        ClassAlerts.refreshStoredAsync(context) { pending.finish() }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val pending = goAsync()
        ClassAlerts.refreshStoredAsync(context) { pending.finish() }
    }
}
