import SwiftUI
import PhotosUI
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
    @State private var showCalendarImport = false
    @State private var showMailCancel = false
    @State private var newHolidayName = ""
    @State private var newHolidayStart = Date()
    @State private var newHolidayEnd = Date()
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
                    HStack(spacing: 12) {
                        iconBadge("flag.checkered", color: .purple)
                        Text("结束日期").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(semesterEndText).font(.system(size: 14)).foregroundStyle(Theme.secondary)
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
                section("假期与不上课时段") {
                    if semester.holidays.isEmpty {
                        Text("还没有假期。导入校历、拍照识别，或在下面手动加一段——假期内的课会自动跳过、不提醒。")
                            .font(.system(size: 13.5, design: .rounded))
                            .foregroundStyle(Theme.secondary)
                    }
                    ForEach(semester.holidays.sorted { $0.startDate < $1.startDate }) { holiday in
                        HStack(spacing: 12) {
                            iconBadge("beach.umbrella.fill", color: .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(holiday.name).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Theme.ink)
                                Text(holidayRangeText(holiday)).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                semester.holidays.removeAll { $0.id == holiday.id }
                                saveHolidays()
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider()
                    labeledField("新时段名称", text: $newHolidayName)
                    HStack(spacing: 12) {
                        Text("开始").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        DatePicker("开始", selection: $newHolidayStart, displayedComponents: .date).labelsHidden()
                        Spacer()
                        Text("结束").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        DatePicker("结束", selection: $newHolidayEnd, displayedComponents: .date).labelsHidden()
                    }
                    saveButton("添加时段") {
                        let name = newHolidayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let start = SemesterCalendar.formatCivil(newHolidayStart, calendar: model.calendar)
                        let end = SemesterCalendar.formatCivil(newHolidayEnd, calendar: model.calendar)
                        semester.holidays.append(HolidayPeriod(id: UUID(), name: name.isEmpty ? "不上课" : name, startDate: min(start, end), endDate: max(start, end)))
                        newHolidayName = ""
                        saveHolidays()
                    }
                    Button {
                        showCalendarImport = true
                    } label: {
                        HStack(spacing: 12) {
                            iconBadge("calendar.badge.plus", color: .teal)
                            Text("校历导入").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("文件 / 拍照识别").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondary.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                    Button {
                        showMailCancel = true
                    } label: {
                        HStack(spacing: 12) {
                            iconBadge("envelope.badge.fill", color: .pink)
                            Text("邮件停课识别").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("粘贴 / 截图").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondary.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if !semester.cancellations.isEmpty {
                        Divider()
                        Text("停课记录")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                        ForEach(semester.cancellations.sorted { $0.date < $1.date }) { entry in
                            HStack(spacing: 12) {
                                iconBadge("calendar.badge.minus", color: .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.courseID == nil ? "全天停课" : entry.courseName).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Theme.ink)
                                    Text(cancellationDetailText(entry)).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    semester.cancellations.removeAll { $0.id == entry.id }
                                    saveHolidays()
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
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
                                title: "检查更新", value: checkingUpdate ? "检查中…" : updateNote,
                                showsChevron: updateURL != nil) {
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
        .sheet(isPresented: $showCalendarImport) {
            CalendarImportView(onConfirm: { drafts in mergeHolidays(drafts) }, onOpenMail: {
                showCalendarImport = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showMailCancel = true }
            })
        }
        .sheet(isPresented: $showMailCancel) {
            MailCancelView { record in mergeCancellation(record) }
        }
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

    private var semesterEndText: String {
        guard let end = SemesterCalendar.endDate(semester: semester, calendar: model.calendar) else { return "—" }
        let cal = model.calendar
        return "\(cal.component(.year, from: end))年\(cal.component(.month, from: end))月\(cal.component(.day, from: end))日（自动推算）"
    }

    private func holidayRangeText(_ holiday: HolidayPeriod) -> String {
        func md(_ civil: String) -> String {
            let parts = civil.split(separator: "-")
            guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return civil }
            return "\(m)月\(d)日"
        }
        return holiday.startDate == holiday.endDate ? md(holiday.startDate) : "\(md(holiday.startDate)) – \(md(holiday.endDate))"
    }

    private func saveHolidays() {
        if let error = model.updateSemester(semester) {
            errorText = error
        } else {
            errorText = nil
            semester = model.document.semester
            lastSyncedSemester = semester
        }
    }

    private func cancellationDetailText(_ entry: ClassCancellation) -> String {
        let parts = entry.date.split(separator: "-")
        let md = parts.count == 3 ? "\(Int(parts[1]) ?? 0)月\(Int(parts[2]) ?? 0)日" : entry.date
        let scope = ["day": "全天", "all": "当天全部节次", "am": "上午", "pm": "下午"][entry.scope] ?? entry.scope
        return entry.reason.isEmpty ? "\(md) · \(scope)" : "\(md) · \(scope) · \(entry.reason)"
    }

    private func mergeCancellation(_ record: ClassCancellation) {
        if !semester.cancellations.contains(where: { $0.date == record.date && $0.courseID == record.courseID && $0.scope == record.scope }) {
            semester.cancellations.append(record)
        }
        saveHolidays()
    }

    private func mergeHolidays(_ drafts: [HolidayPeriod]) {
        for draft in drafts where !semester.holidays.contains(where: { $0.name == draft.name && $0.startDate == draft.startDate && $0.endDate == draft.endDate }) {
            semester.holidays.append(draft)
        }
        saveHolidays()
    }

    private func settingsRow(icon: String, color: Color, title: String, value: String?,
                             destructive: Bool = false, showsChevron: Bool = true, action: @escaping () -> Void) -> some View {
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
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.secondary.opacity(0.6))
                }
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
                updateNote = "已是最新版"
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


// MARK: - 校历导入（文件 .ics 确定性解析 / 拍照 AI 识别，都先出草稿确认页）

private struct HolidayDraft: Identifiable {
    var id = UUID()
    var name: String
    var start: Date
    var end: Date
    var included = true
}

struct CalendarImportView: View {
    var onConfirm: ([HolidayPeriod]) -> Void
    var onOpenMail: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [HolidayDraft] = []
    @State private var note: String?
    @State private var showFileImporter = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedData: Data?
    @State private var busy = false
    @State private var keyDraft = ""
    @State private var hasKey = GradeAIKeyStore.load() != nil
    @State private var showKeyField = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("从校历文件或校历图片识别假期时段，先放进下面的草稿里；逐项核对、改好，点「添加所选」才写入假期列表。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("校历文件") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("选择 .ics 校历文件", systemImage: "doc.badge.plus")
                    }
                }
                Section("拍照识别") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(pickedData == nil ? "选择校历图片" : "换一张校历图片", systemImage: "photo.on.rectangle.angled")
                    }
                    if hasKey && !showKeyField {
                        HStack {
                            Label("Gemini 密钥已保存", systemImage: "key.fill")
                            Spacer()
                            Button("更换") { showKeyField = true }
                        }
                    }
                    if !hasKey || showKeyField {
                        SecureField("粘贴 Gemini API 密钥", text: $keyDraft)
                        Button("保存密钥到钥匙串") {
                            let value = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                GradeAIKeyStore.save(value)
                                hasKey = true
                                showKeyField = false
                                keyDraft = ""
                                note = "密钥已保存，现在可以识别了。"
                            }
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button {
                        runAIRecognition()
                    } label: {
                        if busy {
                            HStack { ProgressView(); Text("识别中…") }
                        } else {
                            Label("AI 识别校历", systemImage: "sparkles")
                        }
                    }
                    .disabled(pickedData == nil || busy)
                }
                if let note {
                    Section {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let onOpenMail {
                    Section {
                        Button {
                            onOpenMail()
                        } label: {
                            Label("老师发邮件说某节课不上？用邮件停课识别", systemImage: "envelope.badge")
                        }
                    }
                }
                Section("待添加的假期（草稿）") {
                    if drafts.isEmpty {
                        Text("还没有草稿。先选一个校历文件，或选一张校历图片识别。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle(isOn: $draft.included) {
                                    TextField("名称", text: $draft.name)
                                }
                                Button(role: .destructive) {
                                    drafts.removeAll { $0.id == draft.id }
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            HStack(spacing: 10) {
                                DatePicker("开始", selection: $draft.start, displayedComponents: .date)
                                DatePicker("结束", selection: $draft.end, displayedComponents: .date)
                            }
                            .font(.system(size: 13))
                        }
                    }
                }
            }
            .navigationTitle("校历导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加所选") {
                        let cal = model.calendar
                        let chosen = drafts.filter { $0.included }.map { draft in
                            HolidayPeriod(
                                id: UUID(),
                                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "假期" : draft.name,
                                startDate: SemesterCalendar.formatCivil(min(draft.start, draft.end), calendar: cal),
                                endDate: SemesterCalendar.formatCivil(max(draft.start, draft.end), calendar: cal)
                            )
                        }
                        onConfirm(chosen)
                        dismiss()
                    }
                    .disabled(!drafts.contains { $0.included })
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data]) { result in
                if case .success(let url) = result {
                    loadICS(url)
                }
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        pickedData = GradeImagePrep.preparedJPEG(data) ?? data
                    }
                }
            }
        }
    }

    private func loadICS(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            note = "这个文件读不出来，换一个 .ics 文件试试。"
            return
        }
        appendDrafts(HolidayImporter.parseICS(text, calendar: model.calendar), source: "文件")
    }

    private func appendDrafts(_ periods: [HolidayPeriod], source: String) {
        let cal = model.calendar
        for period in periods {
            guard let start = SemesterCalendar.parseCivil(period.startDate, calendar: cal),
                  let end = SemesterCalendar.parseCivil(period.endDate, calendar: cal) else { continue }
            drafts.append(HolidayDraft(name: period.name, start: start, end: end))
        }
        note = periods.isEmpty
            ? "没有从\(source)里识别到假期时段，换一份校历试试。"
            : "从\(source)识别到 \(periods.count) 段假期，已放进下面的草稿，请核对后点「添加所选」。"
    }

    private func runAIRecognition() {
        guard let data = pickedData else { return }
        guard let key = GradeAIKeyStore.load(), !key.isEmpty else {
            showKeyField = true
            note = "先粘贴 Gemini 密钥并保存，再点识别。"
            return
        }
        busy = true
        Task {
            do {
                let text = try await CalendarRuleRecognizer.recognize(jpegData: data, apiKey: key)
                appendDrafts(HolidayImporter.parseAI(text, calendar: model.calendar), source: "图片")
            } catch {
                note = (error as? LocalizedError)?.errorDescription ?? "识别失败，换一张更清晰的校历图片再试。"
            }
            busy = false
        }
    }
}

