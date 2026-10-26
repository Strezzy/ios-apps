#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

float hash21(float2 p) { return fract(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
float noise21(float2 p) {
    float2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+float2(1,0)),f.x),mix(hash21(i+float2(0,1)),hash21(i+1),f.x),f.y);
}
float fbm(float2 p) {
    float v=0, a=.5;
    for(int i=0;i<5;i++){v+=a*noise21(p);p=float2(p.x*1.62-p.y*1.2,p.x*1.2+p.y*1.62)+13.1;a*=.5;}
    return v;
}
float ellipseWeight(float2 p, float2 center, float2 radii) {
    float q=length((p-center)/max(radii,float2(.0001)));
    return 1.0-smoothstep(.68,1.0,q);
}

extern "C" { namespace coreimage {
float2 loopReshape(float2 center, float2 radii, float2 axis, float2 strength, float2 shift, destination dest) {
    float2 p=dest.coord(), d=p-center, v=float2(-axis.y,axis.x);
    float2 q=float2(dot(d,axis),dot(d,v));
    float r2=dot(q/radii,q/radii);
    float fall=pow(max(0.0,1.0-r2),3.0);
    return p+(axis*q.x*strength.x+v*q.y*strength.y-shift)*fall;
}
float4 loopSkinMask(float4 face, float4 eyeL, float4 eyeR, float4 mouth, destination dest) {
    float2 p=dest.coord();
    float a=ellipseWeight(p,face.xy,face.zw);
    a*=1.0-ellipseWeight(p,eyeL.xy,eyeL.zw);
    a*=1.0-ellipseWeight(p,eyeR.xy,eyeR.zw);
    a*=1.0-ellipseWeight(p,mouth.xy,mouth.zw);
    return float4(a,a,a,1);
}
float4 loopBilateral(sampler image, float2 delta, destination dest) {
    float2 p=dest.coord(); float4 c=image.sample(image.transform(p)); float4 sum=0;float weights=0;
    for(int i=-4;i<=4;i++) {
        float4 s=image.sample(image.transform(p+delta*float(i)));
        float3 d=s.rgb-c.rgb;
        float w=exp(-float(i*i)/8.0-dot(d,d)/.012);
        sum+=s*w;weights+=w;
    }
    return mix(sum/max(weights,.0001),c,.12);
}
float4 loopRetouch(sample_t source,sample_t smooth,float amount,float detail,float warmth) {
    float3 base=mix(source.rgb,smooth.rgb,clamp(amount,0.0,.9));
    base+=(source.rgb-smooth.rgb)*detail;
    base*=float3(1+warmth*.08,1+warmth*.015,1-warmth*.065);
    return float4(max(base,float3(0)),source.a);
}
float4 loopTemporalMatte(sample_t current,sample_t previous,sample_t nowImage,sample_t oldImage,float stability) {
    float delta=length(nowImage.rgb-oldImage.rgb);
    float safe=(1-smoothstep(.025,.16,delta))*(1-smoothstep(.12,.5,abs(current.r-previous.r)));
    float a=mix(current.r,previous.r,clamp(stability,0.0,1.0)*.60*safe);
    return float4(a,a,a,1);
}
float4 loopRefineMatte(sampler mask,sampler guide,float2 step,float edge,float feather,destination dest) {
    float2 p=dest.coord();float3 c=guide.sample(guide.transform(p)).rgb;
    float total=0,weight=0;
    for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++) {
        float2 d=float2(x,y)*step;
        float3 s=guide.sample(guide.transform(p+d)).rgb;
        float w=exp(-float(x*x+y*y)*.35-dot(s-c,s-c)/.008);
        total+=mask.sample(mask.transform(p+d)).r*w;weight+=w;
    }
    float a=clamp(total/max(weight,.0001)+edge*.14,0.0,1.0);
    float tightened=smoothstep(.025,.975,a);
    a=mix(tightened,a,clamp(feather,0.0,1.0));
    return float4(a,a,a,1);
}
float4 loopAgingDetail(sample_t original,sample_t originalLow,sample_t aged,float detail) {
    float3 restored=aged.rgb+(original.rgb-originalLow.rgb)*detail;
    return float4(clamp(restored,0.0,1.0),original.a);
}
float4 loopWeather(sampler scene,float2 dimensions,float time,float mode,float layer,float density,float speed,float wind,float size,destination dest) {
    float2 px=dest.coord(),uv=px/dimensions;
    float ratio=dimensions.x/dimensions.y;
    float2 p=float2(uv.x*ratio,uv.y);
    float t=time*speed;
    float3 rgb=0;float alpha=0;
    float depth=layer<.5?.38:(layer<1.5?.72:1.25);
    float softness=layer>1.5?1.8:1.0;
    if(mode==7 || mode==8) {
        float n=fbm(p*float2(2.8,4.0)+float2(t*.05*(wind+1),t*.012));
        float n2=fbm(p*6.0-float2(t*.025,t*.008));
        alpha=clamp((n*.75+n2*.25-.27)*.65*density,0.0,.32);
        float low=1-smoothstep(.1,.9,uv.y);
        alpha*=mode==7?.4+.6*low:1.0;
        rgb=mode==8?float3(1.0,.58,.26):float3(.72,.78,.82);
        return float4(rgb*alpha,alpha);
    }
    const int count=112;
    float2 texel=float2(1.0)/dimensions;
    for(int i=0;i<count;i++) {
        float fi=float(i)+layer*127.0;
        float seed=hash21(float2(fi,3.1));
        if(seed>density*.85+.06) continue;
        float hx=hash21(float2(fi,17.0)),hy=hash21(float2(fi,53.0));
        float rad=(.002+.004*hash21(float2(fi,29.0)))*depth*(.5+size);
        float vel=(.10+.2*hy)*depth;
        bool rise=(mode==2||mode==5||mode==9);
        float y=fract(hy+(rise?1.0:-1.0)*t*vel);
        float x=fract(hx+t*wind*.025*depth+sin(t*.35+fi)*.012)*ratio;
        float2 d=p-float2(x,y);
        float a=0;float3 col=float3(.9,.94,1);
        if(mode==1) {
            float2 dir=normalize(float2(wind*.3,-1.0));
            float along=dot(d,dir),across=dot(d,float2(-dir.y,dir.x));
            float len=(.018+.04*hy)*depth;
            float width=max(.00045,rad*.10)*softness;
            a=exp(-across*across/(width*width))*max(0.0,1.0-abs(along)/len)*.20;
            col=float3(.68,.76,.86)+scene.sample(scene.transform(px)).rgb*.18;
        } else if(mode==5) {
            rad*=5;
            float r=length(d)/rad;
            if(r<1.15) {
                float rim=exp(-pow((r-.94)*22.0/softness,2.0));
                float highlight=exp(-length((d/rad)-float2(-.32,.52))*9.0);
                float angle=atan2(d.y,d.x);
                float3 spectral=.55+.45*cos(float3(0,2.1,4.2)+angle*2.0+t*.2+fi);
                float2 refractOffset=d*(.10*(1.0-min(r,1.0)))*dimensions.y;
                float3 refracted=scene.sample(scene.transform(px+refractOffset)).rgb;
                a=clamp(rim*.37+highlight*.6+(r<.95?.045:0.0),0.0,.7);
                col=mix(refracted,spectral,rim*.45)+highlight;
            }
        } else if(mode==6) {
            float angle=fi+t*(.5+hy);
            float2 q=float2(cos(angle)*d.x-sin(angle)*d.y,sin(angle)*d.x+cos(angle)*d.y);
            float width=rad*(.2+.8*abs(cos(t+fi)));
            a=(1-smoothstep(width*.75,width,abs(q.x)))*(1-smoothstep(rad*1.8,rad*2.2,abs(q.y)))*.8;
            col=.45+.4*cos(float3(0,2,4)+fi*2.0);
        } else {
            float r=length(d)/(rad*softness);
            a=exp(-r*r*3.0)*.6;
            if(mode==2||mode==9||mode==3) {
                a+=exp(-r*r*.3)*.09;
                a*=.6+.4*sin(t*(mode==9?1.8:.4)+fi);
                col=mode==2?float3(1,.38,.045):(mode==9?float3(.8,1,.33):float3(.93,.83,1));
            }
            if(mode==4) {a*=.25;col=float3(.82,.76,.67);}
        }
        a=clamp(a,0.0,.85);
        rgb=rgb*(1-a)+col*a;alpha=alpha+(1-alpha)*a;
    }
    return float4(rgb,alpha);
}
}}
