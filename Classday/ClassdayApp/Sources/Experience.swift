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

    /// The tracker itself runs on every non-saver tier, whatever the
    /// theme: signature layers and cards in all eight themes read the
    /// gravity vector (2.3.2 batch 3/4). `allowsMotion` stays as the
    /// narrower per-theme flag for legacy consumers.
    var tracksMotion: Bool { tier != .saver }

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
    /// Visual twin of the spring tilt, quantized to 0.01 steps and
    /// refreshed at most every other sample: views read this one, so a
    /// phone lying still produces zero background/card re-renders while
    /// the haptics keep the full-rate raw channel.
    private(set) var visualTilt = CGVector(dx: 0, dy: 1)
    private var visualTick = 0
    private var velocity = CGVector(dx: 0, dy: 0)
    private let manager = CMMotionManager()
    private var running = false

    // Tilt haptics: detent ticks as the tilt angle steps, a firmer dock
    // tap when the phone returns to upright. Pattern after the levelpro
    // level app (prepare-after-impact, latched zones) with murmur's
    // ~34-degree full-scale calibration; gated by a user toggle.
    var hapticsEnabled = true
    private let softTap = UIImpactFeedbackGenerator(style: .soft)
    private let lightTap = UIImpactFeedbackGenerator(style: .light)
    private let mediumTap = UIImpactFeedbackGenerator(style: .medium)
    private let heavyTap = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidTap = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionTap = UISelectionFeedbackGenerator()
    private let notifier = UINotificationFeedbackGenerator()
    /// The active theme's haptic signature; RootView sets it from the
    /// current theme and re-sets it on every theme change.
    var profile = TiltHapticProfile.make(themeID: "glass", layout: "glass")
    /// 0 standard, 1 keen, 2 maximum. Maximum is the factory default:
    /// finest detents, no settle delay, the loosest dock window.
    /// No observer-based clamp here on purpose: MotionTracker is
    /// @Observable, whose setter routes through the observation
    /// registrar, so the old self-assigning property observer recursed
    /// until the stack overflowed (the 2.3.4-2.3.6 instant launch
    /// crash on real devices; the simulator never runs start(), so
    /// CI could not see it). Reads go through sensitivityTier, which
    /// clamps defensively instead.
    var sensitivity = 2
    private var sensitivityTier: Int { min(2, max(0, sensitivity)) }
    private var lastTickTheta: Double = -100

    private var detentStep: Double {
        max(2.5, profile.detentDegrees * [1.0, 0.6, 0.35][sensitivityTier])
    }
    private var azimuthStep: Double {
        profile.azimuthDegrees > 0 ? max(15, profile.azimuthDegrees * [1.0, 0.6, 0.35][sensitivityTier]) : 0
    }
    private var tapThrottle: TimeInterval { sensitivityTier == 2 ? 0.035 : 0.06 }
    private var lastDetent = -1
    private var candidateDetent = -1
    private var candidateSamples = 0
    private var lastAzimuthDetent = -1
    private var dockArmed = false
    private var lastTapAt: TimeInterval = 0

    func start() {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        hapticsEnabled = UserDefaults.standard.object(forKey: "classday.tiltHaptics") as? Bool ?? true
        sensitivity = min(2, max(0, UserDefaults.standard.object(forKey: "classday.tiltSensitivity") as? Int ?? 2))
        for g in [softTap, lightTap, mediumTap, heavyTap, rigidTap] { g.prepare() }
        selectionTap.prepare()
        notifier.prepare()
        lastDetent = -1
        candidateDetent = -1
        candidateSamples = 0
        lastAzimuthDetent = -1
        dockArmed = false
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let sample = motion?.gravity else { return }
            // Device frame (x right, y up) -> screen frame (x right, y down).
            let target = CGVector(dx: -sample.x, dy: -sample.y)
            // Spring follow (Wave-style) instead of a fixed low-pass blend:
            // the value chases the raw gravity with stiffness and damping,
            // so a tilt lands with a trace of inertia and a soft settle.
            let dt: CGFloat = 1.0 / 30.0
            let stiffness: CGFloat = 165
            let decay = CGFloat(exp(-16.0 * Double(dt)))
            self.velocity = CGVector(
                dx: (self.velocity.dx + (target.dx - self.gravity.dx) * stiffness * dt) * decay,
                dy: (self.velocity.dy + (target.dy - self.gravity.dy) * stiffness * dt) * decay
            )
            self.gravity = CGVector(
                dx: self.gravity.dx + self.velocity.dx * dt,
                dy: self.gravity.dy + self.velocity.dy * dt
            )
            self.visualTick += 1
            if self.visualTick % 2 == 0 {
                let qx = (self.gravity.dx * 100).rounded() / 100
                let qy = (self.gravity.dy * 100).rounded() / 100
                if abs(qx - self.visualTilt.dx) > 0.004 || abs(qy - self.visualTilt.dy) > 0.004 {
                    self.visualTilt = CGVector(dx: qx, dy: qy)
                }
            }
            self.updateHaptics(now: Date().timeIntervalSinceReferenceDate)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
        gravity = CGVector(dx: 0, dy: 1)
        velocity = CGVector(dx: 0, dy: 0)
        lastDetent = -1
        candidateDetent = -1
        lastAzimuthDetent = -1
        dockArmed = false
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .soft: return softTap
        case .light: return lightTap
        case .medium: return mediumTap
        case .heavy: return heavyTap
        case .rigid: return rigidTap
        @unknown default: return mediumTap
        }
    }

    private func fireTick(_ intensity: CGFloat) {
        if profile.useSelection {
            selectionTap.selectionChanged()
            selectionTap.prepare()
        } else {
            let g = generator(for: profile.style)
            g.impactOccurred(intensity: intensity)
            g.prepare()
        }
    }

    private func fireDock() {
        switch profile.dock {
        case .impact(let style, let intensity):
            let g = generator(for: style)
            g.impactOccurred(intensity: intensity)
            g.prepare()
        case .selection:
            selectionTap.selectionChanged()
            selectionTap.prepare()
        case .success:
            notifier.notificationOccurred(.success)
            notifier.prepare()
        }
    }

    /// Fired by the theme gallery's test button: two detent ticks and a
    /// dock, so the active theme's signature can be felt on demand
    /// without tilting the phone around first.
    func previewHaptics() {
        fireTick(profile.intensity)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            self.fireTick(self.profile.intensity)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            self?.fireDock()
        }
    }

    private func updateHaptics(now: TimeInterval) {
        guard hapticsEnabled else { return }
        // Tilt angle from upright: the gravity vector is a unit vector,
        // so its y component is cos(theta) directly.
        let theta = acos(min(1, max(-1, Double(gravity.dy)))) * 180 / .pi
        // Detents every 8 degrees. A new detent must survive two samples
        // before it ticks, so the spring's settle wobble at a boundary
        // does not machine-gun the Taptic Engine.
        let step = detentStep
        let detent = Int(theta / step)
        if detent != candidateDetent {
            candidateDetent = detent
            candidateSamples = 0
        } else {
            candidateSamples += 1
        }
        // Standard/keen wait one extra sample so the spring's settle does
        // not double-fire; maximum fires on the crossing sample itself.
        // All levels share a travel hysteresis (0.4 of a step since the
        // last tick), which is what actually stops boundary rattle.
        let stableNeeded = sensitivityTier == 2 ? 0 : 1
        if candidateSamples >= stableNeeded, detent != lastDetent, abs(theta - lastTickTheta) >= step * 0.4 {
            if lastDetent >= 0, now - lastTapAt > tapThrottle {
                fireTick(profile.intensity)
                lastTapAt = now
            }
            lastDetent = detent
            lastTickTheta = theta
        }
        // Azimuth detents every 45 degrees, only once properly tilted,
        // so swinging a steep phone around also has texture.
        if azimuthStep > 0, theta > 15 {
            let phi = atan2(Double(gravity.dx), -(Double(gravity.dy) - 1)) * 180 / .pi
            let azimuth = Int((phi + 180) / azimuthStep)
            if azimuth != lastAzimuthDetent {
                if lastAzimuthDetent >= 0, now - lastTapAt > tapThrottle {
                    fireTick(profile.azimuthIntensity)
                    lastTapAt = now
                }
                lastAzimuthDetent = azimuth
            }
        } else if theta < 6 {
            lastAzimuthDetent = -1
        }
        if theta > (sensitivityTier == 2 ? 8 : 12) { dockArmed = true }
        // Dock: one firm tap when the phone comes home to upright,
        // latched until it has been properly tilted again.
        if dockArmed, theta < (sensitivityTier == 2 ? 4.0 : 2.5) {
            fireDock()
            dockArmed = false
            lastTapAt = now
        }
    }
}

