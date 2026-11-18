package com.classday.app.ui

import android.os.Build
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.classday.app.core.ClassdayDesignTokens
import com.classday.app.core.PerformanceTier
import com.classday.app.core.Rgb
import kotlin.math.cos
import kotlin.math.sin

fun Rgb.toColor(alpha: Float = 1f): Color = rgb(r, g, b, alpha)

@Immutable
data class IosPalette(
    val isDark: Boolean,
    val accent: Color,
    val ink: Color,
    val secondary: Color,
    val line: Color,
    val elevated: Color,
    val card: Color,
    val hero: Color,
    val segment: Color,
    val accentInk: Color,
    val frostedFill: Color,
    val frostedStrongFill: Color,
    val frostedBorder: Color,
) {
    fun courseBg(colorID: String, alpha: Float = 1f): Color =
        ClassdayDesignTokens.coursePair(colorID).bg(isDark).toColor(alpha)

    fun courseInk(colorID: String, alpha: Float = 1f): Color =
        ClassdayDesignTokens.coursePair(colorID).ink(isDark).toColor(alpha)
}

/** 当前选中的主题；根节点提供，palette 与各处取色都按它走，否则换主题界面不会有任何变化。 */
val LocalClassdayTheme = androidx.compose.runtime.staticCompositionLocalOf<com.classday.app.core.ClassdayTheme?> { null }

@Composable
fun rememberIosPalette(
    dark: Boolean = isSystemInDarkTheme(),
    theme: com.classday.app.core.ClassdayTheme? = LocalClassdayTheme.current,
): IosPalette = remember(dark, theme?.id) {
    if (theme != null) return@remember themePalette(theme, dark)
    if (dark) {
        IosPalette(
            isDark = true,
            accent = ClassdayDesignTokens.accent.toColor(),
            ink = ClassdayDesignTokens.darkInk.toColor(),
            secondary = ClassdayDesignTokens.darkSecondary.toColor(),
            line = ClassdayDesignTokens.darkLine.toColor(),
            elevated = ClassdayDesignTokens.darkElevated.toColor(),
            card = ClassdayDesignTokens.darkCard.toColor(),
            hero = ClassdayDesignTokens.darkHero.toColor(),
            segment = ClassdayDesignTokens.darkSegment.toColor(),
            accentInk = ClassdayDesignTokens.darkAccentInk.toColor(),
            frostedFill = ClassdayDesignTokens.darkCard.toColor(0.84f),
            frostedStrongFill = ClassdayDesignTokens.darkCard.toColor(0.94f),
            frostedBorder = Color.White.copy(alpha = 0.09f),
        )
    } else {
        IosPalette(
            isDark = false,
            accent = ClassdayDesignTokens.accent.toColor(),
            ink = ClassdayDesignTokens.lightInk.toColor(),
            secondary = ClassdayDesignTokens.lightSecondary.toColor(),
            line = ClassdayDesignTokens.lightLine.toColor(),
            elevated = ClassdayDesignTokens.lightElevated.toColor(),
            card = ClassdayDesignTokens.lightCard.toColor(),
            hero = ClassdayDesignTokens.lightHero.toColor(),
            segment = ClassdayDesignTokens.lightSegment.toColor(),
            accentInk = ClassdayDesignTokens.lightAccentInk.toColor(),
            frostedFill = Color.White.copy(alpha = 0.78f),
            frostedStrongFill = Color.White.copy(alpha = 0.94f),
            frostedBorder = Color.White.copy(alpha = 0.92f),
        )
    }
}

/** 主题色板：一套主题里的强调色、卡片色、线条色直接决定界面长相。 */
private fun themePalette(theme: com.classday.app.core.ClassdayTheme, dark: Boolean): IosPalette {
    val isDark = theme.prefersDark || dark
    // 浅色主题下纯白卡片会糊成一片，掺一点主题强调色做成「带色偏的纸」，
    // 再用主题线条色描边，卡片才有层次。
    // 浅色主题：卡片往背景色靠（玻璃感），靠得很近但不消失，边框只剩一丝。
    val cardRgb = if (isDark) theme.card else blend(theme.background, theme.accent, 0.13f)
    val accent = theme.accent.toColor()
    return IosPalette(
        isDark = isDark,
        accent = accent,
        ink = theme.ink.toColor(),
        secondary = theme.secondary.toColor(),
        line = theme.line.toColor(),
        elevated = blend(cardRgb, theme.background, 0.5f).toColor(),
        card = cardRgb.toColor(),
        hero = blend(theme.accent, cardRgb, 0.86f).toColor(),
        segment = blend(cardRgb, theme.background, 0.35f).toColor(),
        accentInk = if (isDark) blend(theme.accent, theme.ink, 0.35f).toColor() else accent,
        frostedFill = cardRgb.toColor(if (isDark) 0.84f else 0.74f),
        frostedStrongFill = cardRgb.toColor(if (isDark) 0.95f else 0.86f),
        frostedBorder = if (isDark) Color.White.copy(alpha = 0.09f) else theme.accent.toColor().copy(alpha = 0.20f),
    )
}

