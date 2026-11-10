import ActivityKit
import Foundation
import ClassdayCore

enum NextClassActivity {
    static func sync(document: StoreDocument, calendar: Calendar) {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let snapshot = NextClassSnapshot.make(document: document, calendar: calendar) else {
            for activity in Activity<NextClassAttributes>.activities {
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
        if let current = Activity<NextClassAttributes>.activities.first {
            Task { await current.update(content) }
        } else {
            _ = try? Activity.request(
                attributes: NextClassAttributes(courseID: snapshot.courseID),
                content: content,
                pushType: nil
            )
        }
    }
}