/// Per-theme tilt haptics: every theme gets its own detent step,
/// generator voice and dock character, so tilting feels the way the
/// theme looks. Keyed by theme id.
struct TiltHapticProfile {
    var label: String
    var detentDegrees: Double
    var style: UIImpactFeedbackGenerator.FeedbackStyle
    var useSelection: Bool
    var intensity: CGFloat
    var azimuthDegrees: Double
    var azimuthIntensity: CGFloat
    var dock: DockKind

    enum DockKind {
        case impact(UIImpactFeedbackGenerator.FeedbackStyle, CGFloat)
        case selection
        case success
    }

    static func make(themeID: String, layout: String) -> TiltHapticProfile {
        switch themeID {
        case "neon":
            return .init(label: "霓虹 · 电流强震", detentDegrees: 6, style: .rigid, useSelection: false, intensity: 1.0, azimuthDegrees: 30, azimuthIntensity: 0.8, dock: .impact(.rigid, 1.0))
        case "glass":
            return .init(label: "玻璃 · 水润强震", detentDegrees: 10, style: .medium, useSelection: false, intensity: 1.0, azimuthDegrees: 45, azimuthIntensity: 0.85, dock: .impact(.medium, 1.0))
        case "hud":
            return .init(label: "HUD · 仪器强刻度", detentDegrees: 5, style: .rigid, useSelection: false, intensity: 1.0, azimuthDegrees: 45, azimuthIntensity: 0.8, dock: .impact(.heavy, 1.0))
        case "aurora":
            return .init(label: "极光 · 饱满漂移", detentDegrees: 12, style: .medium, useSelection: false, intensity: 1.0, azimuthDegrees: 0, azimuthIntensity: 0, dock: .impact(.medium, 1.0))
        case "mech":
            return .init(label: "机甲 · 金属重击", detentDegrees: 10, style: .heavy, useSelection: false, intensity: 1.0, azimuthDegrees: 45, azimuthIntensity: 0.9, dock: .impact(.heavy, 1.0))
        case "orbit":
            return .init(label: "轨道 · 扣合双震", detentDegrees: 9, style: .heavy, useSelection: false, intensity: 1.0, azimuthDegrees: 36, azimuthIntensity: 0.85, dock: .success)
        case "cube":
            return .init(label: "立方 · 玻璃重咔哒", detentDegrees: 8, style: .rigid, useSelection: false, intensity: 1.0, azimuthDegrees: 90, azimuthIntensity: 0.85, dock: .impact(.heavy, 1.0))
        case "dust":
            return .init(label: "星尘 · 飘尘强点", detentDegrees: 12, style: .medium, useSelection: false, intensity: 1.0, azimuthDegrees: 60, azimuthIntensity: 0.7, dock: .impact(.medium, 1.0))
        default:
            return .init(label: "标准强刻度", detentDegrees: 8, style: .rigid, useSelection: false, intensity: 1.0, azimuthDegrees: 45, azimuthIntensity: 0.8, dock: .impact(.rigid, 1.0))
        }
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

    @ViewBuilder
    private func field(size: CGSize, time: Double) -> some View {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let dark = theme.prefersDark
        let grav = tracker.gravity
        let visual = tracker.visualTilt
        // Deviation of the gravity vector from straight-down: zero when the
        // phone is upright, grows as it tilts. Background layers parallax
        // against it; loose particles integrate the raw vector instead.
        let tiltX = CGFloat(visual.dx)
        let tiltY = CGFloat(visual.dy - 1)
        return ZStack {
            Color(theme.background.palette)
            if active {
                ZStack {
                blob(color: theme.glow, size: w * 0.85, opacity: dark ? 0.50 : 0.55,
                     x: w * 0.16 + drift(time, 0.11, 0.0, 26) - tiltX * 30, y: h * 0.10 + drift(time, 0.09, 1.7, 20) - tiltY * 30)
                blob(color: theme.accent, size: w * 0.70, opacity: dark ? 0.42 : 0.45,
                     x: w * 0.86 + drift(time, 0.08, 3.1, 30) - tiltX * 46, y: h * 0.34 + drift(time, 0.12, 0.6, 24) - tiltY * 46)
                blob(color: theme.courseAccents.count > 3 ? theme.courseAccents[3] : theme.glow,
                     size: w * 0.62, opacity: dark ? 0.36 : 0.42,
                     x: w * 0.42 + drift(time, 0.10, 5.2, 22) - tiltX * 36, y: h * 0.88 + drift(time, 0.07, 2.4, 18) - tiltY * 36)
                // Gravity-up light: one soft source pinned near the edge
                // the phone tilts away from, shared by every theme so the
                // tilt always reads somewhere on screen.
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity((dark ? 0.10 : 0.16) + min(abs(tiltX) + abs(tiltY), 1) * 0.10), Color.white.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.475))
                    .frame(width: w * 0.95, height: w * 0.95)
                    .scaleEffect(x: 1, y: (h * 0.30) / (w * 0.95))
                    .position(x: w / 2 - tiltX * w * 0.34, y: -h * 0.03 - tiltY * h * 0.05)
                    .allowsHitTesting(false)
                signature(size: size, time: time, tiltX: tiltX, tiltY: tiltY, gravity: grav)
                }
                .modifier(ThemeShaderModifier(layout: theme.specialLayout, active: active, animated: animated, size: size, tiltX: tiltX, tiltY: tiltY, time: time))
            }
        }
        .frame(width: w, height: h)
    }

    private func blob(color: ThemeColor, size: CGFloat, opacity: Double, x: Double, y: Double) -> some View {
        // Radial-gradient falloff instead of a live Gaussian blur: the
        // same soft pool of light, rasterized directly by the GPU. The
        // blurred layers were the field's biggest per-frame cost.
        // The gradient is circular and ends exactly at the rim, so its
        // alpha reaches zero at the edge in every direction; the flat
        // ellipse comes from scaling the finished circle. Filling an
        // Ellipse directly left ~25% alpha standing along the short
        // axis, which drew a visible rim (and frame) around each glow.
        Circle()
            .fill(RadialGradient(colors: [Color(color.palette).opacity(opacity), Color(color.palette).opacity(opacity * 0.55), Color(color.palette).opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .scaleEffect(x: 1, y: 0.78)
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
                .rotationEffect(.degrees(Double(tiltX) * 4))
                .position(x: w / 2 + tiltX * 40, y: y)
                .allowsHitTesting(false)
        case "aurora":
            RoundedRectangle(cornerRadius: 90)
                .fill(LinearGradient(colors: [Color(theme.glow.palette).opacity(0.55), Color(theme.accent.palette).opacity(0.45), Color(theme.glow.palette).opacity(0.1)], startPoint: .leading, endPoint: .trailing))
                .frame(width: w * 1.3, height: 110)
                .mask(LinearGradient(colors: [.clear, .black, .clear], startPoint: .top, endPoint: .bottom))
                .rotationEffect(.degrees(-7 + Double(tiltX) * 5))
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
                // The grid pans against the tilt (wrapping every cell), so
                // the whole lattice feels bolted to the world, not the glass.
                let gx = (Double(tiltX) * 36).truncatingRemainder(dividingBy: 36)
                let gy = (Double(tiltY) * 36).truncatingRemainder(dividingBy: 36)
                var path = Path()
                var x: CGFloat = CGFloat(gx) - 36
                while x < canvasSize.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    x += 36
                }
                var y: CGFloat = CGFloat(gy) - 36
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
                .rotationEffect(.degrees((animated ? time * 9 : 24) + Double(tiltX) * 130))
                .position(x: w - 58, y: 120)
                .allowsHitTesting(false)
        case "orbit":
            let center = CGPoint(x: w - 30 - tiltX * 30, y: 26 - tiltY * 30)
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
                // Holographic lattice: the whole grid shears and slides
                // with the tilt, like a hologram plate catching the light.
                let shear = 0.5 + tiltY * 0.45
                let phase = (Double(tiltX) * 64).truncatingRemainder(dividingBy: 46)
                var path = Path()
                var d: CGFloat = -canvasSize.height + CGFloat(phase)
                while d < canvasSize.width {
                    path.move(to: CGPoint(x: d, y: 0))
                    path.addLine(to: CGPoint(x: d + canvasSize.height * shear, y: canvasSize.height))
                    d += 46
                }
                context.stroke(path, with: .color(Color(theme.line.palette).opacity(0.4)), lineWidth: 0.7)
                // Counter-drift cross lines at a shallower angle: depth.
                var cross = Path()
                var e: CGFloat = -canvasSize.width - CGFloat(phase) * 0.6
                while e < canvasSize.height {
                    cross.move(to: CGPoint(x: 0, y: e))
                    cross.addLine(to: CGPoint(x: canvasSize.width, y: e + canvasSize.width * (0.22 + tiltX * 0.10)))
                    e += 62
                }
                context.stroke(cross, with: .color(Color(theme.line.palette).opacity(0.22)), lineWidth: 0.7)
            }
            .allowsHitTesting(false)
        case "mech":
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.05), .clear, Color.white.opacity(0.03), .clear], startPoint: .leading, endPoint: .trailing))
                .rotationEffect(.degrees(18 + Double(tiltX) * 16))
                .offset(x: tiltX * 30)
                .scaleEffect(1.6)
                .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }
}

