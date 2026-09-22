#include <metal_stdlib>
using namespace metal;

struct FishVertex { float4 position; float4 normal; float4 detail; };
struct FishUniforms {
    float4 viewport; // width, height, time, water strength
    float4 placement; // x, y, length, depth
    float4 motion; // heading, phase, speed, panic
    float4 kind;
};
struct FishVarying {
    float4 position [[position]];
    float3 normal;
    float3 local;
    float4 detail;
    float species;
    float depth;
};

vertex FishVarying fishVertex(uint id [[vertex_id]], const device FishVertex *vertices [[buffer(0)]],
                             constant FishUniforms &u [[buffer(1)]]) {
    FishVertex v = vertices[id];
    float3 p = v.position.xyz;
    float3 n = v.normal.xyz;
    float species = u.kind.x;
    float t = u.viewport.z;
    float phase = u.motion.y;
    float rate = species == 4 ? 1.75 : 3.6 + min(u.motion.z / 70.0, 2.0) + u.motion.w * 2.0;
    float wave = t * rate + phase;
    if (species == 4) {
        float wing = pow(abs(p.y) / 0.58, 1.45);
        p.z += wing * 0.13 * sin(wave - abs(p.y) * 4.0);
        p.y *= 1.0 - wing * 0.05 * cos(wave);
        n.y += sign(p.y) * wing * 0.35 * cos(wave - abs(p.y) * 4.0);
        if (p.x < -0.22) p.y += pow(-p.x - 0.22, 1.4) * 0.10 * sin(wave - p.x * 5.0);
    } else {
        float tail = 1.0 - smoothstep(-0.60, 0.22, p.x);
        float bend = (0.036 + u.motion.w * 0.020) * tail * tail;
        p.z += sin(wave + p.x * 6.0) * bend * 2.6;
        p.y += sin(wave + p.x * 5.0) * bend * 0.34;
        n.x += cos(wave + p.x * 6.0) * tail * 0.20;
        if (v.detail.y == 1) {
            p.z += sin(wave * 1.35) * 0.065 * v.detail.w;
            p.x += cos(wave * 1.35) * 0.022 * v.detail.w;
        }
    }
    // Heading changes facing and yaw; screen-up remains the fish's dorsal side.
    float facing = cos(u.motion.x) >= 0 ? 1.0 : -1.0;
    float yaw = sin(u.motion.x) * 0.70;
    float yawCos = sqrt(1.0 - yaw * yaw);
    float3 posed = float3(facing * (p.x * yawCos + p.z * yaw), p.y, p.z * yawCos - p.x * yaw);
    float3 normal = float3(facing * (n.x * yawCos + n.z * yaw), n.y, n.z * yawCos - n.x * yaw);
    float pitch = sin(u.motion.x) * facing * (species == 4 ? 0.35 : 0.24);
    float c = cos(pitch), s = sin(pitch);
    posed.xy = float2(c * posed.x - s * posed.y, s * posed.x + c * posed.y);
    normal.xy = float2(c * normal.x - s * normal.y, s * normal.x + c * normal.y);
    float scale = u.placement.z * (1.0 - 0.27 * u.placement.w);
    float2 screen = u.placement.xy + posed.xy * scale;
    FishVarying out;
    out.position = float4(screen / u.viewport.xy * 2.0 - 1.0, 0.12 + u.placement.w * 0.74 - posed.z * 0.065, 1);
    out.normal = normal;
    out.local = v.position.xyz;
    out.detail = v.detail;
    out.species = species;
    out.depth = u.placement.w;
    return out;
}

float band(float x, float center, float width) {
    return 1.0 - smoothstep(width, width + 0.009, abs(x - center));
}