enum CalendarRuleRecognizer {
    static func recognize(jpegData: Data, apiKey: String) async throws -> String {
        let prompt = """
        你是学校校历识别器。读图中这所学校的校历/学期安排，找出所有不上课的时段：寒假、暑假、公众假期、停课周等。只输出一个 JSON 对象，不要输出任何其他文字。格式：
        {"holidays": [{"name": "时段名称", "start": "YYYY-MM-DD", "end": "YYYY-MM-DD"}, ...]}
        规则：start/end 是该时段的第一天和最后一天（都包含在时段内）；只有一天的时段 start 和 end 相同；年份按图中年份，跨年时段注意结束年份；名称用图中原文（如"圣诞假期""寒假"）。
        """
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inlineData": ["mimeType": "image/jpeg", "data": jpegData.base64EncodedString()]]
                ]
            ]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.1]
        ]
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw GradeRuleRecognizer.Failure.badResponse(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw GradeRuleRecognizer.Failure.noText
        }
        return text
    }
}

struct MailCancelView: View {
    var onConfirm: (ClassCancellation) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mailText = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedData: Data?
    @State private var busy = false
    @State private var note: String?
    @State private var keyDraft = ""
    @State private var hasKey = GradeAIKeyStore.load() != nil
    @State private var showKeyField = false
    @State private var hasDraft = false
    @State private var isDay = false
    @State private var draftDate = Date()
    @State private var draftCourseID: UUID?
    @State private var draftScope = "all"
    @State private var draftReason = ""
    @State private var courseMatched = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("老师发邮件说某节课不上时，把邮件文字粘进来（中文、英语、葡语都可以），或者选一张邮件截图。AI 认出日期、课程和时段后先出草稿，你逐项核对、改好，确认才生效；被停的那节课不会再出现、也不会提醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("邮件文字") {
                    TextEditor(text: $mailText)
                        .frame(minHeight: 110)
                    Button {
                        recognizeText()
                    } label: {
                        if busy {
                            HStack { ProgressView(); Text("识别中…") }
                        } else {
                            Label("AI 识别粘贴的文字", systemImage: "sparkles")
                        }
                    }
                    .disabled(mailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
                Section("邮件截图") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(pickedData == nil ? "选择邮件截图" : "换一张邮件截图", systemImage: "photo.on.rectangle.angled")
                    }
                    if hasKey && !showKeyField {
                        HStack {
                            Label("Gemini 密钥已保存", systemImage: "key.fill")
                            Spacer()
                            Button("更换") { showKeyField = true }
                        }
                    }
                    if !hasKey || showKeyField {
                        SecureField("粘贴 Gemini API 密钥", text: $keyDraft)
                        Button("保存密钥到钥匙串") {
                            let value = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                GradeAIKeyStore.save(value)
                                hasKey = true
                                showKeyField = false
                                keyDraft = ""
                                note = "密钥已保存，现在可以识别了。"
                            }
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button {
                        recognizeImage()
                    } label: {
                        if busy {
                            HStack { ProgressView(); Text("识别中…") }
                        } else {
                            Label("AI 识别截图", systemImage: "sparkles")
                        }
                    }
                    .disabled(pickedData == nil || busy)
                }
                if let note {
                    Section {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if hasDraft {
                    Section("停课草稿（逐项可改）") {
                        Picker("类型", selection: $isDay) {
                            Text("单门课停课").tag(false)
                            Text("全天停课").tag(true)
                        }
                        .pickerStyle(.segmented)
                        DatePicker("日期", selection: $draftDate, displayedComponents: .date)
                        if !isDay {
                            Picker("课程", selection: $draftCourseID) {
                                Text("请选择").tag(UUID?.none)
                                ForEach(model.document.courses) { course in
                                    Text(course.name).tag(Optional(course.id))
                                }
                            }
                            if !courseMatched {
                                Text("AI 报的课名没在你的课程里对上号，请在上面手动选一门。")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                            Picker("时段", selection: $draftScope) {
                                Text("仅上午那一节").tag("am")
                                Text("仅下午那一节").tag("pm")
                                Text("当天全部节次").tag("all")
                            }
                        }
                        TextField("原因（可空）", text: $draftReason)
                    }
                }
            }
            .navigationTitle("邮件停课识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认停课") {
                        let name = isDay ? "全天停课" : (model.document.courses.first { $0.id == draftCourseID }?.name ?? "")
                        onConfirm(ClassCancellation(
                            id: UUID(),
                            date: SemesterCalendar.formatCivil(draftDate, calendar: model.calendar),
                            courseID: isDay ? nil : draftCourseID,
                            courseName: name,
                            scope: isDay ? "day" : draftScope,
                            reason: draftReason.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                    .disabled(!hasDraft || (!isDay && draftCourseID == nil))
                }
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        pickedData = GradeImagePrep.preparedJPEG(data) ?? data
                    }
                }
            }
        }
    }

