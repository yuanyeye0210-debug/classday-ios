package com.classday.app.core

/**
 * Applies a stored timetable load to the alarm state without touching Android APIs.
 *
 * A failed load still carries a usable demo document, so the document alone must not
 * authorize scheduling: cancellation of the current notification and scheduled alarm
 * happens only on error, and the demo document is never refreshed.
 */
internal suspend fun applyStoredAlarmResult(
    loaded: StoreLoadResult,
    refresh: suspend (StoreDocument) -> Unit,
    cancelNotification: () -> Unit,
    cancelAlarm: () -> Unit,
) {
    if (loaded.error == null) {
        refresh(loaded.document)
    } else {
        cancelNotification()
        cancelAlarm()
    }
}
