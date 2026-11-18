import SwiftUI
import ClassdayCore

private struct GhostBlock: View {
    var title: String
    var caption: String
    var fill: Color
    var border: Color
    var width: CGFloat
    var height: CGFloat
    var x: CGFloat
    var y: CGFloat
    var accessibilityText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(2)
            Text(caption)
                .font(.system(size: 9, weight: .medium))
        }
        .padding(4)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(border, lineWidth: 1.5)
        }
        .position(x: x, y: y)
        .allowsHitTesting(false)
        .accessibilityLabel(accessibilityText)
    }
}

struct CourseBlockView: View {
    var occurrence: Occurrence
    var namespace: Namespace.ID
    var showsProgress: Bool
    var onOpen: () -> Void
    var onEdit: () -> Void
    var onReschedule: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let current = showsProgress && occurrence.start <= context.date && context.date < occurrence.end
            block(current: current, progress: current ? ScheduleCopy.progress(from: occurrence.start, to: occurrence.end, now: context.date) : nil)
        }
        // No matchedGeometryEffect here: the detail hero lives inside a
        // ScrollView, and geometry-matched destinations in scroll views can
        // resolve to a collapsed frame (the hero rendered as a thin capsule).
        // The detail uses its own scale/opacity transition instead.
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("查看课程详情")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "查看详情", onOpen)
        .accessibilityAction(named: "编辑", onEdit)
        .accessibilityAction(named: "调整时间", onReschedule)
    }

    private func block(current: Bool, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(occurrence.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(occurrence.locationShort)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !occurrence.parityLabel.isEmpty {
                Text(occurrence.parityLabel)
                    .font(.system(size: 8, weight: .bold))
            }
            Spacer(minLength: 0)
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.courseInk(occurrence.colorID, scheme: scheme).opacity(0.2))
                        Capsule()
                            .fill(Theme.courseInk(occurrence.colorID, scheme: scheme))
                            .frame(width: max(4, geo.size.width * progress))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Theme.courseInk(occurrence.colorID, scheme: scheme))
        .background(
            Theme.courseBackground(occurrence.colorID, scheme: scheme),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            if current && !reduceMotion {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.courseInk(occurrence.colorID, scheme: scheme).opacity(0.45), lineWidth: 1)
            }
        }
    }

    private var label: String {
        "\(occurrence.name)，\(ScheduleCopy.weekdayName(occurrence.weekday))\(ScheduleCopy.periodSpan(occurrence.startPeriod, occurrence.endPeriod))，\(occurrence.location)，\(occurrence.timeText)"
    }
}

struct WeekTimetableView: View {
    var namespace: Namespace.ID
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 46

    /// 周览两种形态：时间轴网格 / 日程卡片列表（选择会记住）。
    @AppStorage("classday.week.listMode") private var listMode = false

