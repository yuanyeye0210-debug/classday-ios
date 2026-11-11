import SwiftUI
import ClassdayCore

struct CourseDetailView: View {
    var presentation: CoursePresentation
    var namespace: Namespace.ID
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedMeetingID: UUID?
    @State private var appeared = false
    @State private var showGradeEditor = false

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
                        visualHero(course: course, meeting: meeting)
                            .staggerIn(index: 0, on: appeared)
                        if nextOccurrence(course: course) != nil {
                            bigFact(course: course)
                                .staggerIn(index: 1, on: appeared)
                                .padding(.top, 20)
                        }
                        weekStrip(course: course, focused: meeting)
                            .staggerIn(index: 2, on: appeared)
                            .padding(.top, 18)
                        infoSticker(
                            icon: "mappin.and.ellipse",
                            label: "上课地点",
                            primary: course.location,
                            secondary: course.note,
                            course: course
                        )
                        .staggerIn(index: 3, on: appeared)
                        .padding(.top, 12)
                        infoSticker(
                            icon: "person.fill",
                            label: "任课教师",
                            primary: course.teacher.isEmpty ? "未填写" : course.teacher,
                            secondary: course.department,
                            course: course
                        )
                        .staggerIn(index: 4, on: appeared)
                        .padding(.top, 10)
                        scheduleCard(course: course, focusedID: meeting.id)
                            .staggerIn(index: 5, on: appeared)
                            .padding(.top, 10)
                        gradeCard(course)
                            .staggerIn(index: 6, on: appeared)
                            .padding(.top, 10)
                        reminderCard(course)
                            .staggerIn(index: 7, on: appeared)
                            .padding(.top, 10)
                        PrimaryButton(title: "编辑课程") {
                            model.editor = .edit(course.id)
                        }
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .onAppear { appeared = true }
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
        .sheet(isPresented: $showGradeEditor) {
            GradeEditorView(courseID: presentation.courseID)
        }
    }

    private func gradeCard(_ course: Course) -> some View {
        let bar = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(bar)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(ink)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("成绩")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                if let scheme = course.gradeScheme, let final = scheme.finalGrade, let normalized = scheme.normalizedFinal {
                    Text("\(Self.numberText(final)) / \(Self.numberText(scheme.scale)) 分 · 绩点 \(String(format: "%.1f", AppModel.gradePoint(for: normalized))) · \(Self.creditsText(course.credits))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                } else if course.gradeScheme != nil {
                    Text("已设计分规则 · 还差分项成绩 · \(Self.creditsText(course.credits))")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                } else if let grade = course.grade {
                    Text("\(Self.numberText(grade)) 分 · 绩点 \(String(format: "%.1f", AppModel.gradePoint(for: grade))) · \(Self.creditsText(course.credits))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                } else {
                    Text("还没录入 · \(Self.creditsText(course.credits))")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(course.grade == nil ? "录入" : "修改") { showGradeEditor = true }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(bar))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.elevated)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 10, x: 0, y: 4)
    }

    static func numberText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    static func creditsText(_ credits: Double) -> String {
        credits > 0 ? "\(numberText(credits)) 学分" : "未填学分"
    }

    private func visualHero(course: Course, meeting: Meeting) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [bg, bg.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.white.opacity(scheme == .dark ? 0.06 : 0.45))
                    .frame(width: 170, height: 170)
                    .offset(x: -115, y: -85)
                Circle()
                    .fill(Color.white.opacity(scheme == .dark ? 0.04 : 0.3))
                    .frame(width: 110, height: 110)
                    .offset(x: 135, y: 65)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ink.opacity(0.45))
                    .offset(x: -118, y: 42)
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ink.opacity(0.35))
                    .offset(x: 120, y: -54)
                Text(String(course.name.prefix(1)))
                    .font(.system(size: 116, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            Text(course.name)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.top, 16)
            HStack(spacing: 8) {
                sticker(text: course.kind.isEmpty ? "课程" : course.kind, bg: bg, ink: ink, rotation: -2)
                sticker(text: ScheduleCopy.weekList(course.weeks), bg: Theme.elevated, ink: Theme.ink, rotation: 1.5)
                sticker(text: subtitle(course: course, meeting: meeting), bg: Theme.elevated, ink: Theme.ink, rotation: -1)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func sticker(text: String, bg: Color, ink: Color, rotation: Double) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(bg))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 6, x: 0, y: 3)
            .rotationEffect(.degrees(rotation))
    }

    private func subtitle(course: Course, meeting: Meeting) -> String {
        var parts = ["\(ScheduleCopy.weekdayName(meeting.weekday)) \(ScheduleCopy.periodSpan(meeting.startPeriod, meeting.endPeriod))"]
        if let clocks = ScheduleCopy.clocks(for: meeting, semester: model.document.semester) {
            parts.append(ScheduleCopy.timeRange(clocks.start, clocks.end))
        }
        return parts.joined(separator: " · ")
    }

    private func bigFact(course: Course) -> some View {
        guard let occ = nextOccurrence(course: course) else {
            return AnyView(EmptyView())
        }
        let cal = Calendar.current
        let dayWord = cal.isDateInToday(occ.start) ? "今天" : (cal.isDateInTomorrow(occ.start) ? "明天" : ScheduleCopy.weekdayName(occ.weekday))
        return AnyView(
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下一次上课 · \(dayWord)")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                    Text(ScheduleCopy.hhmm(occ.start, calendar: cal))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("\(ScheduleCopy.periodSpan(occ.startPeriod, occ.endPeriod)) · \(occ.location)")
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                progressRing()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        )
    }

    private func progressRing() -> some View {
        let total = max(model.document.semester.totalWeeks, 1)
        let raw = SemesterCalendar.weekIndex(for: Date(), semester: model.document.semester, calendar: Calendar.current) ?? model.weekIndex
        let current = min(max(raw, 1), total)
        return VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(current) / CGFloat(total))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(current)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("周")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 56, height: 56)
            Text("学期进度")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func weekStrip(course: Course, focused: Meeting) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return HStack(spacing: 7) {
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
                    VStack(spacing: 2) {
                        Text(ScheduleCopy.weekdayShort(day))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text(dayMeeting.map { "\($0.startPeriod)–\($0.endPeriod)" } ?? "·")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isActive ? ink : Theme.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isActive ? bg : Theme.elevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isFocused ? ink : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PressScaleStyle())
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

    private var hairline: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5)
    }

    private func infoSticker(icon: String, label: String, primary: String, secondary: String, course: Course) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: 46, height: 46)
                .background(Circle().fill(bg))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                Text(primary)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                if !secondary.isEmpty {
                    Text(secondary)
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.elevated)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 14, x: 0, y: 6)
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
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(ScheduleCopy.weekList(course.weeks))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                if index > 0 {
                    hairline.padding(.leading, 48)
                }
                scheduleRow(meeting: meeting, focused: meeting.id == focusedID, course: course)
            }
            Text(model.document.semester.name)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.elevated)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 14, x: 0, y: 6)
    }

    private func scheduleRow(meeting: Meeting, focused: Bool, course: Course) -> some View {
        let bg = Theme.courseBackground(course.colorID, scheme: scheme)
        let ink = Theme.courseInk(course.colorID, scheme: scheme)
        return HStack(spacing: 12) {
            Text(ScheduleCopy.weekdayShort(meeting.weekday))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(bg)
                )
            VStack(alignment: .leading, spacing: 1) {
                if let clocks = ScheduleCopy.clocks(for: meeting, semester: model.document.semester) {
                    Text(ScheduleCopy.timeRange(clocks.start, clocks.end))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                }
                Text(ScheduleCopy.periodSpan(meeting.startPeriod, meeting.endPeriod))
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            if focused {
                Text("当前")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(bg))
            }
            Text(parityText(meeting: meeting))
                .font(.system(size: 12, design: .rounded))
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.elevated)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 14, x: 0, y: 6)
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

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

