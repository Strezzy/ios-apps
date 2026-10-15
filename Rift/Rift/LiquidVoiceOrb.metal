#include <metal_stdlib>
using namespace metal;

// Analytic fluid shading: no textures, network assets, or offscreen frame history.
[[ stitchable ]] half4 riftLiquidOrb(float2 position, half4 color, float2 size,
                                    float time, float energy, float state) {
    float2 uv = (position - size * 0.5) / max(1.0, min(size.x, size.y) * 0.5);
    float r2 = dot(uv, uv);
    if (r2 >= 1.0 || color.a <= 0.0h) return half4(0.0h);
    float z = sqrt(max(0.001, 1.0 - r2));
    float speed = state > 1.5 ? 0.95 : state > 0.5 ? 0.56 : 0.32;
    float t = time * speed;
    // Refraction compresses the fluid toward the rim of the spherical surface.
    float2 q = uv / (0.55 + z * 0.65);
    q += float2(sin(q.y * 4.0 + t), cos(q.x * 3.0 - t * 0.8)) * (0.11 + energy * 0.09);
    float flow = sin(q.x * 4.5 + sin(q.y * 4.0 + t) * 1.5 - t)
               + cos(q.y * 5.2 - sin(q.x * 3.0 - t * 0.7) * 1.3 + t * 0.65);
    float pools = smoothstep(-1.4, 1.5, flow);
    float3 garnet = float3(0.24, 0.018, 0.065);
    float3 crimson = float3(0.83, 0.09, 0.20);
    float3 amber = float3(1.0, 0.53, 0.17);
    float3 liquid = mix(garnet, crimson, pools);
    liquid = mix(liquid, amber, smoothstep(0.65, 1.0, pools) * (0.7 + energy * 0.3));
    float3 normal = normalize(float3(uv, z));
    float diffuse = max(0.0, dot(normal, normalize(float3(-0.5, -0.7, 1.0))));
    liquid *= 0.55 + diffuse * 0.55;
    float fresnel = pow(1.0 - z, 2.6);
    float caustic = pow(max(0.0, 1.0 - abs(flow - 0.25) * 2.8), 5.0);
    liquid += float3(1.0, 0.65, 0.38) * caustic * (0.12 + energy * 0.18) * z;
    float specular = pow(max(0.0, dot(normal, normalize(float3(-0.32, -0.48, 1.0)))), 55.0);
    float backlight = state > 0.5 && state < 1.5 ? 0.18 + energy * 0.24 : 0.04;
    liquid += float3(1.0, 0.87, 0.74) * (specular * 0.85 + fresnel * (0.4 + backlight));
    liquid += amber * backlight * max(0.0, uv.y) * z;
    return half4(half3(clamp(liquid, 0.0, 1.0)) * color.a, color.a);
}
