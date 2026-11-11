import SwiftUI
import UIKit
import CoreImage
import CoreHaptics
import CoreMotion
import MapKit
import UniformTypeIdentifiers
import ClassdayCore

struct ClassdayChrome: Equatable {
    var theme: ClassdayTheme
    var tier: PerformanceTier
    var allowsShader: Bool
    var allowsMotion: Bool
    var allowsParticles: Bool

    static func resolve(choice: AppearanceChoice, reduceMotion: Bool, lowPower: Bool) -> ClassdayChrome {
        let tier = ClassdayThemes.effectiveTier(selected: choice.performance, lowPower: lowPower, reduceMotion: reduceMotion)
        let rich = tier != .saver
        return ClassdayChrome(
            theme: choice.theme,
            tier: tier,
            allowsShader: rich && choice.theme.usesShader,
            allowsMotion: rich && choice.theme.usesMotion && !reduceMotion,
            allowsParticles: rich && tier == .high && (choice.theme.specialLayout == "aurora" || choice.theme.specialLayout == "dust")
        )
    }
}

private struct ClassdayChromeKey: EnvironmentKey {
    static let defaultValue = ClassdayChrome.resolve(choice: .standard, reduceMotion: false, lowPower: false)
}

extension EnvironmentValues {
    var classdayChrome: ClassdayChrome {
        get { self[ClassdayChromeKey.self] }
        set { self[ClassdayChromeKey.self] = newValue }
    }
}

@Observable
final class MotionTracker {
    /// Gravity direction in screen coordinates (x right, y down), low-pass
    /// filtered at 30 Hz. Stays (0, 1) — straight down — when the phone is
    /// upright, motion is unavailable (simulator), or tracking is stopped.
    var gravity = CGVector(dx: 0, dy: 1)
    private let manager = CMMotionManager()
    private var running = false

    func start() {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            // Device frame (x right, y up) -> screen frame (x right, y down).
            let target = CGVector(dx: -gravity.x, dy: -gravity.y)
            self.gravity = CGVector(
                dx: self.gravity.dx * 0.72 + target.dx * 0.28,
                dy: self.gravity.dy * 0.72 + target.dy * 0.28
            )
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
        gravity = CGVector(dx: 0, dy: 1)
    }
}

private struct MotionTrackerKey: EnvironmentKey {
    static let defaultValue = MotionTracker()
}

extension EnvironmentValues {
    var motionTracker: MotionTracker {
        get { self[MotionTrackerKey.self] }
        set { self[MotionTrackerKey.self] = newValue }
    }
}

/// Stateful dust for the Stardust Gravity theme: particles integrate the
/// live gravity vector, pool at the low edge and bounce off the walls.
final class DustBox {
    var px: [Double] = []
    var py: [Double] = []
    var vx: [Double] = []
    var vy: [Double] = []
    private var last: Double = 0

    init(count: Int = 42) {
        for i in 0..<count {
            let s = Double(i) * 1.6180339887 + 0.37
            px.append((s * 7.13).truncatingRemainder(dividingBy: 1))
            py.append((s * 11.71).truncatingRemainder(dividingBy: 1))
            vx.append(0)
            vy.append(0)
        }
    }

    func step(gravity: CGVector, time: Double) {
        let dt = last == 0 ? 0.016 : min(max(time - last, 0.001), 0.05)
        last = time
        let damp = pow(0.30, dt)
        for i in px.indices {
            vx[i] += Double(gravity.dx) * 1.5 * dt
            vy[i] += Double(gravity.dy) * 1.5 * dt
            vx[i] *= damp
            vy[i] *= damp
            px[i] += vx[i] * dt
            py[i] += vy[i] * dt
            if px[i] < 0.012 { px[i] = 0.012; vx[i] = abs(vx[i]) * 0.45 }
            if px[i] > 0.988 { px[i] = 0.988; vx[i] = -abs(vx[i]) * 0.45 }
            if py[i] < 0.012 { py[i] = 0.012; vy[i] = abs(vy[i]) * 0.45 }
            if py[i] > 0.988 { py[i] = 0.988; vy[i] = -abs(vy[i]) * 0.45 }
        }
    }
}

