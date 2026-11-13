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
import com.classday.app.platform.FenixAuth
import com.classday.app.ui.ClassdayApp
import com.classday.app.ui.ClassdayModel
import com.classday.app.ui.Screen
import kotlinx.coroutines.flow.MutableStateFlow

class MainActivity : ComponentActivity() {
    private val incoming = MutableStateFlow<Intent?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        incoming.value = intent
        setContent {
            val model: ClassdayModel = viewModel()
            val event by incoming.collectAsState()
            LaunchedEffect(event) { event?.let { handle(model, it) } }
            ClassdayApp(model)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incoming.value = intent
    }

    private fun handle(model: ClassdayModel, intent: Intent?) {
        val data = intent?.data
        if (intent?.action == ACTION_OPEN_NEXT) {
            model.goHome(Screen.Week)
            return
        }
        if (data == null) return
        when (data.host?.lowercase()) {
            "course" -> {
                val parsed = ClassdayLink.parseCourse(data.toString()) ?: return
                model.open(Screen.Detail(parsed.first, parsed.second, model.weekIndex()))
            }
            "timetable" -> model.importShare(data.toString())
            "fenix" -> {
                val imported = FenixAuth.complete(this, data, model.document.semester.totalWeeks)
                if (imported == null) model.banner = "Fénix 登录没有完成"
                else model.importCalendar(imported.courses, imported.exams, imported.homework)
            }
            "appearance" -> data.getQueryParameter("theme")?.let { model.setTheme(it) }
            "about" -> model.open(Screen.About)
        }
    }

    companion object {
        const val ACTION_OPEN_NEXT = "com.classday.app.OPEN_NEXT"
    }
}
