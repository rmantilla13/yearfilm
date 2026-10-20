#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The memory pool: thin wisps of light drifting in a slow swirl around a dark
// center. Domain-warped fractal noise, turned into filaments by keeping only
// the ridges where the noise crosses its midpoint.

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

// Four octaves: enough for smoke, few enough that the wisps stay smooth instead of crinkled.
static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    const float2x2 m = float2x2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = m * p;
        a *= 0.5;
    }
    return v;
}

/// `center` is where the pool sits, as a fraction of the view's size. `touch` (same units) is
/// where a finger, or a memory landing, stirs the water; `stir` (0...1) is how hard, fading
/// back to 0 after the touch ends.
[[ stitchable ]] half4 memoryPool(float2 position, half4 color, float2 size, float time, float intensity, float2 center, float2 touch, float stir) {
    float scale = size.x;  // the pool is sized to the width, so it reads the same on every phone
    float2 uv = (position - size * center) / scale;

    // Stir: twist the water around the touch point, strongest right under it.
    float2 toTouch = (position - size * touch) / scale;
    float near = exp(-dot(toTouch, toTouch) * 14.0) * stir;
    float twist = near * 2.6;
    float2 pivot = (size * touch - size * center) / scale;
    float2 offset = uv - pivot;
    uv = pivot + float2(offset.x * cos(twist) - offset.y * sin(twist), offset.x * sin(twist) + offset.y * cos(twist));

    float r = length(uv);
    float angle = atan2(uv.y, uv.x);

    // Swirl: everything turns slowly, the inner rings a little faster.
    float swirl = time * 0.035 + 0.35 / (r + 0.3);
    float2 p = float2(cos(angle + swirl), sin(angle + swirl)) * r * 1.7;

    float2 q = float2(fbm(p + time * 0.04), fbm(p + float2(5.2, 1.3) - time * 0.035));
    float2 w = float2(fbm(p + 2.2 * q + float2(1.7, 9.2) + time * 0.05),
                      fbm(p + 2.2 * q + float2(8.3, 2.8) - time * 0.045));
    float n = fbm(p + 2.4 * w);

    // Thin bright threads where the noise crosses its midpoint, a soft glow around them,
    // and only in some places at a time, so it reads as wisps rather than marble.
    float ridge = 1.0 - abs(n * 2.0 - 1.0);
    float density = smoothstep(0.3, 0.62, fbm(p * 0.8 + float2(11.0, 3.0) + time * 0.03));
    float filaments = pow(ridge, 9.0) * (0.25 + 0.75 * density);
    float haze = pow(ridge, 3.0) * (0.15 + 0.35 * density);

    // A pool, not a wallpaper: dark at the center, brightest around the rim, fading beyond it.
    float ring = smoothstep(0.06, 0.28, r) * (1.0 - smoothstep(0.5, 1.0, r));
    // A touch lights the water under it too, even in the dark middle of the pool.
    ring = max(ring, near * 1.2);
    float light = (filaments * 1.6 + haze) * ring * intensity + near * 0.18;

    float3 deep = float3(0.016, 0.031, 0.059);
    float3 teal = float3(0.10, 0.52, 0.86);
    float3 ice = float3(0.78, 0.95, 1.0);
    float3 rgb = deep + teal * light + ice * pow(filaments * ring, 3.0) * intensity * 0.9;
    return half4(half3(rgb), 1.0h);
}
