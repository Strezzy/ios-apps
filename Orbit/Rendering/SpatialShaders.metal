#include <metal_stdlib>
using namespace metal;

constexpr sampler linearClamp(coord::normalized, address::clamp_to_edge, filter::linear);

struct MatchParameters { uint width; uint height; int radius; uint padding; };
struct FilterParameters { float historyWeight; float disparityLimit; uint historyValid; uint padding; };
struct RenderParameters {
    float3x3 textureTransform;
    float2 contentScale;
    float2 motion;
    float strength;
    float aspect;
    uint spatial;
    uint hasDepth;
};

kernel void orbitLuma(texture2d<float, access::sample> color [[texture(0)]],
                      texture2d<float, access::write> output [[texture(1)]],
                      uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    float2 uv = (float2(p) + 0.5) / float2(output.get_width(), output.get_height());
    float2 step = 0.30 / float2(output.get_width(), output.get_height());
    float3 c = (color.sample(linearClamp, uv + float2(-step.x, -step.y)).rgb +
                color.sample(linearClamp, uv + float2(step.x, -step.y)).rgb +
                color.sample(linearClamp, uv + float2(-step.x, step.y)).rgb +
                color.sample(linearClamp, uv + float2(step.x, step.y)).rgb) * 0.25;
    output.write(float4(dot(c, float3(0.2126, 0.7152, 0.0722)), 0, 0, 1), p);
}

static int2 boundPoint(int2 p, uint width, uint height) {
    return clamp(p, int2(0), int2(int(width) - 1, int(height) - 1));
}

kernel void orbitCensus(texture2d<float, access::read> luma [[texture(0)]],
                        texture2d<uint, access::write> output [[texture(1)]],
                        uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    float center = luma.read(p).r;
    uint bits = 0;
    uint index = 0;
    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            if (x == 0 && y == 0) continue;
            float neighbor = luma.read(uint2(boundPoint(int2(p) + int2(x, y), luma.get_width(), luma.get_height()))).r;
            bits |= uint(neighbor < center) << index++;
        }
    }
    output.write(uint4(bits, 0, 0, 0), p);
}

static float censusCost(texture2d<uint, access::read> a, texture2d<uint, access::read> b,
                        int2 point, int disparity) {
    int width = int(a.get_width()), height = int(a.get_height());
    if (point.x - disparity < 2 || point.x - disparity >= width - 2) return 2.0;
    // A cross-shaped aggregate makes matching less sensitive to a single noisy pixel.
    constexpr int2 offsets[5] = { int2(0), int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1) };
    float cost = 0;
    for (int i = 0; i < 5; ++i) {
        int2 p = clamp(point + offsets[i], int2(0), int2(width - 1, height - 1));
        int2 q = clamp(p - int2(disparity, 0), int2(0), int2(width - 1, height - 1));
        cost += float(popcount(a.read(uint2(p)).r ^ b.read(uint2(q)).r));
    }
    return cost / 120.0;
}

kernel void orbitCoarseMatch(texture2d<uint, access::read> a [[texture(0)]],
                             texture2d<uint, access::read> b [[texture(1)]],
                             texture2d<float, access::write> output [[texture(2)]],
                             constant MatchParameters &params [[buffer(0)]],
                             uint2 p [[thread_position_in_grid]]) {
    if (p.x >= params.width || p.y >= params.height) return;
    float best = 10, second = 10;
    int winner = 0;
    for (int d = -params.radius; d <= params.radius; ++d) {
        float cost = censusCost(a, b, int2(p), d);
        if (cost < best) { second = best; best = cost; winner = d; }
        else second = min(second, cost);
    }
    float confidence = saturate((second - best) * 10) * (1 - smoothstep(0.26, 0.52, best));
    output.write(float4(float(winner) / float(params.width), confidence, 0, 1), p);
}

