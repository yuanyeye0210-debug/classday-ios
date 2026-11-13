package com.classday.app.platform

import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.classday.app.MainActivity
import com.classday.app.core.CivilCalendar
import com.classday.app.core.tilePresentation
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class NextClassTileService : TileService() {
    private val refreshScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var refreshJob: Job? = null

    override fun onStartListening() {
        super.onStartListening()
        refreshJob?.cancel()
        refreshJob = refreshScope.launch {
            val presentation = withContext(Dispatchers.IO) {
                tilePresentation(
                    ClassdayStore.loadWithStatus(applicationContext),
                    Instant.now(),
                    CivilCalendar(ZoneId.systemDefault()),
                )
            }
            val tile = qsTile ?: return@launch
            tile.label = presentation.label
            tile.state = if (presentation.active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            if (Build.VERSION.SDK_INT >= 29) tile.subtitle = presentation.subtitle
            tile.updateTile()
        }
    }

    override fun onStopListening() {
        refreshJob?.cancel()
        super.onStopListening()
    }

    override fun onDestroy() {
        refreshScope.cancel()
        super.onDestroy()
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
