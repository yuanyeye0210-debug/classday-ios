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
                    VStack(alignment: .leading, spacing: 0) {
                        hero(course: course, meeting: meeting)
                        sectionRow(label: "上课地点", primary: course.location, secondary: course.note)
                        hairline
                        sectionRow(
                            label: "任课教师",
                            primary: course.teacher.isEmpty ? "未填写" : course.teacher,
                            secondary: course.department
                        )
                        hairline
                        scheduleSection(course: course)
                        hairline
                        reminderCard(course)
                        PrimaryButton(title: "编辑课程") {
                            model.editor = .edit(course.id)
                        }
                        .padding(.top, 20)
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
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return VStack(alignment: .leading, spacing: 0) {
            Text(ScheduleCopy.heroTag(kind: course.kind, weeks: course.weeks))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink.opacity(0.72))
            Text(course.name)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(ink)
                .padding(.top, 8)
            Text(ScheduleCopy.heroTime(meeting: meeting, semester: model.document.semester))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.top, 6)
            Rectangle().fill(ink.opacity(0.25)).frame(height: 1)
                .padding(.vertical, 16)
            HStack(alignment: .top, spacing: 24) {
                heroFact(label: "地点", value: course.location, ink: ink)
                if !course.teacher.isEmpty {
                    heroFact(label: "教师", value: course.teacher, ink: ink)
                }
                Spacer(minLength: 0)
            }
            weekStrip(course: course, ink: ink, bg: bg)
                .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func heroFact(label: String, value: String, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(ink.opacity(0.65))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }

    private func weekStrip(course: Course, ink: Color, bg: Color) -> some View {
        let active = Set(course.meetings.map(\.weekday))
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                Text(ScheduleCopy.weekdayShort(day))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active.contains(day) ? bg : ink.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(active.contains(day) ? ink : ink.opacity(0.10))
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5)
    }

    private func sectionRow(label: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
            Text(primary)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func scheduleSection(course: Course) -> some View {
        let meetings = course.meetings.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            return $0.startPeriod < $1.startPeriod
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("课程安排")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text(ScheduleCopy.weekList(course.weeks))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.top, 14)
            .padding(.bottom, 2)
            ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                if index > 0 {
                    hairline
                }
                scheduleRow(meeting: meeting)
            }
            Text(model.document.semester.name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
    }

    private func scheduleRow(meeting: Meeting) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(ScheduleCopy.weekdayName(meeting.weekday))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, alignment: .leading)
            Text(ScheduleCopy.periodSpan(meeting.startPeriod, meeting.endPeriod))
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .frame(width: 68, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let clocks = ScheduleCopy.clocks(for: meeting, semester: model.document.semester) {
                Text(ScheduleCopy.timeRange(clocks.start, clocks.end))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
            Text(parityText(meeting: meeting))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func parityText(meeting: Meeting) -> String {
        switch model.document.weekRules.first(where: { $0.meetingID == meeting.id })?.parity {
        case .odd: return "单周"
        case .even: return "双周"
        default: return "每周"
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
        .padding(.vertical, 14)
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
