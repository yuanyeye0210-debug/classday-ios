import SwiftUI
import UIKit
import ClassdayCore

enum Theme {
    static let accent = Color(red: 58 / 255, green: 107 / 255, blue: 255 / 255)
    static let background = Color.adaptive(light: .rgb(255, 255, 255), dark: .rgb(15, 17, 22))
    static let card = Color.adaptive(light: .rgb(255, 255, 255), dark: .rgb(28, 31, 40))
    static let elevated = Color.adaptive(light: .rgb(244, 246, 251), dark: .rgb(36, 40, 51))
    static let ink = Color.adaptive(light: .rgb(27, 36, 51), dark: .rgb(244, 246, 251))
    static let secondary = Color.adaptive(light: .rgb(142, 150, 168), dark: .rgb(168, 176, 194))
    static let line = Color.adaptive(light: .rgb(232, 236, 244), dark: .rgb(46, 52, 66))
    static let hero = Color.adaptive(light: .rgb(232, 238, 255), dark: .rgb(32, 42, 74))
    static let segment = Color.adaptive(light: .rgb(232, 237, 248), dark: .rgb(36, 42, 56))
    static let accentInk = Color.adaptive(light: .rgb(58, 107, 255), dark: .rgb(150, 176, 255))

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

    static func adaptive(light: PaletteColor, dark: PaletteColor) -> Color {
        Color(uiColor: UIColor { traits in
            let palette = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: palette.r, green: palette.g, blue: palette.b, alpha: 1)
        })
    }
}

struct PressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent))
        }
        .buttonStyle(PressButtonStyle())
    }
}

enum Haptics {
    static func pickUp() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct EditorSheetBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            (scheme == .dark ? Color.black : Color.white).opacity(scheme == .dark ? 0.72 : 0.86)
        }
    }
}
