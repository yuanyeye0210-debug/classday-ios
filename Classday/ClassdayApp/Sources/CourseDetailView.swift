import SwiftUI
import ClassdayCore

struct CourseDetailView: View {
    var presentation: CoursePresentation
    var namespace: Namespace.ID
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedMeetingID: UUID?

    var body: some View {
        let course = model.course(presentation.courseID)
        let baseMeeting = course?.meetings.first { $0.id == presentation.meetingID } ?? course?.meetings.first
        let meeting = course?.meetings.first { $0.id == focusedMeetingID } ?? baseMeeting
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
                        titleBlock(course: course, meeting: meeting)
                        weekStrip(course: course, focused: meeting)
                            .padding(.top, 16)
                        if let next = nextOccurrence(course: course) {
                            nextRow(next)
                        }
                        hairline
                            .padding(.top, 18)
                        sectionRow(label: "上课地点", primary: course.location, secondary: course.note)
                        hairline
                        sectionRow(
                            label: "任课教师",
                            primary: course.teacher.isEmpty ? "未填写" : course.teacher,
                            secondary: course.department
                        )
                        hairline
                        scheduleSection(course: course, focusedID: meeting.id)
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

    private func titleBlock(course: Course, meeting: Meeting) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.courseBackground(course.colorID, scheme: scheme))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(ScheduleCopy.heroTag(kind: course.kind, weeks: course.weeks))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Text(course.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle(course: course, meeting: meeting))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(course: Course, meeting: Meeting) -> String {
        var parts = ["\(ScheduleCopy.weekdayName(meeting.weekday)) \(ScheduleCopy.periodSpan(meeting.startPeriod, meeting.endPeriod))"]
        if let clocks = ScheduleCopy.clocks(for: meeting, semester: model.document.semester) {
            parts.append(ScheduleCopy.timeRange(clocks.start, clocks.end))
        }
        if !course.location.isEmpty {
            parts.append(course.location)
        }
        return parts.joined(separator: " · ")
    }

    private func weekStrip(course: Course, focused: Meeting) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 + 1
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let dayMeeting = course.meetings.filter { $0.weekday == day }.sorted { $0.startPeriod < $1.startPeriod }.first
                let isActive = dayMeeting != nil
                let isFocused = dayMeeting?.id == focused.id
                Button {
                    if let dayMeeting {
                        focusedMeetingID = dayMeeting.id
                        Haptics.selection()
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text(ScheduleCopy.weekdayShort(day))
                            .font(.system(size: 12, weight: .semibold))
                        Text(dayMeeting.map { "\($0.startPeriod)–\($0.endPeriod)" } ?? " ")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(isActive ? ink : Theme.secondary.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isActive ? bg : Theme.elevated.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isFocused ? ink : (day == today ? Theme.secondary : Color.clear), lineWidth: isFocused ? 1.5 : 0.75)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isActive)
            }
        }
    }

    private func nextOccurrence(course: Course) -> Occurrence? {
        let now = Date()
        var best: Occurrence?
        for week in 1...model.document.semester.totalWeeks {
            for occ in model.occurrences(inWeek: week) where occ.courseID == course.id && occ.start > now {
                if best == nil || occ.start < best!.start {
                    best = occ
                }
            }
        }
        return best
    }

    private func nextRow(_ occ: Occurrence) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("下一次上课")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
            Text("\(ScheduleCopy.upcomingFootnote(from: Date(), to: occ.start, calendar: Calendar.current)) · \(occ.location)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
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

    private func scheduleSection(course: Course, focusedID: UUID) -> some View {
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
                scheduleRow(meeting: meeting, focused: meeting.id == focusedID, course: course)
            }
            Text(model.document.semester.name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
    }

    private func scheduleRow(meeting: Meeting, focused: Bool, course: Course) -> some View {
        let focusInk = Theme.courseInk(course.colorID, scheme: scheme)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(ScheduleCopy.weekdayName(meeting.weekday))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(focused ? focusInk : Theme.ink)
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
                    .foregroundStyle(focused ? focusInk : Theme.ink)
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