enum ThemeHaptics {
    private static var engine: CHHapticEngine?

    static func play(_ name: String) {
        if playCore(name) { return }
        switch name {
        case "electric", "metal":
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        case "soft", "glass":
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case "particle", "glide":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private static func playCore(_ name: String) -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                try engine?.start()
            }
            let sharpness: Float
            let intensity: Float
            switch name {
            case "electric": sharpness = 0.9; intensity = 1
            case "metal": sharpness = 0.7; intensity = 0.9
            case "soft", "glass": sharpness = 0.2; intensity = 0.45
            case "particle": sharpness = 0.4; intensity = 0.55
            default: sharpness = 0.35; intensity = 0.6
            }
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine?.makePlayer(with: pattern).start(atTime: 0)
            return true
        } catch {
            return false
        }
    }
}

struct MotionParallax: ViewModifier {
    @Environment(\.classdayChrome) private var chrome
    @State private var offset: CGSize = .zero
    @State private var manager = CMMotionManager()

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .onAppear { start() }
            .onDisappear { manager.stopDeviceMotionUpdates() }
    }

    private func start() {
        guard chrome.allowsMotion, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion else { return }
            offset = CGSize(width: motion.attitude.roll * 12, height: motion.attitude.pitch * 12)
        }
    }
}

struct ThemeFieldView: View {
    var theme: ClassdayTheme
    var active: Bool
    var animated: Bool
    var particles: Bool

    @Environment(\.motionTracker) private var tracker
    @State private var dustBox = DustBox()

    var body: some View {
        GeometryReader { geo in
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    field(size: geo.size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                field(size: geo.size, time: 3.7)
            }
        }
    }

    private func drift(_ time: Double, _ speed: Double, _ phase: Double, _ amp: Double) -> CGFloat {
        animated ? CGFloat(sin(time * speed + phase) * amp) : 0
    }

    private func field(size: CGSize, time: Double) -> some View {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let dark = theme.prefersDark
        let grav = tracker.gravity
        // Deviation of the gravity vector from straight-down: zero when the
        // phone is upright, grows as it tilts. Background layers parallax
        // against it; loose particles integrate the raw vector instead.
        let tiltX = CGFloat(grav.dx)
        let tiltY = CGFloat(grav.dy - 1)
        return ZStack {
            Color(theme.background.palette)
            if active {
                blob(color: theme.glow, size: w * 0.85, blur: 55, opacity: dark ? 0.50 : 0.55,
                     x: w * 0.16 + drift(time, 0.11, 0.0, 26) - tiltX * 30, y: h * 0.10 + drift(time, 0.09, 1.7, 20) - tiltY * 30)
                blob(color: theme.accent, size: w * 0.70, blur: 60, opacity: dark ? 0.42 : 0.45,
                     x: w * 0.86 + drift(time, 0.08, 3.1, 30) - tiltX * 46, y: h * 0.34 + drift(time, 0.12, 0.6, 24) - tiltY * 46)
                blob(color: theme.courseAccents.count > 3 ? theme.courseAccents[3] : theme.glow,
                     size: w * 0.62, blur: 58, opacity: dark ? 0.36 : 0.42,
                     x: w * 0.42 + drift(time, 0.10, 5.2, 22) - tiltX * 36, y: h * 0.88 + drift(time, 0.07, 2.4, 18) - tiltY * 36)
                signature(size: size, time: time, tiltX: tiltX, tiltY: tiltY, gravity: grav)
            }
        }
        .frame(width: w, height: h)
    }

