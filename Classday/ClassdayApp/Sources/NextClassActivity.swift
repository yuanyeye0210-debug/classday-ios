import ActivityKit
import Foundation
import ClassdayCore

enum NextClassActivity {
    static func sync(document: StoreDocument, calendar: Calendar) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let activities = Activity<NextClassAttributes>.activities
        guard let snapshot = NextClassSnapshot.make(document: document, calendar: calendar) else {
            for activity in activities {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
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
            Task { await current.update(content) }
            for stale in activities where stale.id != current.id {
                Task { await stale.end(nil, dismissalPolicy: .immediate) }
            }
        } else {
            for stale in activities {
                Task { await stale.end(nil, dismissalPolicy: .immediate) }
            }
            _ = try? Activity.request(
                attributes: NextClassAttributes(courseID: snapshot.courseID),
                content: content,
                pushType: nil
            )
        }
    }
}