kernel void orbitRefineDepth(texture2d<uint, access::read> a [[texture(0)]],
                             texture2d<uint, access::read> b [[texture(1)]],
                             texture2d<float, access::sample> coarseLeft [[texture(2)]],
                             texture2d<float, access::sample> coarseRight [[texture(3)]],
                             texture2d<float, access::read> luma [[texture(4)]],
                             texture2d<float, access::write> output [[texture(5)]],
                             uint2 p [[thread_position_in_grid]]) {
    uint width = output.get_width(), height = output.get_height();
    if (p.x >= width || p.y >= height) return;
    float2 uv = (float2(p) + 0.5) / float2(width, height);
    // The nearest coarse match avoids averaging foreground and background disparities.
    constexpr sampler nearestClamp(coord::normalized, address::clamp_to_edge, filter::nearest);
    int guess = int(round(coarseLeft.sample(nearestClamp, uv).r * float(width)));
    float costs[9];
    float best = 10;
    int winner = 4;
    for (int i = 0; i < 9; ++i) {
        costs[i] = censusCost(a, b, int2(p), guess + i - 4);
        if (costs[i] < best) { best = costs[i]; winner = i; }
    }
    float runnerUp = 10;
    for (int i = 0; i < 9; ++i) {
        if (abs(i - winner) > 1) runnerUp = min(runnerUp, costs[i]);
    }
    float subpixel = 0;
    if (winner > 0 && winner < 8) {
        float before = costs[winner - 1], after = costs[winner + 1];
        float curvature = before + after - 2 * best;
        if (curvature > 0.001) subpixel = clamp(0.5 * (before - after) / curvature, -0.65, 0.65);
    }
    float disparity = (float(guess + winner - 4) + subpixel) / float(width);
    float confidence = mix(0.18, 1.0, saturate((runnerUp - best) * 9.0));
    confidence *= 1.0 - smoothstep(0.24, 0.48, best);
    // Reject left/right disagreements (occlusions, repeated patterns, and borders).
    float reverse = coarseRight.sample(nearestClamp, uv - float2(disparity, 0)).r;
    float disagreement = abs(disparity + reverse) * float(coarseLeft.get_width());
    confidence *= 1 - smoothstep(1.5, 3.5, disagreement);
    float lo = 1, hi = 0;
    for (int y = -2; y <= 2; y += 2) {
        for (int x = -2; x <= 2; x += 2) {
            float value = luma.read(uint2(boundPoint(int2(p) + int2(x, y), width, height))).r;
            lo = min(lo, value); hi = max(hi, value);
        }
    }
    confidence *= smoothstep(0.012, 0.09, hi - lo);
    if (p.x < 4 || p.x + 4 >= width || p.y < 3 || p.y + 3 >= height) confidence *= 0.1;
    output.write(float4(clamp(disparity, -0.09, 0.09), confidence, 0, 1), p);
}

kernel void orbitStabilizeDepth(texture2d<float, access::read> raw [[texture(0)]],
                                texture2d<float, access::read> luma [[texture(1)]],
                                texture2d<float, access::read> previous [[texture(2)]],
                                texture2d<float, access::read> oldLuma [[texture(3)]],
                                texture2d<float, access::write> output [[texture(4)]],
                                constant FilterParameters &params [[buffer(0)]],
                                uint2 p [[thread_position_in_grid]]) {
    uint width = raw.get_width(), height = raw.get_height();
    if (p.x >= width || p.y >= height) return;
    float center = luma.read(p).r;
    float sum = 0, total = 0, confidence = 0, spatialSum = 0;
    for (int y = -3; y <= 3; ++y) {
        for (int x = -3; x <= 3; ++x) {
            uint2 q = uint2(boundPoint(int2(p) + int2(x, y), width, height));
            float2 sample = raw.read(q).rg;
            float spatial = exp(-float(x*x + y*y) / 7.5);
            float edge = exp(-abs(luma.read(q).r - center) * 24.0);
            float guided = spatial * edge;
            float weight = guided * sample.g;
            sum += sample.r * weight; total += weight;
            confidence += sample.g * guided; spatialSum += guided;
        }
    }
    float conf = confidence / max(spatialSum, 0.0001);
    float depth = total > 0.025 ? sum / total : 0;
    if (params.historyValid != 0) {
        float2 history = previous.read(p).rg;
        float stable = 1 - smoothstep(0.015, 0.085, abs(oldLuma.read(p).r - center));
        stable *= 1 - smoothstep(0.0025, 0.012, abs(history.r - depth));
        float weight = params.historyWeight * stable * smoothstep(0.02, 0.22, history.g);
        depth = mix(depth, history.r, weight);
        conf = mix(conf, history.g, weight);
    }
    output.write(float4(clamp(depth, -params.disparityLimit, params.disparityLimit), conf, 0, 1), p);
}