private extension View {
    func staggerIn(index: Int, on: Bool) -> some View {
        opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 16)
            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.05), value: on)
    }
}

struct GradeEditorView: View {
    var courseID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var gradeText: String = ""
    @State private var loaded = false
    @State private var useScheme = false
    @State private var scheme = GradeScheme()

    var body: some View {
        let course = model.course(courseID)
        NavigationStack {
            Form {
                if useScheme {
                    schemeSections
                } else {
                    simpleSections(course: course)
                }
            }
            .navigationTitle(course?.name ?? "成绩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save(course: course) }
                        .disabled(!useScheme && parsed == nil)
                }
            }
            .onAppear {
                if !loaded {
                    loaded = true
                    if let course {
                        if let existing = course.gradeScheme {
                            scheme = existing
                            useScheme = true
                        }
                        if let grade = course.grade {
                            gradeText = CourseDetailView.numberText(grade)
                        }
                    }
                }
            }
        }
    }

    // MARK: 直接填总分（无规则）

    @ViewBuilder
    private func simpleSections(course: Course?) -> some View {
        Section("成绩（0–100）") {
            TextField("如 92", text: $gradeText)
                .keyboardType(.decimalPad)
            if let value = parsed, let course {
                LabeledContent("绩点") {
                    Text(String(format: "%.1f", AppModel.gradePoint(for: value)))
                }
                LabeledContent("学分") {
                    Text(CourseDetailView.creditsText(course.credits))
                }
            }
        }
        Section {
            Button("设置记分规则") { startScheme() }
        } footer: {
            Text("这门课有自己的算法（分项按权重算、两次考试取高之类）时，在这里设规则；之后只录分项成绩，总成绩自动算。")
        }
        if course?.grade != nil {
            Section {
                Button("清除成绩", role: .destructive) {
                    model.setCourseGrade(courseID, grade: nil)
                    dismiss()
                }
            }
        }
    }

    // MARK: 记分规则

    private var schemeSections: some View {
        Group {
            Section("满分标准") {
                Picker("满分", selection: $scheme.scale) {
                    Text("20 分制").tag(20.0)
                    Text("100 分制").tag(100.0)
                }
                .pickerStyle(.segmented)
            }
            Section("分项成绩") {
                ForEach(Array(scheme.components.enumerated()), id: \.element.id) { index, component in
                    HStack(spacing: 10) {
                        TextField("分项名", text: nameBinding(index))
                        TextField("成绩", value: scoreBinding(component.id), format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Text("/ \(CourseDetailView.numberText(scheme.scale))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) { deleteComponent(component.id) } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
                Button("添加分项") { addComponent() }
            }
            ForEach(Array(scheme.branches.enumerated()), id: \.offset) { branchIndex, branch in
                Section {
                    ForEach(Array(branch.enumerated()), id: \.offset) { termIndex, term in
                        HStack(spacing: 10) {
                            Text(componentName(term.componentID))
                            Spacer()
                            Text("×")
                                .foregroundStyle(.secondary)
                            TextField("权重", value: weightBinding(branch: branchIndex, term: termIndex), format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Button(role: .destructive) { scheme.branches[branchIndex].remove(at: termIndex) } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                    Menu("添加分项到本算法") {
                        ForEach(scheme.components.filter { comp in !branch.contains { $0.componentID == comp.id } }) { comp in
                            Button(comp.name) { scheme.branches[branchIndex].append(GradeTerm(componentID: comp.id, weight: 0)) }
                        }
                    }
                    Button("删除这条算法", role: .destructive) { scheme.branches.remove(at: branchIndex) }
                } header: {
                    HStack {
                        Text("候选算法 \(branchIndex + 1)")
                        Spacer()
                        if scheme.bestBranchIndex == branchIndex {
                            Text("取这条")
                                .font(.caption.weight(.bold))
                        }
                        if let value = scheme.value(of: branch) {
                            Text(CourseDetailView.numberText(value))
                                .fontWeight(.bold)
                        }
                    }
                } footer: {
                    let sum = branch.reduce(0) { $0 + $1.weight }
                    Text("权重合计 \(CourseDetailView.numberText(sum))\(abs(sum - 1) > 0.001 ? "（不等于 1，请确认这门课的算法）" : "")")
                }
            }
            Section {
                Button("添加候选算法") { addBranch() }
            } footer: {
                Text("多条算法时总成绩取最高的一条——比如第一次考试和补考哪条高取哪条。")
            }
            Section("总成绩") {
                if let final = scheme.finalGrade, let normalized = scheme.normalizedFinal {
                    LabeledContent("总成绩") {
                        Text("\(CourseDetailView.numberText(final)) / \(CourseDetailView.numberText(scheme.scale))")
                            .fontWeight(.bold)
                    }
                    LabeledContent("折合百分制") {
                        Text(CourseDetailView.numberText(normalized))
                    }
                    LabeledContent("绩点") {
                        Text(String(format: "%.1f", AppModel.gradePoint(for: normalized)))
                    }
                } else {
                    Text("把任意一条候选算法里的分项都填上，这里就会算出总成绩。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("移除记分规则", role: .destructive) {
                    if let normalized = scheme.normalizedFinal {
                        gradeText = CourseDetailView.numberText(normalized)
                    }
                    useScheme = false
                }
            } footer: {
                Text("移除后回到直接填总分；已算出的总成绩会保留在直接录入的输入框里。")
            }
        }
    }

    // MARK: 草稿操作

    private func startScheme() {
        if scheme.components.isEmpty {
            let exam = GradeComponent(name: "期末考试")
            scheme = GradeScheme(scale: 100, components: [exam], scores: [:], branches: [[GradeTerm(componentID: exam.id, weight: 1.0)]])
        }
        useScheme = true
    }

    private func addComponent() {
        scheme.components.append(GradeComponent(name: "分项\(scheme.components.count + 1)"))
    }

    private func deleteComponent(_ id: String) {
        scheme.components.removeAll { $0.id == id }
        scheme.scores[id] = nil
        for index in scheme.branches.indices {
            scheme.branches[index].removeAll { $0.componentID == id }
        }
    }

    private func addBranch() {
        if let first = scheme.components.first {
            scheme.branches.append([GradeTerm(componentID: first.id, weight: 1.0)])
        } else {
            scheme.branches.append([])
        }
    }

    private func componentName(_ id: String) -> String {
        scheme.components.first { $0.id == id }?.name ?? "（已删除的分项）"
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { scheme.components[index].name },
            set: { scheme.components[index].name = $0 }
        )
    }

    private func scoreBinding(_ id: String) -> Binding<Double?> {
        Binding(
            get: { scheme.scores[id] },
            set: { scheme.scores[id] = $0 }
        )
    }

    private func weightBinding(branch: Int, term: Int) -> Binding<Double> {
        Binding(
            get: { scheme.branches[branch][term].weight },
            set: { scheme.branches[branch][term].weight = $0 }
        )
    }

    private func save(course: Course?) {
        if useScheme {
            var cleaned = scheme
            cleaned.components = cleaned.components.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            let validIDs = Set(cleaned.components.map(\.id))
            cleaned.scores = cleaned.scores.filter { validIDs.contains($0.key) }
            for key in Array(cleaned.scores.keys) {
                cleaned.scores[key] = min(max(cleaned.scores[key] ?? 0, 0), cleaned.scale)
            }
            for index in cleaned.branches.indices {
                cleaned.branches[index] = cleaned.branches[index].filter { validIDs.contains($0.componentID) }
            }
            model.setCourseGradeScheme(courseID, scheme: cleaned)
        } else {
            if course?.gradeScheme != nil {
                model.setCourseGradeScheme(courseID, scheme: nil)
            }
            if let value = parsed {
                model.setCourseGrade(courseID, grade: value)
            }
        }
        dismiss()
    }

    private var parsed: Double? {
        guard let value = Double(gradeText), (0...100).contains(value) else { return nil }
        return value
    }
}
