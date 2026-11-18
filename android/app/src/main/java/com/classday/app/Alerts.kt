package com.classday.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import com.classday.app.core.CivilCalendar
import com.classday.app.core.CountdownCopy
import com.classday.app.core.Occurrence
import com.classday.app.core.ReminderItem
import com.classday.app.core.ReminderPlan
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
    const val reminderChannelId = "classday.reminder"
    const val ACTION_REMINDER = "com.classday.app.REMINDER"
    const val EXTRA_KEY = "com.classday.app.REMINDER_KEY"
    const val EXTRA_TITLE = "com.classday.app.REMINDER_TITLE"
    const val EXTRA_BODY = "com.classday.app.REMINDER_BODY"
    const val EXTRA_COURSE = "com.classday.app.REMINDER_COURSE"
    private const val notificationId = 2902
    private const val requestCode = 2902
    private const val reminderPrefs = "classday.reminders"
    private const val reminderCodesKey = "codes"
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
        val nowMillis = now.toEpochMilli()
        post(context, current, next, nowMillis)
        schedule(context, current, next, nowMillis, calendar)
        scheduleReminders(context, document, calendar, nowMillis)
        WeekBoardWidget().updateAll(context)
        TodayWidget().updateAll(context)
        com.classday.app.widget.NextClassWidget().updateAll(context)
    }

    /**
     * 2.9.7：每一节课按「提前 N 分钟」单独排一条提醒，考试与作业按学期默认提前量。
     * 每次刷新先按 key 与上次的排期对账，取消已经不需要的，避免改课表后残留旧提醒。
     */
    private fun scheduleReminders(context: Context, document: StoreDocument, calendar: CivilCalendar, now: Long) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val prefs = context.getSharedPreferences(reminderPrefs, Context.MODE_PRIVATE)
        val plan = ReminderPlan.build(document, calendar, now)
        val codes = plan.mapTo(mutableSetOf()) { requestCode(it.key) }
        val previous = prefs.getStringSet(reminderCodesKey, emptySet()).orEmpty().mapNotNull { it.toIntOrNull() }
        for (stale in previous - codes) {
            val pending = PendingIntent.getBroadcast(
                context,
                stale,
                Intent(context, ReminderReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            if (pending != null) alarm.cancel(pending)
        }
        val canExact = Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()
        for (item in plan) {
            val code = requestCode(item.key)
            val intent = Intent(context, ReminderReceiver::class.java).apply {
                action = ACTION_REMINDER
                data = Uri.parse("classday-reminder://${item.key}")
                putExtra(EXTRA_KEY, item.key)
                putExtra(EXTRA_TITLE, item.title)
                putExtra(EXTRA_BODY, item.body)
                if (item.courseID != null) putExtra(EXTRA_COURSE, item.courseID)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (canExact) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.triggerAtMillis, pending)
            else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.triggerAtMillis, pending)
        }
        prefs.edit().putStringSet(reminderCodesKey, codes.mapTo(mutableSetOf()) { it.toString() }).apply()
    }

    /** 一条提醒的 requestCode 与通知 id，稳定取自 key，跨进程重启不变。 */
    private fun requestCode(key: String): Int = (key.hashCode() and 0x7FFFFFFF).let { if (it == 0) 1 else it }

    /** 提醒到点后弹出的一次性通知；课程提醒点进去是课程详情，考试与作业进今日页。 */
    fun postReminder(context: Context, item: ReminderItem) {
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureReminderChannel(manager)
        val id = requestCode(item.key)
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (item.courseID != null) {
                action = Intent.ACTION_VIEW
                data = Uri.parse("classday://course/${item.courseID}")
            } else {
                action = MainActivity.ACTION_OPEN_NEXT
            }
        }
        val pending = PendingIntent.getActivity(
            context,
            id,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, reminderChannelId)
            .setSmallIcon(R.drawable.ic_stat_class)
            .setContentTitle(item.title)
            .setContentText(item.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        // 通知权限被拒时 notify 只应静默失败，不影响闹钟与课表本身。
        runCatching { manager.notify(id, notification) }
    }

    private fun ensureReminderChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(reminderChannelId, "课前与考试作业提醒", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "每节课开始前、考试开始前、作业截止前的提醒"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
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
}

/** 2.9.7：到点提醒。只负责发一条通知，不改课表、不重排闹钟（下一次刷新自然重算）。 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ClassAlerts.ACTION_REMINDER) return
        val key = intent.getStringExtra(ClassAlerts.EXTRA_KEY) ?: return
        ClassAlerts.postReminder(
            context,
            com.classday.app.core.ReminderItem(
                key = key,
                triggerAtMillis = 0,
                kind = com.classday.app.core.ReminderKind.CLASS,
                title = intent.getStringExtra(ClassAlerts.EXTRA_TITLE).orEmpty(),
                body = intent.getStringExtra(ClassAlerts.EXTRA_BODY).orEmpty(),
                courseID = intent.getStringExtra(ClassAlerts.EXTRA_COURSE),
            ),
        )
    }
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
        ClassAlerts.refreshStoredAsync(context) {
            try { com.classday.app.platform.ClassroomDnd.sync(context) } finally { pending.finish() }
        }
    }
}
