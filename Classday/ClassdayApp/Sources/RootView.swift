import SwiftUI
import UniformTypeIdentifiers
import ClassdayCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom

    var body: some View {
        @Bindable var model = model
        ZStack {
            TabView(selection: $model.tab) {
                TodayView()
                    .tabItem { Label("今日", systemImage: "sun.max") }
                    .tag(AppTab.today)
                WeekJournalView()
                    .tabItem { Label("周览", systemImage: "calendar") }
                    .tag(AppTab.week)
                CoursesView()
                    .tabItem { Label("课程", systemImage: "books.vertical") }
                    .tag(AppTab.courses)
                SettingsView()
                    .tabItem { Label("我的", systemImage: "person") }
                    .tag(AppTab.settings)
            }
            if let presented = model.presented {
                CourseDetailView(presentation: presented, namespace: zoom)
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
        .toolbar(model.presented == nil ? .visible : .hidden, for: .tabBar)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: model.presented?.id)
        .sheet(item: $model.editor) { route in
            CourseEditorView(route: route, document: model.document, selectedDay: model.selectedDay, calendar: model.calendar)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground { EditorSheetBackground() }
        }
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
        .confirmationDialog("导入分享的课表？", isPresented: Binding(
            get: { model.pendingShare != nil },
            set: { if !$0 { model.cancelSharedTimetable() } }
        )) {
            Button("替换当前课表") { model.commitSharedTimetable() }
            Button("取消", role: .cancel) { model.cancelSharedTimetable() }
        } message: {
            Text("会用分享的课表替换当前课表。当前课表会先自动存一份到课表库里，之后可以切回来。")
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

struct JournalPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct CourseGlyphTile: View {
    var name: String
    var colorID: String
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.44, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.courseInk(colorID, scheme: scheme))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(Theme.courseBackground(colorID, scheme: scheme))
            )
    }
}

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var showNewEvent = false
    @State private var eventToEdit: PersonalEvent?

    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            content(now: tick.date)
        }
        .toolbar(model.presented == nil ? .visible : .hidden, for: .tabBar)
        .sheet(isPresented: $model.showExams) {
            ExamsView()
        }
        .sheet(isPresented: $showNewEvent) {
            EventEditorView(existing: nil)
        }
        .sheet(item: $eventToEdit) { event in
            EventEditorView(existing: event)
        }
    }

    private func content(now: Date) -> some View {
        let todays = model.occurrences(on: now).sorted { $0.start < $1.start }
        let next = todays.first { $0.end > now }
        let doneCount = todays.filter { $0.end <= now }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(now: now)
                if model.document.courses.isEmpty {
                    emptyAllCard
                        .padding(.top, 18)
                } else if let next {
                    nextHero(occ: next, now: now)
                        .padding(.top, 18)
                    progressRow(done: doneCount, total: todays.count)
                        .padding(.top, 14)
                } else if todays.isEmpty {
                    restDayCard(now: now)
                        .padding(.top, 18)
                } else {
                    allDoneCard(now: now)
                        .padding(.top, 18)
                }
                if let exam = nextExam(now: now), let start = examStart(exam) {
                    examCountdownCard(exam: exam, start: start, now: now)
                        .padding(.top, 12)
                }
                let eventsToday = model.events(on: now)
                if !todays.isEmpty || !eventsToday.isEmpty {
                    Text(eventsToday.isEmpty ? "今天的课" : "今天的安排")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                    mergedTimeline(courses: todays, events: eventsToday, now: now)
                }
                let pending = pendingHomework()
                if !pending.isEmpty {
                    homeworkSection(pending, now: now)
                }
                if let loadError = model.loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func header(now: Date) -> some View {
        let cal = model.calendar
        let title = "\(cal.component(.month, from: now))月\(cal.component(.day, from: now))日 · \(ScheduleCopy.weekdayName(SemesterCalendar.isoWeekday(now, calendar: cal)))"
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Text(model.document.semester.shortName)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                    if model.document.origin == .demo {
                        Text("演示数据")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accentInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.hero))
                    }
                }
            }
            Spacer()
            Menu {
                Button("新建课程", systemImage: "plus") { model.beginNewCourse() }
                Button("新建日程", systemImage: "calendar.badge.plus") { showNewEvent = true }
                Button("导入 JSON", systemImage: "square.and.arrow.down") { model.showImporter = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.elevated))
            }
            .accessibilityLabel("新建或导入课程")
        }
    }

    private func nextHero(occ: Occurrence, now: Date) -> some View {
        let bg = Theme.courseBackground(occ.colorID, scheme: scheme)
        let ink = Theme.courseInk(occ.colorID, scheme: scheme)
        let ongoing = occ.start <= now && occ.end > now
        return Button {
            model.present(courseID: occ.courseID, meetingID: occ.meetingID)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(ongoing ? "正在上课" : "下一节课")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(ink.opacity(0.16)))
                    Spacer()
                    Text(ScheduleCopy.upcomingFootnote(from: now, to: occ.start, calendar: model.calendar))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.75))
                }
                HStack(alignment: .center, spacing: 14) {
                    CourseGlyphTile(name: occ.name, colorID: occ.colorID, size: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(occ.name)
                            .font(.system(size: 21, weight: .heavy, design: .rounded))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Text("\(occ.location) · \(ScheduleCopy.periodSpan(occ.startPeriod, occ.endPeriod))")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(ink.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(ScheduleCopy.hhmm(occ.start, calendar: model.calendar))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                }
                .padding(.top, 14)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [bg, bg.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(Color.white.opacity(scheme == .dark ? 0.05 : 0.35))
                        .frame(width: 120, height: 120)
                        .offset(x: 40, y: -55)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: bg.opacity(0.3), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(JournalPressStyle())
        .accessibilityLabel("\(occ.name)，\(ScheduleCopy.hhmm(occ.start, calendar: model.calendar))，\(occ.location)")
    }

    private func progressRow(done: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(done == total && total > 0 ? Theme.accentInk : Theme.secondary)
            }
            .frame(width: 34, height: 34)
            Text(done >= total ? "今天的课都上完了" : "今天已上 \(done) 节 · 还剩 \(total - done) 节")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.elevated))
        .accessibilityElement(children: .combine)
    }

    private func timeline(items: [Occurrence], now: Date) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { _, occ in
                timelineRow(occ: occ, now: now)
            }
        }
    }

    private func mergedTimeline(courses: [Occurrence], events: [PersonalEvent], now: Date) -> some View {
        let cal = model.calendar
        var entries: [(start: Date, course: Occurrence?, event: PersonalEvent?)] = []
        entries += courses.map { ($0.start, $0, nil) }
        entries += events.compactMap { event in
            CivilStamp.date(from: event.startISO, calendar: cal).map { ($0, nil, event) }
        }
        entries.sort { $0.start < $1.start }
        return VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                if let course = entry.course {
                    timelineRow(occ: course, now: now)
                } else if let event = entry.event {
                    eventRow(event, now: now)
                }
            }
        }
    }

    private func eventRow(_ event: PersonalEvent, now: Date) -> some View {
        let cal = model.calendar
        let start = CivilStamp.date(from: event.startISO, calendar: cal) ?? now
        let end = CivilStamp.date(from: event.endISO, calendar: cal) ?? start
        let past = end <= now
        let bar = Theme.courseBackground("purple", scheme: scheme)
        let ink = Theme.courseInk("purple", scheme: scheme)
        return Button {
            eventToEdit = event
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ScheduleCopy.hhmm(start, calendar: cal))
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(past ? Theme.secondary : Theme.ink)
                    Text(ScheduleCopy.hhmm(end, calendar: cal))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                }
                .frame(width: 46)
                Capsule()
                    .fill(past ? Theme.line : bar)
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(event.title)
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            .foregroundStyle(past ? Theme.secondary : Theme.ink)
                            .lineLimit(1)
                        Text("日程")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule(style: .continuous).fill(bar))
                    }
                    Text(event.note.isEmpty ? "个人日程" : event.note)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if past {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ink.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
        }
        .buttonStyle(JournalPressStyle())
        .accessibilityLabel("日程 \(event.title)，\(ScheduleCopy.hhmm(start, calendar: cal))")
    }

    private func timelineRow(occ: Occurrence, now: Date) -> some View {
        let past = occ.end <= now
        let ongoing = occ.start <= now && occ.end > now
        let bg = Theme.courseBackground(occ.colorID, scheme: scheme)
        let ink = Theme.courseInk(occ.colorID, scheme: scheme)
        return Button {
            model.present(courseID: occ.courseID, meetingID: occ.meetingID)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ScheduleCopy.hhmm(occ.start, calendar: model.calendar))
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(past ? Theme.secondary : Theme.ink)
                    Text(ScheduleCopy.hhmm(occ.end, calendar: model.calendar))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                }
                .frame(width: 46)
                Capsule()
                    .fill(past ? Theme.line : bg)
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(occ.name)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(past ? Theme.secondary : Theme.ink)
                        .lineLimit(1)
                    Text("\(occ.location) · \(ScheduleCopy.periodSpan(occ.startPeriod, occ.endPeriod))")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if ongoing {
                    Text("进行中")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(bg))
                } else if past {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(past ? Theme.elevated.opacity(0.6) : Theme.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ongoing ? bg : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(JournalPressStyle())
    }

    private func tomorrowLine(now: Date) -> String? {
        guard let next = ScheduleEngine.nextOccurrence(
            after: now,
            courses: model.document.courses,
            semester: model.document.semester,
            calendar: model.calendar,
            context: model.document.scheduleContext
        ) else { return nil }
        return "接下来：\(next.name) · \(ScheduleCopy.upcomingFootnote(from: now, to: next.start, calendar: model.calendar))"
    }

    private var emptyAllCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.accentInk)
            Text("还没有课程")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("点右上角 + 新建，或者导入一份课表 JSON 开始。")
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.elevated))
    }

    private func restDayCard(now: Date) -> some View {
        softMessageCard(
            icon: "sun.max.fill",
            title: "今天没有课",
            message: tomorrowLine(now: now) ?? "这一周的课都结束了，好好休息。"
        )
    }

    private func allDoneCard(now: Date) -> some View {
        softMessageCard(
            icon: "checkmark.seal.fill",
            title: "今天的课上完了",
            message: tomorrowLine(now: now) ?? "好好休息，明天见。"
        )
    }

    private func softMessageCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.accentInk)
            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.elevated))
        .accessibilityElement(children: .combine)
    }

    private func examStart(_ exam: ExamEvent) -> Date? {
        CivilStamp.date(from: exam.startISO, calendar: model.calendar)
    }

    private func nextExam(now: Date) -> ExamEvent? {
        model.document.exams
            .compactMap { exam in examStart(exam).map { (exam, $0) } }
            .filter { $0.1 > now }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }

    private func daysUntil(_ date: Date, now: Date) -> Int {
        let cal = model.calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }

    private func examCountdownCard(exam: ExamEvent, start: Date, now: Date) -> some View {
        let bg = Theme.courseBackground("orange", scheme: scheme)
        let ink = Theme.courseInk("orange", scheme: scheme)
        let days = daysUntil(start, now: now)
        let cal = model.calendar
        let subtitle = "\(cal.component(.month, from: start))月\(cal.component(.day, from: start))日 \(ScheduleCopy.weekdayName(SemesterCalendar.isoWeekday(start, calendar: cal))) \(ScheduleCopy.hhmm(start, calendar: cal)) · \(exam.location)"
        return Button {
            model.showExams = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("考试倒计时")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(ink.opacity(0.16)))
                    Text(exam.note.isEmpty ? exam.courseName : "\(exam.courseName) · \(exam.note)")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .padding(.top, 10)
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.75))
                        .lineLimit(1)
                        .padding(.top, 3)
                }
                Spacer(minLength: 0)
                VStack(spacing: 1) {
                    Text(days <= 0 ? "今天" : "\(days)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                    if days > 0 {
                        Text("天后开考")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.7))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [bg, bg.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(Color.white.opacity(scheme == .dark ? 0.05 : 0.35))
                        .frame(width: 120, height: 120)
                        .offset(x: 40, y: -55)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: bg.opacity(0.3), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(JournalPressStyle())
        .accessibilityLabel("考试倒计时，\(exam.courseName)，\(subtitle)")
    }

    private func pendingHomework() -> [HomeworkTask] {
        model.document.homework
            .filter { !$0.done }
            .sorted { (CivilStamp.date(from: $0.dueISO, calendar: model.calendar) ?? .distantFuture) < (CivilStamp.date(from: $1.dueISO, calendar: model.calendar) ?? .distantFuture) }
    }

    private func homeworkSection(_ items: [HomeworkTask], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("待办作业")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        Divider().padding(.leading, 47)
                    }
                    homeworkRow(task, now: now)
                }
                if items.count > 5 {
                    Text("还有 \(items.count - 5) 项未完成，在「我的 · 学习」里查看全部")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.elevated))
        }
    }

    private func homeworkRow(_ task: HomeworkTask, now: Date) -> some View {
        Button {
            model.toggleHomework(task.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.secondary.opacity(0.55))
                Text(task.courseName.isEmpty ? task.title : "\(task.courseName) · \(task.title)")
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                dueChip(task, now: now)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("作业 \(task.title)，点按标记完成")
    }

    private func dueChip(_ task: HomeworkTask, now: Date) -> some View {
        let due = CivilStamp.date(from: task.dueISO, calendar: model.calendar)
        let days = due.map { daysUntil($0, now: now) }
        let (text, colorID): (String, String) = {
            guard let due, let days else { return ("", "orange") }
            if days < 0 { return ("已逾期", "pink") }
            if days == 0 { return ("今天截止", "orange") }
            if days == 1 { return ("明天截止", "orange") }
            let cal = model.calendar
            return ("\(cal.component(.month, from: due))月\(cal.component(.day, from: due))日截止", "gray")
        }()
        return Text(text)
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundStyle(colorID == "gray" ? Theme.secondary : Theme.courseInk(colorID, scheme: scheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(colorID == "gray" ? Theme.segment : Theme.courseBackground(colorID, scheme: scheme)))
    }
}

struct CoursesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("全部课程")
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("\(model.document.courses.count) 门")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                }
                if model.document.courses.isEmpty {
                    Text("还没有课程，从「今日」页右上角 + 添加。")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.document.courses.sorted { $0.name < $1.name }, id: \.id) { course in
                            courseCard(course)
                        }
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .toolbar(model.presented == nil ? .visible : .hidden, for: .tabBar)
    }

    private func courseCard(_ course: Course) -> some View {
        let next = nextOccurrence(course: course)
        return Button {
            let meetingID = next?.meetingID ?? course.meetings.first?.id
            if let meetingID {
                model.present(courseID: course.id, meetingID: meetingID)
            }
        } label: {
            HStack(spacing: 13) {
                CourseGlyphTile(name: course.name, colorID: course.colorID, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(course.teacher.isEmpty ? course.location : "\(course.teacher) · \(course.location)")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("下一次")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                    Text(next.map { ScheduleCopy.upcomingFootnote(from: Date(), to: $0.start, calendar: model.calendar) } ?? "已结束")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accentInk)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.secondary.opacity(0.6))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.elevated))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(JournalPressStyle())
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
}

