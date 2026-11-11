import Foundation

public enum PerformanceTier: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case high
    case balanced
    case saver

    public var title: String {
        switch self {
        case .high: return "高性能"
        case .balanced: return "平衡"
        case .saver: return "省电"
        }
    }

    public var detail: String {
        switch self {
        case .high: return "着色器、视差和粒子都打开"
        case .balanced: return "保留动效，小组件用静态皮肤"
        case .saver: return "关闭着色器、陀螺仪和粒子"
        }
    }
}

public struct ThemeColor: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ palette: PaletteColor) {
        r = palette.r
        g = palette.g
        b = palette.b
    }

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var palette: PaletteColor { PaletteColor(r: r, g: g, b: b) }
}

public struct ClassdayTheme: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var englishName: String
    public var tagline: String
    public var prefersDark: Bool
    public var background: ThemeColor
    public var ink: ThemeColor
    public var secondary: ThemeColor
    public var accent: ThemeColor
    public var card: ThemeColor
    public var line: ThemeColor
    public var glow: ThemeColor
    public var courseAccents: [ThemeColor]
    public var haptic: String
    public var specialLayout: String

    public init(
        id: String,
        name: String,
        englishName: String,
        tagline: String,
        prefersDark: Bool,
        background: ThemeColor,
        ink: ThemeColor,
        secondary: ThemeColor,
        accent: ThemeColor,
        card: ThemeColor,
        line: ThemeColor,
        glow: ThemeColor,
        courseAccents: [ThemeColor],
        haptic: String,
        specialLayout: String
    ) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.tagline = tagline
        self.prefersDark = prefersDark
        self.background = background
        self.ink = ink
        self.secondary = secondary
        self.accent = accent
        self.card = card
        self.line = line
        self.glow = glow
        self.courseAccents = courseAccents
        self.haptic = haptic
        self.specialLayout = specialLayout
    }

    public var usesShader: Bool { specialLayout == "neon" || specialLayout == "aurora" || specialLayout == "glass" }
    public var usesMotion: Bool { specialLayout == "glass" || specialLayout == "aurora" || specialLayout == "orbit" || specialLayout == "dust" }
    public var usesOrbit: Bool { specialLayout == "orbit" }
    public var usesCube: Bool { specialLayout == "cube" }
    public var usesFan: Bool { specialLayout == "aurora" }

    public func courseAccent(for colorID: String) -> ThemeColor {
        let index = CourseColors.all.firstIndex { $0.id == colorID } ?? 0
        guard !courseAccents.isEmpty else { return accent }
        return courseAccents[index % courseAccents.count]
    }
}

public enum ClassdayThemes {
    public static let fallbackID = "neon"

