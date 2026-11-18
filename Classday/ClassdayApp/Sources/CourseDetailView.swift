import SwiftUI
import PhotosUI
import Security
import UIKit
import ClassdayCore

private struct FinalScorePredictionSection: View {
    var scheme: GradeScheme
    @State private var finalID = ""
    @State private var targetText = "80"

    var body: some View {
        Section("期末成绩预测") {
            Picker("期末分项", selection: $finalID) {
                Text("请选择").tag("")
                ForEach(scheme.components) { component in Text(component.name).tag(component.id) }
            }
            TextField("目标总分（百分制 0–100）", text: $targetText).keyboardType(.decimalPad)
            Text("先录全参与计算的其他分项成绩；有多条算法时按最容易达到的一条算。不改成绩，已录入的期末分数也不计入。")
                .font(.footnote).foregroundStyle(.secondary)
            if !finalID.isEmpty {
                Text("及格（总分 60%）：\(answer(60))")
                if let target = Double(targetText), target.isFinite, (0...100).contains(target) {
                    Text("自定目标：\(answer(target))")
                } else { Text("目标请输入 0–100") }
            }
            Text("结果只按加权规则试算，不含学校另设的期末最低分、四舍五入或补考限制；及格线请按学校实际要求核对。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func answer(_ target: Double) -> String {
        let result = FinalScorePrediction.evaluate(scheme: scheme, finalComponentID: finalID, targetPercent: target)
        switch result.status {
        case .required:
            let score = ceil((result.minimum ?? 0) * 100) / 100
            return "期末至少考 \(String(format: "%.2f", score)) 分（满分 \(CourseDetailView.numberText(scheme.scale))，按 0.01 分向上取整）"
        case .alreadyReached: return "按当前规则，期末考 0 分也能达到这个目标"
        case .impossible: return "按当前规则，期末考满分也达不到这个目标"
        case .missingScores: return "请先录全参与计算的其他分项成绩（期末除外）"
        case .invalidRule: return "请检查满分、分项、成绩和每条算法的权重（同一条算法内按小数填，合计为 1，如 30% 写 0.3）"
        }
    }
}

struct CourseDetailView: View {
    var presentation: CoursePresentation
    var namespace: Namespace.ID
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedMeetingID: UUID?
    @State private var appeared = false
    @State private var showGradeEditor = false
    @State private var showRoomMap = false

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
                            showRoomMap = true
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
        .sheet(isPresented: $showRoomMap) {
            if let course { RoomMapPreview(location: course.location, pin: model.document.rooms.first { $0.name == course.location }) }
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
                Text(String(model.displayName(course).prefix(1)))
                    .font(.system(size: 116, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            Text(model.displayName(course))
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
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImageData: Data?
    @State private var aiBusy = false
    @State private var aiNote: String?
    @State private var showKeyField = false

    var body: some View {
        let course = model.course(courseID)
        NavigationStack {
            Form {
                aiSection
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
            Section {
                Picker("满分", selection: $scheme.scale) {
                    Text("20 分制").tag(20.0)
                    Text("100 分制").tag(100.0)
                }
                .pickerStyle(.segmented)
                LabeledContent("当前算法") {
                    Text(formulaSummary)
                        .font(.footnote)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("① 满分与算法")
            } footer: {
                Text("照着老师给的评分说明填就行：填评分项的名字、占比和得分，总成绩自动算出来。")
            }

            Section {
                ForEach(Array(scheme.components.enumerated()), id: \.element.id) { index, component in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            TextField("评分项名（如 期末考试）", text: nameBinding(index))
                            TextField("得分", value: scoreBinding(component.id), format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 66)
                            Text("/ \(CourseDetailView.numberText(scheme.scale))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) { deleteComponent(component.id) } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                        HStack(spacing: 6) {
                            Text("占比")
                            TextField("25", value: primaryWeightBinding(component.id), format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 54)
                            Text("%")
                            Spacer()
                            Text("最低分")
                            TextField("可不填", value: minimumBinding(component.id), format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                Button("添加评分项") { addComponent() }
            } header: {
                Text("② 评分项（占比 + 得分）")
            } footer: {
                Text("占比按老师的写法填：25 就是 25%。「最低分」只在规则里写了才填，比如期末至少 8 分才及格。")
            }

            Section {
                ForEach(Array(scheme.branches.enumerated()), id: \.offset) { branchIndex, branch in
                    DisclosureGroup {
                        ForEach(Array(branch.enumerated()), id: \.offset) { termIndex, term in
                            HStack(spacing: 10) {
                                Text(componentName(term.componentID))
                                Spacer()
                                TextField("权重", value: weightBinding(branch: branchIndex, term: termIndex), format: .number.precision(.fractionLength(0...3)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 64)
                                Button(role: .destructive) { scheme.branches[branchIndex].remove(at: termIndex) } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                            .font(.footnote)
                        }
                        Menu("把评分项加进这条方案") {
                            ForEach(scheme.components.filter { comp in !branch.contains { $0.componentID == comp.id } }) { comp in
                                Button(comp.name) { scheme.branches[branchIndex].append(GradeTerm(componentID: comp.id, weight: 0)) }
                            }
                        }
                        .font(.footnote)
                        if scheme.branches.count > 1 {
                            Button("删除这条方案", role: .destructive) { scheme.branches.remove(at: branchIndex) }
                                .font(.footnote)
                        }
                    } label: {
                        HStack {
                            Text("方案 \(branchIndex + 1)：\(branchSummary(branch))")
                                .font(.footnote)
                            Spacer()
                            if scheme.bestBranchIndex == branchIndex, let value = scheme.value(of: branch) {
                                Text(CourseDetailView.numberText(value))
                                    .font(.footnote.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                Button("再加一条方案（补考 / 期末替代期中）") { addBranch() }
            } header: {
                Text("③ 取高方案（可选）")
            } footer: {
                Text("只有老师允许「几种算法取最高」时才需要加。比如期中没考好，就用「期末 75% + 项目 25%」那条。多条方案时总成绩取最高的一条。")
            }

            Section {
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
                    Text("把任意一条方案里的评分项都填上分，这里就会算出总成绩。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(minimumWarnings, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("④ 结果")
            }

            FinalScorePredictionSection(scheme: scheme)

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

    // MARK: 记分规则辅助

    /// ① 里的占比直接写进第一条（默认）方案，避免「占比」和「权重」两处概念打架。
    private func primaryWeightBinding(_ componentID: String) -> Binding<Double> {
        Binding(
            get: {
                scheme.branches.first?.first { $0.componentID == componentID }?.weight ?? 0
            },
            set: { newValue in
                if scheme.branches.isEmpty { scheme.branches = [[]] }
                if let index = scheme.branches[0].firstIndex(where: { $0.componentID == componentID }) {
                    scheme.branches[0][index].weight = newValue / 100
                } else {
                    scheme.branches[0].append(GradeTerm(componentID: componentID, weight: newValue / 100))
                }
            }
        )
    }

    private func minimumBinding(_ componentID: String) -> Binding<Double?> {
        Binding(
            get: { scheme.minimums[componentID] },
            set: { scheme.minimums[componentID] = $0 }
        )
    }

    private var formulaSummary: String {
        guard let first = scheme.branches.first, !first.isEmpty else { return "还没设算法" }
        return branchSummary(first)
    }

    private func branchSummary(_ branch: [GradeTerm]) -> String {
        let parts = branch
            .filter { $0.weight > 0 }
            .sorted { $0.weight > $1.weight }
            .map { term in
                "\(Int((term.weight * 100).rounded()))% \(componentName(term.componentID))"
            }
        return parts.isEmpty ? "还没填占比" : parts.joined(separator: " + ")
    }

    /// 分项低于最低分要求时的提醒（例如期末没到 8 分直接不合格）。
    private var minimumWarnings: [String] {
        scheme.components.compactMap { component in
            guard let min = scheme.minimums[component.id],
                  let score = scheme.scores[component.id],
                  score < min else { return nil }
            return "\(component.name) 只有 \(CourseDetailView.numberText(score)) 分，低于最低要求 \(CourseDetailView.numberText(min)) 分"
        }
    }

    // MARK: 草稿操作

    // MARK: AI 识别记分规则（识别只填草稿，核对后保存才生效）

    @ViewBuilder
    private var aiSection: some View {
        Section {
            if let pickedImageData, let uiImage = UIImage(data: pickedImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(pickedImageData == nil ? "选择规则图片" : "换一张图片", systemImage: "photo.on.rectangle.angled")
            }
                        Button {
                runRecognition()
            } label: {
                if aiBusy {
                    HStack { ProgressView(); Text("识别中…") }
                } else {
                    Label("AI 识别并填入草稿", systemImage: "sparkles")
                }
            }
            .disabled(pickedImageData == nil || aiBusy)
            if let aiNote {
                Text(aiNote).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("AI 识别记分规则")
        } footer: {
            Text("上传评分公式的截图或照片（比如老师发的评分说明），AI 会把满分、分项和候选算法填成下面的草稿；识别只填草稿，核对无误后点保存才生效。")
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    pickedImageData = GradeImagePrep.preparedJPEG(data) ?? data
                }
            }
        }
    }

    private func runRecognition() {
        guard let data = pickedImageData else { return }
        guard let key = GradeAIKeyStore.load(), !key.isEmpty else {
            aiNote = "识别暂不可用，请稍后重试。"
            return
        }
        aiBusy = true
        aiNote = nil
        Task {
            do {
                let recognized = try await GradeRuleRecognizer.recognize(jpegData: data, apiKey: key)
                var merged = recognized
                if useScheme {
                    let oldIDByName = Dictionary(uniqueKeysWithValues: scheme.components.map { ($0.name, $0.id) })
                    for comp in merged.components {
                        if let oldID = oldIDByName[comp.name], let score = scheme.scores[oldID] {
                            merged.scores[comp.id] = score
                        }
                    }
                }
                scheme = merged
                useScheme = true
                aiNote = "已按图片识别填好草稿：满分 \(CourseDetailView.numberText(merged.scale)) 分制、\(merged.components.count) 个分项、\(merged.branches.count) 条候选算法。请逐项核对，确认无误后点保存。"
            } catch {
                aiNote = (error as? LocalizedError)?.errorDescription ?? "识别失败，请换一张更清晰的图片再试。"
            }
            aiBusy = false
        }
    }

    private func startScheme() {
        if scheme.components.isEmpty {
            let project = GradeComponent(name: "小组项目")
            let midterm = GradeComponent(name: "期中测验")
            let exam = GradeComponent(name: "期末考试")
            scheme = GradeScheme(
                scale: 100,
                components: [project, midterm, exam],
                scores: [:],
                branches: [[
                    GradeTerm(componentID: project.id, weight: 0.25),
                    GradeTerm(componentID: midterm.id, weight: 0.25),
                    GradeTerm(componentID: exam.id, weight: 0.50)
                ]]
            )
        }
        useScheme = true
    }

    private func addComponent() {
        let component = GradeComponent(name: "评分项\(scheme.components.count + 1)")
        scheme.components.append(component)
        if scheme.branches.isEmpty { scheme.branches = [[]] }
        scheme.branches[0].append(GradeTerm(componentID: component.id, weight: 0))
    }

    private func deleteComponent(_ id: String) {
        scheme.components.removeAll { $0.id == id }
        scheme.scores[id] = nil
        scheme.minimums[id] = nil
        for index in scheme.branches.indices {
            scheme.branches[index].removeAll { $0.componentID == id }
        }
    }

    private func addBranch() {
        // 新方案默认照抄第一条，只改需要变的那几项（例如期末 75%、项目 25%）
        scheme.branches.append(scheme.branches.first ?? [])
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


// MARK: - 记分规则 AI 识别（Gemini 视觉；密钥内置在构建里，界面不暴露）

enum GradeAIKeyStore {
    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.classday.app",
         kSecAttrAccount as String: "gemini-grade-key"]
    }

    /// 构建内置密钥（Info.plist: ClassdayGradeAIKey）。界面不暴露，用户无需填写。
    private static var bundled: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ClassdayGradeAIKey") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        // 用户没填过（或填了空串）时用内置密钥，保证开箱即用。
        return bundled
    }

    static func save(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

enum GradeImagePrep {
    /// 识别前把图片压到长边 1568 以内并转 JPEG，控制上传体积。
    static func preparedJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1568
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image.jpegData(compressionQuality: 0.85) }
        let ratio = maxSide / longest
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let resized = UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

enum GradeRuleRecognizer {
    enum Failure: LocalizedError {
        case unparsable

        var errorDescription: String? {
            switch self {
            case .unparsable:
                return "没能从这张图里读出记分规则，换一张更清晰、只含公式的图片再试。"
            }
        }
    }

    static func recognize(jpegData: Data, apiKey: String) async throws -> GradeScheme {
        let prompt = """
        你是课程成绩记分规则识别器。仔细读图中的总成绩计算规则（可能有公式、权重、取最高/max、两次考试机会、补考等），只输出一个 JSON 对象，不要输出任何其他文字。格式：
        {"scale": 满分数字, "components": ["分项代号", ...], "branches": [[{"component": "分项代号", "weight": 小数权重}, ...], ...]}
        规则：
        - scale 是总成绩满分：葡萄牙 0–20 分制填 20，百分制填 100，按图中说明判断。
        - components 是所有分项的代号，保留图中原文（如 P、TEST60、EX1、EX2、平时成绩、期末考试）。
        - branches 是候选算法：普通加权平均只有一条；出现 max、取最高、或、补考替代等结构时，每种算法一条，总成绩最终取各条的最高值。
        - weight 用 0 到 1 的小数（25% 写 0.25），同一条内权重之和应为 1。
        - 分项代号必须与 components 里完全一致。
        """
        let text = try await GeminiClient.recognizeImage(jpegData: jpegData, prompt: prompt, apiKey: apiKey)
        guard let result = AIRecognition.parse(text, source: .grade),
              case .grade(let scheme) = result.payload else { throw Failure.unparsable }
        return scheme
    }
}