private fun blend(from: com.classday.app.core.Rgb, to: com.classday.app.core.Rgb, amount: Float) =
    com.classday.app.core.Rgb(
        r = (from.r + (to.r - from.r) * amount).toInt().coerceIn(0, 255),
        g = (from.g + (to.g - from.g) * amount).toInt().coerceIn(0, 255),
        b = (from.b + (to.b - from.b) * amount).toInt().coerceIn(0, 255),
    )
fun Modifier.journalPress(
    enabled: Boolean = true,
    scaleDown: Float = ClassdayDesignTokens.PRESS_SCALE,
    onClick: (() -> Unit)? = null,
): Modifier = composed {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (enabled && isPressed) scaleDown else 1f,
        animationSpec = spring(
            dampingRatio = ClassdayDesignTokens.PRESS_DAMPING_FRACTION,
            stiffness = Spring.StiffnessMediumLow,
        ),
        label = "journalPress",
    )
    val base = this.scale(scale)
    if (onClick != null && enabled) {
        base.clickable(
            interactionSource = interactionSource,
            indication = null,
            onClick = onClick,
        )
    } else {
        base
    }
}

@Composable
fun FrostedCard(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = ClassdayDesignTokens.LIST_CARD_RADIUS_DP.dp,
    tier: PerformanceTier = PerformanceTier.high,
    borderColor: Color? = null,
    borderWidth: Dp = 1.dp,
    containerColor: Color? = null,
    contentPadding: PaddingValues = PaddingValues(14.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val palette = rememberIosPalette()
    // 布局主题（纸张 / 终端 / 蓝图）会改卡片形状与描边，不只是换色。
    val activeTheme = LocalClassdayTheme.current
    val layout = activeTheme?.specialLayout.orEmpty()
    val effectiveRadius = when (layout) {
        "paper" -> 4.dp
        "terminal" -> 2.dp
        "blueprint" -> 10.dp
        "glass" -> 22.dp
        else -> cornerRadius
    }
    val shape = RoundedCornerShape(effectiveRadius)
    val degradeFrosted = tier == PerformanceTier.saver || Build.VERSION.SDK_INT < 31
    val baseFill = containerColor ?: if (degradeFrosted) palette.frostedStrongFill else palette.frostedFill
    val fill = when (layout) {
        "terminal" -> activeTheme!!.card.toColor(0.35f)
        "paper" -> activeTheme!!.card.toColor(0.97f)
        "blueprint" -> activeTheme!!.card.toColor(0.55f)
        "glass" -> activeTheme!!.card.toColor(0.80f)
        else -> baseFill
    }
    val stroke = borderColor ?: when (layout) {
        "paper" -> activeTheme!!.ink.toColor(0.14f)
        "terminal" -> activeTheme!!.accent.toColor(0.55f)
        "blueprint" -> activeTheme!!.accent.toColor(0.40f)
        "glass" -> Color.White.copy(alpha = 0.75f)
        else -> palette.frostedBorder
    }
    val shadowElevation = when (layout) {
        "paper", "terminal", "blueprint" -> 0.dp
        else -> if (degradeFrosted) 2.dp else 6.dp
    }
    val shadowColor = if (palette.isDark) Color.Black.copy(alpha = 0.35f) else Color(0xFF192341).copy(alpha = 0.10f)

    val interactive = if (onClick != null) {
        modifier.journalPress(onClick = onClick)
    } else {
        modifier
    }

    Column(
        modifier = interactive
            .shadow(
                elevation = shadowElevation,
                shape = shape,
                ambientColor = shadowColor,
                spotColor = shadowColor,
            )
            .clip(shape)
            .background(fill, shape)
            .border(borderWidth, stroke, shape)
            .padding(contentPadding),
        content = content,
    )
}

@Composable
fun CourseGlyphTile(
    name: String,
    colorID: String,
    modifier: Modifier = Modifier,
    size: Dp = 58.dp,
    cornerRadius: Dp = 18.dp,
    fontSize: TextUnit = 26.sp,
    frostedHero: Boolean = false,
) {
    val palette = rememberIosPalette()
    val shape = RoundedCornerShape(cornerRadius)
    val bg = if (frostedHero) {
        if (palette.isDark) Color.White.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.72f)
    } else {
        palette.courseBg(colorID)
    }
    val ink = palette.courseInk(colorID)
    val glyph = name.trim().firstOrNull()?.toString() ?: "课"

    Box(
        modifier = modifier
            .size(size)
            .clip(shape)
            .background(bg, shape)
            .then(
                if (frostedHero) Modifier.border(1.dp, Color.White.copy(alpha = if (palette.isDark) 0.18f else 0.9f), shape)
                else Modifier
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = glyph,
            color = ink,
            fontSize = fontSize,
            fontWeight = FontWeight.Black,
        )
    }
}

