import SwiftUI
import WidgetKit
import ClassdayCore

enum WidgetTheme {
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 16 / 255, green: 18 / 255, blue: 24 / 255) : Color.white
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 244 / 255, green: 246 / 255, blue: 251 / 255) : Color(red: 27 / 255, green: 36 / 255, blue: 51 / 255)
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 168 / 255, green: 176 / 255, blue: 194 / 255) : Color(red: 142 / 255, green: 150 / 255, blue: 168 / 255)
    }

    static func courseBackground(_ id: String, scheme: ColorScheme) -> Color {
        let style = CourseColors.style(for: id)
        return Color(scheme == .dark ? style.backgroundDark : style.backgroundLight)
    }

    static func courseInk(_ id: String, scheme: ColorScheme) -> Color {
        let style = CourseColors.style(for: id)
        return Color(scheme == .dark ? style.inkDark : style.inkLight)
    }
}

extension Color {
    init(_ palette: PaletteColor) {
        self.init(.sRGB, red: palette.r, green: palette.g, blue: palette.b)
    }
}

struct WidgetBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetTheme.background(scheme)
    }
}

struct SmallNextClassView: View {
    var state: SmallWidgetState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(phaseTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WidgetTheme.secondary(scheme))
                    Spacer()
                    Text(state.badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.courseInk(state.colorID, scheme: scheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(WidgetTheme.courseInk(state.colorID, scheme: scheme).opacity(0.14))
                        )
                }
                Text(state.timeText)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(WidgetTheme.courseInk(state.colorID, scheme: scheme))
                    .minimumScaleFactor(0.7)
                Text(state.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WidgetTheme.ink(scheme))
                    .lineLimit(1)
                if !state.locationText.isEmpty {
                    Text(state.locationText)
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetTheme.secondary(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(state.footnote)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetTheme.courseInk(state.colorID, scheme: scheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let progress = state.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(WidgetTheme.courseInk(state.colorID, scheme: scheme).opacity(0.18))
                            Capsule()
                                .fill(WidgetTheme.courseInk(state.colorID, scheme: scheme))
                                .frame(width: max(4, geo.size.width * progress))
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { WidgetBackground() }
        .widgetURL(state.url)
        .accessibilityElement(children: .combine)
    }

    private var phaseTitle: String {
        switch state.phase {
        case .inProgress: return "本节"
        case .upcoming: return "下一节"
        case .empty: return "课表"
        }
    }
}

struct MediumTodayView: View {
    var state: MediumWidgetState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(state.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WidgetTheme.ink(scheme))
                    Spacer()
                    Text(state.dateText)
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetTheme.secondary(scheme))
                }
                if state.isEmpty {
                    Spacer(minLength: 0)
                    Text(state.emptyTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WidgetTheme.ink(scheme))
                    Text(state.emptyMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(WidgetTheme.secondary(scheme))
                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 8) {
                        ForEach(state.chips) { chip in
                            Link(destination: chip.url) {
                                chipView(chip)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                HStack {
                    Text(state.footerLeft)
                    Spacer()
                    Text(state.footerRight)
                }
                .font(.system(size: 12))
                .foregroundStyle(WidgetTheme.secondary(scheme))
            }
            .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { WidgetBackground() }
        .accessibilityElement(children: .combine)
    }

    private func chipView(_ chip: WidgetChip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chip.timeText)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WidgetTheme.courseInk(chip.colorID, scheme: scheme))
            Text(chip.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.ink(scheme))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(chip.locationText)
                .font(.system(size: 11))
                .foregroundStyle(WidgetTheme.secondary(scheme))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            WidgetTheme.courseBackground(chip.colorID, scheme: scheme),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chip.timeText) \(chip.name) \(chip.locationText)")
    }
}
