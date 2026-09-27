#include <metal_stdlib>
using namespace metal;
struct FishVertex { float4 position, normal, detail; };
struct FishUniforms { float4 viewport, placement, motion, kind; };
struct EffectUniforms { float4 viewport, placement, style, travel; };
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
    if(u.motion.z>0.5) point = u.placement.xy + (point-u.placement.xy)*1.09 + float2(2,-3)*(0.4+u.placement.w);
    VertexOut o; o.position=float4(point/u.viewport.xy*2-1, 0.2+u.placement.w*0.6-p.z*0.1, 1);
    o.point=point; o.local=v.position.xyz; o.normal=v.normal.xyz; o.detail=v.detail; return o;
}
fragment float4 fishFragment(VertexOut in [[stage_in]], constant FishUniforms &u [[buffer(0)]], texture2d<float> env [[texture(0)]], texture2d<float> mask [[texture(1)]]) {
    float water=maskAt(in.point,u.viewport.xy,mask); if(water<=0) discard_fragment();
    if(u.motion.z>0.5) {
        float alpha=0.09*smoothstep(0.05,0.75,abs(in.normal.z))*water;
        return float4(float3(0.005,0.016,0.009)*alpha,alpha);
    }
    float id=u.kind.x, kind=fmod(id,7.0);
    float2 p=float2(in.local.x*6.7, in.local.y*18);
    float patches=noise(p+float2(id*7, id*3))+0.14*noise(p*2.1+id);
    float3 ivory=float3(0.95,0.93,0.82), red=float3(0.88,0.245,0.075), gold=float3(0.92,0.65,0.13), black=float3(0.06,0.075,0.066);
    float3 color=ivory;
    if(kind==0 || kind==3 || kind==6) color=mix(ivory,red,smoothstep(0.51,0.68,patches));
    if(kind==1) color=mix(gold,ivory,smoothstep(0.84,0.95,patches));
    if(kind==2) color=mix(black,red,smoothstep(0.60,0.75,patches));
    if(kind==4) color=mix(ivory,black,smoothstep(0.45,0.64,patches));
    if(kind==5) color=mix(red,gold,smoothstep(0.88,0.96,patches));
    if(kind==3 || kind==6) color=mix(color,black,smoothstep(0.76,0.91,noise(p*1.2+id*13)));
    float3 normal=normalize(in.normal);
    float curvedBack=pow(max(0.0,normal.z),1.7);
    float shade=0.37+0.59*curvedBack+0.10*normal.y;
    float scales=sin(in.local.x*260+sin(in.local.y*290)*0.8)*sin(in.local.y*290);
    color*=shade*(0.99+scales*0.01);
    color+=float3(0.11,0.13,0.11)*pow(max(0.0,dot(normal,normalize(float3(-0.15,0.30,1)))),9.0);
    float alpha=1;
    if(in.detail.x==1 || in.detail.x==2) {
        float rays=pow(0.5+0.5*cos(in.detail.z*72),5.0);
        color=mix(color,ivory,0.72)*(0.77+rays*0.13);
        alpha=(0.42+0.12*rays)*(1-0.58*smoothstep(0.65,1.0,in.detail.w));
    }
    if(in.detail.x==3) { color*=0.87; alpha=0.38; }
    if(in.detail.x==4) color=float3(0.025,0.03,0.02);
    // Water absorption and reflected environment integrate the entire animal below the surface.
    float3 reflection=env.sample(linearSampler,imageUV(in.point,u.viewport.xy)).rgb;
    float reflectedSky=smoothstep(0.16,0.5,dot(reflection,float3(0.21,0.72,0.07)));
    color=mix(color, reflection,0.14+u.placement.w*0.18+reflectedSky*0.12);
    color=mix(color,float3(0.075,0.21,0.16),u.placement.w*0.10);
    alpha*=water; return float4(color*alpha,alpha);
}
vertex VertexOut effectVertex(uint id [[vertex_id]], constant EffectUniforms &u [[buffer(0)]]) {
    const float2 quad[6]={float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    float2 q=quad[id], p;
    if(u.style.x<1.5 || u.style.x>3.5) p=(q*0.5+0.5)*u.viewport.xy;
    else { float c=cos(u.placement.w),s=sin(u.placement.w); p=u.placement.xy+float2(c*q.x-s*q.y,s*q.x+c*q.y)*u.placement.z; }
    VertexOut o; o.position=float4(p/u.viewport.xy*2-1,0,1);o.point=p;o.local=float3(q,0);o.normal=0;o.detail=0;return o;
}
fragment float4 effectFragment(VertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]], texture2d<float> env [[texture(0)]], texture2d<float> mask [[texture(1)]]) {
    if(u.style.x>3.5) {
        // Independently phased sparse drops at three depths. Eight-second wrapping is
        // reduced in Double on the CPU; each local reset disappears through a fade.
        float alpha=0;
        for(int layer=0;layer<3;layer++) {
            float spacing=40+layer*36;
            float2 grid=in.point/spacing;
            float2 cell=floor(grid), local=fract(grid)*spacing;
            float seed=hash(cell+float2(layer*71,layer*113));
            float other=hash(cell+float2(41+layer*17,93));
            float cycles=10+floor(other*12)+layer*6;
            float t=fract(u.style.y*cycles/8+seed);
            float fade=smoothstep(0.0,0.13,t)*(1-smoothstep(0.78,1.0,t));
            float wind=0.12+0.12*sin(u.style.y*0.785398);
            float2 direction=normalize(float2(wind+(other-0.5)*0.5,-1));
            float2 center=float2(spacing*(0.25+other*0.5),spacing*(0.85-0.70*t));
            center.x+=direction.x*(t-0.5)*spacing*0.5;
            float2 d=local-center;
            float across=dot(d,float2(-direction.y,direction.x));
            float along=dot(d,direction);
            float width=0.48+layer*0.30;
            float length=1.5+layer*1.8+seed*seed*(2+layer*2);
            float drop=exp(-across*across/(width*width)-along*along/(length*length));
            alpha+=drop*fade*(0.24+layer*0.07+other*0.16);
        }
        alpha*=u.style.z;
        return float4(float3(0.70,0.84,0.78)*alpha,alpha);
    }

    float2 uv=imageUV(in.point,u.viewport.xy); float water=maskAt(in.point,u.viewport.xy,mask);
    float phase=u.viewport.z, phase2=u.viewport.w;
    float2 wave=float2(sin(uv.y*67+sin(uv.x*35+phase2)*1.4+phase),cos(uv.x*59+sin(uv.y*29+phase)*1.3+phase2));
    if(u.style.x<0.5) {
        float2 offset=wave*0.00065*water*u.style.z;
        float3 color=env.sample(linearSampler,uv+offset).rgb;
        color*=1-u.style.w*0.04;
        return float4(color,1);
    }
    if(u.style.x<1.5) {
        float glint=pow(max(0.0,wave.x*wave.y),8.0);
        float alpha=water*u.style.z*(0.009+glint*0.055);
        return float4(float3(0.60,0.76,0.67)*alpha,alpha);
    }
    float2 p=in.local.xy;
    // An asymmetric five-lobed maple leaf, with a curled blade and branching veins.
    p.y += 0.09*sin(p.x*5+u.style.w)*p.x;
    float a=atan2(p.y,p.x), r=length(p*float2(0.95,1.17));
    float lobes=cos(a*5+0.16*sin(a*2+u.style.w));
    float edge=0.43+0.13*lobes+0.065*cos(a)+0.023*sin(a*13+u.style.w*2);
    edge+=0.018*(noise(p*24+u.style.w)-0.5);
    float body=1-smoothstep(edge-0.018,edge+0.018,r);
    float midrib=p.y-0.027*sin(p.x*8);
    float stem=(1-smoothstep(0.012,0.025,abs(midrib)))*smoothstep(-0.80,-0.70,p.x)*(1-smoothstep(-0.37,-0.29,p.x));
    float alpha=max(body,stem)*u.style.y;
    if(u.style.z==1) alpha*=water;
    float mottling=noise(p*11+u.style.w*3);
    float3 color=mix(float3(0.14,0.36,0.055),float3(0.59,0.72,0.17),0.52+0.22*sin(u.style.w*2.3)+0.22*mottling);
    float curl=0.70+0.27*cos(midrib*6)+0.17*sin(midrib*9);
    color*=curl*(0.87+0.17*noise(p*38+u.style.w));
    float vein=exp(-abs(midrib)*140);
    float branches=abs(sin((p.x-abs(midrib)*0.85)*32));
    vein=max(vein,exp(-branches*20)*0.42*(1-smoothstep(0.10,0.40,abs(midrib))));
    color=mix(color,color*0.65+float3(0.07,0.10,0.015),vein*0.60);
    color*=0.79+0.21*smoothstep(0.0,0.09,edge-r);
    return float4(color*alpha,alpha);
}

