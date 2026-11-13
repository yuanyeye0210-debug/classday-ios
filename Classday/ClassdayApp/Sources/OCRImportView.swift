import SwiftUI
import PhotosUI
import Vision
import PDFKit
import UniformTypeIdentifiers
import CoreFoundation
import ClassdayCore

/// Smart import: photos, CSV files and pasted text are parsed into editable
/// drafts first. Nothing reaches the timetable until the user confirms.
/// Presentation follows the approved preview: source cards with icon tiles,
/// one designed card per drafted course, and a card-based editor — no bare
/// form rows.
struct SmartImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var drafts: [ImportedCourseDraft] = []
    @State private var excluded: Set<UUID> = []
    @State private var unparsed: [String] = []
    @State private var sourceName = ""
    @State private var editingID: UUID?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var pasteText = ""
    @State private var analyzing = false

    static let palette = ["blue", "orange", "purple", "green", "pink", "sage"]

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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceCard
                    pasteCard
                    if analyzing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在识别…").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                        }
                        .padding(.horizontal, 6)
                    }
                    if !drafts.isEmpty { confirmSection }
                    if !unparsed.isEmpty { unparsedCard }
                }
                .padding(18)
            }
            .background(Theme.elevated)
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
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("导入选中的 \(selectedCount) 门课")
                        }
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selectedCount == 0 ? Theme.secondary : Theme.accent))
                        .shadow(color: Theme.accent.opacity(selectedCount == 0 ? 0 : 0.35), radius: 12, y: 5)
                    }
                    .buttonStyle(JournalPressStyle())
                    .disabled(selectedCount == 0)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
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
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: Self.fileTypes) { result in
                if case let .success(url) = result { readFile(url) }
            }
            .sheet(item: editingBinding) { draft in
                DraftEditorView(draft: binding(for: draft.id))
            }
        }
    }

    // MARK: sections

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("选择来源", caption: "三种方式，识别完先确认再导入")
            PhotosPicker(selection: $pickerItem, matching: .images) {
                sourceRow(icon: "photo.on.rectangle.angled",
                          colors: [Color(red: 0.45, green: 0.35, blue: 0.95), Color(red: 0.25, green: 0.55, blue: 0.98)],
                          title: "课表图片",
                          subtitle: "截图或照片 · 网格和文字版都能认")
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 66)
            Button {
                showFileImporter = true
            } label: {
                sourceRow(icon: "tablecells.fill",
                          colors: [Color(red: 0.15, green: 0.68, blue: 0.38), Color(red: 0.05, green: 0.55, blue: 0.55)],
                          title: "表格 / 文档文件",
                          subtitle: "CSV · Excel · Word · PDF · HTML 都能认")
            }
            .buttonStyle(.plain)
            if !sourceName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("来源：\(sourceName)")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 12)
            }
        }
        .importCard()
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                iconTile(icon: "text.viewfinder",
                         colors: [Color(red: 0.98, green: 0.55, blue: 0.20), Color(red: 0.95, green: 0.35, blue: 0.35)],
                         size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("粘贴文本").font(.system(size: 16, weight: .bold))
                    Text("把课表文字粘进来，一行一节课也行")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.elevated)
                TextEditor(text: $pasteText)
                    .frame(minHeight: 84)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if pasteText.isEmpty {
                    Text("例如：高等数学 周一 08:00-09:40 教学楼A301 陈老师 1-16周")
                        .font(.footnote).foregroundStyle(Theme.secondary.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            Button {
                load(text: pasteText, source: "粘贴的文本", isCSV: pasteText.contains(",") || pasteText.contains(";") || pasteText.contains("\t"))
            } label: {
                Text("解析这段文本")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.secondary : Theme.accent))
            }
            .buttonStyle(JournalPressStyle())
            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .importCard()
    }

    private var confirmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("确认识别结果", caption: "点开任意一门课就能改，勾选的才会导入")
            ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                DraftCard(draft: draftWithPeriodIssues(draft),
                          colorID: Self.palette[index % Self.palette.count],
                          included: !excluded.contains(draft.id),
                          duplicate: model.document.courses.contains { $0.name == draft.name && !draft.name.isEmpty },
                          onToggle: {
                              if excluded.contains(draft.id) { excluded.remove(draft.id) } else { excluded.insert(draft.id) }
                          },
                          onEdit: { editingID = draft.id })
            }
        }
    }

    private var unparsedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("没认出的内容", caption: "这些不会导入，你可以对照原文手动加课")
            ForEach(unparsed, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                    Text(line).font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
        }
        .importCard()
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
    }

    private func sectionHeader(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            Text(caption).font(.caption).foregroundStyle(Theme.secondary)
        }
        .padding(.bottom, 12)
    }

    private func sourceRow(icon: String, colors: [Color], title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            iconTile(icon: icon, colors: colors, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func iconTile(icon: String, colors: [Color], size: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 6, y: 3)
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

    /// Everything the Files app might hand us: delimited text, OOXML,
    /// PDF, HTML-disguised xls, calendar files, our own JSON, and images.
    static let fileTypes: [UTType] = [
        .commaSeparatedText, .tabSeparatedText, .plainText, .spreadsheet,
        .pdf, .html, .image, .json,
        UTType(filenameExtension: "xlsx")!, UTType(filenameExtension: "docx")!,
        UTType(filenameExtension: "ics")!, UTType(filenameExtension: "xls")!,
        UTType(filenameExtension: "csv")!, UTType(filenameExtension: "tsv")!,
    ]

    private func readFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.lastPathComponent
        let lower = name.lowercased()
        if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) {
            model.banner = "这是老式 .xls 格式，请在 Excel 里另存为 .xlsx 或 CSV 再导入"
            return
        }
        let decoded = ScheduleTextImporter.decodeText(data)
        if lower.hasSuffix(".ics") || (decoded?.contains("BEGIN:VCALENDAR") ?? false) {
            guard let text = decoded else { return }
            let calendar = ICSImporter.parse(text, totalWeeks: model.document.semester.totalWeeks)
            model.importCalendar(calendar)
            model.banner = "日历文件已导入 \(calendar.courses.count) 门课"
            dismiss()
            return
        }
        if lower.hasSuffix(".json") {
            dismiss()
            model.showImporter = true
            model.banner = "这是课曜的 JSON 备份，已为你打开导入确认"
            return
        }
        if lower.hasSuffix(".pdf") || data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            readPDF(data, name: name)
            return
        }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") || lower.hasSuffix(".heic")
            || data.starts(with: [0xFF, 0xD8]) || data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            Task { await recognize(imageData: data, source: name) }
            return
        }
        guard let result = ScheduleTextImporter.parseFileData(data) else {
            model.banner = "这个文件里没找到能认的课表"
            return
        }
        drafts = result.drafts
        unparsed = result.unparsed
        excluded = []
        sourceName = name
        if result.drafts.isEmpty {
            model.banner = "没有认出课程，换一份试试"
        }
    }

    private func readPDF(_ data: Data, name: String) {
        guard let document = PDFDocument(data: data) else {
            model.banner = "这个 PDF 打不开"
            return
        }
        var blocks: [OCRTextBlock] = []
        var pagesText: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pagesText.append(page.string ?? "")
            blocks += pdfBlocks(page: page)
        }
        if pagesText.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            model.banner = "这个 PDF 里没有文字层（像是扫描件），截成图片用「课表图片」导入"
            return
        }
        if let grid = ScheduleTextImporter.parseGrid(blocks) {
            drafts = grid.drafts
            unparsed = grid.unparsed
            excluded = []
            sourceName = "\(name)（PDF 课表）"
            return
        }
        load(text: pagesText.joined(separator: "\n"), source: name, isCSV: false)
    }

    /// Word-level blocks from a PDF text layer, in the same bottom-left
    /// coordinate space Vision OCR uses, so parseGrid can consume them.
    private func pdfBlocks(page: PDFPage) -> [OCRTextBlock] {
        let content = page.string ?? ""
        let characters = Array(content)
        let count = min(page.numberOfCharacters, characters.count)
        guard count > 0 else { return [] }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return [] }
        var words: [(text: String, rect: CGRect)] = []
        var current = ""
        var currentRect: CGRect?
        func flush() {
            if !current.isEmpty, let rect = currentRect { words.append((current, rect)) }
            current = ""
            currentRect = nil
        }
        for index in 0..<count {
            let character = characters[index]
            if character.isWhitespace { flush(); continue }
            current.append(character)
            let rect = page.characterBounds(at: index)
            currentRect = currentRect?.union(rect) ?? rect
        }
        flush()
        return words.map { word in
            OCRTextBlock(
                text: word.text,
                centerX: Double((word.rect.midX - box.minX) / box.width),
                centerY: Double((word.rect.midY - box.minY) / box.height),
                height: Double(word.rect.height / box.height))
        }
    }

    static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // 1586 = kCFStringEncodingGB_18030_2000 (the named constant is not
        // exposed to Swift on this toolchain, so use its stable value).
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(1586)))
        if let text = String(data: data, encoding: gb18030) { return text }
        return String(data: data, encoding: .utf16) ?? ""
    }

    private func recognize(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        analyzing = true
        defer { analyzing = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await recognize(imageData: data, source: "课表图片")
    }

    private func recognize(imageData data: Data, source: String) async {
        analyzing = true
        defer { analyzing = false }
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let results = request.results ?? []
        // Grid first: timetable screenshots are tables — read them by layout.
        let blocks = results.compactMap { observation -> OCRTextBlock? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return OCRTextBlock(
                text: text,
                centerX: Double(observation.boundingBox.midX),
                centerY: Double(observation.boundingBox.midY),
                height: Double(observation.boundingBox.height))
        }
        if let grid = ScheduleTextImporter.parseGrid(blocks) {
            drafts = grid.drafts
            unparsed = grid.unparsed
            excluded = []
            sourceName = source == "课表图片" ? "课表图片（网格识别）" : source
            return
        }
        let observations = results.sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        load(text: text, source: source, isCSV: false)
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
        let invalid = drafts.filter { !excluded.contains($0.id) && hasInvalidExplicitPeriods($0) }
        guard invalid.isEmpty else {
            model.banner = "节次超出当前学期范围或起止倒序，请修改或取消勾选：" + invalid.map(\.name).joined(separator: "、")
            return
        }
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
                colorID: Self.palette[offset % Self.palette.count], weeks: weeks, meetings: meetings))
        }
        return (built, parities)
    }

    private func hasInvalidExplicitPeriods(_ draft: ImportedCourseDraft) -> Bool {
        draft.meetings.contains {
            $0.startPeriod != nil && $0.validatedExplicitPeriodSpan(in: model.document.semester.periods) == nil
        }
    }

    private func draftWithPeriodIssues(_ draft: ImportedCourseDraft) -> ImportedCourseDraft {
        var result = draft
        if hasInvalidExplicitPeriods(draft) {
            result.issues.append("节次超出学期范围或倒序")
        }
        return result
    }

    private func periodSpan(for meeting: ImportedMeetingDraft, periods: [PeriodTemplate]) -> (Int, Int)? {
        if meeting.startPeriod != nil {
            return meeting.validatedExplicitPeriodSpan(in: periods)
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

extension View {
    func importCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct DraftCard: View {
    var draft: ImportedCourseDraft
    var colorID: String
    var included: Bool
    var duplicate: Bool
    var onToggle: () -> Void
    var onEdit: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var courseBG: Color { Theme.courseBackground(colorID, scheme: scheme) }
    private var courseInk: Color { Theme.courseInk(colorID, scheme: scheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CourseGlyphTile(name: draft.name.isEmpty ? "课" : draft.name, colorID: colorID, size: 50)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(draft.name.isEmpty ? "课程名待补" : draft.name)
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                    if duplicate { badge("已有同名课", color: .orange) }
                    ForEach(draft.issues, id: \.self) { issue in
                        badge(issue, color: .red)
                    }
                }
                ForEach(draft.meetings) { meeting in
                    meetingLine(meeting)
                }
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.caption2)
                    Text(weeksLine).font(.caption)
                }
                .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            Button(action: onToggle) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(included ? Theme.accent : Theme.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .importCard()
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .opacity(included ? 1 : 0.45)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func meetingLine(_ meeting: ImportedMeetingDraft) -> some View {
        let day = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let weekday = (0...7).contains(meeting.weekday) ? day[meeting.weekday] : "星期待选"
        var time = "时间待补"
        if let start = meeting.startMinutes {
            time = "\(Self.clock(start))–\(Self.clock(meeting.endMinutes ?? start + 95))"
        } else if let start = meeting.startPeriod {
            time = "第 \(start)–\(meeting.endPeriod ?? start) 节"
        }
        let location = meeting.location.isEmpty ? draft.location : meeting.location
        return HStack(spacing: 6) {
            Text(weekday)
                .font(.caption.weight(.heavy))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(courseBG))
                .foregroundStyle(courseInk)
            Text(time).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            if !location.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "mappin").font(.caption2)
                    Text(location).font(.subheadline)
                }
                .foregroundStyle(Theme.secondary)
            }
            if meeting.parity != 0 {
                badge(meeting.parity == 1 ? "单周" : "双周", color: .purple)
            }
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    courseCard
                    weeksCard
                    ForEach($draft.meetings.indices, id: \.self) { index in
                        meetingCard(index: index, meeting: $draft.meetings[index])
                    }
                    Button {
                        draft.meetings.append(ImportedMeetingDraft(weekday: 1, startMinutes: 480, endMinutes: 580, location: draft.location))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("再加一个上课安排")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.accent.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [7, 5])))
                    }
                    .buttonStyle(JournalPressStyle())
                }
                .padding(18)
            }
            .background(Theme.elevated)
            .navigationTitle("修改识别结果")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.fontWeight(.bold)
                }
            }
            .onAppear {
                for index in draft.meetings.indices { normalize(&draft.meetings[index]) }
            }
        }
    }

    private var courseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("课程", icon: "book.fill", color: Theme.accent)
            field("课程名称", placeholder: "例如 高等数学", text: $draft.name)
            field("老师", placeholder: "例如 陈老师", text: $draft.teacher)
            field("默认教室", placeholder: "各安排没单独写时用这个", text: $draft.location)
        }
        .importCard()
    }

    private var weeksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("上课周", icon: "calendar", color: .purple)
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
                        let selected = draft.customWeeks.contains(week)
                        Button {
                            if selected {
                                draft.customWeeks.removeAll { $0 == week }
                            } else {
                                draft.customWeeks.append(week)
                                draft.customWeeks.sort()
                            }
                        } label: {
                            Text("\(week)")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(selected ? Theme.accent : Theme.segment))
                                .foregroundStyle(selected ? .white : Theme.ink)
                        }
                        .buttonStyle(JournalPressStyle())
                    }
                }
                Text("点选这门课真正上课的周，其余周不上。")
                    .font(.caption).foregroundStyle(Theme.secondary)
            } else {
                Stepper("起始周：第 \(draft.firstWeek) 周", value: $draft.firstWeek, in: 1...30)
                    .font(.system(size: 16, weight: .medium))
                Stepper("结束周：第 \(draft.lastWeek) 周", value: $draft.lastWeek, in: 1...30)
                    .font(.system(size: 16, weight: .medium))
            }
        }
        .importCard()
    }

    private func meetingCard(index: Int, meeting: Binding<ImportedMeetingDraft>) -> some View {
        let value = meeting.wrappedValue
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                cardTitle("上课安排 \(index + 1)", icon: "clock.fill", color: .orange)
                Spacer()
                Button(role: .destructive) {
                    draft.meetings.removeAll { $0.id == value.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.red.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let selected = value.weekday == day
                    Button {
                        meeting.wrappedValue.weekday = day
                        var copy = meeting.wrappedValue
                        normalize(&copy)
                        meeting.wrappedValue = copy
                    } label: {
                        Text(["一", "二", "三", "四", "五", "六", "日"][day - 1])
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selected ? Theme.accent : Theme.segment))
                            .foregroundStyle(selected ? .white : Theme.ink)
                    }
                    .buttonStyle(JournalPressStyle())
                }
            }
            if value.startPeriod != nil,
               value.validatedExplicitPeriodSpan(in: model.document.semester.periods) == nil {
                Text("原安排第 \(value.startPeriod ?? 0)–\(value.endPeriod ?? value.startPeriod ?? 0) 节不在当前学期节次范围内。请填写有效的开始和结束时间，或删除这个安排；未修正前不能导入。")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                timeField("开始", binding: timeBinding(meeting, isStart: true))
                timeField("结束", binding: timeBinding(meeting, isStart: false))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("这个安排的单双周").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                Picker("单双周", selection: meeting.parity) {
                    Text("每周").tag(0)
                    Text("单周").tag(1)
                    Text("双周").tag(2)
                }
                .pickerStyle(.segmented)
            }
            field("教室", placeholder: "例如 教学楼A301", text: meeting.location)
        }
        .importCard()
    }

    private func cardTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
            Text(title).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.elevated))
        }
    }

    private func timeField(_ label: String, binding: Binding<Date>) -> some View {
        HStack {
            Text(label).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.secondary)
            Spacer()
            DatePicker(label, selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.elevated))
        .frame(maxWidth: .infinity)
    }

    /// Period-based drafts are converted to clock times for editing, using the
    /// semester's period table.
    private func normalize(_ meeting: inout ImportedMeetingDraft) {
        meeting.normalizeForClockEditing(in: model.document.semester.periods)
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
                meeting.wrappedValue.setClockTime(minutes, isStart: isStart)
            }
        )
    }
}