fragment float4 fishFragment(FishVarying in [[stage_in]]) {
    float3 p = in.local;
    float material = in.detail.x;
    float species = in.species;
    float3 n = normalize(in.normal);
    float3 light = normalize(float3(-0.25, 0.65, 1.2));
    float diffuse = max(dot(n, light), 0.0);
    float3 halfVector = normalize(light + float3(0, 0, 1));
    float sheen = pow(max(dot(n, halfVector), 0.0), 38.0);
    float3 color;
    float alpha = 1.0;
    if (species == 0) {
        float dorsal = smoothstep(-0.08, 0.11, p.y);
        color = mix(float3(0.80, 0.91, 0.95), float3(0.10, 0.37, 0.50), dorsal);
        float lateral = exp(-pow((p.y + 0.008) / 0.019, 2.0));
        color = mix(color, float3(0.35, 0.83, 0.94), lateral * 0.58);
        float scales = sin(p.x * 195 + sin(p.y * 160) * 1.8) * sin(p.y * 160);
        color += scales * 0.025;
    } else if (species == 1) {
        color = float3(1.0, 0.32, 0.035);
        float x = p.x + p.y * 0.13 + 0.010 * sin(p.y * 22.0);
        float edging = max(max(band(x, 0.225, 0.041), band(x, -0.025, 0.053)), band(x, -0.265, 0.028));
        float stripe = max(max(band(x, 0.225, 0.027), band(x, -0.025, 0.037)), band(x, -0.265, 0.017));
        color = mix(color, float3(0.10, 0.065, 0.035), edging);
        color = mix(color, float3(0.98, 0.97, 0.88), stripe);
    } else if (species == 2) {
        color = float3(0.035, 0.26, 0.90);
        float upper = smoothstep(0.012, 0.027, p.y) * (1.0 - smoothstep(0.26, 0.31, p.x));
        float oval = length(float2((p.x + 0.015) / 0.19, (p.y - 0.07) / 0.090));
        float blueIsland = 1.0 - smoothstep(0.76, 0.88, oval);
        float pattern = upper * (1.0 - blueIsland);
        color = mix(color, float3(0.018, 0.028, 0.09), pattern * 0.95);
        color = mix(color, float3(0.08, 0.54, 0.92), exp(-pow((p.y + 0.08) / 0.05, 2.0)) * 0.30);
        if (p.x < -0.22) color = mix(color, float3(1.0, 0.81, 0.045), 1.0 - smoothstep(-0.30, -0.22, p.x));
    } else if (species == 3) {
        color = mix(float3(1.0, 0.66, 0.035), float3(1.0, 0.94, 0.34), smoothstep(-0.18, 0.22, p.y));
        float stripe = pow(0.5 + 0.5 * sin((p.x + p.y * 0.47) * 48.0), 7.0);
        color *= 1.0 - stripe * 0.37;
        float mask = band(p.x - p.y * 0.14, 0.285, 0.026);
        color = mix(color, float3(0.055, 0.065, 0.06), mask);
        float spot = 1.0 - smoothstep(0.029, 0.036, length(float2(p.x + 0.18, p.y - 0.09)));
        color = mix(color, float3(0.045, 0.07, 0.07), spot);
    } else {
        color = mix(float3(0.07, 0.15, 0.20), float3(0.25, 0.37, 0.40), smoothstep(0.02, 0.10, p.z));
        float shoulder = exp(-pow((abs(p.y) - 0.13) / 0.08, 2.0)) * smoothstep(-0.13, 0.28, p.x);
        color += float3(0.25, 0.29, 0.27) * shoulder;
        color += 0.005 * sin(p.x * 19.0 + p.y * 12.0);
    }
    if (material == 1 || material == 2) {
        alpha = material == 2 ? 0.87 : 0.58;
        float height = species == 0 ? 0.115 : species == 1 ? 0.205 : species == 2 ? 0.245 : 0.285;
        float2 root = material == 2 ? float2(-0.28, 0) : in.detail.y == 1 ? float2(0.14, -height * 0.18) : float2(-0.1, sign(p.y) * height * 0.49);
        float angle = atan2(p.y - root.y, p.x - root.x);
        float ray = pow(0.5 + 0.5 * cos(angle * 37.0), 13.0);
        ray *= 1.0 - smoothstep(0.06, 0.20, fwidth(angle));
        color *= 0.85 + 0.22 * ray;
        alpha += ray * 0.12;
        if (species == 0) { color = mix(color, float3(0.46, 0.72, 0.79), 0.5); alpha *= 0.67; }
        if (species == 1) {
            float rim = smoothstep(0.82, 0.94, in.detail.w);
            color = mix(color, float3(0.055, 0.05, 0.045), rim);
            color = mix(color, float3(0.87, 0.85, 0.75), smoothstep(0.97, 1.0, in.detail.w));
        }
        if (species == 2 && material == 2) color = float3(1.0, 0.84, 0.035) * (0.89 + ray * 0.18);
        if (species == 3) color = mix(color, float3(0.94, 0.66, 0.035), 0.3);
    }
    if (material == 3) color = species == 4 ? float3(0.30, 0.40, 0.40) : float3(0.90, 0.76, 0.39);
    if (material == 4) color = float3(0.012, 0.020, 0.027);
    if (material == 5) return float4(0.94, 0.99, 1.0, 1.0);
    if (material == 6) { color *= 0.29; alpha = 0.62; }
    float lighting = 0.44 + 0.61 * diffuse;
    color *= lighting;
    color += sheen * (species == 0 ? 0.43 : 0.18);
    float rimLight = pow(1.0 - abs(n.z), 3.0) * 0.12;
    color += float3(0.20, 0.44, 0.53) * rimLight;
    color = mix(color, color * float3(0.76, 0.87, 0.95), in.depth * 0.35);
    return float4(clamp(color, 0.0, 1.0) * alpha, alpha);
}