    private func blob(color: ThemeColor, size: CGFloat, blur: CGFloat, opacity: Double, x: Double, y: Double) -> some View {
        Ellipse()
            .fill(Color(color.palette))
            .frame(width: size, height: size * 0.78)
            .blur(radius: blur)
            .opacity(opacity)
            .blendMode(theme.prefersDark ? .screen : .normal)
            .position(x: x, y: y)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func signature(size: CGSize, time: Double, tiltX: CGFloat, tiltY: CGFloat, gravity: CGVector) -> some View {
        let w = size.width
        let h = size.height
        switch theme.specialLayout {
        case "neon":
            let travel = Double(h) + 200
            let y = animated ? CGFloat((time * 52).truncatingRemainder(dividingBy: travel) - 100) : h * 0.30
            Rectangle()
                .fill(LinearGradient(colors: [Color(theme.glow.palette).opacity(0), Color(theme.glow.palette).opacity(0.30), Color(theme.accent.palette).opacity(0.22), Color(theme.glow.palette).opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(height: 92)
                .position(x: w / 2, y: y)
                .allowsHitTesting(false)
        case "aurora":
            RoundedRectangle(cornerRadius: 90)
                .fill(LinearGradient(colors: [Color(theme.glow.palette).opacity(0.55), Color(theme.accent.palette).opacity(0.45), Color(theme.glow.palette).opacity(0.1)], startPoint: .leading, endPoint: .trailing))
                .frame(width: w * 1.3, height: 110)
                .blur(radius: 26)
                .rotationEffect(.degrees(-7))
                .position(x: w / 2 + drift(time, 0.07, 0.9, 30), y: h * 0.14)
                .allowsHitTesting(false)
            if particles {
                Canvas { context, canvasSize in
                    for i in 0..<26 {
                        let seed = Double(i) * 1.6180339887
                        let frac = seed.truncatingRemainder(dividingBy: 1)
                        let period = 8 + frac * 7
                        let progress = (time / period + frac * 3.7).truncatingRemainder(dividingBy: 1)
                        let x = frac * canvasSize.width + sin(time * 0.7 + seed) * 9 + Double(tiltX) * 44 * progress
                        let y = canvasSize.height - progress * (canvasSize.height + 24)
                        let r = 1.4 + (seed * 0.53).truncatingRemainder(dividingBy: 1) * 2.2
                        let fade = sin(progress * Double.pi)
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.85 * fade)))
                    }
                }
                .allowsHitTesting(false)
            }
        case "hud":
            Canvas { context, canvasSize in
                var path = Path()
                var x: CGFloat = 0
                while x < canvasSize.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    x += 36
                }
                var y: CGFloat = 0
                while y < canvasSize.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    y += 36
                }
                context.stroke(path, with: .color(Color(theme.line.palette).opacity(0.55)), lineWidth: 0.6)
            }
            .allowsHitTesting(false)
            Circle()
                .strokeBorder(Color(theme.accent.palette).opacity(0.65), style: StrokeStyle(lineWidth: 1.6, dash: [7, 6]))
                .frame(width: 86, height: 86)
                .rotationEffect(.degrees(animated ? time * 9 : 24))
                .position(x: w - 58, y: 120)
                .allowsHitTesting(false)
        case "orbit":
            let center = CGPoint(x: w - 30, y: 26)
            Circle()
                .stroke(Color(theme.accent.palette).opacity(0.40), lineWidth: 1.4)
                .frame(width: 218, height: 218)
                .position(x: center.x, y: center.y)
                .allowsHitTesting(false)
            Circle()
                .stroke(Color(theme.glow.palette).opacity(0.30), lineWidth: 1.2)
                .frame(width: 138, height: 138)
                .position(x: center.x, y: center.y)
                .allowsHitTesting(false)
            let angle = animated ? time * 0.45 : 0.8
            Circle()
                .fill(Color(theme.accent.palette))
                .frame(width: 11, height: 11)
                .shadow(color: Color(theme.accent.palette), radius: 7)
                .position(x: center.x + CGFloat(cos(angle)) * 109, y: center.y + CGFloat(sin(angle)) * 109)
                .allowsHitTesting(false)
        case "glass":
            RoundedRectangle(cornerRadius: 60)
                .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.34), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 120, height: h * 1.5)
                .blur(radius: 14)
                .rotationEffect(.degrees(-22))
                .position(x: w / 2 + tiltX * w * 0.85, y: h / 2)
                .allowsHitTesting(false)
        case "dust":
            Canvas { context, canvasSize in
                let cw = Double(canvasSize.width)
                let ch = Double(canvasSize.height)
                // Three star layers parallaxing against the tilt, by depth.
                for layer in 0..<3 {
                    let depth = [6.0, 14.0, 26.0][layer]
                    for i in 0..<36 {
                        let seed = Double(layer * 131 + i * 17 + 7)
                        let fx = (sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                        let fy = (sin(seed * 78.233) * 12543.123).truncatingRemainder(dividingBy: 1)
                        var sx = (abs(fx) * cw - Double(tiltX) * depth * 1.6).truncatingRemainder(dividingBy: cw)
                        var sy = (abs(fy) * ch - Double(tiltY) * depth * 1.6).truncatingRemainder(dividingBy: ch)
                        if sx < 0 { sx += cw }
                        if sy < 0 { sy += ch }
                        let r = 0.8 + Double(layer) * 0.6 + abs(fx) * 0.7
                        let rect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.30 + Double(layer) * 0.26)))
                    }
                }
                // Dust with real gravity: integrates the live vector, pools
                // at the low edge, bounces off the walls.
                if animated {
                    dustBox.step(gravity: gravity, time: time)
                }
                for i in dustBox.px.indices {
                    let r = 1.3 + Double(i % 5) * 0.45
                    let rect = CGRect(x: dustBox.px[i] * cw - r, y: dustBox.py[i] * ch - r, width: r * 2, height: r * 2)
                    let gold = i % 4 != 0
                    context.fill(Path(ellipseIn: rect), with: .color(gold ? Color(red: 1.0, green: 0.90, blue: 0.62).opacity(0.95) : Color(theme.glow.palette).opacity(0.9)))
                }
            }
            .allowsHitTesting(false)
        case "cube":
            Canvas { context, canvasSize in
                var path = Path()
                var d: CGFloat = -canvasSize.height
                while d < canvasSize.width {
                    path.move(to: CGPoint(x: d, y: 0))
                    path.addLine(to: CGPoint(x: d + canvasSize.height * 0.5, y: canvasSize.height))
                    d += 46
                }
                context.stroke(path, with: .color(Color(theme.line.palette).opacity(0.4)), lineWidth: 0.7)
            }
            .allowsHitTesting(false)
        case "mech":
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.05), .clear, Color.white.opacity(0.03), .clear], startPoint: .leading, endPoint: .trailing))
                .rotationEffect(.degrees(18))
                .scaleEffect(1.6)
                .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }
}

