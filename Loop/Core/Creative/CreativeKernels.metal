#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;
extern "C" { namespace coreimage {
float4 loopFlowAlign(sampler previous,sampler flow,float2 scale,destination dest) {
    float2 p=dest.coord();float2 v=flow.sample(flow.transform(p)).rg;
    // Vision vectors are measured in analysis pixels. Convert to render pixels.
    return previous.sample(previous.transform(p+float2(v.x,-v.y)*scale));
}
float4 loopCosmetic(sample_t source,float3 tint,float amount) {
    float luminance=dot(source.rgb,float3(.2126,.7152,.0722));
    float t=max(.05,dot(tint,float3(.2126,.7152,.0722)));
    float3 colored=tint*(luminance/t);
    return float4(mix(source.rgb,colored,amount*.65),source.a);
}
float4 loopDepthLayer(sample_t particles,sample_t depth,float layer,float enabled) {
    float distance=layer<.5?.20:(layer<1.5?.52:.90);
    float visible=1-smoothstep(distance-.055,distance+.055,depth.r);
    return particles*mix(1.0,visible,enabled);
}
float4 loopDepthLook(sampler image,sampler depth,float4 lighting,float4 focus,float2 dimensions,destination dest) {
    float2 p=dest.coord();float4 original=image.sample(image.transform(p));
    float d=depth.sample(depth.transform(p)).r;
    float dx=depth.sample(depth.transform(p+float2(3,0))).r-depth.sample(depth.transform(p-float2(3,0))).r;
    float dy=depth.sample(depth.transform(p+float2(0,3))).r-depth.sample(depth.transform(p-float2(0,3))).r;
    float3 n=normalize(float3(-dx*18,-dy*18,1));
    float3 l=normalize(float3(lighting.z,.5,.8));
    float illumination=dot(n,l)-.55;
    float3 rgb=original.rgb*(1+illumination*lighting.x*.65);
    rgb*=1+float3(.10,.015,-.09)*lighting.y*lighting.x;
    float fog=pow(max(0.0,1-d),1.6)*lighting.w*.55;
    rgb=mix(rgb,float3(.72,.78,.82),fog);
    float blur=abs(d-focus.x)*focus.y*dimensions.y*.014;
    if(blur>.5) {
        float3 sum=0;float weights=0;
        for(int i=0;i<12;i++) {
            float angle=float(i)*2.3999632;
            float2 q=p+float2(cos(angle),sin(angle))*blur*sqrt((float(i)+.5)/12.0);
            float sd=depth.sample(depth.transform(q)).r;
            float w=exp(-abs(sd-d)*22);
            sum+=image.sample(image.transform(q)).rgb*w;weights+=w;
        }
        rgb=mix(rgb,sum/max(.0001,weights),min(.8,focus.y));
    }
    return float4(max(rgb,0.0),original.a);
}
float4 loopBackgroundFill(sampler source,sampler mask,float radius,destination dest) {
    float2 p=dest.coord();float4 center=source.sample(source.transform(p));
    float alpha=mask.sample(mask.transform(p)).r;
    if(alpha<.05)return center;
    float4 sum=0;float weight=0;
    for(int i=0;i<32;i++) {
        float a=float(i)*2.3999632;float r=radius*sqrt((float(i)+1)/32.0);
        float2 q=p+float2(cos(a),sin(a))*r;
        float w=pow(max(0.0,1-mask.sample(mask.transform(q)).r),6.0)/(1+r);
        sum+=source.sample(source.transform(q))*w;weight+=w;
    }
    return weight>.0001?sum/weight:center;
}
float4 loopLUTDomain(sample_t source,float3 low,float3 high) {
    return float4(clamp((source.rgb-low)/max(high-low,float3(.0001)),0.0,1.0),source.a);
}
}}