    private func savedKey() -> String? {
        guard let key = GradeAIKeyStore.load(), !key.isEmpty else {
            showKeyField = true
            note = "先粘贴 Gemini 密钥并保存，再点识别（和记分规则识别共用同一个密钥）。"
            return nil
        }
        return key
    }

    private func recognizeText() {
        guard let key = savedKey() else { return }
        busy = true
        Task {
            do {
                let json = try await MailCancelRecognizer.recognize(text: mailText, courses: model.document.courses, today: Date(), calendar: model.calendar, apiKey: key)
                applyResult(json)
            } catch {
                note = (error as? LocalizedError)?.errorDescription ?? "识别失败，稍后再试。"
            }
            busy = false
        }
    }

    private func recognizeImage() {
        guard let data = pickedData, let key = savedKey() else { return }
        busy = true
        Task {
            do {
                let json = try await MailCancelRecognizer.recognize(jpegData: data, courses: model.document.courses, today: Date(), calendar: model.calendar, apiKey: key)
                applyResult(json)
            } catch {
                note = (error as? LocalizedError)?.errorDescription ?? "识别失败，换一张更清晰的截图再试。"
            }
            busy = false
        }
    }

    private func applyResult(_ json: String) {
        guard let draft = CancellationParser.parseAI(json, courses: model.document.courses, calendar: model.calendar) else {
            note = "没从这封邮件里认出停课信息。可以检查一下粘贴的内容，或者直接在假期区手动加一段不上课时段。"
            return
        }
        isDay = draft.scope == "day"
        draftDate = SemesterCalendar.parseCivil(draft.date, calendar: model.calendar) ?? Date()
        draftCourseID = draft.courseID
        draftScope = draft.scope == "day" ? "all" : draft.scope
        draftReason = draft.reason
        courseMatched = draft.courseMatched
        hasDraft = true
        note = (draft.courseMatched || isDay)
            ? "已认出停课信息：核对下面的草稿，点「确认停课」生效。"
            : "日期和时段认出来了，但课程没对上号，请在草稿里手动选一门课再确认。"
    }
}

