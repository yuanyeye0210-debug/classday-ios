package com.classday.app.core

data class Rgb(val r: Int, val g: Int, val b: Int)

data class CourseColorPair(
    val id: String,
    val lightBg: Rgb,
    val lightInk: Rgb,
    val darkBg: Rgb,
    val darkInk: Rgb,
) {
    fun bg(dark: Boolean): Rgb = if (dark) darkBg else lightBg
    fun ink(dark: Boolean): Rgb = if (dark) darkInk else lightInk
}

object ClassdayDesignTokens {
    val accent = Rgb(58, 107, 255)      // #3A6BFF
    val lightInk = Rgb(27, 36, 51)      // #1B2433
    val darkInk = Rgb(244, 246, 251)    // #F4F6FB
    val lightSecondary = Rgb(142, 150, 168) // #8E96A8
    val darkSecondary = Rgb(168, 176, 194)  // #A8B0C2
    val lightLine = Rgb(232, 236, 244)  // #E8ECF4
    val darkLine = Rgb(46, 52, 66)      // #2E3442
    val lightElevated = Rgb(244, 246, 251) // #F4F6FB
    val darkElevated = Rgb(36, 40, 51)  // #242833
    val lightCard = Rgb(255, 255, 255)  // #FFFFFF
    val darkCard = Rgb(28, 31, 40)      // #1C1F28
    val lightHero = Rgb(232, 238, 255)  // #E8EEFF
    val darkHero = Rgb(32, 42, 74)      // #202A4A
    val lightSegment = Rgb(232, 237, 248) // #E8EDF8
    val darkSegment = Rgb(36, 42, 56)   // #242A38
    val lightAccentInk = Rgb(58, 107, 255) // #3A6BFF
    val darkAccentInk = Rgb(150, 176, 255) // #96B0FF

    const val HERO_CARD_RADIUS_DP = 26
    const val DAY_CARD_RADIUS_DP = 22
    const val GROUP_CARD_RADIUS_DP = 20
    const val LIST_CARD_RADIUS_DP = 18
    const val BUTTON_RADIUS_DP = 16
    const val COURSE_BLOCK_RADIUS_DP = 12
    const val SHEET_TOP_RADIUS_DP = 28
    const val CAPSULE_RADIUS_DP = 99

    const val PRESS_SCALE = 0.96f
    const val PRESS_RESPONSE_SECONDS = 0.32f
    const val PRESS_DAMPING_FRACTION = 0.55f

    val coursePairs: List<CourseColorPair> = listOf(
        CourseColorPair(
            id = "blue",
            lightBg = Rgb(228, 236, 255),  // #E4ECFF
            lightInk = Rgb(42, 87, 214),   // #2A57D6
            darkBg = Rgb(36, 52, 95),
            darkInk = Rgb(214, 226, 255),
        ),
        CourseColorPair(
            id = "orange",
            lightBg = Rgb(255, 232, 212),  // #FFE8D4
            lightInk = Rgb(212, 106, 44),  // #D46A2C
            darkBg = Rgb(90, 58, 36),
            darkInk = Rgb(255, 215, 190),
        ),
        CourseColorPair(
            id = "green",
            lightBg = Rgb(227, 246, 232),  // #E3F6E8
            lightInk = Rgb(46, 139, 87),   // #2E8B57
            darkBg = Rgb(30, 70, 48),
            darkInk = Rgb(205, 238, 219),
        ),
        CourseColorPair(
            id = "purple",
            lightBg = Rgb(240, 232, 255),  // #F0E8FF
            lightInk = Rgb(122, 82, 199),  // #7A52C7
            darkBg = Rgb(58, 44, 85),
            darkInk = Rgb(228, 216, 255),
        ),
        CourseColorPair(
            id = "pink",
            lightBg = Rgb(253, 231, 238),  // #FDE7EE
            lightInk = Rgb(212, 83, 122),  // #D4537A
            darkBg = Rgb(85, 36, 51),
            darkInk = Rgb(255, 213, 226),
        ),
        CourseColorPair(
            id = "sage",
            lightBg = Rgb(230, 243, 228),  // #E6F3E4
            lightInk = Rgb(78, 143, 69),   // #4E8F45
            darkBg = Rgb(36, 56, 31),
            darkInk = Rgb(215, 240, 210),
        ),
    )

    fun coursePair(colorID: String): CourseColorPair =
        coursePairs.firstOrNull { it.id.equals(colorID, ignoreCase = true) } ?: coursePairs.first()
}

data class ClassdayTheme(
    val id: String,
    val name: String,
    val englishName: String,
    val tagline: String,
    val prefersDark: Boolean,
    val background: Rgb,
    val ink: Rgb,
    val secondary: Rgb,
    val accent: Rgb,
    val card: Rgb,
    val line: Rgb,
    val glow: Rgb,
    val courseAccents: List<Rgb>,
    val haptic: String,
    val specialLayout: String,
) {
    val usesShader: Boolean get() = specialLayout == "neon" || specialLayout == "aurora" || specialLayout == "glass"
    val usesMotion: Boolean get() = specialLayout == "glass" || specialLayout == "aurora" || specialLayout == "orbit" || specialLayout == "dust"
    val usesOrbit: Boolean get() = specialLayout == "orbit"
    val usesCube: Boolean get() = specialLayout == "cube"

    fun courseAccent(colorId: String): Rgb {
        val index = CourseColors.all.indexOf(colorId).let { if (it < 0) 0 else it }
        if (courseAccents.isEmpty()) return accent
        return courseAccents[index % courseAccents.size]
    }
}

