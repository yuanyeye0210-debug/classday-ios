import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit
import ClassdayCore

struct MarkArrivedIntent: AppIntent {
    static var title: LocalizedStringResource = "已到教室"
    static var description = IntentDescription("课曜：记下这节课已经到教室。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let suite = AppGroupContainer.resolution().identifier ?? AppGroup.identifier
        UserDefaults(suiteName: suite)?.set(Date().timeIntervalSince1970, forKey: "classday.arrived")
        return .result()
    }
}

struct DelayClassIntent: AppIntent {
    static var title: LocalizedStringResource = "推迟 10 分钟"
    static var description = IntentDescription("课曜：把即将开始的这一节推迟 10 分钟。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        guard let url = AppGroupContainer.storeURL(), let data = try? Data(contentsOf: url) else { return .result() }
        guard var document = StoreCodec.importing(data).document else { return .result() }
        let calendar = ClassdayCalendar.make()
        guard let next = ScheduleEngine.nextOccurrence(
            after: Date(),
            courses: document.courses,
            semester: document.semester,
            calendar: calendar,
            context: document.scheduleContext
        ) ?? ScheduleEngine.currentOccurrence(at: Date(), courses: document.courses, semester: document.semester, calendar: calendar, context: document.scheduleContext) else {
            return .result()
        }
        document = TimetableLibrary.overriding(document, with: OccurrenceOverride(
            courseID: next.courseID, meetingID: next.meetingID, week: next.weekIndex, kind: .delayed, delayMinutes: 10
        ))
        try? StoreFile.save(document, to: url)
        for kind in WidgetID.all {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        await ReminderDelivery.replacePending(
            NotificationPlan.make(document: document, now: Date(), calendar: calendar),
            calendar: calendar
        )
        return .result()
    }
}

struct NextFanCardIntent: AppIntent {
    static var title: LocalizedStringResource = "下一张卡片"
    static var description = IntentDescription("课曜：翻开今日课程的下一张卡片。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: AppGroupContainer.resolution().identifier ?? AppGroup.identifier)
        let current = defaults?.integer(forKey: FanDeck.defaultsKey) ?? 0
        defaults?.set(current + 1, forKey: FanDeck.defaultsKey)
        return .result()
    }
}

struct WhereIsNextIntent: AppIntent {
    static var title: LocalizedStringResource = "下一节在哪上课"
    static var description = IntentDescription("课曜：说出下一节课的地点。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = AppGroupContainer.storeURL(),
              let data = try? Data(contentsOf: url),
              let document = StoreCodec.importing(data).document,
              let snapshot = NextClassSnapshot.make(document: document) else {
            return .result(dialog: "还没有读到下一节课。")
        }
        return .result(dialog: "\(snapshot.phase) \(snapshot.title)，在\(snapshot.location)。")
    }
}

struct OpenNextClassIntent: AppIntent {
    static var title: LocalizedStringResource = "打开下一节"
    static var description = IntentDescription("课曜：打开下一节课。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct FanStackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetID.fanStack, provider: ClassdayProvider()) { entry in
            FanStackView(date: entry.date)
        }
        .configurationDisplayName("卡片叠放")
        .description("左右叠放今天的课，点下一张翻开。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct FanStackView: View {
    var date: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let document = SharedWidgetStore.load()
        let theme = document?.appearance.theme ?? ClassdayThemes.theme(id: "aurora")
        let suite = AppGroupContainer.resolution().identifier ?? AppGroup.identifier
        let index = UserDefaults(suiteName: suite)?.integer(forKey: FanDeck.defaultsKey) ?? 0
        let page = document.map { FanDeck.page(at: date, document: $0, calendar: ClassdayCalendar.make(), index: index) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日课程").font(.headline)
                Spacer()
                Button(intent: NextFanCardIntent()) {
                    Label("下一张", systemImage: "rectangle.stack")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            if let page, !page.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(page.chips.enumerated()), id: \.element.id) { offset, chip in
                        VStack(alignment: .leading) {
                            Text(chip.timeText).font(.caption.bold())
                            Text(chip.name).font(.caption).lineLimit(2)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color(theme.courseAccent(for: chip.colorID).palette).opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                        .rotationEffect(.degrees(Double(offset - 1) * 4))
                    }
                }
            } else {
                Text("今天没有课").font(.title3.bold())
            }
        }
        .padding(14)
        .foregroundStyle(Color(theme.ink.palette))
        .containerBackground(for: .widget) { Color(theme.background.palette) }
        .environment(\.colorScheme, theme.prefersDark ? .dark : scheme)
    }
}

struct WeekBoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetID.weekBoard, provider: ClassdayProvider()) { entry in
            WeekBoardView(date: entry.date)
        }
        .configurationDisplayName("本周课表")
        .description("用静态皮肤看这一周。")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

struct WeekBoardView: View {
    var date: Date

    var body: some View {
        let document = SharedWidgetStore.load()
        let theme = document?.appearance.theme ?? ClassdayThemes.theme(id: "neon")
        let calendar = ClassdayCalendar.make()
        let week = document.flatMap { SemesterCalendar.weekIndex(for: date, semester: $0.semester, calendar: calendar) } ?? 1
        let items = document.map {
            ScheduleEngine.occurrences(inWeek: week, courses: $0.courses, semester: $0.semester, calendar: calendar, context: $0.scheduleContext)
        } ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text("第 \(week) 周").font(.headline)
            ForEach(1...7, id: \.self) { weekday in
                let day = items.filter { $0.weekday == weekday }
                HStack {
                    Text(ScheduleCopy.weekdayName(weekday)).frame(width: 28, alignment: .leading).font(.caption2)
                    Text(day.map(\.name).joined(separator: " · "))
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer()
                }
            }
            HStack {
                Button(intent: MarkArrivedIntent()) { Text("已到教室").font(.caption2) }.buttonStyle(.plain)
                Button(intent: DelayClassIntent()) { Text("推迟 10 分钟").font(.caption2) }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .foregroundStyle(Color(theme.ink.palette))
        .containerBackground(for: .widget) { Color(theme.background.palette) }
    }
}

struct LockNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetID.lockScreen, provider: ClassdayProvider()) { entry in
            LockNextView(date: entry.date)
        }
        .configurationDisplayName("锁屏下一节")
        .description("在锁屏上看下一节的时间和地点。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockNextView: View {
    var date: Date

    var body: some View {
        let snapshot = SharedWidgetStore.load().flatMap { NextClassSnapshot.make(document: $0, now: date) }
        VStack(alignment: .leading) {
            Text(snapshot?.title ?? "课曜")
                .font(.headline)
                .widgetAccentable()
            Text(snapshot?.location ?? "打开课曜")
                .font(.caption2)
            if let end = snapshot?.endsAt {
                Text(end, style: .timer).font(.caption2.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct NextClassActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextClassAttributes.self) { context in
            VStack(alignment: .leading) {
                Text(context.state.phase).font(.caption)
                Text(context.state.title).font(.headline)
                Text(context.state.location).font(.subheadline)
                Text(context.state.endsAt, style: .timer).font(.title2.monospacedDigit())
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.endsAt, style: .timer)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.location)
                }
            } compactLeading: {
                Image(systemName: "clock")
            } compactTrailing: {
                Text(context.state.endsAt, style: .timer)
            } minimal: {
                Image(systemName: "clock")
            }
        }
    }
}

@available(iOS 18.0, *)
struct NextClassControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "NextClassControl") {
            ControlWidgetButton(action: OpenNextClassIntent()) {
                Label("下一节", systemImage: "clock")
            }
        }
        .displayName("下一节")
        .description("打开下一节课。")
    }
}
