package com.classday.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.core.view.WindowCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.classday.app.core.ClassdayLink
import com.classday.app.ui.ClassdayApp
import com.classday.app.ui.ClassdayModel
import com.classday.app.ui.Screen
import kotlinx.coroutines.flow.MutableStateFlow

class MainActivity : ComponentActivity() {
    private val incoming = MutableStateFlow<Intent?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = androidx.activity.SystemBarStyle.auto(
                android.graphics.Color.TRANSPARENT,
                android.graphics.Color.TRANSPARENT,
            ),
            navigationBarStyle = androidx.activity.SystemBarStyle.auto(
                android.graphics.Color.TRANSPARENT,
                android.graphics.Color.TRANSPARENT,
            ),
        )
        WindowCompat.setDecorFitsSystemWindows(window, false)
        incoming.value = intent
        // 2.9.7：打开应用就重新计算倒计时通知、本节课提醒与小组件。
        // 此前只有保存课表或开机才会刷新，装完首次打开时一条闹钟都没有。
        ClassAlerts.refreshStoredAsync(this)
        setContent {
            val model: ClassdayModel = viewModel()
            val event by incoming.collectAsState()
            LaunchedEffect(event) { event?.let { handle(model, it) } }
            ClassdayApp(model)
        }
    }

    override fun onResume() {
        super.onResume()
        com.classday.app.platform.ClassroomDnd.refreshAsync(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incoming.value = intent
    }

    private fun handle(model: ClassdayModel, intent: Intent?) {
        if (intent?.action == android.app.NotificationManager.ACTION_AUTOMATIC_ZEN_RULE) {
            model.ensureReminderDraft()
            model.open(Screen.Reminders)
            return
        }
        val data = intent?.data
        if (intent?.action == ACTION_OPEN_NEXT) {
            model.goHome(Screen.Today)
            return
        }
        if (data == null) return
        when (data.host?.lowercase()) {
            "today" -> model.goHome(Screen.Today)
            "course" -> {
                val parsed = ClassdayLink.parseCourse(data.toString()) ?: return
                model.open(Screen.Detail(parsed.first, parsed.second, model.weekIndex()))
            }
            "timetable" -> model.importShare(data.toString())
            "appearance" -> data.getQueryParameter("theme")?.let { model.setTheme(it) }
            "about" -> model.open(Screen.About)
        }
    }

    companion object {
        const val ACTION_OPEN_NEXT = "com.classday.app.OPEN_NEXT"
    }
}