struct EffectUniforms {
    float4 viewport;
    float4 placement; // x, y, radius, angle
    float4 style; // type: caustic, ripple, current, bubble; age, strength, seed
};
struct EffectVarying { float4 position [[position]]; float2 uv; };
vertex EffectVarying effectVertex(uint id [[vertex_id]], constant EffectUniforms &u [[buffer(0)]]) {
    const float2 corners[] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
    float2 uv = corners[id];
    float2 point = uv * u.placement.z;
    if (u.style.x == 2) point.y *= 0.28;
    float c = cos(u.placement.w), s = sin(u.placement.w);
    point = float2(c * point.x - s * point.y, s * point.x + c * point.y);
    EffectVarying out;
    out.position = float4((u.placement.xy + point) / u.viewport.xy * 2.0 - 1.0, 0.98, 1);
    out.uv = uv;
    return out;
}
fragment float4 effectFragment(EffectVarying in [[stage_in]], constant EffectUniforms &u [[buffer(0)]]) {
    float2 p = in.uv;
    float r = length(p);
    float alpha = 0;
    float3 color = float3(0.74, 0.92, 1.0);
    float time = u.viewport.z;
    if (u.style.x == 0) {
        float2 q = p * 4.6;
        q += float2(sin(q.y * 0.8 + time * 0.21 + u.style.w), cos(q.x * 0.9 - time * 0.17)) * 0.47;
        float field = sin(q.x + q.y * 0.45) * cos(q.y - q.x * 0.31);
        float ridge = exp(-abs(field) * 34.0);
        alpha = ridge * pow(max(0.0, 1.0 - r), 2.2) * 0.13 * u.style.z;
    } else if (u.style.x == 1) {
        float wobble = 0.009 * sin(atan2(p.y, p.x) * 9.0 + time * 1.4);
        float ring = exp(-pow((r - 0.83 + wobble) / 0.014, 2.0));
        float inner = exp(-pow((r - 0.68 + wobble) / 0.021, 2.0));
        alpha = (ring + inner * 0.40) * u.style.z * 0.22 * pow(max(0.0, 1.0 - u.style.y / 2.8), 1.6);
    } else if (u.style.x == 2) {
        float bend = p.y + 0.18 * sin(p.x * 3.0 + u.style.w);
        float filament = exp(-pow((abs(bend) - 0.26) / 0.042, 2.0));
        alpha = filament * pow(max(0.0, 1.0 - abs(p.x)), 1.8) * 0.12 * exp(-u.style.y * 1.9);
    } else {
        float ring = exp(-pow((r - 0.69) / 0.07, 2.0));
        float highlight = exp(-dot(p - float2(-0.26, 0.35), p - float2(-0.26, 0.35)) * 100.0);
        alpha = (ring * 0.22 + highlight * 0.45) * u.style.z;
    }
    alpha = clamp(alpha, 0.0, 0.55);
    return float4(color * alpha, alpha);
}