/// GPU signature layer (2.3.2), the physics tier: thin-film iridescence
/// on glass, a tilt-riding specular band on mech, and a gravitational-lens
/// bend on stardust. All three are fed by the same spring-followed gravity
/// vector as the rest of the field, so they move as one physical system.
private struct ThemeShaderModifier: ViewModifier {
    var layout: String
    var active: Bool
    var animated: Bool
    var size: CGSize
    var tiltX: CGFloat
    var tiltY: CGFloat
    var time: Double

    func body(content: Content) -> some View {
        if layout == "glass", active {
            content.colorEffect(ShaderLibrary.iridescentFilm(
                .float2(Float(size.width), Float(size.height)),
                .float2(Float(tiltX), Float(tiltY)),
                .float(Float(time)),
                .float(0.30)
            ))
        } else if layout == "mech", active {
            content.colorEffect(ShaderLibrary.mechSheen(
                .float2(Float(size.width), Float(size.height)),
                .float(Float(tiltX))
            ))
        } else if layout == "dust", animated {
            content.distortionEffect(
                ShaderLibrary.gravityLens(
                    .float2(Float(size.width / 2 + tiltX * size.width * 0.26), Float(size.height / 2 + tiltY * size.height * 0.26)),
                    .float(1.0)
                ),
                maxSampleOffset: CGSize(width: 48, height: 48)
            )
        } else {
            content
        }
    }
}