struct ThemeBackground: View {
    @Environment(\.classdayChrome) private var chrome

    var body: some View {
        ThemeFieldView(
            theme: chrome.theme,
            active: chrome.tier != .saver,
            animated: chrome.tier == .high,
            particles: chrome.allowsParticles
        )
        .ignoresSafeArea()
    }
}


struct ThemeGalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.classdayChrome) private var chrome

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("外观")
                        .font(.system(size: 34, weight: .bold))
                    Text("选一套主题，App、桌面小组件、锁屏小组件和上课时的灵动岛会同时换成这套配色，不用分别设置。性能档决定这些特效开多少。")
                        .font(.subheadline)
                        .foregroundStyle(Color(chrome.theme.secondary.palette))
                    if chrome.tier != model.document.appearance.performance {
                        Text("你选的是「\(model.document.appearance.performance.title)」，但当前实际生效「\(chrome.tier.title)」：系统低电量模式或「减弱动态效果」开着时会自动降档。")
                            .font(.caption)
                            .foregroundStyle(Color(chrome.theme.secondary.palette))
                    }
                    ForEach(ClassdayThemes.all) { theme in
                        Button {
                            model.setAppearance(AppearanceChoice(themeID: theme.id, performance: model.document.appearance.performance))
                        } label: {
                            preview(theme)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("性能")
                        .font(.headline)
                    ForEach(PerformanceTier.allCases, id: \.self) { tier in
                        Button {
                            model.setPerformance(tier)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(tier.title).font(.headline)
                                    Text(tier.detail).font(.caption)
                                }
                                Spacer()
                                if model.document.appearance.performance == tier {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(chrome.theme.card.palette)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(ThemeBackground())
            .navigationTitle("主题")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func preview(_ theme: ClassdayTheme) -> some View {
        let selected = model.document.appearance.themeID == theme.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(theme.name).font(.headline)
                Text(theme.englishName).font(.caption)
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").symbolEffect(.bounce, value: selected) }
            }
            Text(theme.tagline).font(.caption)
            HStack(spacing: 6) {
                ForEach(theme.courseAccents.prefix(4), id: \.r) { color in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(color.palette))
                        .frame(height: 28)
                }
            }
            LiveThemePreview(theme: theme)
        }
        .padding(14)
        .foregroundStyle(Color(theme.ink.palette))
        .background {
            ZStack {
                ThemeFieldView(theme: theme, active: true, animated: selected && chrome.tier == .high, particles: selected && chrome.allowsParticles)
                Color(theme.card.palette).opacity(0.74)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(theme.glow.palette), lineWidth: selected ? 2 : 0))
    }
}

