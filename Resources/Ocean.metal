#include <metal_stdlib>
using namespace metal;
struct FishVertex { float4 position, normal, detail; };
struct FishUniforms { float4 viewport, placement, motion, kind; };
struct EffectUniforms { float4 viewport, placement, style; };
struct VertexOut { float4 position [[position]]; float2 point; float3 local; float3 normal; float4 detail; };
constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
float2 imageUV(float2 p, float2 size) {
    float scale = max(size.x / 1600.0, size.y / 1000.0);
    float2 uv = (p - (size - float2(1600,1000) * scale) * 0.5) / (float2(1600,1000) * scale);
    return float2(uv.x, 1-uv.y);
}
float maskAt(float2 p, float2 size, texture2d<float> mask) { return smoothstep(0.0, 5.0, mask.sample(linearSampler, imageUV(p,size)).r); }
float hash(float2 p) { return fract(sin(dot(p,float2(127.1,311.7))) * 43758.5453); }
float noise(float2 p) {
    float2 i=floor(p), f=fract(p); f=f*f*(3-2*f);
    return mix(mix(hash(i),hash(i+float2(1,0)),f.x),mix(hash(i+float2(0,1)),hash(i+1),f.x),f.y);
}
vertex VertexOut fishVertex(uint id [[vertex_id]], const device FishVertex *mesh [[buffer(0)]], constant FishUniforms &u [[buffer(1)]]) {
    FishVertex v=mesh[id]; float3 p=v.position.xyz;
    float bend=pow(clamp((0.22-p.x)/0.75,0.0,1.0),2.0);
    p.y += sin(u.motion.y + p.x*5.0) * bend * 0.09;
    if(v.detail.x==2) p.y += sign(p.y)*sin(u.motion.y+1.2)*v.detail.w*0.025;
    float c=cos(u.motion.x), s=sin(u.motion.x);
    float2 point=u.placement.xy + float2(c*p.x-s*p.y,s*p.x+c*p.y)*u.placement.z;
    if(u.motion.z>0.5) point += float2(3,-5)*(0.4+u.placement.w);
    VertexOut o; o.position=float4(point/u.viewport.xy*2-1, 0.2+u.placement.w*0.6-p.z*0.1, 1);
    o.point=point; o.local=v.position.xyz; o.normal=v.normal.xyz; o.detail=v.detail; return o;
}
fragment float4 fishFragment(VertexOut in [[stage_in]], constant FishUniforms &u [[buffer(0)]], texture2d<float> env [[texture(0)]], texture2d<float> mask [[texture(1)]]) {
    float water=maskAt(in.point,u.viewport.xy,mask); if(water<=0) discard_fragment();
    if(u.motion.z>0.5) return float4(float3(0.005,0.016,0.009)*0.14,0.14)*water;
    float id=u.kind.x, kind=fmod(id,7.0);
    float2 p=float2(in.local.x*8, in.local.y*22);
    float patches=noise(p+float2(id*7, id*3))+0.34*noise(p*2.7+id);
    float3 ivory=float3(0.95,0.93,0.82), red=float3(0.88,0.245,0.075), gold=float3(0.92,0.65,0.13), black=float3(0.06,0.075,0.066);
    float3 color=ivory;
    if(kind==0 || kind==3 || kind==6) color=mix(ivory,red,smoothstep(0.66,0.73,patches));
    if(kind==1) color=mix(gold,ivory,smoothstep(0.84,0.95,patches));
    if(kind==2) color=mix(black,red,smoothstep(0.72,0.79,patches));
    if(kind==4) color=mix(ivory,black,smoothstep(0.58,0.64,patches));
    if(kind==5) color=mix(red,gold,smoothstep(0.88,0.96,patches));
    if(kind==3 || kind==6) color=mix(color,black,smoothstep(0.83,0.91,noise(p*1.7+id*13)));
    float shade=0.67+0.32*max(0.0,dot(normalize(in.normal),normalize(float3(-0.25,0.4,1))));
    float scales=sin(in.local.x*260+sin(in.local.y*290)*0.8)*sin(in.local.y*290);
    color*=shade*(0.97+scales*0.035);
    float alpha=1;
    if(in.detail.x==1 || in.detail.x==2) {
        color=mix(color,ivory,0.55)*(0.8+0.12*sin(in.detail.z*17)); alpha=0.52;
    }
    if(in.detail.x==3) { color*=0.75; alpha=0.65; }
    if(in.detail.x==4) color=float3(0.025,0.03,0.02);
    // Water absorption and reflected environment integrate the entire animal below the surface.
    float3 reflection=env.sample(linearSampler,imageUV(in.point,u.viewport.xy)).rgb;
    color=mix(color, reflection,0.13+u.placement.w*0.20);
    color=mix(color,float3(0.075,0.21,0.16),u.placement.w*0.10);
    alpha*=water; return float4(color*alpha,alpha);
}
vertex VertexOut effectVertex(uint id [[vertex_id]], constant EffectUniforms &u [[buffer(0)]]) {
    const float2 quad[6]={float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    float2 q=quad[id], p;
    if(u.style.x<1.5) p=(q*0.5+0.5)*u.viewport.xy;
    else { float c=cos(u.placement.w),s=sin(u.placement.w); float scale=(u.style.x>2.5 && u.style.z<0.5)?1.35:1.0; p=u.placement.xy+float2(c*q.x-s*q.y,s*q.x+c*q.y)*u.placement.z*scale; }
    VertexOut o; o.position=float4(p/u.viewport.xy*2-1,0,1);o.point=p;o.local=float3(q,0);o.normal=0;o.detail=0;return o;
}
fragment float4 effectFragment(VertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]], texture2d<float> env [[texture(0)]], texture2d<float> mask [[texture(1)]]) {
    float2 uv=imageUV(in.point,u.viewport.xy); float water=maskAt(in.point,u.viewport.xy,mask);
    float phase=u.viewport.z, phase2=u.viewport.w;
    float2 wave=float2(sin(uv.y*67+sin(uv.x*35+phase2)*1.4+phase),cos(uv.x*59+sin(uv.y*29+phase)*1.3+phase2));
    if(u.style.x<0.5) {
        float2 offset=wave*0.00065*water*u.style.z;
        float3 color=env.sample(linearSampler,uv+offset).rgb;
        color*=1-u.style.w*0.10;
        return float4(color,1);
    }
    if(u.style.x<1.5) {
        float glint=pow(max(0.0,wave.x*wave.y),8.0);
        float alpha=water*u.style.z*(0.009+glint*0.055);
        return float4(float3(0.57,0.68,0.66)*alpha,alpha);
    }
    if(u.style.x<2.5) {
        float r=length(in.point-u.placement.xy), radius=u.style.y*95;
        float lifetime=u.style.w>0.5?1.4:2.3;
        float fade=pow(max(0.0,1-u.style.y/lifetime),1.5)*smoothstep(0.0,0.08,u.style.y);
        float d=r-radius;
        float ring=exp(-d*d/2.0)+0.45*exp(-pow(d+5,2.0)/2.4)+0.18*exp(-pow(d+10,2.0)/3.0);
        float alpha=ring*fade*u.style.z*water*(u.style.w>0.5 ? 0.75 : 0.32);
        return float4(float3(0.66,0.77,0.72)*alpha,alpha);
    }
    float2 p=in.local.xy;
    // Small pointed, lobed autumn leaf with a central vein and asymmetrical edges.
    float a=atan2(p.y,p.x), r=length(p*float2(1,1.25));
    float edge=0.47+0.12*cos(a*5)+0.04*sin(a*9+u.style.w);
    float body=1-smoothstep(edge-0.025,edge+0.025,r);
    float stem=(1-smoothstep(0.018,0.032,abs(p.y)))*smoothstep(-0.85,-0.75,p.x)*(1-smoothstep(-0.4,-0.3,p.x));
    float alpha=max(body,stem)*u.style.y;
    if(u.style.z==1) alpha*=water;
    float3 color=mix(float3(0.43,0.19,0.035),float3(0.76,0.52,0.075),0.5+0.4*sin(u.style.w*2.3));
    color*=0.85+0.15*p.y;
    color*=1-0.23*exp(-abs(p.y)*90);
    return float4(color*alpha,alpha);
}