/// Glass card kit (2.3.2): the card leans in 3D with the phone, a light
/// sweep stays pinned to the gravity-up side, and under the glass theme
/// the surface itself gets the thin-film foil. Angles stay small on
/// purpose - a card is a physical object on the desk, not a weather vane.
struct TiltCardFX: ViewModifier {
    var cornerRadius: CGFloat
    var strength: CGFloat = 1
    /// List rows skip the per-card shader foil (an offscreen pass each);
    /// the hero card keeps the full kit.
    var lite: Bool = false
    @Environment(\.motionTracker) private var tracker
    @Environment(\.classdayChrome) private var chrome

    func body(content: Content) -> some View {
        let g = tracker.visualTilt
        let tx = g.dx
        let ty = g.dy - 1
        let on = chrome.tracksMotion
        content
            .overlay {
                if on {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.14), .clear, .white.opacity(0.04)],
                                startPoint: UnitPoint(x: 0.5 - tx * 0.8, y: 0),
                                endPoint: UnitPoint(x: 0.5 + tx * 0.8, y: 1)
                            ))
                        if !lite, chrome.theme.specialLayout == "glass" {
                            GeometryReader { geo in
                                // Foil stays a whisper: soft-light blend at
                                // low strength, so it can tint the card
                                // surface but never paint over the text.
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(.white.opacity(0.08))
                                    .colorEffect(ShaderLibrary.iridescentFilm(
                                        .float2(Float(geo.size.width), Float(geo.size.height)),
                                        .float2(Float(tx), Float(ty)),
                                        .float(0),
                                        .float(0.12)
                                    ))
                                    .blendMode(.softLight)
                            }
                        }
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .allowsHitTesting(false)
                }
            }
            .rotation3DEffect(.degrees(on ? Double(ty) * -5.5 * Double(strength) : 0), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
            .rotation3DEffect(.degrees(on ? Double(tx) * 5.5 * Double(strength) : 0), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.55)
    }
}