enum MailCancelRecognizer {
    private static func prompt(courses: [Course], today: Date, calendar: Calendar) -> String {
        let todayText = SemesterCalendar.formatCivil(today, calendar: calendar)
        let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = weekdayNames[max(0, calendar.component(.weekday, from: today) - 1)]
        return """
        你是停课通知识别器。下面是一封老师发的邮件（可能是中文、英语或葡语），请找出其中通知取消课程的信息。今天是 \(todayText)（\(weekday)）。只输出一个 JSON 对象，不要输出任何其他文字。格式：
        {"date": "YYYY-MM-DD", "course": "课程名", "scope": "am", "reason": "原因"}
        规则：
        - date 是停课的日期：「今天」就是今天，「明天」是今天的下一天，「下周X」按今天推算；邮件写了具体日期就按写的来。
        - course 从这个课程列表里选对应的那一门，填列表里的原名：\(courses.map(\.name).joined(separator: "、"))。如果是全校/全天停课，course 填空字符串。
        - scope：只取消上午的课填 "am"，只取消下午的填 "pm"，某门课当天全部取消填 "all"，全天所有课都取消填 "day"；邮件没提时段就填 "all"。
        - reason 是简短原因（如"大风天气"），没有就填空字符串。
        - 如果邮件里根本没有取消课程的信息，输出 {"date": "", "course": "", "scope": "", "reason": ""}。
        """
    }

    static func recognize(text: String, courses: [Course], today: Date, calendar: Calendar, apiKey: String) async throws -> String {
        try await call(parts: [["text": prompt(courses: courses, today: today, calendar: calendar) + "\n\n邮件内容：\n" + text]], apiKey: apiKey)
    }

    static func recognize(jpegData: Data, courses: [Course], today: Date, calendar: Calendar, apiKey: String) async throws -> String {
        try await call(parts: [
            ["text": prompt(courses: courses, today: today, calendar: calendar)],
            ["inlineData": ["mimeType": "image/jpeg", "data": jpegData.base64EncodedString()]]
        ], apiKey: apiKey)
    }

    private static func call(parts: [[String: Any]], apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.1]
        ]
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw GradeRuleRecognizer.Failure.badResponse(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw GradeRuleRecognizer.Failure.noText
        }
        return text
    }
}
