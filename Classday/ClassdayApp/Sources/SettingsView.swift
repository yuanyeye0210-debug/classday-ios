import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ClassdayCore

struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var semester: Semester
    @State private var didLoadSemester = false
    @State private var lastSyncedSemester: Semester?
    @State private var errorText: String?
    @State private var exporting = false
    @State private var exportDocument = JSONFileDocument(data: Data())
    @State private var showChangelog = false
    @State private var updateNote: String?
    @State private var updateURL: URL?
    @State private var checkingUpdate = false

    init() {
        _semester = State(initialValue: DemoData.makeSemester())
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("我的")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                VStack(spacing: 0) {
                    settingsRow(icon: "paintpalette.fill", color: .purple,
                                title: "主题", value: model.document.appearance.theme.name) {
                        model.showThemeGallery = true
                    }
                    Divider().padding(.leading, 58)
                    settingsRow(icon: "square.and.arrow.down.fill", color: Theme.accent,
                                title: "考试、作业、导入和分享", value: nil) {
                        model.showStudyDesk = true
                    }
                }
                .settingsCard(padding: 6)
                if let loadError = model.loadError {
                    notice(loadError)
                }
                section("学期") {
                    labeledField("名称", text: $semester.name)
                    labeledField("简称", text: $semester.shortName)
                    HStack(spacing: 12) {
                        iconBadge("calendar", color: .red)
                        Text("开始日期").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        DatePicker("开始日期", selection: startDateBinding, displayedComponents: .date)
                            .labelsHidden()
                    }
                    HStack(spacing: 12) {
                        iconBadge("number", color: .orange)
                        Stepper(value: $semester.totalWeeks, in: 1...30) {
                            Text("共 \(semester.totalWeeks) 周").font(.system(size: 16, weight: .medium))
                        }
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                    saveButton("保存学期") {
                        if let error = model.updateSemester(semester) {
                            errorText = error
                        } else {
                            errorText = nil
                            semester = model.document.semester
                            lastSyncedSemester = semester
                        }
                    }
                    .disabled(!didLoadSemester)
                }
                section("上课时间") {
                    ForEach(semester.periods) { period in
                        HStack(spacing: 10) {
                            Text("第 \(period.index) 节")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.accentInk)
                                .frame(width: 52, height: 34)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.12)))
                            Spacer()
                            DatePicker("开始", selection: timeBinding(period.index, isStart: true), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("–").foregroundStyle(Theme.secondary)
                            DatePicker("结束", selection: timeBinding(period.index, isStart: false), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        if period.index != semester.periods.last?.index {
                            Divider()
                        }
                    }
                    HStack(spacing: 10) {
                        tintedButton("添加一节", icon: "plus.circle.fill", color: .green) { addPeriod() }
                        tintedButton("删除最后一节", icon: "trash.fill", color: .red) { removeLastPeriod() }
                    }
                    saveButton("保存节次与学期") {
                        if let error = model.updateSemester(semester) {
                            errorText = error
                        } else {
                            errorText = nil
                            semester = model.document.semester
                            lastSyncedSemester = semester
                        }
                    }
                    .disabled(!didLoadSemester)
                    HStack(spacing: 10) {
                        tintedButton("30 分钟 × 20 节", icon: "rectangle.grid.3x2.fill", color: .blue) { applyPeriodTemplate(minutes: 30, count: 20) }
                        tintedButton("45 分钟 × 10 节", icon: "rectangle.grid.2x2.fill", color: .gray) { applyPeriodTemplate(minutes: 45, count: 10) }
                    }
                    noteCard("节次按序号连续排列。删除只允许从最后一节开始，并且不能还有课程占用它。保存会连同学期名称、周数和默认提醒一起写入本机。上面两个模板从 08:00 起排：30 分钟 × 20 节是里斯本 IST 的节次表，套用后先别保存，核对无误再点保存（保存前 App 会自动把当前课表存进课表库备份）。")
                }
                section("提醒") {
                    HStack(spacing: 12) {
                        iconBadge("bell.fill", color: .orange)
                        Stepper(value: $semester.defaultReminderMinutes, in: 0...120) {
                            Text(semester.defaultReminderMinutes == 0 ? "默认不提醒" : "默认提前 \(semester.defaultReminderMinutes) 分钟")
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                    HStack(spacing: 12) {
                        iconBadge("bell.badge.fill", color: .pink)
                        Circle()
                            .fill(notificationDotColor)
                            .frame(width: 9, height: 9)
                        Text("通知权限：\(model.notificationStatusText)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Button("检查") {
                            Task {
                                _ = await ReminderScheduler.shared.requestAuthorization()
                                await model.refreshNotificationStatus()
                            }
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                        .buttonStyle(JournalPressStyle())
                    }
                    if model.notificationStatusText == "已拒绝" {
                        settingsRow(icon: "gearshape.fill", color: .gray,
                                    title: "打开系统设置去允许", value: nil) {
                            openSettings()
                        }
                    }
                    noteCard("开启某门课的提醒时才会向系统请求权限。允许后，课曜会在本地安排最多 \(NotificationPlan.pendingLimit) 条即将上课的通知。")
                }
                section("数据") {
                    settingsRow(icon: "square.and.arrow.up.fill", color: Theme.accent,
                                title: "导出 JSON", value: nil) {
                        if let data = try? model.exportData() {
                            exportDocument = JSONFileDocument(data: data)
                            exporting = true
                        }
                    }
                    Divider().padding(.leading, 58)
                    settingsRow(icon: "square.and.arrow.down.fill", color: .green,
                                title: "导入 JSON", value: nil) {
                        model.showImporter = true
                    }
                    Divider().padding(.leading, 58)
                    settingsRow(icon: "sparkles", color: .purple,
                                title: "智能导入课表", value: "图片 / 文件 / 文本") {
                        model.showSmartImport = true
                    }
                    Divider().padding(.leading, 58)
                    settingsRow(icon: "arrow.counterclockwise", color: .orange,
                                title: "恢复演示数据", value: nil) {
                        model.confirmReset = true
                    }
                    Divider().padding(.leading, 58)
                    settingsRow(icon: "trash.fill", color: .red,
                                title: "清空课程", value: nil, destructive: true) {
                        model.confirmClear = true
                    }
                    noteCard("导入会替换当前课表。文件需要 schemaVersion \(StoreDocument.currentSchema)。没有校园账号，也不会查询成绩。")
                }
                section("关于") {
                    HStack(spacing: 14) {
                        Text("课")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.55, green: 0.35, blue: 0.98)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("课曜 / Heptara").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accentInk)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                        }
                        Spacer()
                    }
                    Text("独立设计的本地课表。界面参考了常见的周课表和彩色课程卡片，不是「超级课程表」官方产品，也不追求与它功能一致。课程、教师、教室和时间都可以是你自己的数据；首次打开时的示例已标明为演示数据。")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    settingsRow(icon: "newspaper.fill", color: .indigo,
                                title: "更新日志", value: AppChangelog.entries.first?.version) {
                        showChangelog = true
                    }
                    Divider().padding(.leading, 58)
                    settingsRow(icon: "arrow.down.circle.fill", color: .teal,
                                title: "检查更新", value: checkingUpdate ? "检查中…" : updateNote) {
                        Task { await checkForUpdate() }
                    }
                    if let updateURL {
                        Divider().padding(.leading, 58)
                        Link(destination: updateURL) {
                            HStack(spacing: 12) {
                                iconBadge("square.and.arrow.down.fill", color: .green)
                                Text("下载新版 IPA")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.secondary.opacity(0.6))
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Text("安装步骤（SideStore）：① 点上面下载，IPA 会存进「文件」；② 打开 LocalDevVPN 点连接；③ 打开 SideStore，点 + 选中刚下载的 IPA，签好自动装上，课表数据不会丢。还没装 SideStore 的话，首次需要在电脑上用 iloader 装一次，装好后以后更新都不用电脑。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if !didLoadSemester || semester == lastSyncedSemester {
                semester = model.document.semester
                lastSyncedSemester = model.document.semester
                didLoadSemester = true
            }
        }
        .onChange(of: model.document.semester) { _, newValue in
            // Sync from the document only while the editor holds no
            // unsaved edits; otherwise a background document change
            // (timetable switch, mirror restore) would silently rewrite
            // what the user is looking at - or the reverse on save.
            if semester == lastSyncedSemester {
                semester = newValue
                lastSyncedSemester = newValue
            }
        }
        .sheet(isPresented: $showChangelog) { ChangelogView() }
        .sheet(isPresented: $model.showThemeGallery) { ThemeGalleryView() }
        .sheet(isPresented: $model.showStudyDesk) { StudyDeskView() }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "课曜课表.json"
        ) { result in
            if case .failure = result { model.banner = "导出没有完成" }
        }
    }

    // MARK: building blocks

    private var notificationDotColor: Color {
        switch model.notificationStatusText {
        case "已允许", "已开启": return .green
        case "已拒绝": return .red
        default: return .orange
        }
    }

    private func iconBadge(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
    }

    private func settingsRow(icon: String, color: Color, title: String, value: String?,
                             destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconBadge(icon, color: color)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(destructive ? .red : Theme.ink)
                Spacer()
                if let value {
                    Text(value).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.secondary.opacity(0.6))
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func saveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent))
        }
        .buttonStyle(JournalPressStyle())
    }

    private func tintedButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12)))
        }
        .buttonStyle(JournalPressStyle())
    }

    private func noteCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.background.opacity(0.65)))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .settingsCard()
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.hero, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
            TextField(title, text: text)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: {
                SemesterCalendar.parseCivil(semester.startDate, calendar: model.calendar) ?? Date()
            },
            set: { newValue in
                semester.startDate = SemesterCalendar.formatCivil(newValue, calendar: model.calendar)
            }
        )
    }

    private func timeBinding(_ index: Int, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                let raw = semester.periods.first { $0.index == index }.map { isStart ? $0.start : $0.end } ?? "08:00"
                return clockDate(raw)
            },
            set: { newValue in
                guard let periodIndex = semester.periods.firstIndex(where: { $0.index == index }) else { return }
                let text = clockText(newValue)
                if isStart {
                    semester.periods[periodIndex].start = text
                } else {
                    semester.periods[periodIndex].end = text
                }
            }
        )
    }

    private func clockDate(_ raw: String) -> Date {
        let clock = ClockTime.parse(raw) ?? ClockTime(hour: 8, minute: 0)
        var components = model.calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = clock.hour
        components.minute = clock.minute
        return model.calendar.date(from: components) ?? Date()
    }

    private func clockText(_ date: Date) -> String {
        let hour = model.calendar.component(.hour, from: date)
        let minute = model.calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private func addPeriod() {
        let next = (semester.periods.map(\.index).max() ?? 0) + 1
        let previousEnd = semester.periods.sorted { $0.index < $1.index }.last?.end ?? "08:00"
        let start = ClockTime.parse(previousEnd) ?? ClockTime(hour: 8, minute: 0)
        let startMinutes = min(start.totalMinutes + 10, 23 * 60)
        // Inherit the previous period's length instead of assuming the
        // 45-minute mainland default: a 30-minute grid stays 30 minutes.
        let duration = semester.periods.sorted { $0.index < $1.index }.last.flatMap { last -> Int? in
            guard let s = ClockTime.parse(last.start), let e = ClockTime.parse(last.end) else { return nil }
            let d = e.totalMinutes - s.totalMinutes
            return d > 0 ? d : nil
        } ?? 45
        let endMinutes = min(startMinutes + duration, 23 * 60 + 50)
        guard endMinutes > startMinutes else {
            model.banner = "已经排到当天末尾"
            return
        }
        semester.periods.append(
            PeriodTemplate(
                index: next,
                start: ClockTime(hour: startMinutes / 60, minute: startMinutes % 60).hhmm,
                end: ClockTime(hour: endMinutes / 60, minute: endMinutes % 60).hhmm
            )
        )
    }

    private func applyPeriodTemplate(minutes: Int, count: Int) {
        // One-tap period tables, laid out back-to-back from 08:00. Classes
        // reference periods by index, so re-applying the table a timetable
        // was built against re-aligns every class to its real clock time.
        var periods: [PeriodTemplate] = []
        var cursor = 8 * 60
        for index in 1...count {
            let end = cursor + minutes
            periods.append(PeriodTemplate(
                index: index,
                start: ClockTime(hour: cursor / 60, minute: cursor % 60).hhmm,
                end: ClockTime(hour: end / 60, minute: end % 60).hhmm
            ))
            cursor = end
        }
        semester.periods = periods
        let over = model.document.courses.flatMap(\.meetings).filter { $0.endPeriod > count }.count
        if over > 0 {
            errorText = "已套用模板（还没保存）。注意：有 \(over) 个上课安排排在第 \(count) 节之后，超出新节次表。"
        } else {
            errorText = nil
            model.banner = "已套用 \(minutes) 分钟 × \(count) 节模板，点保存后生效"
        }
    }

    private func removeLastPeriod() {
        guard semester.periods.count > 1, let last = semester.periods.map(\.index).max() else {
            model.banner = "至少保留 1 个节次"
            return
        }
        let used = model.document.courses.contains { course in
            course.meetings.contains { $0.startPeriod == last || $0.endPeriod == last || ($0.startPeriod < last && $0.endPeriod > last) }
        }
        if used {
            model.banner = "已有课程使用第 \(last) 节"
            return
        }
        semester.periods.removeAll { $0.index == last }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension View {
    func settingsCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppChangelog.entries, id: \.version) { entry in
                    Section {
                        ForEach(entry.changes, id: \.self) { change in
                            HStack(alignment: .top, spacing: 8) {
                                Text("·").foregroundStyle(.secondary)
                                Text(change)
                            }
                        }
                    } header: {
                        Text("\(entry.version) · \(entry.title)")
                    }
                }
            }
            .navigationTitle("更新日志")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct GitHubRelease: Decodable {
    let tag_name: String
}

extension SettingsView {
    /// Compares the app's own version against the latest GitHub release
    /// of the (public) repo; releases are published alongside each IPA
    /// delivery, so this is the sideload-friendly update channel.
    func checkForUpdate() async {
        checkingUpdate = true
        updateURL = nil
        defer { checkingUpdate = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/yuanyeye0210-debug/classday-ios/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            if Self.version(latest, isNewerThan: current) {
                updateNote = "新版 \(latest)"
                // Release assets can't be attached through the API token
                // channel (uploads host), so the IPAs live in the public
                // classday-releases archive repo under predictable names.
                updateURL = URL(string: "https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/Classday-v\(latest).ipa")
            } else {
                updateNote = "已是最新"
            }
        } catch {
            updateNote = "检查失败"
        }
    }

    static func version(_ a: String, isNewerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