    var body: some View {
        let periods = model.document.semester.periods.sorted { $0.index < $1.index }
        let dates = SemesterCalendar.dates(inWeek: model.weekIndex, semester: model.document.semester, calendar: model.calendar)
        VStack(spacing: 8) {
            Picker("周览形态", selection: $listMode) {
                Text("时间轴").tag(false)
                Text("日程列表").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("切换周览形态")

            if listMode {
                ScrollView {
                    weekCardList(dates: dates)
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
            } else {
                GeometryReader { geo in
                    let timeWidth: CGFloat = 46
                    let columnWidth = max(30, (geo.size.width - timeWidth) / 7)
                    VStack(spacing: 6) {
                        dayHeader(dates: dates, timeWidth: timeWidth, columnWidth: columnWidth)
                        ScrollView {
                            grid(periods: periods, timeWidth: timeWidth, columnWidth: columnWidth)
                                .frame(height: rowHeight * CGFloat(max(periods.count, 1)))
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .simultaneousGesture(weekSwipe)
    }

    /// 日程卡片列表：按天分组，一天没课也显示（写明「无课」），方便一眼看完一周。
    @ViewBuilder
    private func weekCardList(dates: [Date]) -> some View {
        let items = model.occurrences()
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                let weekday = SemesterCalendar.isoWeekday(date, calendar: model.calendar)
                let dayItems = items
                    .filter { $0.weekday == weekday }
                    .sorted { $0.startPeriod < $1.startPeriod }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(ScheduleCopy.weekdayName(weekday)) \(ScheduleCopy.dayNumber(date, calendar: model.calendar))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(model.calendar.isDateInToday(date) ? Theme.accent : Theme.secondary)
                        Spacer()
                        Text(dayItems.isEmpty ? "无课" : "\(dayItems.count) 节")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    if dayItems.isEmpty {
                        Text("这天没有课")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        ForEach(dayItems) { item in
                            Button {
                                model.select(day: date)
                            } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Theme.courseBackground(item.colorID, scheme: scheme))
                                        .frame(width: 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                        Text("\(item.timeText) · \(item.locationShort.isEmpty ? "地点未填" : item.locationShort)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.secondary.opacity(0.5))
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func dayHeader(dates: [Date], timeWidth: CGFloat, columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeWidth, height: 1)
            ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                let weekday = SemesterCalendar.isoWeekday(date, calendar: model.calendar)
                let isToday = model.calendar.isDateInToday(date)
                Button {
                    model.select(day: date)
                } label: {
                    VStack(spacing: 4) {
                        Text(ScheduleCopy.weekdayShort(weekday))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                        Text(ScheduleCopy.dayNumber(date, calendar: model.calendar))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isToday ? Color.white : Theme.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(isToday ? Theme.accent : Color.clear))
                    }
                    .frame(width: columnWidth)
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityLabel("\(ScheduleCopy.weekdayName(weekday)) \(ScheduleCopy.dayNumber(date, calendar: model.calendar))")
                .accessibilityAddTraits(isToday ? .isSelected : [])
            }
        }
    }

    private func grid(periods: [PeriodTemplate], timeWidth: CGFloat, columnWidth: CGFloat) -> some View {
        let items = model.occurrences()
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(periods) { period in
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(period.index)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                            Text(String(period.start.prefix(5)))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.secondary)
                        }
                        .frame(width: timeWidth - 4, alignment: .trailing)
                        .padding(.top, 4)
                        Rectangle()
                            .fill(Theme.line)
                            .frame(height: 0.5)
                            .padding(.leading, 6)
                    }
                    .frame(height: rowHeight, alignment: .top)
                }
            }
            ForEach(items) { item in
                placedBlock(item, timeWidth: timeWidth, columnWidth: columnWidth, periodCount: periods.count)
            }
            if let drag = model.drag {
                ghost(drag: drag, columnWidth: columnWidth, timeWidth: timeWidth)
            }
        }
        .coordinateSpace(name: "week-grid")
    }

    private func placedBlock(_ item: Occurrence, timeWidth: CGFloat, columnWidth: CGFloat, periodCount: Int) -> some View {
        let span = CGFloat(item.endPeriod - item.startPeriod + 1)
        let height = rowHeight * span - 4
        let width = columnWidth - 4
        let centerX = timeWidth + columnWidth * CGFloat(item.weekday - 1) + columnWidth / 2
        let centerY = rowHeight * CGFloat(item.startPeriod - 1) + (height + 4) / 2
        let hidden = model.drag?.meetingID == item.meetingID || model.presented?.meetingID == item.meetingID
        let priority = Double(1000 - (item.weekday * 20 + item.startPeriod))
        return CourseBlockView(
            occurrence: item,
            namespace: namespace,
            showsProgress: true,
            onOpen: { model.present(courseID: item.courseID, meetingID: item.meetingID) },
            onEdit: { model.editor = .edit(item.courseID) },
            onReschedule: { model.editor = .reschedule(courseID: item.courseID, meetingID: item.meetingID) }
        )
        .frame(width: width, height: height)
        .position(x: centerX, y: centerY)
        .opacity(hidden ? 0 : 1)
        .gesture(rescheduleGesture(for: item, timeWidth: timeWidth, columnWidth: columnWidth, periodCount: periodCount))
        .accessibilitySortPriority(priority)
        .accessibilityHidden(hidden)
    }

    private func ghost(drag: DragSession, columnWidth: CGFloat, timeWidth: CGFloat) -> some View {
        let blockHeight = rowHeight * CGFloat(drag.duration) - 4
        let blockWidth = columnWidth - 4
        let originX = timeWidth + columnWidth * CGFloat(drag.proposedWeekday - 1) + columnWidth / 2
        let originY = rowHeight * CGFloat(max(0, drag.proposedStart - 1)) + (blockHeight + 4) / 2
        let validation = model.dragValidation()
        let conflict: Bool
        let caption: String
        switch validation {
        case .some(.conflict):
            conflict = true
            caption = "时间冲突"
        case .some(.outOfBounds):
            conflict = true
            caption = "超出节次"
        default:
            conflict = !drag.fingerInside
            caption = drag.fingerInside ? "松开调整" : "松开取消"
        }
        let fill = conflict ? Color.red.opacity(0.16) : Theme.hero
        let border = conflict ? Color.red : Theme.accent
        let title = model.course(drag.courseID)?.name ?? "课程"
        let label = "正在调整时间，\(caption)"
        return GhostBlock(
            title: title,
            caption: caption,
            fill: fill,
            border: border,
            width: blockWidth,
            height: blockHeight,
            x: originX,
            y: originY,
            accessibilityText: label
        )
    }

    private func rescheduleGesture(
        for item: Occurrence,
        timeWidth: CGFloat,
        columnWidth: CGFloat,
        periodCount: Int
    ) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("week-grid")))
            .onChanged { value in
                switch value {
                case .first(true):
                    if model.drag?.meetingID != item.meetingID {
                        Haptics.pickUp()
                        model.beginDrag(item)
                    }
                case .second(true, let drag?):
                    let x = drag.location.x - timeWidth
                    let y = drag.location.y
                    let width = columnWidth * 7
                    let height = rowHeight * CGFloat(periodCount)
                    let inside = x >= 0 && y >= 0 && x <= width && y <= height
                    let weekday = min(7, max(1, Int(x / max(columnWidth, 1)) + 1))
                    let period = min(periodCount, max(1, Int(y / max(rowHeight, 1)) + 1))
                    model.updateDrag(
                        weekday: inside ? weekday : item.weekday,
                        startPeriod: inside ? period : item.startPeriod,
                        fingerInside: inside
                    )
                default:
                    break
                }
            }
            .onEnded { _ in
                if model.drag?.meetingID == item.meetingID {
                    model.commitDrag()
                }
            }
    }

    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard model.drag == nil else { return }
                guard abs(value.translation.width) > abs(value.translation.height) + 12, abs(value.translation.width) > 48 else { return }
                let delta = value.translation.width < 0 ? 1 : -1
                withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                    model.shiftWeek(by: delta)
                }
            }
    }
}

