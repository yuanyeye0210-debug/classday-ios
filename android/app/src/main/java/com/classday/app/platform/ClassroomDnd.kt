package com.classday.app.platform

import android.app.AlarmManager
import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.notification.Condition
import com.classday.app.MainActivity
import com.classday.app.core.CivilCalendar
import com.classday.app.core.ClassroomDndPlan
import java.time.Instant
import java.time.ZoneId

/** Owns one optional automatic rule; never changes the global interruption filter. */
object ClassroomDnd {
    private val conditionId = Uri.parse("condition://com.classday.app/classroom")
    private fun prefs(context: Context) = context.getSharedPreferences("classroom-dnd", Context.MODE_PRIVATE)
    fun consent(context: Context) = prefs(context).getBoolean("consent", false)
    fun supported() = Build.VERSION.SDK_INT >= 29
    fun policyAccess(context: Context) = context.getSystemService(NotificationManager::class.java).isNotificationPolicyAccessGranted
    fun exactAccess(context: Context) = Build.VERSION.SDK_INT < 31 || context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    fun status(context: Context): String {
        if (!supported()) return "系统版本不支持课曜独立勿扰规则，应用内上课专注仍可用。"
        if (!consent(context)) return "未启用上课勿扰。"
        if (!policyAccess(context)) return "未生效：请允许勿扰访问；课曜不能替你授权。"
        if (!exactAccess(context)) return "未生效：请允许精确定时，以安排下课退出。"
        return try {
            val manager = context.getSystemService(NotificationManager::class.java)
            val rule = prefs(context).getString("rule", null)?.let { manager.getAutomaticZenRule(it) }
            if (rule == null || rule.conditionId != conditionId) "未生效：规则已移除，请重新同意启用。"
            else if (!rule.isEnabled) "规则已在系统中关闭，请自行在系统设置中启用。"
            else prefs(context).getString("status", "已启用：按课表管理课曜自己的勿扰规则。").orEmpty()
        } catch (_: Exception) { "无法读取勿扰规则，请检查系统设置。" }
    }

    @Synchronized
    fun setConsent(context: Context, enabled: Boolean): String {
        if (enabled && (!supported() || !policyAccess(context) || !exactAccess(context)))
            return "尚未启用：需要 Android 10 或以上、勿扰访问和精确定时授权，请授权后再同意启用。"
        prefs(context).edit().putBoolean("consent", enabled).apply()
        if (enabled) {
            try {
                if (Build.VERSION.SDK_INT >= 29) {
                    val manager = context.getSystemService(NotificationManager::class.java)
                    val existing = prefs(context).getString("rule", null)?.let { manager.getAutomaticZenRule(it) }
                    if (existing == null) {
                        val rule = AutomaticZenRule("课曜上课勿扰", null,
                            ComponentName(context, MainActivity::class.java), conditionId, null,
                            NotificationManager.INTERRUPTION_FILTER_PRIORITY, true)
                        val id = manager.addAutomaticZenRule(rule)
                        prefs(context).edit().putString("rule", id).apply()
                    }
                }
            } catch (_: Exception) {
                prefs(context).edit().putBoolean("consent", false).apply()
                return "未能建立课曜的勿扰规则，应用内专注仍可用。"
            }
        }
        sync(context)
        return status(context)
    }

    fun refreshAsync(context: Context) {
        val application = context.applicationContext
        Thread { sync(application) }.start()
    }

    @Synchronized
    fun sync(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(context, 295,
            Intent(context, ClassroomDndReceiver::class.java).setAction("com.classday.app.CLASSROOM_BOUNDARY"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarms.cancel(pending)
        if (Build.VERSION.SDK_INT < 29) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.isNotificationPolicyAccessGranted) return
        try {
            val id = prefs(context).getString("rule", null) ?: return
            val rule = manager.getAutomaticZenRule(id) ?: return
            if (rule.conditionId != conditionId) return
            val loaded = ClassdayStore.loadWithStatus(context)
            val plan = ClassroomDndPlan.make(Instant.now(), loaded.document, CivilCalendar(ZoneId.systemDefault()),
                consent(context) && rule.isEnabled, true, exactAccess(context), loaded.error == null)
            // Schedule the exit/next boundary before publishing TRUE. If scheduling fails, release our condition.
            if (plan.nextBoundary != null) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, plan.nextBoundary, pending)
            manager.setAutomaticZenRuleState(id, Condition(conditionId, "课表上课时段",
                if (plan.active) Condition.STATE_TRUE else Condition.STATE_FALSE))
            prefs(context).edit().putString("status", if (plan.active) "上课中：课曜勿扰规则已请求生效，下课撤销本规则。"
                else "未在上课时段或条件不足：课曜未请求勿扰。其他勿扰规则不受影响。").apply()
        } catch (_: Exception) {
            prefs(context).edit().putString("status", "未能更新勿扰规则，请在系统中检查课曜规则。").apply()
            releaseOwnCondition(context)
        }
    }

    private fun releaseOwnCondition(context: Context) {
        if (Build.VERSION.SDK_INT < 29) return
        runCatching {
            val manager = context.getSystemService(NotificationManager::class.java)
            val id = prefs(context).getString("rule", null) ?: return
            if (manager.getAutomaticZenRule(id)?.conditionId == conditionId)
                manager.setAutomaticZenRuleState(id, Condition(conditionId, "课曜不请求勿扰", Condition.STATE_FALSE))
        }
    }
}

class ClassroomDndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (Build.VERSION.SDK_INT >= 30 && intent?.action == NotificationManager.ACTION_AUTOMATIC_ZEN_RULE_STATUS_CHANGED) {
            val status = intent.getIntExtra(NotificationManager.EXTRA_AUTOMATIC_ZEN_RULE_STATUS, -1)
            if (status !in listOf(NotificationManager.AUTOMATIC_RULE_STATUS_ENABLED,
                    NotificationManager.AUTOMATIC_RULE_STATUS_DISABLED, NotificationManager.AUTOMATIC_RULE_STATUS_REMOVED)) return
        }
        val result = goAsync()
        Thread { try { ClassroomDnd.sync(context) } finally { result.finish() } }.start()
    }
}
