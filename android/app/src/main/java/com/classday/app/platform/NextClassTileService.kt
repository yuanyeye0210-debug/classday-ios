package com.classday.app.platform

import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.classday.app.MainActivity
import com.classday.app.core.CivilCalendar
import com.classday.app.core.ScheduleEngine
import java.time.Instant
import java.time.ZoneId

class NextClassTileService : TileService() {
    override fun onStartListening() {
        val tile = qsTile ?: return
        val document = ClassdayStore.load(this)
        val calendar = CivilCalendar(ZoneId.systemDefault())
        val now = Instant.now()
        val item = ScheduleEngine.current(now, document.courses, document.semester, calendar, document.scheduleContext)
            ?: ScheduleEngine.next(now, document.courses, document.semester, calendar, document.scheduleContext)
        tile.label = "下一节"
        tile.state = Tile.STATE_ACTIVE
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = item?.name ?: "今天没有课"
        tile.updateTile()
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_NEXT
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val pending = android.app.PendingIntent.getActivity(
                this, 7, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
