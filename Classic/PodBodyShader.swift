//
//  PodBodyShader.swift
//  Classic
//
//  Renders the iPod's front face below the screen: anodised aluminium body,
//  matte click wheel ring and centre button. Everything is analytic — each
//  surface is a height profile whose slope gives a normal that is lit by a
//  light that follows the device's tilt.
//
//  Compiled at runtime (MTLDevice.makeLibrary(source:)) so building the app
//  doesn't require Xcode's optional Metal toolchain component.
//

let podBodyShaderSource = """
#include <metal_stdlib>
using namespace metal;

// Must match PodBodyUniforms in PodBodyView.swift.
struct PodBodyUniforms {
    float2 viewSize;      // px
    float2 wheelCenter;   // px
    float  outerRadius;   // px
    float  innerRadius;   // px
    float  scale;         // px per pt
    float  centerPress;   // 0…1
    float4 bodyColor;
    float4 wheelColor;
    float4 centerColor;
    float2 tilt;          // −1…1, device tilt
    float2 pressDir;      // unit vector toward the pressed ring button (y down)
    float  pressAmount;   // 0…1
    float  darkness;      // 0 light body … 1 black body
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut podBodyVertex(uint vid [[vertex_id]]) {
    // Single oversized triangle covering the viewport.
    float2 p = float2((vid << 1) & 2, vid & 2);
    VertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// MARK: - Noise

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + float2(1, 0)), u.x),
               mix(hash12(i + float2(0, 1)), hash12(i + float2(1, 1)), u.x), u.y);
}

// MARK: - Lighting

struct Material {
    float3 albedo;
    float  gloss;       // Blinn-Phong exponent
    float  specular;    // highlight strength
    float  sheen;       // broad soft reflection (metal)
};

static float3 shade(Material m, float3 n, float3 L, float2 uv, float2 tilt) {
    const float3 V = float3(0, 0, 1);
    float3 H = normalize(L + V);
    float diffuse = saturate(dot(n, L));
    float spec = pow(saturate(dot(n, H)), m.gloss) * m.specular;
    // Broad environment reflection: a soft window-light band that slides with tilt.
    float band = exp(-pow((uv.x * 0.7 + uv.y * 0.5) - (0.55 + tilt.x * 0.35 + tilt.y * 0.25), 2.0) / 0.06);
    float3 color = m.albedo * (0.62 + 0.38 * diffuse);
    return color + spec + band * m.sheen;
}

/// Normal for a radially symmetric surface with slope dh/dr, plus a planar tilt.
static float3 radialNormal(float2 rel, float slope, float2 extraTilt) {
    float2 dir = length(rel) > 0.0001 ? normalize(rel) : float2(0);
    return normalize(float3(-slope * dir + extraTilt, 1.0));
}

// MARK: - Fragment

fragment float4 podBodyFragment(VertexOut in [[stage_in]],
                                constant PodBodyUniforms &u [[buffer(0)]]) {
    float2 px = in.position.xy;
    float2 uv = px / u.viewSize;
    float s = u.scale;
    float aa = 1.0 / s;                       // one pixel, in points

    float3 L = normalize(float3(-0.35 + u.tilt.x * 0.6, -0.75 + u.tilt.y * 0.6, 1.0));

    float2 rel = (px - u.wheelCenter) / s;    // points from wheel centre
    float d = length(rel);
    float R = u.outerRadius / s;
    float Ri = u.innerRadius / s;
    float yPt = px.y / s;

    // ---- Body: bead-blasted anodised aluminium ----
    float grain = hash12(floor(px)) - 0.5;
    float mottle = valueNoise(px / (s * 30.0)) - 0.5;
    Material body;
    body.albedo = u.bodyColor.rgb * (1.0 + grain * 0.045 + mottle * 0.03);
    body.gloss = 18.0;
    body.specular = mix(0.07, 0.10, u.darkness);
    body.sheen = mix(0.10, 0.07, u.darkness);
    float3 bodyN = float3(0, 0, 1);
    // Faint curvature toward the side edges, like the slightly domed front.
    bodyN.x += (uv.x - 0.5) * 0.12;
    bodyN = normalize(bodyN);
    float3 bodyCol = shade(body, bodyN, L, uv, u.tilt);

    // Polished chamfer where the body meets the screen glass.
    float chamfer = exp(-pow((yPt - 1.4) / 0.7, 2.0));
    bodyCol += chamfer * 0.30;
    bodyCol *= 1.0 - 0.55 * exp(-pow(yPt / 0.45, 2.0));      // hairline gap to the glass
    bodyCol *= 1.0 - 0.06 * exp(-yPt / 10.0);                // glass edge occlusion

    // Ambient occlusion around the wheel, which sits fractionally below the face.
    if (d > R) {
        bodyCol *= 1.0 - 0.14 * exp(-(d - R) / 2.2);
    }

    // ---- Ring: soft-touch matte plastic ----
    float outerBevel = pow(saturate((d - (R - 3.0)) / 3.0), 2.0);
    float innerBevel = pow(saturate(((Ri + 2.5) - d) / 2.5), 2.0);
    float ringSlope = 0.035 - 1.1 * outerBevel + 0.9 * innerBevel;
    // The ring rocks toward whichever button is pressed.
    float2 rock = u.pressDir * u.pressAmount * 0.14;
    float3 ringN = radialNormal(rel, ringSlope, rock);
    Material ring;
    ring.albedo = u.wheelColor.rgb * (1.0 + (hash12(floor(px) + 17.0) - 0.5) * 0.02);
    ring.gloss = 10.0;
    ring.specular = 0.06;
    ring.sheen = 0.035;
    float3 ringCol = shade(ring, ringN, L, uv, u.tilt);
    float2 relDir = d > 0.001 ? rel / d : float2(0);
    ringCol *= 1.0 - 0.07 * u.pressAmount * saturate(dot(relDir, u.pressDir));
    // Soft top-to-bottom falloff: the wheel catches more light on its upper half.
    ringCol *= 1.0 - 0.05 * clamp(rel.y / R, -1.0, 1.0);

    // ---- Centre button: gently domed, slightly glossier ----
    float Rc = Ri - 1.1;
    float press = u.centerPress;
    float domeSlope = -0.30 * (1.0 - 1.6 * press) * (d / max(Rc, 1.0))
                      - 1.2 * pow(saturate((d - (Rc - 2.0)) / 2.0), 2.0);
    float3 centerN = radialNormal(rel, domeSlope, float2(0));
    Material button;
    button.albedo = u.centerColor.rgb * (1.0 - 0.10 * press);
    button.gloss = 16.0;
    button.specular = 0.07;
    button.sheen = 0.03;
    float3 centerCol = shade(button, centerN, L, uv, u.tilt);

    // ---- Compose, outside in, with 1px coverage ramps ----
    // Groove walls face the wheel centre; the side facing the light glints.
    float wallLight = saturate(dot(-relDir, normalize(L.xy)));
    float3 gapOuter = mix(u.bodyColor.rgb * 0.35, u.bodyColor.rgb * 1.15 + 0.08, wallLight * 0.7);
    float3 gapInner = mix(u.wheelColor.rgb * 0.35, u.wheelColor.rgb * 1.10 + 0.06, wallLight * 0.6);
    float3 c = bodyCol;
    c = mix(c, gapOuter, saturate((R + 0.9 - d) / aa + 0.5));
    c = mix(c, ringCol, saturate((R - d) / aa + 0.5));
    c = mix(c, gapInner, saturate((Ri - d) / aa + 0.5));
    c = mix(c, centerCol, saturate((Rc - d) / aa + 0.5));

    // Dither to kill banding in the smooth gradients.
    c += (hash12(px + 0.5) - 0.5) / 255.0;
    return float4(saturate(c), 1.0);
}
"""