private struct LiveThemePreview: View {
    var theme: ClassdayTheme

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("下一节").font(.caption2)
                Text("08:00").font(.title3.bold())
                Text("高等数学").font(.caption)
            }
            Spacer()
            Image(systemName: "clock")
                .symbolEffect(.pulse, options: .repeating)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(theme.background.palette)))
    }
}

struct OrbitWeekView: View {
    @Environment(AppModel.self) private var model
    @State private var spin: Double = 0

    var body: some View {
        let items = model.occurrences(on: model.selectedDay)
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) * 0.32
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                Text(ScheduleCopy.weekdayName(SemesterCalendar.isoWeekday(model.selectedDay, calendar: model.calendar)))
                    .font(.title2.bold())
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let angle = (Double(index) / Double(max(items.count, 1))) * 360 + spin
                    satellite(item)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(angle))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture().onEnded { value in
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                        spin += Double(value.translation.width)
                    }
                    Haptics.play("glide")
                }
            )
        }
        .padding(24)
    }

    private func satellite(_ item: Occurrence) -> some View {
        VStack(spacing: 2) {
            Text(ScheduleCopy.hhmm(item.start, calendar: model.calendar)).font(.caption2.bold())
            Text(item.name).font(.caption2).lineLimit(1)
        }
        .padding(8)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .rotationEffect(.degrees(-spin))
        .onTapGesture { model.openCourse(item.courseID, meeting: item.meetingID) }
    }
}

struct CubeWeekView: View {
    @Environment(AppModel.self) private var model
    @State private var yaw: Double = 0

    var body: some View {
        let items = model.occurrences(on: model.selectedDay)
        VStack(spacing: 12) {
            Text("左右轻扫，旋转到下一天")
                .font(.caption)
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 260, height: 320)
                    .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0))
                VStack(alignment: .leading, spacing: 10) {
                    Text(ScheduleCopy.weekdayName(SemesterCalendar.isoWeekday(model.selectedDay, calendar: model.calendar)))
                        .font(.headline)
                    ForEach(items.prefix(4)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.bold())
                            Text("\(item.timeText)  \(item.locationShort)").font(.caption2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.4).scaleEffect(phase.isIdentity ? 1 : 0.92)
                        }
                        .onTapGesture { model.openCourse(item.courseID, meeting: item.meetingID) }
                    }
                }
                .padding(28)
                .frame(width: 260, height: 320)
                .rotation3DEffect(.degrees(yaw * 0.15), axis: (x: 0.2, y: 1, z: 0))
            }
            .gesture(
                DragGesture().onEnded { value in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        yaw += value.translation.width > 0 ? -28 : 28
                    }
                    model.shiftDay(by: value.translation.width > 0 ? -1 : 1)
                    Haptics.play("glass")
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CountdownDial: View {
    var progress: Double
    var label: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.02, min(progress, 1)))
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(label).font(.caption.monospacedDigit())
            }
            .frame(width: 88, height: 88)
        }
    }
}

struct StudyDeskView: View {
    @Environment(AppModel.self) private var model
    @State private var homeworkTitle = ""
    @State private var icsURL = ""
    @State private var fenixID = FenixConfig.clientID
    @State private var fenixSecret = FenixConfig.clientSecret
    @State private var timetableName = ""
    @State private var showImporter = false
    @State private var showOCR = false