struct VertexOutput { float4 position [[position]]; float2 uv; };
vertex VertexOutput orbitVertex(uint index [[vertex_id]]) {
    // One triangle covers the drawable, without a seam down the video.
    const float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOutput result;
    result.position = float4(positions[index], 0, 1);
    result.uv = float2(positions[index].x * 0.5 + 0.5, 0.5 - positions[index].y * 0.5);
    return result;
}

static float2 guidedDepth(texture2d<float, access::sample> depth,
                           texture2d<float, access::sample> color, float2 uv) {
    float center = dot(color.sample(linearClamp, uv).rgb, float3(0.2126, 0.7152, 0.0722));
    float2 pixel = 1.0 / float2(depth.get_width(), depth.get_height());
    float sum = 0, weightSum = 0, confidence = 0;
    // Joint bilateral upsampling preserves sharper subject edges than plain depth scaling.
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x != 0 && y != 0) continue;
            float2 q = uv + float2(x, y) * pixel;
            float2 value = depth.sample(linearClamp, q).rg;
            float light = dot(color.sample(linearClamp, q).rgb, float3(0.2126, 0.7152, 0.0722));
            float weight = exp(-abs(light - center) * 30.0) * (x == 0 && y == 0 ? 2.0 : 1.0);
            sum += value.r * weight; confidence += value.g * weight; weightSum += weight;
        }
    }
    return float2(sum, confidence) / max(weightSum, 0.001);
}

fragment float4 orbitFragment(VertexOutput in [[stage_in]],
                               texture2d<float, access::sample> left [[texture(0)]],
                               texture2d<float, access::sample> right [[texture(1)]],
                               texture2d<float, access::sample> depth [[texture(2)]],
                               constant RenderParameters &params [[buffer(0)]]) {
    float2 uv = (in.uv - 0.5) / params.contentScale + 0.5;
    if (any(uv < 0) || any(uv > 1)) return float4(0, 0, 0, 1);
    bool spatial = params.spatial != 0 && params.hasDepth != 0 && params.strength > 0;
    if (!spatial) {
        float2 raw = (params.textureTransform * float3(uv, 1)).xy;
        return float4(left.sample(linearClamp, raw).rgb, 1);
    }
    // A small guard band hides pixels that neither recorded camera can see.
    uv = (uv - 0.5) / 1.10 + 0.5;
    float2 raw = (params.textureTransform * float3(uv, 1)).xy;
    float2 displayMotion = params.motion * float2(1.0, params.aspect) * params.strength * 1.10;
    float2 ray = (params.textureTransform * float3(displayMotion, 0)).xy;
    ray = clamp(ray, -1.25, 1.25);
    // Synthesize a view between the recorded eyes, then move it in two axes.
    // Disparity changes per pixel: foreground and background move independently.
    float2 source = raw;
    float2 value = depth.sample(linearClamp, source).rg;
    float certainty = smoothstep(0.015, 0.16, value.g);
    float2 leftRay = float2(0.5, 0) + ray;
    for (int step = 0; step < 3; ++step) {
        float disparity = depth.sample(linearClamp, source).r;
        source = raw + clamp(leftRay * disparity * certainty, -0.045, 0.045);
    }
    value = guidedDepth(depth, left, source);
    float disparity = value.r;
    source = raw + clamp(leftRay * disparity * certainty, -0.045, 0.045);
    float2 rightSource = source - float2(disparity, 0);
    float3 l = left.sample(linearClamp, source).rgb;
    float3 r = right.sample(linearClamp, rightSource).rgb;
    float agreement = 1 - smoothstep(0.035, 0.18, length(l - r));
    // Blend aligned evidence only. At occlusions, prefer the nearer recorded eye.
    // This avoids the double silhouettes caused by blindly crossfading stereo views.
    float preferredRight = smoothstep(0.20, 0.80, 0.5 + ray.x);
    float blend = mix(preferredRight > 0.5 ? 1.0 : 0.0, preferredRight, agreement);
    blend *= certainty;
    if (any(rightSource < 0) || any(rightSource > 1)) blend = 0;
    float3 result = mix(l, r, blend);
    // Confidence failures fade to the original image instead of inventing depth.
    float3 original = left.sample(linearClamp, raw).rgb;
    return float4(mix(original, result, certainty), 1);
}
