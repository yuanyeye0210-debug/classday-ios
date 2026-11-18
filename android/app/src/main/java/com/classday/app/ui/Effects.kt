package com.classday.app.ui

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.dp
import com.classday.app.core.ClassdayTheme
import com.classday.app.core.PerformanceTier

fun rgb(r: Int, g: Int, b: Int, alpha: Float = 1f) = Color(r / 255f, g / 255f, b / 255f, alpha)

fun ClassdayTheme.bg() = rgb(background.r, background.g, background.b)
fun ClassdayTheme.ink() = rgb(ink.r, ink.g, ink.b)
fun ClassdayTheme.accent() = rgb(accent.r, accent.g, accent.b)
fun ClassdayTheme.card() = rgb(card.r, card.g, card.b)
fun ClassdayTheme.line() = rgb(line.r, line.g, line.b)
fun ClassdayTheme.glow() = rgb(glow.r, glow.g, glow.b)
fun ClassdayTheme.secondary() = rgb(secondary.r, secondary.g, secondary.b)

/**
 * 背景按系统深浅色绘制，与 rememberIosPalette() 和 MaterialTheme 配色同源；
 * 页面文字也统一取自该配色，不再用所选主题的 ink()/secondary()，避免浅底配浅字。
 * theme 参数保留给调用方的动效判断。
 */
@Composable
fun ThemeBackdrop(
    theme: ClassdayTheme,
    tier: PerformanceTier,
    tilt: Offset,
    modifier: Modifier = Modifier,
) {
    // 背景跟「选中的主题」走，而不是跟系统深色模式走：
    // 否则暗色主题 + 系统浅色 = 浅底配暗卡片。
    val isDark = theme.prefersDark || isSystemInDarkTheme()
    val bg = theme.background
    val white = com.classday.app.core.Rgb(255, 255, 255)
    val baseGradient = if (isDark) {
        Brush.verticalGradient(
            listOf(
                bg.toColor(),
                com.classday.app.core.Rgb(
                    (bg.r + (white.r - bg.r) * 0.05f).toInt(),
                    (bg.g + (white.g - bg.g) * 0.05f).toInt(),
                    (bg.b + (white.b - bg.b) * 0.05f).toInt(),
                ).toColor(),
                bg.toColor(),
            ),
        )
    } else {
        Brush.verticalGradient(
            listOf(
                com.classday.app.core.Rgb(
                    (bg.r + (white.r - bg.r) * 0.55f).toInt(),
                    (bg.g + (white.g - bg.g) * 0.55f).toInt(),
                    (bg.b + (white.b - bg.b) * 0.55f).toInt(),
                ).toColor(),
                bg.toColor(),
                com.classday.app.core.Rgb(
                    (bg.r + (white.r - bg.r) * 0.45f).toInt(),
                    (bg.g + (white.g - bg.g) * 0.45f).toInt(),
                    (bg.b + (white.b - bg.b) * 0.45f).toInt(),
                ).toColor(),
            ),
        )
    }

    val useBlur = Build.VERSION.SDK_INT >= 31 && tier != PerformanceTier.saver
    // 纸张 / 终端 / 蓝图这三种布局是「平的」，不铺彩色光斑，只叠各自的纹理。
    val flatLayout = theme.specialLayout == "paper" || theme.specialLayout == "terminal" || theme.specialLayout == "blueprint"
    val blobAlpha = when {
        flatLayout -> 0f
        tier == PerformanceTier.saver -> if (isDark) 0.12f else 0.28f
        isDark -> 0.24f
        else -> 0.55f
    }

    val blob1 = if (isDark) Color(0xFF284696) else Color(0xFFBFD0FF)
    val blob2 = if (isDark) Color(0xFF4B3278) else Color(0xFFE9D9FF)
    val blob3 = if (isDark) Color(0xFF1E5540) else Color(0xFFD4F0E0)
    val blob4 = if (isDark) Color(0xFF6E3C24) else Color(0xFFFFE3CF)

    Box(modifier = modifier.fillMaxSize().background(baseGradient)) {
        val glowModifier = if (useBlur) Modifier.fillMaxSize().blur(56.dp) else Modifier.fillMaxSize()
        Canvas(modifier = glowModifier) {
            val w = size.width
            val h = size.height
            val tx = tilt.x * 1.6f
            val ty = tilt.y * 1.6f

            drawSoftBlob(
                color = blob1.copy(alpha = blobAlpha),
                center = Offset(w * 0.16f + tx, h * 0.08f + ty),
                radius = w * 0.42f,
                useSolid = useBlur,
            )
            drawSoftBlob(
                color = blob2.copy(alpha = blobAlpha),
                center = Offset(w * 0.88f - tx, h * 0.18f + ty),
                radius = w * 0.36f,
                useSolid = useBlur,
            )
            drawSoftBlob(
                color = blob3.copy(alpha = blobAlpha),
                center = Offset(w * 0.14f + tx, h * 0.56f - ty),
                radius = w * 0.34f,
                useSolid = useBlur,
            )
            drawSoftBlob(
                color = blob4.copy(alpha = blobAlpha),
                center = Offset(w * 0.84f - tx, h * 0.78f - ty),
                radius = w * 0.35f,
                useSolid = useBlur,
            )
        }
        if (flatLayout) {
            Canvas(Modifier.fillMaxSize()) {
                when (theme.specialLayout) {
                    "paper" -> {
                        val step = 26.dp.toPx()
                        var y = step
                        val ink = theme.ink.toColor()
                        while (y < size.height) {
                            drawLine(ink.copy(alpha = 0.06f), Offset(0f, y), Offset(size.width, y), 1f)
                            y += step
                        }
                    }
                    "terminal" -> {
                        val step = 3.dp.toPx()
                        var y = 0f
                        while (y < size.height) {
                            drawRect(Color.Black.copy(alpha = 0.22f), Offset(0f, y), androidx.compose.ui.geometry.Size(size.width, 1f))
                            y += step * 2
                        }
                    }
                    "blueprint" -> {
                        val step = 30.dp.toPx()
                        val line = theme.accent.toColor().copy(alpha = 0.10f)
                        var x = 0f
                        while (x < size.width) { drawLine(line, Offset(x, 0f), Offset(x, size.height), 1f); x += step }
                        var y = 0f
                        while (y < size.height) { drawLine(line, Offset(0f, y), Offset(size.width, y), 1f); y += step }
                    }
                }
            }
        }
    }
}

private fun DrawScope.drawSoftBlob(
    color: Color,
    center: Offset,
    radius: Float,
    useSolid: Boolean,
) {
    if (radius <= 0f) return
    if (useSolid) {
        drawCircle(color = color, radius = radius * 0.72f, center = center)
    } else {
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(color, color.copy(alpha = color.alpha * 0.45f), Color.Transparent),
                center = center,
                radius = radius,
            ),
            radius = radius,
            center = center,
        )
    }
}

fun DrawScope.hudTicks(color: Color) {
    val w = size.width
    val h = size.height
    drawLine(color, Offset(8f, 8f), Offset(28f, 8f), 2f)
    drawLine(color, Offset(8f, 8f), Offset(8f, 28f), 2f)
    drawLine(color, Offset(w - 8f, 8f), Offset(w - 28f, 8f), 2f)
    drawLine(color, Offset(w - 8f, 8f), Offset(w - 8f, 28f), 2f)
}