struct ThemeBackground: View {
    @Environment(\.classdayChrome) private var chrome
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ThemeFieldView(
            theme: chrome.theme,
            active: chrome.tier != .saver,
            animated: chrome.tier == .high && scenePhase == .active,
            particles: chrome.allowsParticles && scenePhase == .active
        )
        .ignoresSafeArea()
    }
}


struct ThemeGalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.classdayChrome) private var chrome
    @Environment(\.motionTracker) private var tracker
    @AppStorage("classday.tiltHaptics") private var tiltHaptics = true
    @AppStorage("classday.tiltSensitivity") private var tiltSensitivity = 2

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
                    tiltReadout
                    tiltHapticsToggle
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

    /// Live tilt readout: the ground-truth check for the tracking engine.
    /// If the dot follows the phone in this card, the sensor pipeline is
    /// alive and any remaining complaint is about effect strength, not
    /// about tracking itself.
    private var tiltReadout: some View {
        let g = tracker.gravity
        let dx = g.dx
        let dy = g.dy - 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(chrome.theme.line.palette), lineWidth: 1)
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(Color(chrome.theme.accent.palette))
                        .frame(width: 12, height: 12)
                        .offset(x: max(-26, min(26, dx * 44)), y: max(-26, min(26, dy * 44)))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("倾斜实时读数")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(chrome.theme.ink.palette))
                    Text("横 \(String(format: "%+.2f", Double(dx))) · 纵 \(String(format: "%+.2f", Double(dy)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color(chrome.theme.secondary.palette))
                    Text(chrome.tracksMotion ? "跟踪运行中：斜着拿手机，圆点应该跟着往低的那侧跑。" : "当前是省电档，跟踪未开启，这张卡只作传感器自检。")
                        .font(.caption)
                        .foregroundStyle(Color(chrome.theme.secondary.palette))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(chrome.theme.card.palette).opacity(0.7)))
        .onAppear { tracker.hapticsEnabled = tiltHaptics; tracker.sensitivity = tiltSensitivity; tracker.start() }
        .onDisappear { if !chrome.tracksMotion { tracker.stop() } }
    }

    private var tiltHapticsToggle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $tiltHaptics) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("倾斜震动反馈")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(chrome.theme.ink.palette))
                    Text("每套主题一种震法：倾斜跨刻度震一记，摆正时一记「归位」。省电档不震。")
                        .font(.caption)
                        .foregroundStyle(Color(chrome.theme.secondary.palette))
                }
            }
            .tint(Color(chrome.theme.accent.palette))
            Picker("灵敏度", selection: $tiltSensitivity) {
                Text("标准").tag(0)
                Text("灵敏").tag(1)
                Text("最敏感").tag(2)
            }
            .pickerStyle(.segmented)
            .onChange(of: tiltSensitivity) { _, value in tracker.sensitivity = value }
            HStack(spacing: 10) {
                Text("当前震法：\(tracker.profile.label)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(chrome.theme.secondary.palette))
                Spacer()
                Button("试震一下") { tracker.previewHaptics() }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .tint(Color(chrome.theme.accent.palette))
                    .disabled(!tiltHaptics)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(chrome.theme.card.palette).opacity(0.7)))
        .onChange(of: tiltHaptics) { _, value in tracker.hapticsEnabled = value }
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
    @Environment(\.dismiss) private var dismiss
    @State private var editingTask: HomeworkTask?
    @State private var newTask: HomeworkTask?
    @State private var showExams = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("考试、作业与成绩预测集中在这里。首页显示待办摘要，这里管理的是同一份数据。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("考试") {
                    Button("管理考试与倒计时") { showExams = true }
                    Text("共 \(model.document.exams.count) 场考试，可手动添加；日历文件请到「我的 → 数据」导入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("作业") {
                    Button("添加作业") {
                        newTask = HomeworkTask(courseName: "", title: "", dueISO: CivilStamp.string(from: Date(), calendar: model.calendar))
                    }
                    ForEach(model.document.homework.sorted { $0.dueISO < $1.dueISO }) { task in
                        HStack {
                            Button { model.toggleHomework(task.id) } label: {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(task.done ? "标记未完成" : "标记已完成")
                            Button { editingTask = task } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).strikethrough(task.done)
                                    Text("\(task.courseName) · \(task.dueISO)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { model.deleteHomework(task.id) } label: { Label("删除", systemImage: "trash") }
                            Button { editingTask = task } label: { Label("编辑", systemImage: "pencil") }.tint(.orange)
                        }
                    }
                    if model.document.homework.isEmpty { Text("暂无作业，先添加一项截止任务。组织课程请使用课表页。") }
                }
                Section("成绩与预测") {
                    NavigationLink("期末成绩预测") { StudyGradesView() }
                    Text("选择课程，设置评分规则并录入已有分项成绩，再试算及格或达到目标所需的期末分数。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("导入数据、课表库、分享和日历同步统一放在「我的 → 数据」，学习页不再重复导入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("学习")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $showExams) { ExamsView() }
            .sheet(item: $newTask) { task in
                HomeworkEditor(task: task, creating: true) { title, course, due in model.addHomework(title: title, courseName: course, due: due) }
            }
            .sheet(item: $editingTask) { task in
                HomeworkEditor(task: task) { title, course, due in model.updateHomework(task.id, title: title, courseName: course, due: due) }
            }
        }
    }
}

