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
                        heroCard(course: course, meeting: meeting)
                        weekStrip(course: course, focused: meeting)
                            .padding(.top, 14)
                        if let next = nextOccurrence(course: course) {
                            nextBanner(next, course: course)
                                .padding(.top, 12)
                        }
                        infoCard(course: course)
                            .padding(.top, 12)
                        scheduleCard(course: course, focusedID: meeting.id)
                            .padding(.top, 12)
                        reminderCard(course)
                            .padding(.top, 12)
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

    private func heroCard(course: Course, meeting: Meeting) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                heroChip(text: course.kind.isEmpty ? "课程" : course.kind, ink: ink)
                heroChip(text: ScheduleCopy.weekList(course.weeks), ink: ink)
                Spacer(minLength: 0)
            }
            Text(course.name)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(ink)
                .padding(.top, 12)
            Text(subtitle(course: course, meeting: meeting))
                .font(.system(size: 13.5))
                .foregroundStyle(ink.opacity(0.78))
                .padding(.top, 5)
            Rectangle().fill(ink.opacity(0.18)).frame(height: 0.5)
                .padding(.top, 14)
            HStack(spacing: 18) {
                heroFact(icon: "mappin.and.ellipse", text: course.location, ink: ink)
                heroFact(icon: "person.fill", text: course.teacher.isEmpty ? "未填写" : course.teacher, ink: ink)
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [bg, bg.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(ink.opacity(0.14))
                    .frame(width: 190, height: 190)
                    .blur(radius: 42)
                    .offset(x: 56, y: -64)
                Text(String(course.name.prefix(1)))
                    .font(.system(size: 118, weight: .heavy))
                    .foregroundStyle(ink.opacity(0.09))
                    .offset(x: 10, y: -18)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: bg.opacity(0.38), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .combine)
    }

    private func heroChip(text: String, ink: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(ink.opacity(0.16)))
    }

    private func heroFact(icon: String, text: String, ink: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(ink.opacity(0.92))
    }

    private func subtitle(course: Course, meeting: Meeting) -> String {
        var parts = ["\(ScheduleCopy.weekdayName(meeting.weekday)) \(ScheduleCopy.periodSpan(meeting.startPeriod, meeting.endPeriod))"]
        if let clocks = ScheduleCopy.clocks(for: meeting, semester: model.document.semester) {
            parts.append(ScheduleCopy.timeRange(clocks.start, clocks.end))
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
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isActive
                                ? AnyShapeStyle(LinearGradient(colors: [bg, bg.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Theme.elevated.opacity(0.5)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isFocused ? ink : (day == today ? Theme.secondary : Color.clear), lineWidth: isFocused ? 1.5 : 0.75)
                    )
                    .shadow(color: isActive ? bg.opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
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

    private func nextBanner(_ occ: Occurrence, course: Course) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(bg))
            VStack(alignment: .leading, spacing: 2) {
                Text("下一次上课")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                Text("\(ScheduleCopy.upcomingFootnote(from: Date(), to: occ.start, calendar: Calendar.current)) · \(occ.location)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(bg.opacity(scheme == .dark ? 0.26 : 0.13))
        )
        .accessibilityElement(children: .combine)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5)
    }

    private func infoCard(course: Course) -> some View {
        VStack(spacing: 0) {
            infoRow(
                icon: "mappin.and.ellipse",
                label: "上课地点",
                primary: course.location,
                secondary: course.note,
                course: course
            )
            hairline.padding(.leading, 58)
            infoRow(
                icon: "person.fill",
                label: "任课教师",
                primary: course.teacher.isEmpty ? "未填写" : course.teacher,
                secondary: course.department,
                course: course
            )
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.elevated)
        )
    }

    private func infoRow(icon: String, label: String, primary: String, secondary: String, course: Course) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(bg))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                Text(primary)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if !secondary.isEmpty {
                    Text(secondary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func scheduleCard(course: Course, focusedID: UUID) -> some View {
        let meetings = course.meetings.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            return $0.startPeriod < $1.startPeriod
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("课程安排")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text(ScheduleCopy.weekList(course.weeks))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                if index > 0 {
                    hairline.padding(.leading, 46)
                }
                scheduleRow(meeting: meeting, focused: meeting.id == focusedID, course: course)
            }
            Text(model.document.semester.name)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.elevated)
        )
    }

    private func scheduleRow(meeting: Meeting, focused: Bool, course: Course) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return HStack(spacing: 12) {
            Text(ScheduleCopy.weekdayShort(meeting.weekday))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [bg, bg.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                )
            VStack(alignment: .leading, spacing: 1) {
                if let clocks = ScheduleCopy.clocks(for: meeting, semester: model.document.semester) {
                    Text(ScheduleCopy.timeRange(clocks.start, clocks.end))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Text(ScheduleCopy.periodSpan(meeting.startPeriod, meeting.endPeriod))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            if focused {
                Text("当前")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(bg))
            }
            Text(parityText(meeting: meeting))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 9)
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.elevated)
        )
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