struct ExamsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let next = upcoming.first, let start = start(of: next) {
                        heroCard(exam: next, start: start)
                    }
                    if upcoming.isEmpty && past.isEmpty {
                        Text("还没有考试。从 Fénix 或日历导入的考试会自动出现在这里，也可以点右上角 + 手动添加。")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Theme.secondary)
                            .padding(.top, 24)
                    }
                    if !upcoming.isEmpty {
                        Text("全部考试")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 22)
                            .padding(.bottom, 10)
                        VStack(spacing: 10) {
                            ForEach(upcoming, id: \.id) { exam in
                                examRow(exam)
                            }
                        }
                    }
                    if !past.isEmpty {
                        Text("已结束")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.secondary)
                            .padding(.top, 22)
                            .padding(.bottom, 10)
                        VStack(spacing: 10) {
                            ForEach(past, id: \.id) { exam in
                                examRow(exam)
                                    .opacity(0.55)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("考试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加考试")
                }
            }
            .sheet(isPresented: $showAdd) {
                ExamEditorView()
            }
        }
    }

    private func start(of exam: ExamEvent) -> Date? {
        CivilStamp.date(from: exam.startISO, calendar: model.calendar)
    }

    private var upcoming: [ExamEvent] {
        let now = Date()
        return model.document.exams
            .compactMap { exam in start(of: exam).map { (exam, $0) } }
            .filter { $0.1 > now }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private var past: [ExamEvent] {
        let now = Date()
        return model.document.exams
            .compactMap { exam in start(of: exam).map { (exam, $0) } }
            .filter { $0.1 <= now }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func daysUntil(_ date: Date) -> Int {
        let cal = model.calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
    }

    private func colorID(for exam: ExamEvent) -> String {
        model.document.courses.first { $0.name == exam.courseName }?.colorID ?? "orange"
    }

    private func subtitle(of exam: ExamEvent, start: Date) -> String {
        let cal = model.calendar
        return "\(cal.component(.month, from: start))月\(cal.component(.day, from: start))日 \(ScheduleCopy.hhmm(start, calendar: cal)) · \(exam.location)"
    }

    private func heroCard(exam: ExamEvent, start: Date) -> some View {
        let bg = Theme.courseBackground("orange", scheme: scheme)
        let ink = Theme.courseInk("orange", scheme: scheme)
        let days = daysUntil(start)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("最近一场")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(ink.opacity(0.16)))
                Text(exam.note.isEmpty ? exam.courseName : "\(exam.courseName) · \(exam.note)")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .padding(.top, 10)
                Text(subtitle(of: exam, start: start))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.75))
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(days <= 0 ? "今天" : "\(days)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                if days > 0 {
                    Text("天后开考")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.7))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [bg, bg.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.white.opacity(scheme == .dark ? 0.05 : 0.35))
                    .frame(width: 120, height: 120)
                    .offset(x: 40, y: -55)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: bg.opacity(0.3), radius: 14, x: 0, y: 8)
    }

    private func examRow(_ exam: ExamEvent) -> some View {
        let start = start(of: exam)
        let days = start.map { daysUntil($0) }
        return HStack(spacing: 13) {
            CourseGlyphTile(name: exam.courseName, colorID: colorID(for: exam), size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(exam.courseName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(start.map { subtitle(of: exam, start: $0) } ?? exam.startISO)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let days {
                Text(days <= 0 ? "已结束" : "还有 \(days) 天")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.courseInk("orange", scheme: scheme))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(Theme.courseBackground("orange", scheme: scheme)))
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.elevated))
        .contextMenu {
            Button("删除这场考试", systemImage: "trash", role: .destructive) {
                model.deleteExam(exam.id)
            }
        }
    }
}

