#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 neonScan(float2 position, half4 color, float time) {
    float scan = 0.82 + 0.18 * sin(position.y * 0.08 + time * 3.0);
    float glow = 0.5 + 0.5 * sin(position.x * 0.02 + time);
    half3 tint = half3(color.r * half(scan), color.g * half(glow), color.b);
    return half4(tint, color.a);
}

[[ stitchable ]] half4 auroraFlow(float2 position, half4 color, float time) {
    float wave = sin(position.x * 0.02 + time) * cos(position.y * 0.015 - time * 0.7);
    half3 tint = half3(color.r, color.g * half(0.7 + 0.3 * wave), color.b * half(0.8 + 0.2 * wave));
    return half4(tint, color.a);
}

[[ stitchable ]] half4 glassWarp(float2 position, half4 color, float time) {
    float band = 0.85 + 0.15 * sin((position.x + position.y) * 0.03 + time * 1.4);
    return half4(color.rgb * half(band), color.a);
}
