import SwiftUI
import UniformTypeIdentifiers
import ClassdayCore

struct RootView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            TimetableRoot()
                .supplyingAppModel(model)
                .tabItem { Label("课表", systemImage: "square.grid.2x2") }
                .tag(AppTab.timetable)
            AgendaView()
                .supplyingAppModel(model)
                .tabItem { Label("日程", systemImage: "calendar") }
                .tag(AppTab.agenda)
            SettingsView()
                .supplyingAppModel(model)
                .tabItem { Label("我的", systemImage: "person") }
                .tag(AppTab.settings)
        }
        .supplyingAppModel(model)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                Text(banner)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule(style: .continuous).fill(Theme.elevated))
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                    .accessibilityAddTraits(.isStaticText)
                    .task(id: banner) {
                        try? await Task.sleep(nanoseconds: 2_800_000_000)
                        if model.banner == banner { model.banner = nil }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let undo = model.undo, model.presented == nil {
                HStack(spacing: 12) {
                    Text(undo.message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button("撤销") { model.performUndo() }
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.elevated))
                .padding(.horizontal, 16)
                .padding(.bottom, 56)
                .accessibilityElement(children: .combine)
            }
        }
        .fileImporter(isPresented: $model.showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case let .success(url):
                readImport(url)
            case .failure:
                model.banner = "没有读到文件"
            }
        }
        .alert("无法导入", isPresented: Binding(
            get: { model.importErrors != nil },
            set: { if !$0 { model.importErrors = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.importErrors ?? "")
        }
        .confirmationDialog("这份课表有时间重叠", isPresented: Binding(
            get: { model.stagedImport != nil },
            set: { if !$0 { model.stagedImport = nil; model.importWarnings = [] } }
        ), titleVisibility: .visible) {
            Button("仍然导入") { model.commitStagedImport() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.importWarnings.prefix(3).joined(separator: "\n"))
        }
        .confirmationDialog("删除这门课？", isPresented: Binding(
            get: { model.confirmDeleteCourseID != nil },
            set: { if !$0 { model.confirmDeleteCourseID = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = model.confirmDeleteCourseID { model.deleteCourse(id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只从这台手机删除，不会影响任何校园系统。")
        }
        .confirmationDialog("恢复演示数据？", isPresented: $model.confirmReset, titleVisibility: .visible) {
            Button("恢复", role: .destructive) { model.resetDemo() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前课程和学期设置会被示例课表替换。")
        }
        .confirmationDialog("清空全部课程？", isPresented: $model.confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { model.clearCourses() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("学期和节次设置会保留。")
        }
    }

    private func readImport(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            model.stageImport(try Data(contentsOf: url))
        } catch {
            model.banner = "没有读到文件"
        }
    }
}

struct TimetableRoot: View {
    @Environment(\.appModel) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var widthClass
    @Namespace private var zoom

    var body: some View {
        @Bindable var model = model
        ZStack {
            VStack(spacing: 12) {
                if widthClass == .regular {
                    Text("横屏课表")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
                header
                modeBar
                statusBanner
                if let loadError = model.loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                }
                Group {
                    if model.document.appearance.theme.usesOrbit && model.preferSpecialLayout {
                        OrbitWeekView()
                    } else if model.document.appearance.theme.usesCube && model.preferSpecialLayout {
                        CubeWeekView()
                    } else if model.mode == .week {
                        WeekTimetableView(namespace: zoom)
                    } else {
                        DayTimetableView(namespace: zoom)
                    }
                }
                .gesture(
                    MagnificationGesture().onEnded { scale in
                        if scale < 0.9 { model.mode = .day; model.preferSpecialLayout = false }
                        if scale > 1.1 { model.mode = .week }
                    }
                )
                .animation(motion, value: model.weekIndex)
                summary
            }
            .padding(.top, 8)
            if let presented = model.presented {
                CourseDetailView(presentation: presented, namespace: zoom)
                    .supplyingAppModel(model)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(2)
            }
        }
        .background {
            ThemeBackground()
            if model.document.appearance.theme.specialLayout == "glass" {
                ThemeBackground().modifier(MotionParallax())
            }
        }
        .toolbar(model.presented == nil ? Visibility.visible : Visibility.hidden, for: .tabBar)
        .animation(motion, value: model.presented?.id)
        .sheet(item: $model.editor) { route in
            CourseEditorView(route: route, document: model.document, selectedDay: model.selectedDay, calendar: model.calendar)
                .supplyingAppModel(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground { EditorSheetBackground() }
        }
        .sensoryFeedback(.selection, trigger: model.weekIndex)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("课曜")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Menu {
                    Button("新建课程", systemImage: "plus") { model.beginNewCourse() }
                    Button("导入 JSON", systemImage: "square.and.arrow.down") { model.showImporter = true }
                } label: {
                    Text("导入 +")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accentInk)
                }
                .accessibilityLabel("导入或新建课程")
            }
            HStack(spacing: 8) {
                Text(model.document.semester.shortName)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                if model.document.origin == .demo {
                    Text("演示数据")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.hero))
                        .accessibilityLabel("当前是演示数据")
                }
            }
            HStack(alignment: .center, spacing: 12) {
                Text("第 \(model.weekIndex) 周")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 8) {
                    Button { changeWeek(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(model.weekIndex <= 1)
                    Text(SemesterCalendar.weekRangeLabel(week: model.weekIndex, semester: model.document.semester, calendar: model.calendar))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                    Button { changeWeek(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(model.weekIndex >= model.document.semester.totalWeeks)
                }
                .foregroundStyle(Theme.accentInk)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("第 \(model.weekIndex) 周，\(SemesterCalendar.weekRangeLabel(week: model.weekIndex, semester: model.document.semester, calendar: model.calendar))")
                .accessibilityAdjustableAction { direction in
                    changeWeek(direction == .increment ? 1 : -1)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(TimetableMode.allCases) { mode in
                Button {
                    model.mode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.mode == mode ? Theme.ink : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(model.mode == mode ? Theme.card : Color.clear)
                                .shadow(color: model.mode == mode ? .black.opacity(0.04) : .clear, radius: 4, y: 1)
                        )
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
            }
            Button { returnToToday() } label: {
                Text("回本周")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityHint("回到今天所在的周")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.segment))
        .padding(.horizontal, 20)
    }

    private var statusBanner: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            let schedule = model.document.scheduleContext
            let current = ScheduleEngine.currentOccurrence(
                at: tick.date,
                courses: model.document.courses,
                semester: model.document.semester,
                calendar: model.calendar,
                context: schedule
            )
            let next = ScheduleEngine.nextOccurrence(
                after: tick.date,
                courses: model.document.courses,
                semester: model.document.semester,
                calendar: model.calendar,
                context: schedule
            )
            if let text = ScheduleCopy.statusBanner(current: current, next: next, now: tick.date, calendar: model.calendar) {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .accessibilityLabel(text)
            }
        }
    }

    private var summary: some View {
        let summary = ScheduleCopy.weekSummary(occurrences: model.occurrences())
        return HStack {
            Text(summary.headline)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(summary.aside)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.elevated))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private func changeWeek(_ delta: Int) {
        withAnimation(motion) { model.shiftWeek(by: delta) }
    }

    private func returnToToday() {
        withAnimation(motion) { model.returnToCurrentWeek() }
    }
}