struct ExamEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var courseName = ""
    @State private var location = ""
    @State private var start = Date().addingTimeInterval(86_400)
    @State private var end = Date().addingTimeInterval(86_400 + 7_200)

    var body: some View {
        NavigationStack {
            Form {
                TextField("课程名，如 高等数学", text: $courseName)
                TextField("地点，如 教学楼 A · 301", text: $location)
                DatePicker("开始时间", selection: $start)
                DatePicker("结束时间", selection: $end)
            }
            .navigationTitle("添加考试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        model.addExam(
                            courseName: courseName.trimmingCharacters(in: .whitespaces),
                            location: location.trimmingCharacters(in: .whitespaces),
                            start: start,
                            end: max(end, start)
                        )
                        dismiss()
                    }
                    .disabled(courseName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct EventEditorView: View {
    var existing: PersonalEvent?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var day: Date
    @State private var startTime: Date
    @State private var endTime: Date

    init(existing: PersonalEvent?) {
        self.existing = existing
        let cal = Calendar.current
        let start = existing.flatMap { CivilStamp.date(from: $0.startISO) }
            ?? cal.date(bySettingHour: 19, minute: 0, second: 0, of: Date())
            ?? Date()
        let end = existing.flatMap { CivilStamp.date(from: $0.endISO) }
            ?? start.addingTimeInterval(3600)
        _title = State(initialValue: existing?.title ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _day = State(initialValue: start)
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日程") {
                    TextField("标题，如 健身", text: $title)
                    TextField("备注（可选）", text: $note)
                }
                Section("时间") {
                    DatePicker("日期", selection: $day, displayedComponents: .date)
                    DatePicker("开始", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                if let existing {
                    Section {
                        Button("删除这条日程", role: .destructive) {
                            model.deleteEvent(existing.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建日程" : "编辑日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let cal = model.calendar
        func compose(_ time: Date) -> Date {
            let t = cal.dateComponents([.hour, .minute], from: time)
            return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
        }
        let start = compose(startTime)
        let end = max(compose(endTime), start.addingTimeInterval(900))
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanNote = note.trimmingCharacters(in: .whitespaces)
        if let existing {
            model.updateEvent(existing.id, title: cleanTitle, note: cleanNote, start: start, end: end)
        } else {
            model.addEvent(title: cleanTitle, note: cleanNote, start: start, end: end)
        }
        dismiss()
    }
}
