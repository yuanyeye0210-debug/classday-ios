import ActivityKit
import BackgroundTasks
import Foundation
import ClassdayCore

enum NextClassActivity {
    static let backgroundTaskID = "com.classday.app.refresh-next-class"

    /// UserDefaults key for when the current Live Activity was requested.
    /// `UserDefaults.standard` follows `UpdateService`'s precedent for
    /// storing a `Date` (last-check / last-reported keys); the timestamp
    /// must survive an app restart because the Activity itself is
    /// system-owned and outlives the process.
    private static let requestedAtKey = "classday.liveActivity.requestedAt"

    /// When the current Live Activity was requested, if known. Only the
    /// long-day rebuild rule reads it (`shouldRebuild`); it is set on a
    /// successful `Activity.request` and cleared when all activities end.
    private static var requestedAt: Date? {
        get { UserDefaults.standard.object(forKey: requestedAtKey) as? Date }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: requestedAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: requestedAtKey)
            }
        }
    }

    static func scheduleBackgroundRefresh(document: StoreDocument, calendar: Calendar, now: Date = Date()) {
        // Pre-class wake: when the next change is a midnight flip and the
        // flipped day's first class starts 8+ hours after it, wake 60
        // minutes before that class instead of at midnight — an Activity
        // created at midnight would expire as the class starts. In-day
        // boundaries are returned unchanged by `nextWakeDate`.
        // Heartbeat: when no snapshot change is in sight within the 7-day
        // horizon (e.g. a long holiday with no classes), re-queue at the
        // next midnight instead of letting the refresh chain die. The
        // background-task callback re-runs sync + schedule, so the chain
        // re-evaluates daily until a real boundary appears.
        let beginDate = NextClassSnapshot.nextWakeDate(after: now, document: document, calendar: calendar)
            ?? NextClassSnapshot.nextHeartbeat(after: now, calendar: calendar)
        guard let beginDate else { return }
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = beginDate
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("classday: BG refresh submit failed: \(error)")
        }
    }

    static func sync(document: StoreDocument, calendar: Calendar) {
        Task { await syncAsync(document: document, calendar: calendar) }
    }

    static func syncAsync(document: StoreDocument, calendar: Calendar, now: Date = Date()) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let activities = Activity<NextClassAttributes>.activities
        guard let snapshot = NextClassSnapshot.make(document: document, now: now, calendar: calendar) else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            requestedAt = nil
            return
        }
        let state = NextClassAttributes.ContentState(
            title: snapshot.title,
            location: snapshot.location,
            endsAt: snapshot.endsAt,
            phase: snapshot.phase
        )
        let content = ActivityContent(state: state, staleDate: snapshot.endsAt)
        // Attributes are immutable: an activity created for another course
        // must be ended and recreated, not just updated with new text.
        // Same for the long-day rebuild: an Activity 7+ hours old with
        // classes still ahead is ended and re-requested to reopen its
        // 8-hour window, instead of being updated in place.
        if let current = activities.first(where: { $0.attributes.courseID == snapshot.courseID }),
           !NextClassSnapshot.shouldRebuild(activityStartedAt: requestedAt, now: now, snapshot: snapshot) {
            await current.update(content)
            for stale in activities where stale.id != current.id {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        } else {
            for stale in activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
            let requested = try? Activity.request(
                attributes: NextClassAttributes(courseID: snapshot.courseID),
                content: content,
                pushType: nil
            )
            if requested != nil {
                requestedAt = now
            }
        }
    }
}
