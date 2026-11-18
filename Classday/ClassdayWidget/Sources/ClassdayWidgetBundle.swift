import Foundation
import SwiftUI
import WidgetKit
import ClassdayCore

struct ClassdayEntry: TimelineEntry {
    var date: Date
    var state: WidgetRenderState
    var document: StoreDocument? = nil
}

enum SharedWidgetStore {
    static func load() -> StoreDocument? {
        let primary = AppGroupContainer.storeURL().flatMap { try? Data(contentsOf: $0) }
        let fallback = AppGroupContainer.resolution().identifier.flatMap {
            UserDefaults(suiteName: $0)?.data(forKey: WidgetStoreSnapshot.defaultsKey)
        }
        let mirrored = AppGroupContainer.loadMirroredSnapshot()
        return WidgetStoreSnapshot.document(primary: primary, fallback: fallback, mirrored: mirrored)
    }

    static func missingState(at now: Date, calendar: Calendar) -> WidgetRenderState {
        WidgetProjection.missingStoreState(at: now, calendar: calendar, detail: AppGroupContainer.diagnostics())
    }
}

struct ClassdayProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClassdayEntry {
        sampleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (ClassdayEntry) -> Void) {
        let calendar = ClassdayCalendar.make()
        let now = Date()
        if let document = SharedWidgetStore.load() {
            completion(ClassdayEntry(date: now, state: WidgetProjection.state(at: now, document: document, calendar: calendar), document: document))
        } else {
            completion(context.isPreview ? sampleEntry() : ClassdayEntry(
                date: now, state: SharedWidgetStore.missingState(at: now, calendar: calendar)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClassdayEntry>) -> Void) {
        let calendar = ClassdayCalendar.make()
        let now = Date()
        guard let document = SharedWidgetStore.load() else {
            let entry = ClassdayEntry(date: now, state: SharedWidgetStore.missingState(at: now, calendar: calendar))
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        let plan = WidgetProjection.timelinePlan(now: now, document: document, calendar: calendar)
        let entries = plan.entryDates.map { date in
            ClassdayEntry(date: date, state: WidgetProjection.state(at: date, document: document, calendar: calendar), document: document)
        }
        let refresh = max(plan.refreshAfter, now.addingTimeInterval(WidgetProjection.minimumRefreshInterval))
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    /// Gallery sample only. The home screen uses the shared store and the device clock.
    private func sampleEntry() -> ClassdayEntry {
        let calendar = ClassdayCalendar.make(timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 11
        components.day = 2
        components.hour = 7
        components.minute = 40
        let date = calendar.date(from: components) ?? Date()
        return ClassdayEntry(
            date: date,
            state: WidgetProjection.state(at: date, document: DemoData.makeDocument(), calendar: calendar),
            document: DemoData.makeDocument()
        )
    }
}

struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetID.nextClass, provider: ClassdayProvider()) { entry in
            SmallNextClassView(state: entry.state.small)
        }
        .configurationDisplayName("下一节")
        .description("显示即将开始的课程、地点和倒计时。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct TodayCoursesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetID.todayCourses, provider: ClassdayProvider()) { entry in
            MediumTodayView(state: entry.state.medium)
        }
        .configurationDisplayName("今日课程")
        .description("在一张卡片里查看今天的课程。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct ClassdayWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        TodayCoursesWidget()
        FanStackWidget()
        WeekBoardWidget()
        LockNextWidget()
        NextClassActivityWidget()
        if #available(iOS 18.0, *) {
            NextClassControl()
        }
    }
}