struct WeekJournalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var eventToEdit: PersonalEvent?

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(1...7, id: \.self) { weekday in
                    dayCard(weekday: weekday)
                        .padding(.top, 10)
                }
                summaryCard
                    .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .toolbar(model.presented == nil ? .visible : .hidden, for: .tabBar)
        .sensoryFeedback(.selection, trigger: model.weekIndex)
        .sheet(item: $eventToEdit) { event in
            EventEditorView(existing: event)
        }
    }

    private var header: some View {
        let currentWeek = SemesterCalendar.weekIndex(for: Date(), semester: model.document.semester, calendar: model.calendar) ?? model.weekIndex
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("第 \(model.weekIndex) 周")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(SemesterCalendar.weekRangeLabel(week: model.weekIndex, semester: model.document.semester, calendar: model.calendar))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if model.weekIndex != currentWeek {
                    Button {
                        withAnimation(motion) { model.returnToCurrentWeek() }
                    } label: {
                        Text("回本周")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accentInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Capsule(style: .continuous).fill(Theme.elevated))
                    }
                    .buttonStyle(JournalPressStyle())
                }
                Button {
                    withAnimation(motion) { model.shiftWeek(by: -1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.elevated))
                }
                .buttonStyle(JournalPressStyle())
                .disabled(model.weekIndex <= 1)
                Button {
                    withAnimation(motion) { model.shiftWeek(by: 1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.elevated))
                }
                .buttonStyle(JournalPressStyle())
                .disabled(model.weekIndex >= model.document.semester.totalWeeks)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -70 {
                        withAnimation(motion) { model.shiftWeek(by: 1) }
                    } else if value.translation.width > 70 {
                        withAnimation(motion) { model.shiftWeek(by: -1) }
                    }
                }
        )
        .accessibilityElement(children: .contain)
    }

    private func dayCard(weekday: Int) -> some View {
        let dates = SemesterCalendar.dates(inWeek: model.weekIndex, semester: model.document.semester, calendar: model.calendar)
        let date = weekday - 1 < dates.count ? dates[weekday - 1] : Date()
        let isToday = model.calendar.isDateInToday(date)
        let items = model.occurrences().filter { $0.weekday == weekday }.sorted { $0.start < $1.start }
        let events = model.events(on: date)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text("\(model.calendar.component(.day, from: date))")
                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                    .foregroundStyle(isToday ? Theme.accentInk : Theme.ink)
                Text(ScheduleCopy.weekdayShort(weekday))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                if isToday {
                    Text("今天")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(Theme.accent))
                }
                if model.holiday(on: date) != nil {
                    Text("假期")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(Color.orange))
                }
            }
            .frame(width: 42)
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty && events.isEmpty {
                    Text(model.holiday(on: date).map { "假期 · \($0.name)" } ?? "无课")
                        .font(.system(size: 13.5, design: .rounded))
                        .foregroundStyle(Theme.secondary.opacity(0.7))
                        .padding(.vertical, 6)
                } else {
                    ForEach(items, id: \.id) { occ in
                        miniRow(occ: occ)
                    }
                    ForEach(events, id: \.id) { event in
                        miniEventRow(event)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.elevated))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isToday ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func miniRow(occ: Occurrence) -> some View {
        let bg = Theme.courseBackground(occ.colorID, scheme: scheme)
        return Button {
            model.present(courseID: occ.courseID, meetingID: occ.meetingID)
        } label: {
            HStack(spacing: 10) {
                Capsule()
                    .fill(bg)
                    .frame(width: 5, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(occ.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(ScheduleCopy.hhmm(occ.start, calendar: model.calendar))–\(ScheduleCopy.hhmm(occ.end, calendar: model.calendar)) · \(occ.location)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bg.opacity(scheme == .dark ? 0.25 : 0.35)))
        }
        .buttonStyle(JournalPressStyle())
    }

    private func miniEventRow(_ event: PersonalEvent) -> some View {
        let cal = model.calendar
        let start = CivilStamp.date(from: event.startISO, calendar: cal)
        let end = CivilStamp.date(from: event.endISO, calendar: cal)
        let bar = Theme.courseBackground("purple", scheme: scheme)
        let ink = Theme.courseInk("purple", scheme: scheme)
        return Button {
            eventToEdit = event
        } label: {
            HStack(spacing: 10) {
            Capsule()
                .fill(bar)
                .frame(width: 5, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("日程")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule(style: .continuous).fill(bar))
                }
                if let start, let end {
                    Text("\(ScheduleCopy.hhmm(start, calendar: cal))–\(ScheduleCopy.hhmm(end, calendar: cal))\(event.note.isEmpty ? "" : " · \(event.note)")")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bar.opacity(scheme == .dark ? 0.25 : 0.35)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .accessibilityElement(children: .combine)
        }
        .buttonStyle(JournalPressStyle())
    }

    private var summaryCard: some View {
        let summary = ScheduleCopy.weekSummary(occurrences: model.occurrences())
        return HStack {
            Text(summary.headline)
                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(summary.aside)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.elevated))
        .accessibilityElement(children: .combine)
    }
}