object ClassdayThemes {
    const val fallbackId = "neon"

    val all: List<ClassdayTheme> = listOf(
        theme("neon", "霓虹赛博", "Neon Cyber", "辉光描边、扫描线和电脉冲", true, c(8, 6, 18), c(244, 236, 255), c(168, 150, 196), c(255, 46, 154), c(18, 12, 36), c(86, 40, 120), c(0, 229, 255), listOf(c(255, 46, 154), c(0, 229, 255), c(176, 92, 255), c(255, 196, 0), c(64, 255, 170), c(255, 92, 64)), "electric", "neon"),
        theme("glass", "玻璃全息", "Liquid Glass", "磨砂玻璃、虹彩和滚动折射", false, c(236, 240, 246), c(28, 36, 52), c(110, 120, 140), c(70, 120, 255), c(255, 255, 255), c(190, 205, 230), c(180, 140, 255), listOf(c(90, 140, 255), c(120, 200, 170), c(255, 176, 120), c(190, 150, 255), c(255, 140, 180), c(120, 190, 230)), "soft", "glass"),
        theme("hud", "深空 HUD", "Deep Space", "细线、准星锁定和倒计时表盘", true, c(4, 8, 14), c(214, 236, 244), c(110, 150, 160), c(80, 210, 220), c(10, 18, 28), c(40, 80, 90), c(80, 210, 220), listOf(c(80, 210, 220), c(240, 180, 70), c(120, 160, 255), c(90, 200, 140), c(200, 140, 90), c(160, 190, 210)), "tick", "hud"),
        theme("aurora", "极光粒子", "Aurora Depth", "极光网格、倾斜卡片和点击粒子", true, c(6, 10, 28), c(230, 240, 255), c(140, 160, 200), c(120, 90, 255), c(16, 22, 48), c(70, 60, 140), c(40, 220, 180), listOf(c(90, 140, 255), c(40, 210, 170), c(150, 100, 255), c(80, 180, 255), c(200, 120, 255), c(60, 200, 220)), "particle", "aurora"),
        theme("mech", "机甲金属", "Mech Armor", "钛合金块、液压抬升和碰撞回弹", true, c(14, 16, 20), c(230, 232, 236), c(140, 146, 156), c(210, 170, 90), c(28, 32, 38), c(70, 76, 86), c(90, 200, 220), listOf(c(210, 170, 70), c(70, 190, 210), c(190, 60, 60), c(80, 140, 210), c(160, 170, 180), c(120, 160, 90)), "metal", "mech"),
        theme("orbit", "星际轨道", "Orbit", "一天是行星，课程沿轨道转", true, c(4, 8, 22), c(226, 234, 255), c(130, 150, 190), c(255, 186, 92), c(12, 18, 40), c(40, 60, 110), c(90, 160, 255), listOf(c(255, 186, 92), c(90, 170, 255), c(140, 210, 255), c(255, 140, 90), c(180, 160, 255), c(120, 200, 180)), "glide", "orbit"),
        theme("cube", "立方全息", "Cube Holo", "一周是玻璃立方，轻扫转到下一天", true, c(6, 8, 16), c(230, 236, 255), c(140, 150, 180), c(150, 190, 255), c(16, 20, 36), c(60, 80, 120), c(180, 210, 255), listOf(c(140, 180, 255), c(120, 210, 230), c(180, 160, 255), c(100, 170, 255), c(200, 210, 255), c(90, 150, 220)), "glass", "cube"),
        theme("dust", "星尘引力", "Stardust Gravity", "星尘受重力牵引，手机往哪倾往哪流", true, c(7, 9, 26), c(232, 238, 255), c(150, 160, 200), c(255, 196, 92), c(13, 17, 40), c(52, 64, 110), c(120, 150, 255), listOf(c(255, 196, 92), c(120, 170, 255), c(170, 140, 255), c(90, 210, 200), c(255, 150, 120), c(150, 200, 255)), "glide", "dust"),
    )

    fun theme(id: String): ClassdayTheme = all.firstOrNull { it.id == id } ?: all[0]

    fun cycle(id: String): String {
        val index = all.indexOfFirst { it.id == id }.let { if (it < 0) 0 else it }
        return all[(index + 1) % all.size].id
    }

    fun effectiveTier(selected: PerformanceTier, lowPower: Boolean, reduceMotion: Boolean): PerformanceTier {
        if (lowPower || reduceMotion) return PerformanceTier.saver
        return selected
    }

    private fun c(r: Int, g: Int, b: Int) = Rgb(r, g, b)

    private fun theme(
        id: String,
        name: String,
        english: String,
        tagline: String,
        dark: Boolean,
        bg: Rgb,
        ink: Rgb,
        secondary: Rgb,
        accent: Rgb,
        card: Rgb,
        line: Rgb,
        glow: Rgb,
        courses: List<Rgb>,
        haptic: String,
        layout: String,
    ) = ClassdayTheme(id, name, english, tagline, dark, bg, ink, secondary, accent, card, line, glow, courses, haptic, layout)
}
