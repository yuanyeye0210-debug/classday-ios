import EventKit
import Foundation
import ClassdayCore

enum CalendarSync {
    static var status = "系统日历还没有同步。打开后，改课会更新或删掉对应事件。"
    private static let store = EKEventStore()
    private static let marker = "classday-event"

    static func sync(_ document: StoreDocument, calendar: Calendar) {
        store.requestFullAccessToEvents { granted, error in
            finish(document, calendar: calendar, granted: granted, error: error)
        }
    }

    private static func finish(_ document: StoreDocument, calendar: Calendar, granted: Bool, error: Error?) {
        guard granted, error == nil, let ek = store.defaultCalendarForNewEvents else {
            status = "没有日历权限，课表仍只保存在课曜里。"
            return
        }
        let now = Date()
        guard let end = calendar.date(byAdding: .day, value: 120, to: now) else { return }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-86_400), end: end, calendars: [ek])
        let existing = store.events(matching: predicate).filter { $0.notes?.contains(marker) == true }
        var seen = Set<String>()
        for week in 1...document.semester.totalWeeks {
            let items = ScheduleEngine.occurrences(
                inWeek: week,
                courses: document.courses,
                semester: document.semester,
                calendar: calendar,
                context: document.scheduleContext
            )
            for item in items where item.end > now {
                let key = "\(marker):\(item.id)"
                seen.insert(key)
                let event = existing.first { $0.notes?.contains(key) == true } ?? EKEvent(eventStore: store)
                event.calendar = ek
                event.title = item.name
                event.location = item.location
                event.startDate = item.start
                event.endDate = item.end
                event.notes = "\(key)\n\(item.teacher)"
                event.url = ClassdayLink.course(item.courseID, meeting: item.meetingID)
                try? store.save(event, span: .thisEvent)
            }
        }
        for event in existing {
            let key = event.notes?.split(separator: "\n").first.map(String.init) ?? ""
            if key.hasPrefix(marker), !seen.contains(key) {
                try? store.remove(event, span: .thisEvent)
            }
        }
        status = "已写入系统日历。取消或推迟某一周后会跟着更新。"
    }
}