    var body: some View {
        NavigationStack {
            List {
                Section("考试") {
                    if model.document.exams.isEmpty {
                        Text("还没有考试。可以从日历或 Fénix 导入。")
                    }
                    ForEach(model.document.exams) { exam in
                        VStack(alignment: .leading) {
                            Text(exam.courseName).font(.headline)
                            Text(exam.startISO).font(.caption)
                            if let date = CivilStamp.date(from: exam.startISO, calendar: model.calendar) {
                                Text(CountdownCopy.remaining(until: date, now: Date()))
                                    .font(.caption.bold())
                            }
                        }
                    }
                }
                Section("作业") {
                    TextField("作业标题", text: $homeworkTitle)
                    Button("添加作业") {
                        guard !homeworkTitle.isEmpty else { return }
                        model.addHomework(title: homeworkTitle, courseName: "", due: Date().addingTimeInterval(86_400))
                        homeworkTitle = ""
                    }
                    ForEach(model.document.homework) { task in
                        Button {
                            model.toggleHomework(task.id)
                        } label: {
                            HStack {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(task.title)
                                    Text(task.dueISO).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("多课表") {
                    TextField("另存为", text: $timetableName)
                    Button("保存当前课表") { model.duplicateTimetable(named: timetableName) }
                    ForEach(model.document.library) { table in
                        Button(table.name) { model.switchTimetable(to: table.id) }
                    }
                }
                Section("导入") {
                    TextField("iCal 订阅地址", text: $icsURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("订阅并导入") { Task { await subscribe() } }
                    Button("导入 .ics 或 JSON 文件") { showImporter = true }
                    Button("智能导入课表（图片 / CSV / 文本）") { showOCR = true }
                    TextField("Fénix client id", text: $fenixID)
                    SecureField("Fénix client secret", text: $fenixSecret)
                    Button("用 Fénix 登录并导入") {
                        FenixConfig.clientID = fenixID
                        FenixConfig.clientSecret = fenixSecret
                        Task { await FenixAuth.signIn(model: model) }
                    }
                    Text("在 Fénix → Personal → Manage Applications 新建应用，redirect URI 填 classday://fenix。免费 Apple ID 也能走这个网页登录。")
                        .font(.caption)
                }
                Section("分享") {
                    ShareLink(item: ShareCodec.url(for: model.document)) {
                        Label("分享课表链接", systemImage: "square.and.arrow.up")
                    }
                    TimetableQR(text: ShareCodec.url(for: model.document).absoluteString)
                }
                Section("同步") {
                    Toggle("自动同步到系统日历", isOn: Binding(
                        get: { CalendarSync.isEnabled },
                        set: { enabled in
                            CalendarSync.isEnabled = enabled
                            if enabled { CalendarSync.sync(model.document, calendar: model.calendar) }
                        }
                    ))
                    Text(CalendarSync.status)
                    Text(CloudMirror.status)
                    Button("立即写入系统日历") {
                        CalendarSync.isEnabled = true
                        CalendarSync.sync(model.document, calendar: model.calendar)
                    }
                    Button("尝试 iCloud") { Task { await CloudMirror.push(model.document) } }
                }
            }
            .navigationTitle("学习")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, UTType(filenameExtension: "ics") ?? .data]) { result in
                if case let .success(url) = result { read(url) }
            }
            .sheet(isPresented: $showOCR) { SmartImportView() }
        }
    }

    private func subscribe() async {
        guard let url = URL(string: icsURL) else { model.banner = "地址无效"; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            model.importCalendar(ICSImporter.parse(text, calendar: model.calendar, totalWeeks: model.document.semester.totalWeeks), subscribeURL: icsURL)
        } catch {
            model.banner = "没有下载到日历"
        }
    }

    private func read(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        if url.pathExtension.lowercased() == "json" {
            model.stageImport(data)
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            model.importCalendar(ICSImporter.parse(text, calendar: model.calendar, totalWeeks: model.document.semester.totalWeeks))
        }
    }
}

struct TimetableQR: View {
    var text: String

    var body: some View {
        if let image = QRCode.image(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 160, height: 160)
                .accessibilityLabel("课表二维码")
        }
    }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let data = Data(text.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum RoomNavigator {
    static func open(location: String, pin: RoomPin?) {
        let item: MKMapItem
        if let pin, let latitude = pin.latitude, let longitude = pin.longitude {
            item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)))
            item.name = location
        }
        item.name = pin?.query ?? location
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