// Wave gradients are signed and additive: intersections share one water normal.
vertex VertexOut waveVertex(uint id [[vertex_id]], constant EffectUniforms &u [[buffer(0)]]) {
    const float2 quad[6]={float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    float2 p=u.placement.xy+quad[id]*u.placement.z;
    VertexOut o; o.position=float4(p/u.viewport.xy*2-1,0,1); o.point=p; return o;
}
float packetDerivative(float d, float width, float k) {
    return exp(-d*d/(width*width))*(-k*sin(k*d)-2*d/(width*width)*cos(k*d));
}
fragment float4 waveFragment(VertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]]) {
    float age=u.style.y, strength=u.style.z;
    float2 p=in.point-u.placement.xy, gradient=0;
    float foam=0;
    if(u.style.x==3) {
        float travel=length(u.travel.xy);
        if(travel<0.1) return 0;
        float2 axis=u.travel.xy/travel, lateral=float2(-axis.y,axis.x);
        float along=dot(p,axis), across=dot(p,lateral);
        // A finite strip along the accepted segment, with lateral ripples peeling
        // away from its sides. There is no radial/end-cap ring.
        float span=max(18.0,travel), t=-along/span;
        float taper=smoothstep(-0.18,0.12,t)*(1-smoothstep(0.78,1.18,t));
        float width=5+age*3;
        float d=abs(across)-(3+age*19);
        float fade=exp(-age*1.8)*(1-smoothstep(1.7,2.3,age));
        float wake=packetDerivative(d,width,0.62)*sign(across)*taper;
        gradient=lateral*wake*strength*fade*2.2;
        gradient+=axis*exp(-across*across/45)*sin(t*3.14159)*taper*strength*fade*0.10;
    } else {
        bool rain=u.style.x==1;
        float seed=hash(u.placement.xy), angle=atan2(p.y,p.x), r=length(p);
        float lifetime=rain?1.4:2.3;
        float fade=pow(max(0.0,1-age/lifetime),1.4)*smoothstep(0.0,0.035,age);
        float speed=rain?45:65;
        float width=rain?6+seed*3:11;
        float d=r-speed*age*(0.94+seed*0.12);
        d+=sin(angle*3+seed*6)*0.75+sin(angle*7-seed*9)*0.3;
        float breakup=0.72+0.18*sin(angle*4+seed*7)+0.10*sin(angle*9+age*3);
        float derivative=packetDerivative(d,width,rain?1.05:0.65)*breakup;
        // Initial depression, then sub-0.2 second asymmetric splash glints.
        derivative+=r*0.15*exp(-r*r/16)*exp(-age*25);
        gradient=p/max(r,0.01)*derivative*fade*strength*(rain?2.3:0.7);
        float splash=exp(-pow((r-(2+age*14))/1.1,2.0));
        foam=splash*pow(max(0.0,sin(angle*5+seed*11)),12.0)*(1-smoothstep(0.04,0.18,age))*strength*0.28;
    }
    return float4(gradient,foam,0);
}
fragment float4 waterFragment(VertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]],
    texture2d<float> env [[texture(0)]], texture2d<float> mask [[texture(1)]],
    texture2d<float> scene [[texture(2)]], texture2d<float> waves [[texture(3)]]) {
    float2 uv=float2(in.point.x/u.viewport.x,1-in.point.y/u.viewport.y);
    float distance=mask.sample(linearSampler,imageUV(in.point,u.viewport.xy)).r;
    float coverage=smoothstep(1.0,18.0,distance);
    float3 field=waves.sample(linearSampler,uv).rgb*coverage;
    float2 normal=field.xy;
    float2 offset=clamp(normal*3.0,float2(-2.8),float2(2.8))/u.viewport.xy;
    float4 color=scene.sample(linearSampler,uv+float2(offset.x,-offset.y));
    float light=dot(normal,float2(-0.55,0.83));
    color.rgb+=light*float3(0.14,0.18,0.16)+field.z*float3(0.55,0.65,0.60);
    return float4(clamp(color.rgb,0.0,1.0),color.a);
}
