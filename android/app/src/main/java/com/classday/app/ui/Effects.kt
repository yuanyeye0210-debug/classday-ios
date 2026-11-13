package com.classday.app.ui

import android.graphics.RuntimeShader
import android.os.Build
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.drawscope.DrawScope
import com.classday.app.core.ClassdayTheme
import com.classday.app.core.PerformanceTier
import kotlin.math.sin

fun rgb(r: Int, g: Int, b: Int, alpha: Float = 1f) = Color(r / 255f, g / 255f, b / 255f, alpha)

fun ClassdayTheme.bg() = rgb(background.r, background.g, background.b)
fun ClassdayTheme.ink() = rgb(ink.r, ink.g, ink.b)
fun ClassdayTheme.accent() = rgb(accent.r, accent.g, accent.b)
fun ClassdayTheme.card() = rgb(card.r, card.g, card.b)
fun ClassdayTheme.line() = rgb(line.r, line.g, line.b)
fun ClassdayTheme.glow() = rgb(glow.r, glow.g, glow.b)
fun ClassdayTheme.secondary() = rgb(secondary.r, secondary.g, secondary.b)

@Composable
fun ThemeBackdrop(theme: ClassdayTheme, tier: PerformanceTier, tilt: Offset, modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "backdrop")
    val time by transition.animateFloat(
        initialValue = 0f,
        targetValue = 12f,
        animationSpec = infiniteRepeatable(tween(12000, easing = LinearEasing), RepeatMode.Restart),
        label = "time",
    )
    val useShader = tier == PerformanceTier.high && theme.usesShader && Build.VERSION.SDK_INT >= 33
    if (useShader) {
        ShaderFill(theme.specialLayout, time, tilt, modifier)
    } else {
        val brush = Brush.linearGradient(
            listOf(theme.bg(), theme.card().copy(alpha = 0.95f), theme.glow().copy(alpha = if (tier == PerformanceTier.saver) 0.05f else 0.28f)),
        )
        Box(modifier.fillMaxSize().background(brush))
        if (tier == PerformanceTier.high && (theme.specialLayout == "aurora" || theme.specialLayout == "dust")) {
            ParticleField(theme, time, tilt, modifier)
        }
    }
}

@Composable
private fun ShaderFill(layout: String, time: Float, tilt: Offset, modifier: Modifier) {
    val shader = androidx.compose.runtime.remember(layout) { RuntimeShader(shaderSource(layout)) }
    Canvas(modifier.fillMaxSize()) {
        shader.setFloatUniform("resolution", size.width, size.height)
        shader.setFloatUniform("time", time)
        shader.setFloatUniform("tilt", tilt.x, tilt.y)
        drawRect(ShaderBrush(shader))
    }
}

@Composable
private fun ParticleField(theme: ClassdayTheme, time: Float, tilt: Offset, modifier: Modifier) {
    Canvas(modifier.fillMaxSize()) {
        repeat(18) { index ->
            val px = (size.width * ((index * 37 % 100) / 100f) + tilt.x * (index % 3) + sin(time + index) * 18f)
            val py = (size.height * ((index * 53 % 100) / 100f) + tilt.y * 2 + sin(time * 0.7f + index) * 24f)
            drawCircle(theme.glow().copy(alpha = 0.35f), radius = 3f + (index % 4), center = Offset(px, py))
        }
    }
}

private fun shaderSource(layout: String): String = when (layout) {
    "glass" -> """
        uniform float2 resolution;
        uniform float time;
        uniform float2 tilt;
        half4 main(float2 frag) {
          float2 uv = frag / resolution;
          float wave = sin(uv.x * 8.0 + time + tilt.x * 0.05) * sin(uv.y * 6.0 - time * 0.6);
          float3 col = mix(float3(0.93, 0.95, 0.98), float3(0.72, 0.62, 1.0), 0.18 + 0.12 * wave);
          col += float3(0.15, 0.25, 0.45) * (0.15 * sin(uv.y * 40.0 + time * 2.0));
          return half4(half3(col), 1.0);
        }
    """.trimIndent()
    "aurora" -> """
        uniform float2 resolution;
        uniform float time;
        uniform float2 tilt;
        half4 main(float2 frag) {
          float2 uv = frag / resolution + tilt * 0.002;
          float band = sin(uv.x * 3.0 + uv.y * 2.0 + time) * 0.5 + 0.5;
          float band2 = sin(uv.y * 5.0 - time * 0.8 + tilt.y) * 0.5 + 0.5;
          float3 col = float3(0.03, 0.04, 0.12);
          col += float3(0.35, 0.15, 0.9) * band * 0.45;
          col += float3(0.05, 0.75, 0.65) * band2 * 0.35;
          return half4(half3(col), 1.0);
        }
    """.trimIndent()
    else -> """
        uniform float2 resolution;
        uniform float time;
        uniform float2 tilt;
        half4 main(float2 frag) {
          float2 uv = frag / resolution;
          float scan = 0.9 + 0.1 * sin(uv.y * 520.0 + time * 10.0);
          float pulse = 0.5 + 0.5 * sin(time * 2.4 + uv.x * 7.0 + tilt.x * 0.08);
          float3 col = float3(0.03, 0.02, 0.07);
          col += float3(1.0, 0.18, 0.6) * 0.16 * pulse * (1.0 - uv.y);
          col += float3(0.0, 0.9, 1.0) * 0.08 * sin(uv.x * 16.0 + time);
          col *= scan;
          return half4(half3(col), 1.0);
        }
    """.trimIndent()
}

fun DrawScope.hudTicks(color: Color) {
    val w = size.width
    val h = size.height
    drawLine(color, Offset(8f, 8f), Offset(28f, 8f), 2f)
    drawLine(color, Offset(8f, 8f), Offset(8f, 28f), 2f)
    drawLine(color, Offset(w - 8f, 8f), Offset(w - 28f, 8f), 2f)
    drawLine(color, Offset(w - 8f, 8f), Offset(w - 8f, 28f), 2f)
}
