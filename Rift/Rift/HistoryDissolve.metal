#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

static float historyHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Sample the actual message layer, including sent bubbles and attachments.
// Only the upper third pays for particle work. The wider cell search supports
// twelve-point swirling motion; every texture sample stays within 24 points.
// Empty cells are rejected before reading the message texture.
[[ stitchable ]] half4 historyDissolve(float2 position, SwiftUI::Layer layer,
                                     float originY, float height, float time, float strength) {
    half4 original = layer.sample(position);
    if (height <= 0 || strength <= 0.001) return original;
    float y = position.y + originY;
    float amount = (1.0 - smoothstep(height * 0.035, height / 3.0, y)) * strength;
    if (amount <= 0.001) return original;

    const float cellSize = 7.0;
    float2 cell = floor(position / cellSize);
    half4 particles = half4(0);
    for (int row = -2; row <= 2; ++row) {
        for (int col = -2; col <= 2; ++col) {
            float2 id = cell + float2(col, row);
            float seed = historyHash(id);
            float2 source = (id + 0.5) * cellSize;
            // Layered orbits avoid a synchronized sway or a static pixel grid.
            float phase = seed * 19.0;
            float2 drift = float2(sin(time * 1.7 + phase) * 9.0 + cos(time * 2.6 + phase) * 3.0,
                                 cos(time * 1.35 + phase) * 8.0 + sin(time * 2.2 + phase) * 2.0 - 1.0) * amount;
            float angle = sin(time * 1.8 + phase) * amount * 1.1;
            float2 local = position - source - drift;
            float2 delta = abs(float2(cos(angle) * local.x - sin(angle) * local.y,
                                     sin(angle) * local.x + cos(angle) * local.y));
            float2 halfSize = mix(float2(2.9), float2(0.65 + seed * 0.9, 0.55 + seed * 0.45), amount);
            float edge = max(delta.x - halfSize.x, delta.y - halfSize.y);
            float coverage = 1.0 - smoothstep(-0.25, 0.9, edge);
            float halo = (1.0 - smoothstep(0.0, 2.0, max(edge, 0.0))) * 0.12;
            if (coverage + halo < 0.001) continue;
            half4 ink = (layer.sample(source) + layer.sample(source + float2(1.4, 0.7))
                        + layer.sample(source - float2(1.4, 0.7))) / 3.0h;
            // A little crimson light keeps white text and dark text in-theme.
            ink.rgb = mix(ink.rgb, half3(1.0h, 0.32h, 0.37h) * ink.a, half(amount * 0.22));
            particles += ink * half((coverage + halo) * (0.7 + 0.3 * seed));
        }
    }
    particles = min(particles, half4(1));
    float topFade = mix(0.45, 1.0, smoothstep(0.0, height * 0.12, y));
    return mix(original, particles * half(topFade), half(amount));
}