@Composable
fun CircleActionBtn(
    label: String,
    modifier: Modifier = Modifier,
    size: Dp = 38.dp,
    fontSize: TextUnit = 20.sp,
    contentDescription: String? = null,
    onClick: () -> Unit,
) {
    val palette = rememberIosPalette()
    val shadowColor = if (palette.isDark) Color.Black.copy(alpha = 0.35f) else Color(0xFF192341).copy(alpha = 0.10f)
    Box(
        modifier = modifier
            .size(size)
            .journalPress(onClick = onClick)
            .semantics {
                role = Role.Button
                if (contentDescription != null) this.contentDescription = contentDescription
            }
            .shadow(4.dp, CircleShape, ambientColor = shadowColor, spotColor = shadowColor)
            .clip(CircleShape)
            .background(if (palette.isDark) palette.elevated else Color.White.copy(alpha = 0.88f), CircleShape)
            .border(1.dp, palette.line, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = palette.ink,
            fontSize = fontSize,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
fun IosSegmentedControl(
    items: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    fullWidth: Boolean = false,
) {
    val palette = rememberIosPalette()
    val outerShape = RoundedCornerShape(13.dp)
    val innerShape = RoundedCornerShape(10.dp)
    Row(
        modifier = modifier
            .clip(outerShape)
            .background(palette.segment, outerShape)
            .padding(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items.forEachIndexed { index, title ->
            val active = index == selectedIndex
            val itemModifier = if (fullWidth) Modifier.weight(1f) else Modifier
            Box(
                modifier = itemModifier
                    .journalPress(scaleDown = 0.97f) { onSelect(index) }
                    .semantics {
                        role = Role.Tab
                        selected = active
                    }
                    .then(
                        if (active) {
                            Modifier
                                .shadow(
                                    elevation = 2.dp,
                                    shape = innerShape,
                                    ambientColor = Color.Black.copy(alpha = 0.10f),
                                    spotColor = Color.Black.copy(alpha = 0.10f),
                                )
                                .clip(innerShape)
                                .background(palette.card, innerShape)
                        } else {
                            Modifier.clip(innerShape)
                        }
                    )
                    .padding(horizontal = 14.dp, vertical = 7.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = title,
                    color = if (active) palette.ink else palette.secondary,
                    fontSize = 13.sp,
                    fontWeight = if (active) FontWeight.Bold else FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
fun StatusPill(
    text: String,
    containerColor: Color,
    contentColor: Color,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(ClassdayDesignTokens.CAPSULE_RADIUS_DP.dp)
    Box(
        modifier = modifier
            .clip(shape)
            .background(containerColor, shape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = contentColor,
            fontSize = 11.5.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
        )
    }
}

private data class CapsuleTabItem(
    val screen: Screen,
    val title: String,
    val iconKind: String,
)

@Composable
fun FloatingCapsuleTabBar(
    current: Screen,
    onSelect: (Screen) -> Unit,
    tier: PerformanceTier,
    modifier: Modifier = Modifier,
) {
    val palette = rememberIosPalette()
    val tabs = remember {
        listOf(
            CapsuleTabItem(Screen.Today, "今日", "sun"),
            CapsuleTabItem(Screen.Week, "课表", "cal"),
            CapsuleTabItem(Screen.Countdown, "课程", "book"),
            CapsuleTabItem(Screen.Settings, "我的", "user"),
        )
    }
    val activeRoot = when (current) {
        Screen.Today -> Screen.Today
        Screen.Week -> Screen.Week
        Screen.Countdown, Screen.StudyGrades, is Screen.GradePrediction -> Screen.Countdown
        else -> Screen.Settings
    }
    val degradeFrosted = tier == PerformanceTier.saver || Build.VERSION.SDK_INT < 31
    val barFill = if (degradeFrosted) palette.frostedStrongFill else {
        if (palette.isDark) palette.card.copy(alpha = 0.88f) else Color.White.copy(alpha = 0.82f)
    }
    val barShape = RoundedCornerShape(34.dp)
    val shadowColor = if (palette.isDark) Color.Black.copy(alpha = 0.45f) else Color(0xFF192341).copy(alpha = 0.16f)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(68.dp)
                .shadow(16.dp, barShape, ambientColor = shadowColor, spotColor = shadowColor)
                .clip(barShape)
                .background(barFill, barShape)
                .border(1.dp, palette.frostedBorder, barShape)
                .padding(horizontal = 8.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            tabs.forEach { tab ->
                val active = activeRoot == tab.screen
                val tint = if (active) palette.accent else palette.secondary
                val pillShape = RoundedCornerShape(24.dp)
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .journalPress(scaleDown = 0.95f) { onSelect(tab.screen) }
                        .semantics {
                            role = Role.Tab
                            selected = active
                            contentDescription = tab.title
                        }
                        .clip(pillShape)
                        .background(
                            if (active) palette.accent.copy(alpha = if (palette.isDark) 0.18f else 0.11f)
                            else Color.Transparent,
                            pillShape,
                        ),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    TabLineIcon(kind = tab.iconKind, color = tint, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.height(3.dp))
                    Text(
                        text = tab.title,
                        color = tint,
                        fontSize = 11.sp,
                        fontWeight = if (active) FontWeight.Bold else FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

@Composable
private fun TabLineIcon(kind: String, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val stroke = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
        val w = size.width
        val h = size.height
        when (kind) {
            "sun" -> {
                val center = Offset(w / 2f, h / 2f)
                drawCircle(color = color, radius = w * 0.19f, center = center, style = stroke)
                val inner = w * 0.31f
                val outer = w * 0.42f
                for (deg in 0 until 360 step 45) {
                    val rad = Math.toRadians(deg.toDouble())
                    val c = cos(rad).toFloat()
                    val s = sin(rad).toFloat()
                    drawLine(
                        color = color,
                        start = Offset(center.x + c * inner, center.y + s * inner),
                        end = Offset(center.x + c * outer, center.y + s * outer),
                        strokeWidth = stroke.width,
                        cap = StrokeCap.Round,
                    )
                }
            }
            "cal" -> {
                val left = w * 0.13f
                val top = h * 0.21f
                val rectW = w * 0.74f
                val rectH = h * 0.66f
                drawRoundRect(
                    color = color,
                    topLeft = Offset(left, top),
                    size = Size(rectW, rectH),
                    cornerRadius = CornerRadius(w * 0.14f, w * 0.14f),
                    style = stroke,
                )
                drawLine(
                    color = color,
                    start = Offset(left, h * 0.42f),
                    end = Offset(left + rectW, h * 0.42f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = Offset(w * 0.33f, h * 0.12f),
                    end = Offset(w * 0.33f, h * 0.29f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = Offset(w * 0.67f, h * 0.12f),
                    end = Offset(w * 0.67f, h * 0.29f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
            }
            "book" -> {
                val path = Path().apply {
                    moveTo(w * 0.5f, h * 0.26f)
                    cubicTo(w * 0.38f, h * 0.18f, w * 0.22f, h * 0.18f, w * 0.12f, h * 0.24f)
                    lineTo(w * 0.12f, h * 0.78f)
                    cubicTo(w * 0.22f, h * 0.72f, w * 0.38f, h * 0.72f, w * 0.5f, h * 0.80f)
                    cubicTo(w * 0.62f, h * 0.72f, w * 0.78f, h * 0.72f, w * 0.88f, h * 0.78f)
                    lineTo(w * 0.88f, h * 0.24f)
                    cubicTo(w * 0.78f, h * 0.18f, w * 0.62f, h * 0.18f, w * 0.5f, h * 0.26f)
                    close()
                }
                drawPath(path = path, color = color, style = stroke)
                drawLine(
                    color = color,
                    start = Offset(w * 0.5f, h * 0.26f),
                    end = Offset(w * 0.5f, h * 0.80f),
                    strokeWidth = stroke.width,
                    cap = StrokeCap.Round,
                )
            }
            else -> {
                drawCircle(
                    color = color,
                    radius = w * 0.17f,
                    center = Offset(w * 0.5f, h * 0.34f),
                    style = stroke,
                )
                val arcPath = Path().apply {
                    moveTo(w * 0.20f, h * 0.84f)
                    cubicTo(w * 0.22f, h * 0.63f, w * 0.78f, h * 0.63f, w * 0.80f, h * 0.84f)
                }
                drawPath(path = arcPath, color = color, style = stroke)
            }
        }
    }
}
