import SwiftUI
import PhotosUI
import Vision
import UniformTypeIdentifiers
import CoreFoundation
import ClassdayCore

/// Smart import: photos, CSV files and pasted text are parsed into editable
/// drafts first. Nothing reaches the timetable until the user confirms.
struct SmartImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [ImportedCourseDraft] = []
    @State private var excluded: Set<UUID> = []
    @State private var unparsed: [String] = []
    @State private var sourceName = ""
    @State private var editingID: UUID?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var pasteText = ""
    @State private var analyzing = false

    private static let sampleCSV = """
    课程名称,星期,开始时间,结束时间,教室,教师,周次
    高等数学,周一,08:00,09:40,教学楼A301,陈老师,1-16周
    高等数学,周三,10:10,11:50,教学楼A301,陈老师,1-16周
    程序设计,周一,14:00,15:40,,周老师,1-16周
    程序设计,周五,14:00,15:40,实验楼机房3,周老师,1-16周
    大学英语,周四,08:00,09:40,教学楼B205,林老师,1-16周
    """

    var body: some View {
        NavigationStack {
            List {
                sourceSection
                if !drafts.isEmpty { confirmSection }
                if !unparsed.isEmpty { unparsedSection }
            }
            .navigationTitle("智能导入课表")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !drafts.isEmpty {
                    Button {
                        importSelected()
                    } label: {
                        Text("导入选中的 \(selectedCount) 门课")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCount == 0)
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
            .onAppear {
                if model.smartImportSample, drafts.isEmpty {
                    load(text: Self.sampleCSV, source: "示例课表.csv", isCSV: true)
                }
            }
            .onChange(of: pickerItem) { _, item in
                Task { await recognize(item) }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                if case let .success(url) = result { readFile(url) }
            }
            .sheet(item: editingBinding) { draft in
                DraftEditorView(draft: binding(for: draft.id))
            }
        }
    }

    // MARK: sections

    private var sourceSection: some View {
        Section("选择来源") {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("课表图片（截图或照片）", systemImage: "photo.on.rectangle.angled")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("CSV / 表格文件", systemImage: "tablecells")
            }
            TextEditor(text: $pasteText)
                .frame(minHeight: 84)
            Button {
                load(text: pasteText, source: "粘贴的文本", isCSV: pasteText.contains(",") || pasteText.contains(";") || pasteText.contains("\t"))
            } label: {
                Label("解析粘贴的文本", systemImage: "text.viewfinder")
            }
            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if analyzing {
                HStack { ProgressView(); Text("正在识别…").foregroundStyle(.secondary) }
            }
            if !sourceName.isEmpty {
                Text("来源：\(sourceName)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var confirmSection: some View {
        Section("确认识别结果（点开可改）") {
            ForEach(drafts) { draft in
                DraftCard(draft: draft,
                          included: !excluded.contains(draft.id),
                          duplicate: model.document.courses.contains { $0.name == draft.name && !draft.name.isEmpty },
                          onToggle: {
                              if excluded.contains(draft.id) { excluded.remove(draft.id) } else { excluded.insert(draft.id) }
                          },
                          onEdit: { editingID = draft.id })
            }
        }
    }

    private var unparsedSection: some View {
        Section("没认出的内容（不会导入）") {
            ForEach(unparsed, id: \.self) { line in
                Text(line).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: loading sources

    private func load(text: String, source: String, isCSV: Bool) {
        let result = isCSV ? ScheduleTextImporter.parseCSV(text) : ScheduleTextImporter.parseText(text)
        drafts = result.drafts
        unparsed = result.unparsed
        excluded = []
        sourceName = source
        if result.drafts.isEmpty {
            model.banner = "没有认出课程，换一份试试"
        }
    }

    private func readFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let text = Self.decode(data)
        load(text: text, source: url.lastPathComponent, isCSV: true)
    }

    static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gb18030) { return text }
        return String(data: data, encoding: .utf16) ?? ""
    }

    private func recognize(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        analyzing = true
        defer { analyzing = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data), let cgImage = image.cgImage else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let observations = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        load(text: text, source: "课表图片", isCSV: false)
    }

    // MARK: import

    private var selectedCount: Int {
        drafts.filter { !excluded.contains($0.id) && !$0.name.isEmpty }.count
    }

    private var editingBinding: Binding<ImportedCourseDraft?> {
        Binding(
            get: {
                guard let editingID, let index = drafts.firstIndex(where: { $0.id == editingID }) else { return nil }
                return drafts[index]
            },
            set: { newValue in
                if newValue == nil { editingID = nil }
            }
        )
    }

    private func binding(for id: UUID) -> Binding<ImportedCourseDraft> {
        Binding(
            get: { drafts.first { $0.id == id } ?? ImportedCourseDraft(name: "", meetings: []) },
            set: { newValue in
                if let index = drafts.firstIndex(where: { $0.id == id }) { drafts[index] = newValue }
            }
        )
    }

    private func importSelected() {
        let (courses, parities) = buildCourses()
        guard !courses.isEmpty else {
            model.banner = "选中的课程还缺名称或时间，先点开补上"
            return
        }
        model.importCalendar(ImportedCalendar(courses: courses, exams: [], homework: [], warnings: []))
        model.applyImportedParities(parities)
        dismiss()
    }

    private func buildCourses() -> (courses: [Course], parities: [(meetingID: UUID, parity: WeekParity)]) {
        let periods = model.document.semester.periods
        let totalWeeks = model.document.semester.totalWeeks
        let palette = ["blue", "orange", "purple", "green", "pink", "sage"]
        var built: [Course] = []
        var parities: [(meetingID: UUID, parity: WeekParity)] = []
        for (offset, draft) in drafts.enumerated() {
            guard !excluded.contains(draft.id), !draft.name.isEmpty else { continue }
            var weekSet = Set<Int>()
            if !draft.customWeeks.isEmpty {
                weekSet = Set(draft.customWeeks)
            } else {
                for meeting in draft.meetings {
                    for week in draft.firstWeek...max(draft.firstWeek, draft.lastWeek) {
                        if meeting.parity == 0 || (meeting.parity == 1 ? week % 2 == 1 : week % 2 == 0) {
                            weekSet.insert(week)
                        }
                    }
                }
            }
            var weeks = weekSet.filter { $0 <= totalWeeks }.sorted()
            if weeks.isEmpty { weeks = Array(1...totalWeeks) }
            var meetings: [Meeting] = []
            for meeting in draft.meetings where (1...7).contains(meeting.weekday) {
                guard let span = periodSpan(for: meeting, periods: periods) else { continue }
                let created = Meeting(id: UUID(), weekday: meeting.weekday, startPeriod: span.0, endPeriod: span.1)
                meetings.append(created)
                if meeting.parity == 1 { parities.append((created.id, .odd)) }
                if meeting.parity == 2 { parities.append((created.id, .even)) }
            }
            guard !meetings.isEmpty else { continue }
            built.append(Course(
                id: UUID(), name: draft.name, teacher: draft.teacher, location: draft.location,
                colorID: palette[offset % palette.count], weeks: weeks, meetings: meetings))
        }
        return (built, parities)
    }

    private func periodSpan(for meeting: ImportedMeetingDraft, periods: [PeriodTemplate]) -> (Int, Int)? {
        if let start = meeting.startPeriod {
            return (start, max(start, meeting.endPeriod ?? start))
        }
        guard let startMinutes = meeting.startMinutes, !periods.isEmpty else { return nil }
        let starts = periods.map { Self.minutes(of: $0.start) }
        var startIndex = 0
        for (index, start) in starts.enumerated() where start <= startMinutes { startIndex = index }
        let endMinutes = meeting.endMinutes ?? startMinutes + 95
        var endIndex = startIndex
        for (index, start) in starts.enumerated() where start < endMinutes { endIndex = index }
        return (periods[startIndex].index, periods[max(startIndex, endIndex)].index)
    }

    static func minutes(of clock: String) -> Int {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return 0 }
        return hour * 60 + minute
    }
}

private struct DraftCard: View {
    var draft: ImportedCourseDraft
    var included: Bool
    var duplicate: Bool
    var onToggle: () -> Void
    var onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Text(String(draft.name.first ?? "课"))
                    .font(.headline)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(draft.name.isEmpty ? "课程名待补" : draft.name).font(.headline)
                    if duplicate {
                        badge("已有同名课", color: .orange)
                    }
                    ForEach(draft.issues, id: \.self) { issue in
                        badge(issue, color: .orange)
                    }
                }
                ForEach(draft.meetings) { meeting in
                    Text(meetingLine(meeting)).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(weeksLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onToggle) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(included ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .opacity(included ? 1 : 0.4)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private func meetingLine(_ meeting: ImportedMeetingDraft) -> String {
        let day = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let weekday = (0...7).contains(meeting.weekday) ? day[meeting.weekday] : "星期待选"
        var time = "时间待补"
        if let start = meeting.startMinutes {
            time = "\(Self.clock(start))–\(Self.clock(meeting.endMinutes ?? start + 95))"
        } else if let start = meeting.startPeriod {
            time = "第 \(start)–\(meeting.endPeriod ?? start) 节"
        }
        let location = meeting.location.isEmpty ? draft.location : meeting.location
        let parity = meeting.parity == 1 ? "单周" : meeting.parity == 2 ? "双周" : ""
        return [weekday, time, location, parity].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var weeksLine: String {
        let teacher = draft.teacher.isEmpty ? "" : " · \(draft.teacher)"
        if !draft.customWeeks.isEmpty {
            let list = draft.customWeeks.sorted().map(String.init).joined(separator: "、")
            return "第 \(list) 周（自定义）\(teacher)"
        }
        return "第 \(draft.firstWeek)–\(draft.lastWeek) 周\(teacher)"
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

private struct DraftEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: ImportedCourseDraft
    @State private var customMode: Bool?

    private var isCustom: Binding<Bool> {
        Binding(get: { customMode ?? !draft.customWeeks.isEmpty }, set: { customMode = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程") {
                    TextField("课程名称", text: $draft.name)
                    TextField("老师", text: $draft.teacher)
                    TextField("默认教室", text: $draft.location)
                }
                Section("上课周") {
                    Picker("方式", selection: isCustom) {
                        Text("按周范围").tag(false)
                        Text("自定义周").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isCustom.wrappedValue) { _, custom in
                        if custom, draft.customWeeks.isEmpty {
                            draft.customWeeks = Array(draft.firstWeek...max(draft.firstWeek, draft.lastWeek))
                        }
                        if !custom { draft.customWeeks = [] }
                    }
                    if isCustom.wrappedValue {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(1...max(1, model.document.semester.totalWeeks), id: \.self) { week in
                                Button("\(week)") {
                                    if draft.customWeeks.contains(week) {
                                        draft.customWeeks.removeAll { $0 == week }
                                    } else {
                                        draft.customWeeks.append(week)
                                        draft.customWeeks.sort()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(draft.customWeeks.contains(week) ? .accentColor : .secondary)
                            }
                        }
                        Text("点选这门课真正上课的周，其余周不上。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Stepper("起始周：第 \(draft.firstWeek) 周", value: $draft.firstWeek, in: 1...30)
                        Stepper("结束周：第 \(draft.lastWeek) 周", value: $draft.lastWeek, in: 1...30)
                    }
                }
                ForEach($draft.meetings) { $meeting in
                    Section("上课安排（各自独立）") {
                        HStack(spacing: 6) {
                            ForEach(1...7, id: \.self) { day in
                                Button(["一", "二", "三", "四", "五", "六", "日"][day - 1]) {
                                    meeting.weekday = day
                                    normalize(&meeting)
                                }
                                .buttonStyle(.bordered)
                                .tint(meeting.weekday == day ? .accentColor : .secondary)
                            }
                        }
                        DatePicker("开始", selection: timeBinding($meeting, isStart: true), displayedComponents: .hourAndMinute)
                        DatePicker("结束", selection: timeBinding($meeting, isStart: false), displayedComponents: .hourAndMinute)
                        Picker("这个安排的单双周", selection: $meeting.parity) {
                            Text("每周").tag(0)
                            Text("单周").tag(1)
                            Text("双周").tag(2)
                        }
                        .pickerStyle(.segmented)
                        TextField("教室", text: $meeting.location)
                        Button("删除这个安排", role: .destructive) {
                            draft.meetings.removeAll { $0.id == meeting.id }
                        }
                    }
                }
                Button {
                    draft.meetings.append(ImportedMeetingDraft(weekday: 1, startMinutes: 480, endMinutes: 580, location: draft.location))
                } label: {
                    Label("再加一个上课安排", systemImage: "plus.circle")
                }
            }
            .navigationTitle("修改识别结果")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                for index in draft.meetings.indices { normalize(&draft.meetings[index]) }
            }
        }
    }

    /// Period-based drafts are converted to clock times for editing, using the
    /// semester's period table.
    private func normalize(_ meeting: inout ImportedMeetingDraft) {
        guard meeting.startMinutes == nil, let start = meeting.startPeriod else { return }
        let periods = model.document.semester.periods
        if let period = periods.first(where: { $0.index == start }) {
            meeting.startMinutes = SmartImportView.minutes(of: period.start)
        }
        if let end = meeting.endPeriod, let period = periods.first(where: { $0.index == end }) {
            meeting.endMinutes = SmartImportView.minutes(of: period.end)
        }
        meeting.startPeriod = nil
        meeting.endPeriod = nil
    }

    private func timeBinding(_ meeting: Binding<ImportedMeetingDraft>, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minutes = (isStart ? meeting.wrappedValue.startMinutes : meeting.wrappedValue.endMinutes) ?? 480
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                if isStart { meeting.wrappedValue.startMinutes = minutes } else { meeting.wrappedValue.endMinutes = minutes }
            }
        )
    }
}
