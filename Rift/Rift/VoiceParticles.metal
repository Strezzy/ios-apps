#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

static float voiceScatterHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// A compact 3x3 search on individual message surfaces during transitions only.
// Ten-point source cells bound all drifting fragments within this neighborhood.
[[ stitchable ]] half4 voiceTextScatter(float2 position, SwiftUI::Layer layer, float amount) {
    half4 original = layer.sample(position);
    if (amount <= 0.001) return original;
    if (amount >= 0.999) return half4(0);
    const float cellSize = 10.0;
    float2 cell = floor(position / cellSize);
    half4 fragments = half4(0);
    for (int row = -1; row <= 1; ++row) {
        for (int col = -1; col <= 1; ++col) {
            float2 id = cell + float2(col, row);
            float seed = voiceScatterHash(id);
            float phase = seed * 19.0;
            float scatter = smoothstep(seed * 0.12, 0.65 + seed * 0.12, amount);
            float2 source = (id + 0.5) * cellSize;
            float2 drift = float2(sin(phase) * 8, cos(phase * 1.3) * 8 - 1) * scatter;
            float angle = sin(phase) * scatter * 1.1;
            float2 local = position - source - drift;
            float2 delta = abs(float2(cos(angle) * local.x - sin(angle) * local.y,
                                     sin(angle) * local.x + cos(angle) * local.y));
            float2 halfSize = mix(float2(3.4), float2(0.65 + seed * 0.9, 0.55 + seed * 0.45), scatter);
            float edge = max(delta.x - halfSize.x, delta.y - halfSize.y);
            float coverage = 1 - smoothstep(-0.25, 0.9, edge);
            float halo = (1 - smoothstep(0.0, 2.0, max(edge, 0.0))) * 0.12;
            if (coverage + halo < 0.001) continue;
            half4 ink = (layer.sample(source) + layer.sample(source + float2(1.4, 0.7))
                        + layer.sample(source - float2(1.4, 0.7))) / 3.0h;
            ink.rgb = mix(ink.rgb, half3(1.0h, 0.32h, 0.37h) * ink.a, half(scatter * 0.22));
            fragments += ink * half(coverage + halo);
        }
    }
    float breakup = smoothstep(0.0, 0.42, amount);
    float fade = 1 - smoothstep(0.48, 1.0, amount);
    return mix(original, min(fragments, half4(1)), half(breakup)) * half(fade);
}
