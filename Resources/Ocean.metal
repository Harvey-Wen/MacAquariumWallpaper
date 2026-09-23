#include <metal_stdlib>
using namespace metal;

struct FishVertex { float4 position; float4 normal; float4 detail; };
struct FishUniforms {
    float4 viewport; // width, height, unused, unused
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
    float2 waterPoint;
    float3 water;
};

// A smoothly warped cellular field gives connected light ribbons rather than
// isolated rings. Both phases enter through sin/cos so independent wraps agree.
float waterCaustic(float2 p, float2 phase) {
    p += float2(sin(p.y * 1.17 + phase.x), cos(p.x * 0.93 - phase.y)) * 0.55;
    p += float2(sin(p.y * 2.4 + cos(p.x * 1.8 + phase.x) + phase.y),
                cos(p.x * 2.3 + sin(p.y * 1.9 - phase.y) - phase.x)) * 0.34;
    float2 cell = floor(p), local = fract(p);
    float nearest = 8.0, second = 8.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 neighbor = float2(x, y);
            float2 id = cell + neighbor;
            float2 seed = fract(sin(float2(dot(id, float2(127.1, 311.7)),
                                           dot(id, float2(269.5, 183.3)))) * 43758.5453);
            float2 center = 0.5 + 0.28 * sin(seed * 6.2831853 + float2(phase.x, -phase.y));
            float2 delta = neighbor + center - local;
            float distance = dot(delta, delta);
            if (distance < nearest) { second = nearest; nearest = distance; }
            else second = min(second, distance);
        }
    }
    float edge = sqrt(second) - sqrt(nearest);
    float width = max(fwidth(edge), 0.012);
    float core = 1.0 - smoothstep(0.006, 0.045 + width, edge);
    float glow = 1.0 - smoothstep(0.02, 0.16 + width, edge);
    float focus = 0.62 + 0.38 * sin(p.x * 2.1 + p.y * 1.7 + phase.x) *
                              sin(p.y * 1.3 - phase.y);
    return (core * 0.72 + glow * 0.28) * focus;
}

float waterRays(float2 uv, float2 phase) {
    float depth = 1.0 - uv.y;
    float rays = 0;
    for (int i = 0; i < 4; ++i) {
        float seed = float(i);
        float origin = 0.08 + seed * 0.28;
        float sway = 0.018 * sin(phase.x + seed * 2.3) + 0.009 * cos(phase.y - seed);
        float center = origin + depth * (0.10 + seed * 0.025) + sway;
        float width = 0.014 + depth * 0.075;
        float distance = (uv.x - center) / width;
        rays += exp(-distance * distance) * (0.7 + 0.3 * sin(phase.y + seed * 1.7));
    }
    return rays * exp(-depth * 1.7);
}

float2 waterCoordinates(float2 uv, float aspect) {
    return float2(uv.x * aspect, uv.y) * 6.4;
}

vertex FishVarying fishVertex(uint id [[vertex_id]], const device FishVertex *vertices [[buffer(0)]],
                             constant FishUniforms &u [[buffer(1)]]) {
    FishVertex v = vertices[id];
    float3 p = v.position.xyz;
    float3 n = v.normal.xyz;
    float species = u.kind.x;
    // The simulation integrates phase; speed changes never multiply elapsed time.
    float wave = u.motion.y;
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
            p.z += sin(wave * 2.0) * 0.065 * v.detail.w * sign(v.position.z);
            p.x += cos(wave * 2.0) * 0.022 * v.detail.w;
        }
    }
    // Continuous yaw passes through an edge-on view, with the dorsal axis upright.
    float c = cos(u.motion.x), s = sin(u.motion.x);
    float pitch = s * (species == 4 ? 0.35 : 0.24);
    float3 posed = float3(c * p.x + s * p.z, p.y + pitch * p.x, c * p.z - s * p.x);
    n.x -= pitch * n.y;
    float3 normal = float3(c * n.x + s * n.z, n.y, c * n.z - s * n.x);
    float scale = u.placement.z * (1.0 - 0.27 * u.placement.w);
    float2 screen = u.placement.xy + posed.xy * scale;
    FishVarying out;
    out.position = float4(screen / u.viewport.xy * 2.0 - 1.0, 0.12 + u.placement.w * 0.74 - posed.z * 0.065, 1);
    out.normal = normal;
    out.local = v.position.xyz;
    out.detail = v.detail;
    out.species = species;
    out.depth = u.placement.w;
    out.waterPoint = screen / u.viewport.xy;
    out.water = u.kind.yzw;
    // x is aspect; keep placement and light in the same normalized screen space.
    out.detail.z = u.viewport.x / u.viewport.y;
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
    if (in.water.z > 0) {
        float2 phase = in.water.xy;
        float caustic = waterCaustic(waterCoordinates(in.waterPoint, in.detail.z), phase);
        float rays = waterRays(in.waterPoint, phase);
        float amount = min(in.water.z / 0.45, 1.65);
        float haze = (0.05 + in.depth * 0.19) * amount;
        color = mix(color, float3(0.06, 0.32, 0.40), haze);
        color += float3(0.46, 0.77, 0.80) * (caustic * 0.16 + rays * 0.08) * amount * max(n.y * 0.5 + 0.5, 0.0);
    }
    return float4(clamp(color, 0.0, 1.0) * alpha, alpha);
}

struct EffectUniforms {
    float4 viewport; // width, height, independently wrapped animation phases
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
    out.position = u.style.x == 0 ? float4(uv, 0.98, 1) :
        float4((u.placement.xy + point) / u.viewport.xy * 2.0 - 1.0, 0.98, 1);
    out.uv = uv;
    return out;
}
fragment float4 effectFragment(EffectVarying in [[stage_in]], constant EffectUniforms &u [[buffer(0)]]) {
    float2 p = in.uv;
    float r = length(p);
    float alpha = 0;
    float3 color = float3(0.74, 0.92, 1.0);
    if (u.style.x == 0) {
        float2 uv = p * 0.5 + 0.5;
        float depth = 1.0 - uv.y;
        float aspect = u.viewport.x / u.viewport.y;
        float2 phase = u.viewport.zw;
        float caustic = waterCaustic(waterCoordinates(uv, aspect), phase);
        // Compress the top light network into a receding surface, with no horizon edge.
        float2 surfacePoint = float2((uv.x - 0.5) * aspect * 2.2, 1.3) / (depth + 0.18);
        float surface = waterCaustic(surfacePoint, phase) * exp(-depth * 13.0);
        float rays = waterRays(uv, phase);
        float amount = min(u.style.z / 0.45, 1.65);
        float haze = (0.075 + 0.15 * pow(depth, 0.8)) * amount;
        float light = (surface * 0.48 + rays * 0.19 + caustic * (0.07 + depth * 0.11)) * amount;
        light = min(light, 0.52);
        float3 tint = mix(float3(0.055, 0.48, 0.57), float3(0.015, 0.18, 0.29), depth);
        alpha = haze + light * (1.0 - haze);
        float3 premultiplied = tint * haze * (1.0 - light) + float3(0.61, 0.91, 0.96) * light;
        return float4(premultiplied, alpha);
    } else if (u.style.x == 1) {
        float wobble = 0.009 * sin(atan2(p.y, p.x) * 9.0 + u.viewport.z);
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
