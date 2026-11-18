package com.classday.app

import com.classday.app.core.DemoData
import com.classday.app.core.StoreDocument
import com.classday.app.core.StoreLoadResult
import com.classday.app.core.applyStoredAlarmResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class StoredAlarmPolicyTest {
    @Test
    fun unreadableTimetableCancelsAlarmAndNotificationWithoutRefreshingDemoData() = runBlocking {
        val demo = DemoData.makeDocument()
        var refreshed: StoreDocument? = null
        var notificationCancels = 0
        var alarmCancels = 0

        applyStoredAlarmResult(
            loaded = StoreLoadResult(demo, "原课表无法读取"),
            refresh = { refreshed = it },
            cancelNotification = { notificationCancels += 1 },
            cancelAlarm = { alarmCancels += 1 },
        )

        assertNull(refreshed)
        assertEquals(1, notificationCancels)
        assertEquals(1, alarmCancels)
    }

    @Test
    fun readableTimetableRefreshesExactDocumentWithoutCancelling() = runBlocking {
        val document = DemoData.makeDocument()
        var refreshed: StoreDocument? = null
        var cancels = 0

        applyStoredAlarmResult(
            loaded = StoreLoadResult(document),
            refresh = { refreshed = it },
            cancelNotification = { cancels += 1 },
            cancelAlarm = { cancels += 1 },
        )

        assertSame(document, refreshed)
        assertEquals(0, cancels)
    }

    @Test
    fun loadErrorDecidesEvenWhenTheReturnedDocumentLooksUsable() = runBlocking {
        val document = DemoData.makeDocument()
        var refreshed: StoreDocument? = null
        var cancels = 0

        applyStoredAlarmResult(
            loaded = StoreLoadResult(document, "读取失败"),
            refresh = { refreshed = it },
            cancelNotification = { cancels += 1 },
            cancelAlarm = { cancels += 1 },
        )
        assertNull(refreshed)
        assertEquals(2, cancels)

        applyStoredAlarmResult(
            loaded = StoreLoadResult(document),
            refresh = { refreshed = it },
            cancelNotification = { cancels += 1 },
            cancelAlarm = { cancels += 1 },
        )
        assertSame(document, refreshed)
        assertEquals(2, cancels)
    }
}
