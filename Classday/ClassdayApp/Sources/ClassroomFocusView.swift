import Foundation
import SwiftUI
import ClassdayCore

/// 2.9.8：应用内上课专注 —— 真正的全屏界面。
///
/// 进入方式：课程详情的「上课专注」、我的 › Siri 与上课专注里的按钮、
/// Siri「开始课曜上课专注」，以及深链 `classday://classroom`。
/// 只显示当前这一节（没在上课时显示下一节）、剩余时间与地点；
/// 课程结束后自动收起，不需要手动退出。
struct ClassroomFocusView: View {
    var model: AppModel
    var onClose: () -> Void

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var document: StoreDocument? {
        model.loadError == nil ? model.document : nil
    }

    private var current: Occurrence? {
        guard let document else { return nil }
        return ScheduleEngine.currentOccurrence(
            at: now,
            courses: document.courses,
            semester: document.semester,
            calendar: model.calendar,
            context: document.scheduleContext
        )
    }

    private var upcoming: Occurrence? {
        guard let document else { return nil }
        return ScheduleEngine.nextOccurrence(
            after: now,
            courses: document.courses,
            semester: document.semester,
            calendar: model.calendar,
            context: document.scheduleContext
        )
    }

    private var focus: Occurrence? { current ?? upcoming }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(current != nil ? "正在上课" : "下一节课")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("结束专注") { onClose() }
                        .buttonStyle(.bordered)
                }

                if let course = focus {
                    Text(course.name)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    VStack(alignment: .leading, spacing: 10) {
                        Label(course.location.isEmpty ? "教室未定" : course.location, systemImage: "mappin.and.ellipse")
                        Label(course.timeText, systemImage: "clock")
                        Label("第 \(course.startPeriod)–\(course.endPeriod) 节 · 第 \(course.weekIndex) 周", systemImage: "calendar")
                        if !course.teacher.isEmpty {
                            Label(course.teacher, systemImage: "person")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Text(remainingText)
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    if let next = upcoming, next.id != focus?.id {
                        Divider()
                        Text("接着：\(next.name) · \(next.timeText) · \(next.location.isEmpty ? "教室未定" : next.location)")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("现在没有安排")
                        .font(.title2.weight(.semibold))
                    Text("今天的课都上完了，或者课表还没读到。")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .onReceive(ticker) { value in
            now = value
            // 课程结束且今天后面没有课：自动退出专注。
            if model.showClassroomFocus, current == nil, upcoming == nil {
                onClose()
            }
        }
    }

    private var remainingText: String {
        guard let course = focus else { return "--:--" }
        let target = current != nil ? course.end : course.start
        let seconds = Int(target.timeIntervalSince(now))
        if seconds <= 0 { return current != nil ? "已下课" : "即将开始" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