    public static let all: [ClassdayTheme] = [
        theme(
            "neon", "霓虹赛博", "Neon Cyber", "辉光描边、扫描线和电脉冲",
            dark: true, bg: (8, 6, 18), ink: (244, 236, 255), secondary: (168, 150, 196),
            accent: (255, 46, 154), card: (18, 12, 36), line: (86, 40, 120), glow: (0, 229, 255),
            courses: [(255, 46, 154), (0, 229, 255), (176, 92, 255), (255, 196, 0), (64, 255, 170), (255, 92, 64)],
            haptic: "electric", layout: "neon"
        ),
        theme(
            "glass", "玻璃全息", "Liquid Glass", "磨砂玻璃、虹彩和滚动折射",
            dark: false, bg: (236, 240, 246), ink: (28, 36, 52), secondary: (110, 120, 140),
            accent: (70, 120, 255), card: (255, 255, 255), line: (190, 205, 230), glow: (180, 140, 255),
            courses: [(90, 140, 255), (120, 200, 170), (255, 176, 120), (190, 150, 255), (255, 140, 180), (120, 190, 230)],
            haptic: "soft", layout: "glass"
        ),
        theme(
            "hud", "深空 HUD", "Deep Space", "细线、准星锁定和倒计时表盘",
            dark: true, bg: (4, 8, 14), ink: (214, 236, 244), secondary: (110, 150, 160),
            accent: (80, 210, 220), card: (10, 18, 28), line: (40, 80, 90), glow: (80, 210, 220),
            courses: [(80, 210, 220), (240, 180, 70), (120, 160, 255), (90, 200, 140), (200, 140, 90), (160, 190, 210)],
            haptic: "tick", layout: "hud"
        ),
        theme(
            "aurora", "极光粒子", "Aurora Depth", "极光网格、倾斜卡片和点击粒子",
            dark: true, bg: (6, 10, 28), ink: (230, 240, 255), secondary: (140, 160, 200),
            accent: (120, 90, 255), card: (16, 22, 48), line: (70, 60, 140), glow: (40, 220, 180),
            courses: [(90, 140, 255), (40, 210, 170), (150, 100, 255), (80, 180, 255), (200, 120, 255), (60, 200, 220)],
            haptic: "particle", layout: "aurora"
        ),
        theme(
            "mech", "机甲金属", "Mech Armor", "钛合金块、液压抬升和碰撞回弹",
            dark: true, bg: (14, 16, 20), ink: (230, 232, 236), secondary: (140, 146, 156),
            accent: (210, 170, 90), card: (28, 32, 38), line: (70, 76, 86), glow: (90, 200, 220),
            courses: [(210, 170, 70), (70, 190, 210), (190, 60, 60), (80, 140, 210), (160, 170, 180), (120, 160, 90)],
            haptic: "metal", layout: "mech"
        ),
        theme(
            "orbit", "星际轨道", "Orbit", "一天是行星，课程沿轨道转",
            dark: true, bg: (4, 8, 22), ink: (226, 234, 255), secondary: (130, 150, 190),
            accent: (255, 186, 92), card: (12, 18, 40), line: (40, 60, 110), glow: (90, 160, 255),
            courses: [(255, 186, 92), (90, 170, 255), (140, 210, 255), (255, 140, 90), (180, 160, 255), (120, 200, 180)],
            haptic: "glide", layout: "orbit"
        ),
        theme(
            "cube", "立方全息", "Cube Holo", "一周是玻璃立方，轻扫转到下一天",
            dark: true, bg: (6, 8, 16), ink: (230, 236, 255), secondary: (140, 150, 180),
            accent: (150, 190, 255), card: (16, 20, 36), line: (60, 80, 120), glow: (180, 210, 255),
            courses: [(140, 180, 255), (120, 210, 230), (180, 160, 255), (100, 170, 255), (200, 210, 255), (90, 150, 220)],
            haptic: "glass", layout: "cube"
        ),
        theme(
            "dust", "星尘引力", "Stardust Gravity", "星尘受重力牵引，手机往哪倾往哪流",
            dark: true, bg: (7, 9, 26), ink: (232, 238, 255), secondary: (150, 160, 200),
            accent: (255, 196, 92), card: (13, 17, 40), line: (52, 64, 110), glow: (120, 150, 255),
            courses: [(255, 196, 92), (120, 170, 255), (170, 140, 255), (90, 210, 200), (255, 150, 120), (150, 200, 255)],
            haptic: "glide", layout: "dust"
        ),
    ]

    public static func theme(id: String) -> ClassdayTheme {
        all.first { $0.id == id } ?? all[0]
    }

    public static func effectiveTier(
        selected: PerformanceTier,
        lowPower: Bool,
        reduceMotion: Bool
    ) -> PerformanceTier {
        if lowPower || reduceMotion { return .saver }
        return selected
    }

    private static func theme(
        _ id: String,
        _ name: String,
        _ english: String,
        _ tagline: String,
        dark: Bool,
        bg: (Int, Int, Int),
        ink: (Int, Int, Int),
        secondary: (Int, Int, Int),
        accent: (Int, Int, Int),
        card: (Int, Int, Int),
        line: (Int, Int, Int),
        glow: (Int, Int, Int),
        courses: [(Int, Int, Int)],
        haptic: String,
        layout: String
    ) -> ClassdayTheme {
        func color(_ rgb: (Int, Int, Int)) -> ThemeColor {
            ThemeColor(PaletteColor.rgb(rgb.0, rgb.1, rgb.2))
        }
        return ClassdayTheme(
            id: id,
            name: name,
            englishName: english,
            tagline: tagline,
            prefersDark: dark,
            background: color(bg),
            ink: color(ink),
            secondary: color(secondary),
            accent: color(accent),
            card: color(card),
            line: color(line),
            glow: color(glow),
            courseAccents: courses.map(color),
            haptic: haptic,
            specialLayout: layout
        )
    }
}

public struct AppearanceChoice: Codable, Equatable, Hashable, Sendable {
    public var themeID: String
    public var performance: PerformanceTier

    public init(themeID: String = ClassdayThemes.fallbackID, performance: PerformanceTier = .balanced) {
        self.themeID = ClassdayThemes.theme(id: themeID).id
        self.performance = performance
    }

    public static let standard = AppearanceChoice()

    public var theme: ClassdayTheme { ClassdayThemes.theme(id: themeID) }
}
