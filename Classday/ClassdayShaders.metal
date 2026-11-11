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

// Thin-film iridescence (2.3.2): the palette comes from an interference
// phase - film depth (radial), view tilt and time - not a painted gradient,
// so the bands flow and recombine as the phone tilts, like a soap film.
[[ stitchable ]] half4 iridescentFilm(float2 position, half4 color, float2 size, float2 tilt, float time, float strength) {
    float2 uv = position / max(size, float2(1.0));
    float d = length((uv - 0.5) * float2(size.x / max(size.y, 1.0), 1.0));
    float film = d * 3.1 + tilt.x * 2.4 - tilt.y * 1.5 + time * 0.10 + uv.x * 0.8;
    half3 iri = half3(0.5 + 0.5 * cos(6.28318 * (film + float3(0.0, 0.33, 0.67))));
    float fres = pow(min(d * 1.35, 1.2), 2.0);
    return half4(color.rgb + iri * half(fres * strength), color.a);
}

// Mech specular band (2.3.2): one hard sheen whose position rides the
// tilt, like light sliding across brushed titanium.
[[ stitchable ]] half4 mechSheen(float2 position, half4 color, float2 size, float tiltX) {
    float2 uv = position / max(size, float2(1.0));
    float cx = (uv.x - 0.5) + tiltX * 0.55 + uv.y * 0.35;
    float band = exp(-pow(cx * 4.2, 2.0));
    return half4(color.rgb + half3(half(band * 0.32)), color.a);
}

// Gravitational lens (2.3.2): bends the sampled position around a centre
// that trails the tilt, so the starfield smears into arcs around it.
[[ stitchable ]] float2 gravityLens(float2 position, float2 center, float strength) {
    float2 dl = position - center;
    float dist2 = dot(dl, dl);
    float bend = strength * 700.0 / (dist2 + 300.0);
    return position + normalize(dl + float2(0.001, 0.0)) * (bend * 14.0);
}
