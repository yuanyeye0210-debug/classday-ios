import EventKit
import Foundation
import ClassdayCore

enum CalendarSync {
    private static let statusLock = NSLock()
    private static var _status = "系统日历还没有同步。打开后，改课会更新或删掉对应事件。"
    static var status: String {
        get { statusLock.withLock { _status } }
        set { statusLock.withLock { _status = newValue } }
    }

    private static let enabledKey = "classday.calendarSyncEnabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

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
        // Lookup window must cover everything the creation loop can create:
        // the whole semester, not a fixed 120 days from today.
        let firstWeek = SemesterCalendar.dates(inWeek: 1, semester: document.semester, calendar: calendar)
        let lastWeek = SemesterCalendar.dates(inWeek: document.semester.totalWeeks, semester: document.semester, calendar: calendar)
        let windowStart = firstWeek.first?.addingTimeInterval(-86_400) ?? now.addingTimeInterval(-86_400)
        let windowEnd = lastWeek.last?.addingTimeInterval(2 * 86_400) ?? calendar.date(byAdding: .day, value: 120, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: [ek])
        let existing = store.events(matching: predicate).filter { $0.notes?.contains(marker) == true }
        var seen = Set<String>()
        var failures = 0
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
                do {
                    try store.save(event, span: .thisEvent)
                } catch {
                    failures += 1
                }
            }
        }
        for event in existing {
            let key = event.notes?.split(separator: "\n").first.map(String.init) ?? ""
            if key.hasPrefix(marker), !seen.contains(key) {
                do {
                    try store.remove(event, span: .thisEvent)
                } catch {
                    failures += 1
                }
            }
        }
        status = failures == 0
            ? "已写入系统日历。取消或推迟某一周后会跟着更新。"
            : "已同步，但有 \(failures) 个事件写入失败，稍后保存课表时会再试。"
    }
}
