import SwiftUI
import ClassdayCore

struct CourseDetailView: View {
    var presentation: CoursePresentation
    var namespace: Namespace.ID
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let course = model.course(presentation.courseID)
        let meeting = course?.meetings.first { $0.id == presentation.meetingID } ?? course?.meetings.first
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)) {
                        model.presented = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("课程详情")
                    }
                    .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("返回课表")
                Spacer()
                Menu {
                    Button("编辑课程") { model.editor = .edit(presentation.courseID) }
                    Button("调整时间") {
                        model.editor = .reschedule(courseID: presentation.courseID, meetingID: presentation.meetingID)
                    }
                    if let occurrence = model.occurrences().first(where: { $0.meetingID == presentation.meetingID && $0.weekIndex == model.weekIndex }) {
                        Button("仅本周取消") { model.cancelThisWeek(occurrence) }
                        Button("本周推迟 10 分钟") { model.delayThisWeek(occurrence) }
                    }
                    Button("单周") { model.setParity(meetingID: presentation.meetingID, parity: .odd) }
                    Button("双周") { model.setParity(meetingID: presentation.meetingID, parity: .even) }
                    Button("每周") { model.setParity(meetingID: presentation.meetingID, parity: .any) }
                    if let course {
                        Button("导航到教室") {
                            let pin = model.document.rooms.first { $0.name == course.location }
                            RoomNavigator.open(location: course.location, pin: pin)
                        }
                    }
                    Button("删除课程", role: .destructive) { model.confirmDeleteCourseID = presentation.courseID }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("更多操作")
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let course, let meeting {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero(course: course, meeting: meeting)
                        infoBlock(title: "上课地点", primary: course.location, secondary: course.note)
                        infoBlock(
                            title: "任课教师",
                            primary: course.teacher.isEmpty ? "未填写" : course.teacher,
                            secondary: course.department
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            Text("课程安排")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondary)
                            ForEach(Array(ScheduleCopy.arrangementLines(course: course, semester: model.document.semester).enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: index == 0 ? 18 : 14, weight: index == 0 ? .semibold : .regular))
                                    .foregroundStyle(index == 0 ? Theme.ink : Theme.secondary)
                            }
                        }
                        reminderCard(course)
                        PrimaryButton(title: "编辑课程") {
                            model.editor = .edit(course.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            } else {
                Text("这门课已经不在课表里")
                    .foregroundStyle(Theme.secondary)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }

    private func hero(course: Course, meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ScheduleCopy.heroTag(kind: course.kind, weeks: course.weeks))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accentInk)
            Text(course.name)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(ScheduleCopy.heroTime(meeting: meeting, semester: model.document.semester))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func infoBlock(title: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            Text(primary)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
            Rectangle().fill(Theme.line).frame(height: 0.5).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func reminderCard(_ course: Course) -> some View {
        let lead = course.reminderLeadMinutes ?? model.document.semester.defaultReminderMinutes
        let enabled = lead > 0
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("上课提醒")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(reminderCaption(enabled: enabled, lead: lead))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Toggle("上课提醒", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    Task { await model.setReminder(courseID: course.id, enabled: newValue) }
                }
            ))
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(16)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func reminderCaption(enabled: Bool, lead: Int) -> String {
        let base = enabled ? "提前 \(lead) 分钟" : "关闭"
        if model.notificationStatusText == "已拒绝" {
            return "\(base) · 系统通知已拒绝"
        }
        if model.notificationStatusText == "未请求" && enabled {
            return "\(base) · 开启时会向系统请求权限"
        }
        return base
    }
}
