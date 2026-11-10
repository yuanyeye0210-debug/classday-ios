import SwiftUI
import ClassdayCore

struct DayTimetableView: View {
    var namespace: Namespace.ID
    @Environment(\.appModel) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let items = model.occurrences(on: model.selectedDay)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(ScheduleCopy.agendaTitle(model.selectedDay, calendar: model.calendar))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ScheduleCopy.agendaTitle(model.selectedDay, calendar: model.calendar))
            .accessibilityAdjustableAction { direction in
                shift(direction == .increment ? 1 : -1)
            }

            ScrollView {
                if items.isEmpty {
                    Text("这天没有课")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    VStack(spacing: 12) {
                        ForEach(items) { item in
                            dayCard(item)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)
        }
        .gesture(daySwipe)
    }

    private func dayCard(_ item: Occurrence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.timeText)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.courseInk(item.colorID, scheme: scheme))
            Text(item.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(item.location)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
            HStack {
                Text(ScheduleCopy.periodSpan(item.startPeriod, item.endPeriod))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button("调整时间") {
                    model.editor = .reschedule(courseID: item.courseID, meetingID: item.meetingID)
                }
                .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.courseBackground(item.colorID, scheme: scheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .matchedGeometryEffect(id: item.meetingID.uuidString, in: namespace)
        .opacity(model.presented?.meetingID == item.meetingID ? 0 : 1)
        .accessibilityHidden(model.presented?.meetingID == item.meetingID)
        .onTapGesture { model.present(courseID: item.courseID, meetingID: item.meetingID) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name)，\(item.timeText)，\(item.location)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "调整时间") {
            model.editor = .reschedule(courseID: item.courseID, meetingID: item.meetingID)
        }
    }

    private func shift(_ delta: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86)) {
            model.shiftDay(by: delta)
        }
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) + 12, abs(value.translation.width) > 48 else { return }
                shift(value.translation.width < 0 ? 1 : -1)
            }
    }
}

struct AgendaView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        let groups = agendaGroups()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("日程")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                if groups.isEmpty {
                    Text("接下来两周没有课")
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                } else {
                    ForEach(groups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ScheduleCopy.agendaTitle(group.day, calendar: model.calendar))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                            ForEach(group.items) { item in
                                Button {
                                    model.tab = .timetable
                                    model.present(courseID: item.courseID, meetingID: item.meetingID)
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(ScheduleCopy.hhmm(item.start, calendar: model.calendar))
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(Theme.accentInk)
                                            .frame(width: 64, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Theme.ink)
                                            Text(item.location)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Theme.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(PressButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }

    private func agendaGroups() -> [(day: Date, items: [Occurrence])] {
        let start = model.calendar.startOfDay(for: Date())
        return (0..<14).compactMap { offset in
            guard let day = model.calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let items = model.occurrences(on: day)
            guard !items.isEmpty else { return nil }
            return (day, items)
        }
    }
}
