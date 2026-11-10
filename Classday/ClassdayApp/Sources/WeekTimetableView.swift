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
        .matchedGeometryEffect(id: occurrence.meetingID.uuidString, in: namespace)
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
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 46

    var body: some View {
        let periods = model.document.semester.periods.sorted { $0.index < $1.index }
        let dates = SemesterCalendar.dates(inWeek: model.weekIndex, semester: model.document.semester, calendar: model.calendar)
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
        .padding(.horizontal, 8)
        .simultaneousGesture(weekSwipe)
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
