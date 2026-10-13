#include <metal_stdlib>
using namespace metal;
struct Vertex { float4 position [[position]]; float2 uv; };
struct Uniforms { float2 tilt; float amount; float hasDepth; };
vertex Vertex cardVertex(uint id [[vertex_id]]) {
    float2 positions[4] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
    Vertex v; v.position = float4(positions[id],0,1); v.uv = float2(positions[id].x*.5+.5,.5-positions[id].y*.5); return v;
}
fragment float4 cardFragment(Vertex v [[stage_in]], texture2d<float> photo [[texture(0)]], texture2d<float> depth [[texture(1)]], constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    // Bounded inverse-depth ray intersection. Overscan hides disoccluded borders.
    float2 base = (v.uv-.5)/1.055+.5;
    float2 ray = u.tilt * float2(.043,.031) * u.amount * u.hasDepth;
    float2 uv = base - ray*.5;
    float previous = 1.; float previousSurface = 0.;
    for (int i=0;i<=24;i++) {
        float z = 1.-float(i)/24.;
        float2 p = base + ray*(z-.5);
        float surface = depth.sample(s,p).r;
        if (z <= surface) {
            float a = previous-previousSurface, b = z-surface;
            float t = clamp(a/max(a-b,.00001),0.,1.);
            uv = base + ray*(mix(previous,z,t)-.5); break;
        }
        previous=z; previousSurface=surface;
    }
    return float4(photo.sample(s,uv).rgb,1);
}
