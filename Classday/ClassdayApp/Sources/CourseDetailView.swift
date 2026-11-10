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
                    VStack(alignment: .leading, spacing: 16) {
                        hero(course: course, meeting: meeting)
                        infoCard(course: course)
                        scheduleCard(course: course)
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
        VStack(alignment: .leading, spacing: 12) {
            Text(ScheduleCopy.heroTag(kind: course.kind, weeks: course.weeks))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.card.opacity(0.65)))
            Text(course.name)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(ScheduleCopy.heroTime(meeting: meeting, semester: model.document.semester))
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.accentInk)
            HStack(spacing: 8) {
                heroChip(icon: "mappin.and.ellipse", text: course.location)
                if !course.teacher.isEmpty {
                    heroChip(icon: "person.fill", text: course.teacher)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func heroChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.card.opacity(0.65)))
    }

    private func infoCard(course: Course) -> some View {
        VStack(spacing: 0) {
            infoRow(icon: "mappin.and.ellipse", title: "上课地点", primary: course.location, secondary: course.note)
            Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 64)
            infoRow(
                icon: "person.fill",
                title: "任课教师",
                primary: course.teacher.isEmpty ? "未填写" : course.teacher,
                secondary: course.department
            )
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
    }

    private func infoRow(icon: String, title: String, primary: String, secondary: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.elevated))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                Text(primary)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if !secondary.isEmpty {
                    Text(secondary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func scheduleCard(course: Course) -> some View {
        let meetings = course.meetings.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            return $0.startPeriod < $1.startPeriod
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
                Text("课程安排")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text(ScheduleCopy.weekList(course.weeks))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                if index > 0 {
                    Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 72)
                }
                scheduleRow(meeting: meeting)
            }
            Text(model.document.semester.name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
    }

    private func scheduleRow(meeting: Meeting) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(ScheduleCopy.weekdayName(meeting.weekday))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                Text(ScheduleCopy.periodSpan(meeting.startPeriod, meeting.endPeriod))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accentInk.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 48, height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hero))
            VStack(alignment: .leading, spacing: 2) {
                if let clocks = ScheduleCopy.clocks(for: meeting, semester: model.document.semester) {
                    Text(ScheduleCopy.timeRange(clocks.start, clocks.end))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                } else {
                    Text(ScheduleCopy.periodSpan(meeting.startPeriod, meeting.endPeriod))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Text(parityText(meeting: meeting))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func parityText(meeting: Meeting) -> String {
        switch model.document.weekRules.first(where: { $0.meetingID == meeting.id })?.parity {
        case .odd: return "单周上课"
        case .even: return "双周上课"
        default: return "每周上课"
        }
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