private struct StudyGradesView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Course?
    var body: some View {
        List {
            Section {
                Text("先选择课程。编辑评分规则和已有成绩后，页面内的「期末成绩预测」会试算所需分数，不替你修改期末成绩。")
            }
            ForEach(model.document.courses) { course in
                Button { selected = course } label: {
                    VStack(alignment: .leading) {
                        Text(course.name)
                        Text(course.gradeScheme == nil ? "先设置评分规则" : "录分与期末预测").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if model.document.courses.isEmpty { Text("暂无课程，请先在课表中添加课程，或到数据页导入。") }
        }
        .navigationTitle("期末成绩预测")
        .sheet(item: $selected) { course in GradeEditorView(courseID: course.id) }
    }
}

struct DataUtilitiesView: View {
    @Environment(AppModel.self) private var model
    @State private var timetableName = ""
    @State private var icsURL = ""
    @State private var importNote: String?
    @State private var pendingCalendar: ImportedCalendar?
    @State private var pendingURL = ""
    @State private var importing = false

    var body: some View {
        List {
            Section("课表库 · 本机多课表") {
                Text("先给当前课表命名另存，再点一份已存课表切换。切换时会保留当前课表，课程、考试和作业一起切换；不上传到云端。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("另存名称", text: $timetableName)
                Button("另存当前课表") { model.duplicateTimetable(named: timetableName); timetableName = "" }
                    .disabled(timetableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(model.document.library) { table in Button("切换到 · \(table.name)") { model.switchTimetable(to: table.id) } }
                if model.document.library.isEmpty { Text("尚未另存课表。") }
            }
            Section("分享") {
                ShareLink(item: ShareCodec.url(for: model.document)) { Label("分享当前课表链接", systemImage: "square.and.arrow.up") }
                TimetableQR(text: ShareCodec.url(for: model.document).absoluteString)
            }
            Section("日历地址导入") {
                Text("填写公开日历地址，本次读取后先核对数量，确认才追加课程、考试与作业。不会自动刷新或删除原有安排；需要更新时重新读取。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("iCal 订阅地址", text: $icsURL).textInputAutocapitalization(.never).keyboardType(.URL)
                Button(importing ? "正在读取…" : "读取并预览日历") { Task { await subscribe() } }.disabled(importing)
                if let importNote { Text(importNote).font(.caption) }
            }
            Section("系统日历") {
                Toggle("自动写入系统日历", isOn: Binding(get: { CalendarSync.isEnabled }, set: { enabled in
                    CalendarSync.isEnabled = enabled
                    if enabled { CalendarSync.sync(model.document, calendar: model.calendar) }
                }))
                Text("需要系统日历权限。写入的是课曜日程副本；关闭自动写入不会删除已经写入的副本。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(CalendarSync.status)
                Button("立即写入系统日历") { CalendarSync.isEnabled = true; CalendarSync.sync(model.document, calendar: model.calendar) }
            }
        }
        .navigationTitle("课表库、分享与日历")
        .onAppear { if icsURL.isEmpty { icsURL = model.document.subscribedICSURL } }
        .confirmationDialog("确认追加日历数据？", isPresented: Binding(get: { pendingCalendar != nil }, set: { if !$0 { pendingCalendar = nil } })) {
            Button("确认追加") {
                if let calendar = pendingCalendar { model.importCalendar(calendar, subscribeURL: pendingURL) }
                pendingCalendar = nil
                importNote = "已确认导入；可在学习页查看考试与作业。"
            }
            Button("取消", role: .cancel) { pendingCalendar = nil }
        } message: {
            Text("将追加 \(pendingCalendar?.courses.count ?? 0) 门课程、\(pendingCalendar?.exams.count ?? 0) 场考试、\(pendingCalendar?.homework.count ?? 0) 项作业。" + "\n" + (pendingCalendar?.warnings.joined(separator: "\n") ?? ""))
        }
    }

    private func subscribe() async {
        guard let url = URL(string: icsURL), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            importNote = "请输入完整的 HTTP/HTTPS 日历地址"; return
        }
        importing = true
        defer { importing = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 8 * 1024 * 1024, let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
                importNote = "未读到有效日历，请检查公开地址与文件格式（不超过 8 MB）"; return
            }
            pendingURL = url.absoluteString
            pendingCalendar = ICSImporter.parse(text, calendar: model.calendar, totalWeeks: model.document.semester.totalWeeks, periods: model.document.semester.periods)
        } catch { importNote = "没有下载到日历，检查地址和网络再试" }
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

struct RoomMapPreview: View {
    var location: String
    var pin: RoomPin?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: MKMapItem?
    @State private var results: [MKMapItem] = []
    @State private var position = MapCameraPosition.automatic
    @State private var searching = false
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("学校、楼宇或教室名称", text: $query).textFieldStyle(.roundedBorder)
                    Button(searching ? "正在搜索…" : "搜索地点") { Task { await search() } }
                        .disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if searching { ProgressView() }
                    if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    if let selected {
                        Map(position: $position) {
                            Marker(selected.name ?? "教室", coordinate: selected.placemark.coordinate)
                        }
                        .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text(selected.name ?? "已设置的教室位置").font(.headline)
                        if let address = selected.placemark.title { Text(address).font(.footnote) }
                        Button("在苹果地图中查看步行路线") {
                            if !selected.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking]) {
                                note = "未能打开苹果地图，请检查手机上的地图应用。"
                            }
                        }
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        Button { select(item) } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "地点")
                                Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text("同名教室可能位于不同校区，请先核对地图标记。路线由苹果地图计算；本页不请求读取你的定位。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("导航到教室")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task {
                query = RoomNavigation.destinationQuery(location: location, pin: pin)
                if RoomNavigation.hasValidCoordinates(pin), let latitude = pin?.latitude, let longitude = pin?.longitude {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
                    item.name = query.isEmpty ? "已设置的教室位置" : query
                    select(item)
                } else if query.isEmpty { note = "没有教室名称或有效坐标，请先编辑课程填写地点。" }
                else { await search() }
            }
        }
    }

    @MainActor private func select(_ item: MKMapItem) {
        selected = item
        position = .region(MKCoordinateRegion(center: item.placemark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
    }

    @MainActor private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true
        selected = nil
        results = []
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = Array(response.mapItems.prefix(8))
            note = results.isEmpty ? "没找到地点，请补充学校、校区或楼宇名称后重试。" : "请选择正确校区和地点，再查看路线。"
        } catch { note = "地点搜索未完成，请检查网络或补充名称后重试。" }
    }
}

/// Homework editor opened from the study desk's swipe action: title,
/// course and due date, all editable before anything is written back.
struct HomeworkEditor: View {
    var task: HomeworkTask
    var creating: Bool
    var onSave: (String, String, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var courseName: String
    @State private var due: Date

    init(task: HomeworkTask, creating: Bool = false, onSave: @escaping (String, String, Date) -> Void) {
        self.task = task
        self.creating = creating
        self.onSave = onSave
        _title = State(initialValue: task.title)
        _courseName = State(initialValue: task.courseName)
        _due = State(initialValue: CivilStamp.date(from: task.dueISO) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("作业标题", text: $title)
                TextField("课程（可空）", text: $courseName)
                DatePicker("截止时间", selection: $due, displayedComponents: [.date, .hourAndMinute])
            }
            .navigationTitle(creating ? "添加作业" : "编辑作业")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(title, courseName, due); dismiss() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
