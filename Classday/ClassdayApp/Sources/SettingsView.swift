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
    @State private var errorText: String?
    @State private var exporting = false
    @State private var exportDocument = JSONFileDocument(data: Data())

    init() {
        _semester = State(initialValue: DemoData.makeSemester())
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("我的")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if !model.appGroupAvailable {
                    notice("未能访问 App Group「\(AppGroup.identifier)」。课程仍保存在本机，但桌面小组件读不到。请在签名里为 App 和小组件打开同一个 App Group。")
                }
                if let loadError = model.loadError {
                    notice(loadError)
                }
                section("学期") {
                    labeledField("名称", text: $semester.name)
                    labeledField("简称", text: $semester.shortName)
                    DatePicker(
                        "开始日期",
                        selection: startDateBinding,
                        displayedComponents: .date
                    )
                    Stepper(value: $semester.totalWeeks, in: 1...30) {
                        Text("共 \(semester.totalWeeks) 周")
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                    Button("保存学期") {
                        if let error = model.updateSemester(semester) {
                            errorText = error
                        } else {
                            errorText = nil
                            semester = model.document.semester
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
                section("上课时间") {
                    ForEach(semester.periods) { period in
                        HStack {
                            Text("第 \(period.index) 节")
                                .frame(width: 64, alignment: .leading)
                            DatePicker("开始", selection: timeBinding(period.index, isStart: true), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("–")
                            DatePicker("结束", selection: timeBinding(period.index, isStart: false), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .font(.system(size: 14))
                    }
                    HStack {
                        Button("添加一节") { addPeriod() }
                        Spacer()
                        Button("删除最后一节") { removeLastPeriod() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    Button("保存节次与学期") {
                        if let error = model.updateSemester(semester) {
                            errorText = error
                        } else {
                            errorText = nil
                            semester = model.document.semester
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    Text("节次按序号连续排列。删除只允许从最后一节开始，并且不能还有课程占用它。保存会连同学期名称、周数和默认提醒一起写入本机。")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                section("提醒") {
                    Stepper(value: $semester.defaultReminderMinutes, in: 0...120) {
                        Text(semester.defaultReminderMinutes == 0 ? "默认不提醒" : "默认提前 \(semester.defaultReminderMinutes) 分钟")
                    }
                    Text("通知权限：\(model.notificationStatusText)")
                        .foregroundStyle(Theme.secondary)
                    Button("检查通知权限") {
                        Task {
                            _ = await ReminderScheduler.shared.requestAuthorization()
                            await model.refreshNotificationStatus()
                            _ = model.updateSemester(semester)
                        }
                    }
                    if model.notificationStatusText == "已拒绝" {
                        Button("打开系统设置") { openSettings() }
                    }
                    Text("开启某门课的提醒时才会向系统请求权限。允许后，课间会在本地安排最多 \(NotificationPlan.pendingLimit) 条即将上课的通知。")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                section("数据") {
                    Button("导出 JSON") {
                        if let data = try? model.exportData() {
                            exportDocument = JSONFileDocument(data: data)
                            exporting = true
                        }
                    }
                    Button("导入 JSON") { model.showImporter = true }
                    Button("恢复演示数据") { model.confirmReset = true }
                    Button("清空课程") { model.confirmClear = true }
                    Text("导入会替换当前课表。文件需要 schemaVersion \(StoreDocument.currentSchema)。没有校园账号，也不会查询成绩。")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                section("关于") {
                    Text("课间 / Classday")
                        .font(.system(size: 17, weight: .semibold))
                    Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                        .foregroundStyle(Theme.secondary)
                    Text("独立设计的本地课表。界面参考了常见的周课表和彩色课程卡片，不是「超级课程表」官方产品，也不追求与它功能一致。课程、教师、教室和时间都可以是你自己的数据；首次打开时的示例已标明为演示数据。")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            guard !didLoadSemester else { return }
            didLoadSemester = true
            semester = model.document.semester
        }
        .onChange(of: model.document.semester) { _, newValue in
            semester = newValue
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "课间课表.json"
        ) { result in
            if case .failure = result { model.banner = "导出没有完成" }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(Theme.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
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
        let endMinutes = min(startMinutes + 45, 23 * 60 + 50)
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
