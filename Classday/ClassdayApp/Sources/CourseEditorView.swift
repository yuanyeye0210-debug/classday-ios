import SwiftUI
import ClassdayCore

enum WeekPattern: String, CaseIterable, Identifiable {
    case all
    case odd
    case even
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全学期"
        case .odd: return "单周"
        case .even: return "双周"
        case .custom: return "自定义"
        }
    }

    static func detect(weeks: [Int], total: Int) -> WeekPattern {
        let all = Array(1...max(total, 1))
        if weeks == all { return .all }
        if weeks == all.filter({ $0 % 2 == 1 }) { return .odd }
        if weeks == all.filter({ $0 % 2 == 0 }) { return .even }
        return .custom
    }

    func weeks(total: Int) -> [Int]? {
        let all = Array(1...max(total, 1))
        switch self {
        case .all: return all
        case .odd: return all.filter { $0 % 2 == 1 }
        case .even: return all.filter { $0 % 2 == 0 }
        case .custom: return nil
        }
    }
}

struct CourseEditorView: View {
    var route: EditorRoute
    var document: StoreDocument
    var selectedDay: Date
    var calendar: Calendar

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Course
    @State private var pattern: WeekPattern
    @State private var errorText: String?
    @FocusState private var focused: Bool

    init(route: EditorRoute, document: StoreDocument, selectedDay: Date, calendar: Calendar) {
        self.route = route
        self.document = document
        self.selectedDay = selectedDay
        self.calendar = calendar
        let course = Self.initialCourse(route: route, document: document, selectedDay: selectedDay, calendar: calendar)
        _draft = State(initialValue: course)
        _pattern = State(initialValue: WeekPattern.detect(weeks: course.weeks, total: document.semester.totalWeeks))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isReschedule {
                        Text("把这节课调到新的星期和节次。若和别的课重叠，会停在原时间。")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                        meetingEditors
                    } else {
                        field("课程名称", text: $draft.name)
            field("中文名（可选，课程原名是英文时填这里）", text: Binding(
                get: { draft.nameZH ?? "" },
                set: { draft.nameZH = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ))
            field("英文名（可选，用于英文模式）", text: Binding(
                get: { draft.nameEN ?? "" },
                set: { draft.nameEN = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ))
                        kindPicker
                        field("任课教师", text: $draft.teacher)
                        field("上课地点", text: $draft.location)
                        field("院系", text: $draft.department)
                        field("备注", text: $draft.note)
                        Stepper(value: $draft.credits, in: 0...12, step: 0.5) {
                            Text("学分：\(draft.credits > 0 ? String(format: "%g", draft.credits) : "未填")")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.ink)
                        }
                        .accessibilityLabel("学分")
                        colorPicker
                        weekPicker
                        meetingEditors
                        reminderStepper
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("保存失败，\(errorText)")
                    }
                    PrimaryButton(title: isReschedule ? "确定调整" : "保存") { save() }
                    if case .edit = route {
                        Button("删除课程", role: .destructive) {
                            model.confirmDeleteCourseID = draft.id
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var title: String {
        switch route {
        case .newCourse: return "新建课程"
        case .edit: return "编辑课程"
        case .reschedule: return "调整时间"
        }
    }

    private var isReschedule: Bool {
        if case .reschedule = route { return true }
        return false
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            TextField(title, text: text)
                .focused($focused)
                .padding(12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var kindPicker: some View {
        Picker("课程性质", selection: $draft.kind) {
            Text("必修课").tag("必修课")
            Text("选修课").tag("选修课")
            Text("实践").tag("实践")
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("课程性质")
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("颜色")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                ForEach(CourseColors.all) { style in
                    Button {
                        draft.colorID = style.id
                    } label: {
                        Circle()
                            .fill(Color(style.backgroundLight))
                            .overlay(Circle().strokeBorder(draft.colorID == style.id ? Theme.accent : Color.clear, lineWidth: 2))
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(style.name)
                    .accessibilityAddTraits(draft.colorID == style.id ? .isSelected : [])
                }
            }
        }
    }

    private var weekPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("上课周")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            Picker("上课周", selection: $pattern) {
                ForEach(WeekPattern.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: pattern) { _, newValue in
                if let weeks = newValue.weeks(total: document.semester.totalWeeks) {
                    draft.weeks = weeks
                }
            }
            if pattern == .custom {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(1...document.semester.totalWeeks, id: \.self) { week in
                        let on = draft.weeks.contains(week)
                        Button {
                            if on {
                                draft.weeks.removeAll { $0 == week }
                            } else {
                                draft.weeks.append(week)
                                draft.weeks.sort()
                            }
                        } label: {
                            Text("\(week)")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundStyle(on ? Color.white : Theme.ink)
                                .background(on ? Theme.accent : Theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .accessibilityLabel("第 \(week) 周")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var meetingEditors: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isReschedule ? "新的时间" : "上课时间")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            ForEach(draft.meetings) { meeting in
                if isReschedule, meeting.id != rescheduleMeetingID { EmptyView() }
                else { meetingRow(meeting) }
            }
            if !isReschedule {
                Button("添加上课时间") {
                    let weekday = draft.meetings.last?.weekday ?? 1
                    draft.meetings.append(Meeting(id: UUID(), weekday: weekday, startPeriod: 1, endPeriod: 2))
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
    }

    private var rescheduleMeetingID: UUID? {
        if case let .reschedule(_, meetingID) = route { return meetingID }
        return nil
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("星期", selection: binding(for: meeting.id, keyPath: \.weekday)) {
                ForEach(1...7, id: \.self) { day in
                    Text(ScheduleCopy.weekdayName(day)).tag(day)
                }
            }
            .accessibilityLabel("星期")
            Stepper(value: binding(for: meeting.id, keyPath: \.startPeriod), in: 1...maxPeriod) {
                Text("开始 \(binding(for: meeting.id, keyPath: \.startPeriod).wrappedValue) 节")
            }
            Stepper(value: binding(for: meeting.id, keyPath: \.endPeriod), in: 1...maxPeriod) {
                Text("结束 \(binding(for: meeting.id, keyPath: \.endPeriod).wrappedValue) 节")
            }
            if draft.meetings.count > 1 && !isReschedule {
                Button("删除这节") {
                    draft.meetings.removeAll { $0.id == meeting.id }
                }
                .font(.footnote)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var reminderStepper: some View {
        Stepper(value: reminderBinding, in: 0...120) {
            Text(reminderBinding.wrappedValue == 0 ? "不提醒" : "提前 \(reminderBinding.wrappedValue) 分钟")
        }
        .accessibilityLabel("上课提醒")
    }

    private var reminderBinding: Binding<Int> {
        Binding(
            get: { draft.reminderLeadMinutes ?? document.semester.defaultReminderMinutes },
            set: { draft.reminderLeadMinutes = $0 }
        )
    }

    private var maxPeriod: Int {
        document.semester.periods.map(\.index).max() ?? 1
    }

    private func binding(for id: UUID, keyPath: WritableKeyPath<Meeting, Int>) -> Binding<Int> {
        Binding(
            get: { draft.meetings.first { $0.id == id }?[keyPath: keyPath] ?? 1 },
            set: { newValue in
                guard let index = draft.meetings.firstIndex(where: { $0.id == id }) else { return }
                draft.meetings[index][keyPath: keyPath] = newValue
                if draft.meetings[index].endPeriod < draft.meetings[index].startPeriod {
                    draft.meetings[index].endPeriod = draft.meetings[index].startPeriod
                }
            }
        )
    }

    private func save() {
        if !isReschedule && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorText = "请填写课程名称"
            return
        }
        if draft.weeks.isEmpty {
            errorText = "请至少选择一周"
            return
        }
        if let message = model.saveCourse(draft) {
            errorText = message
            Haptics.warning()
        } else {
            Haptics.success()
            dismiss()
        }
    }

    private static func initialCourse(route: EditorRoute, document: StoreDocument, selectedDay: Date, calendar: Calendar) -> Course {
        switch route {
        case .newCourse:
            let weekday = SemesterCalendar.isoWeekday(selectedDay, calendar: calendar)
            return Course(
                id: UUID(),
                name: "",
                teacher: "",
                location: "",
                colorID: "blue",
                weeks: Array(1...document.semester.totalWeeks),
                meetings: [Meeting(id: UUID(), weekday: weekday, startPeriod: 1, endPeriod: 2)]
            )
        case .edit(let id):
            return document.courses.first { $0.id == id } ?? initialCourse(route: .newCourse, document: document, selectedDay: selectedDay, calendar: calendar)
        case .reschedule(let courseID, _):
            return document.courses.first { $0.id == courseID } ?? initialCourse(route: .newCourse, document: document, selectedDay: selectedDay, calendar: calendar)
        }
    }
}
