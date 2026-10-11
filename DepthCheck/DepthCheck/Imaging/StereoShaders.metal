#include <metal_stdlib>
using namespace metal;

struct StereoUniforms { uint width; uint height; float amount; float convergence; };
constexpr sampler linearClamp(coord::normalized, address::clamp_to_edge, filter::linear);

// Joint bilateral sampling lets source color edges guide the low-resolution
// depth boundary without reducing the full-resolution source color image.
float guidedDepth(texture2d<float, access::sample> image,
                  texture2d<float, access::sample> depth, float2 uv) {
    float2 step = 1.0f / float2(depth.get_width(), depth.get_height());
    float3 center = image.sample(linearClamp, uv).rgb;
    float sum = 0.0f, weights = 0.0f;
    const float2 offsets[5] = {float2(0), float2(-1,0), float2(1,0), float2(0,-1), float2(0,1)};
    for (uint i = 0; i < 5; ++i) {
        float2 p = uv + offsets[i] * step * 0.7f;
        float3 difference = center - image.sample(linearClamp, p).rgb;
        float weight = (i == 0 ? 2.0f : 1.0f) * exp(-dot(difference, difference) * 32.0f);
        sum += depth.sample(linearClamp, p).r * weight;
        weights += weight;
    }
    return clamp(sum / max(weights, 0.00001f), 0.0f, 1.0f);
}

kernel void depthCheckSplat(texture2d<float, access::sample> image [[texture(0)]],
                            texture2d<float, access::sample> depth [[texture(1)]],
                            device atomic_uint* left [[buffer(0)]],
                            device atomic_uint* right [[buffer(1)]],
                            constant StereoUniforms& u [[buffer(2)]], uint2 p [[thread_position_in_grid]]) {
    if (p.x >= u.width || p.y >= u.height) return;
    float2 uv = (float2(p) + 0.5f) / float2(u.width, u.height);
    float d = guidedDepth(image, depth, uv);
    float shift = (d - u.convergence) * u.amount * float(u.width) * 0.5f;
    // Atomic maximum is a depth test. A second pass reads winners, avoiding
    // racing color writes and preserving the foreground at depth discontinuities.
    uint key = ((uint(d * 65534.0f) + 1u) << 16u) | p.x;
    int lx = int(floor(float(p.x) + shift));
    int rx = int(floor(float(p.x) - shift));
    for (int i = 0; i < 2; ++i) {
        if (lx+i >= 0 && lx+i < int(u.width)) atomic_fetch_max_explicit(&left[p.y*u.width+uint(lx+i)], key, memory_order_relaxed);
        if (rx+i >= 0 && rx+i < int(u.width)) atomic_fetch_max_explicit(&right[p.y*u.width+uint(rx+i)], key, memory_order_relaxed);
    }
}

kernel void depthCheckResolve(texture2d<float, access::sample> image [[texture(0)]],
                              texture2d<float, access::sample> depth [[texture(1)]],
                              texture2d<float, access::write> output [[texture(2)]],
                              device const uint* keys [[buffer(0)]],
                              constant StereoUniforms& u [[buffer(1)]],
                              constant float& direction [[buffer(2)]], uint2 p [[thread_position_in_grid]]) {
    if (p.x >= u.width || p.y >= u.height) return;
    uint key = keys[p.y*u.width+p.x];
    bool hole = key == 0;
    if (hole) {
        uint before = 0, after = 0;
        int radius = min(1024, int(ceil(u.amount * float(u.width))) + 3);
        for (int offset = 1; offset <= radius && (before == 0 || after == 0); ++offset) {
            if (before == 0 && int(p.x)-offset >= 0) before = keys[p.y*u.width+p.x-uint(offset)];
            if (after == 0 && p.x+uint(offset) < u.width) after = keys[p.y*u.width+p.x+uint(offset)];
        }
        // Newly revealed areas use the farther surface, not stretched foreground.
        key = before == 0 ? after : (after == 0 ? before : min(before, after));
    }
    float sx = key == 0 ? float(p.x) : float(key & 65535u);
    if (!hole) {
        float2 uv = (float2(sx, float(p.y)) + 0.5f) / float2(u.width, u.height);
        float d = guidedDepth(image, depth, uv);
        float inverse = float(p.x) - direction * (d-u.convergence)*u.amount*float(u.width)*0.5f;
        sx = clamp(inverse, sx-1.0f, sx+1.0f);
    }
    float2 uv = (float2(sx, float(p.y)) + 0.5f) / float2(u.width, u.height);
    output.write(float4(image.sample(linearClamp, uv).rgb, 1.0f), p);
}

kernel void depthCheckPack(texture2d<float, access::read> left [[texture(0)]],
                           texture2d<float, access::read> right [[texture(1)]],
                           texture2d<float, access::write> output [[texture(2)]],
                           constant uint& mode [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    float4 color;
    if (mode == 0) color = p.x < left.get_width() ? left.read(p) : right.read(uint2(p.x-left.get_width(), p.y));
    else if (mode == 1) color = p.y < left.get_height() ? left.read(p) : right.read(uint2(p.x, p.y-left.get_height()));
    else { float4 l = left.read(p), r = right.read(p); color = float4(l.r, r.g, r.b, 1); }
    output.write(color, p);
}

kernel void depthCheckDepthDisplay(texture2d<float, access::sample> depth [[texture(0)]],
                                   texture2d<float, access::write> output [[texture(1)]],
                                   uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    float2 uv = (float2(p)+0.5f) / float2(output.get_width(), output.get_height());
    float d = depth.sample(linearClamp, uv).r;
    output.write(float4(d, d, d, 1), p);
}
