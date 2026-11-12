import ActivityKit
import BackgroundTasks
import Foundation
import ClassdayCore

enum NextClassActivity {
    static let backgroundTaskID = "com.classday.app.refresh-next-class"

    static func scheduleBackgroundRefresh(document: StoreDocument, calendar: Calendar, now: Date = Date()) {
        guard let boundary = NextClassSnapshot.nextBoundary(after: now, document: document, calendar: calendar) else { return }
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = boundary
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("classday: BG refresh submit failed: \(error)")
        }
    }

    static func sync(document: StoreDocument, calendar: Calendar) {
        Task { await syncAsync(document: document, calendar: calendar) }
    }

    static func syncAsync(document: StoreDocument, calendar: Calendar) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let activities = Activity<NextClassAttributes>.activities
        guard let snapshot = NextClassSnapshot.make(document: document, calendar: calendar) else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
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
        if let current = activities.first(where: { $0.attributes.courseID == snapshot.courseID }) {
            await current.update(content)
            for stale in activities where stale.id != current.id {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        } else {
            for stale in activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
            _ = try? Activity.request(
                attributes: NextClassAttributes(courseID: snapshot.courseID),
                content: content,
                pushType: nil
            )
        }
    }
}
