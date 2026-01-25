// LUTShared.metal
#include <metal_stdlib>
using namespace metal;

struct FullscreenOut {
    float4 pos [[position]];
    float2 uv;
};

vertex FullscreenOut compositeVS(uint vid [[vertex_id]])
{
    float2 pos[6] = {
        {-1,-1}, { 1,-1}, {-1, 1},
        { 1,-1}, { 1, 1}, {-1, 1}
    };

    FullscreenOut o;
    o.pos = float4(pos[vid], 0, 1);
    o.uv = float2(
        pos[vid].x * 0.5 + 0.5,
        1.0 - (pos[vid].y * 0.5 + 0.5)
    );
    return o;
}

float3 tetra_high_precision(texture3d<float> lutTex, float3 color, sampler s) {
    float lutSize = float(lutTex.get_width());
    float3 scaled = color * (lutSize - 1.0);
    float3 index = floor(scaled);
    float3 frac  = scaled - index;

    float3 p000 = (index + float3(0.0, 0.0, 0.0)) / (lutSize - 1.0);
    float3 p001 = (index + float3(0.0, 0.0, 1.0)) / (lutSize - 1.0);
    float3 p010 = (index + float3(0.0, 1.0, 0.0)) / (lutSize - 1.0);
    float3 p011 = (index + float3(0.0, 1.0, 1.0)) / (lutSize - 1.0);
    float3 p100 = (index + float3(1.0, 0.0, 0.0)) / (lutSize - 1.0);
    float3 p101 = (index + float3(1.0, 0.0, 1.0)) / (lutSize - 1.0);
    float3 p110 = (index + float3(1.0, 1.0, 0.0)) / (lutSize - 1.0);
    float3 p111 = (index + float3(1.0, 1.0, 1.0)) / (lutSize - 1.0);

    float3 c000 = lutTex.sample(s, p000).rgb;
    float3 c001 = lutTex.sample(s, p001).rgb;
    float3 c010 = lutTex.sample(s, p010).rgb;
    float3 c011 = lutTex.sample(s, p011).rgb;
    float3 c100 = lutTex.sample(s, p100).rgb;
    float3 c101 = lutTex.sample(s, p101).rgb;
    float3 c110 = lutTex.sample(s, p110).rgb;
    float3 c111 = lutTex.sample(s, p111).rgb;

    float fx = frac.x;
    float fy = frac.y;
    float fz = frac.z;

    float3 result;

    if (fx >= fy) {
        if (fy >= fz) {
            result = c000 + (c100 - c000) * fx
                           + (c110 - c100) * fy
                           + (c111 - c110) * fz;
        } else if (fx >= fz) {
            result = c000 + (c100 - c000) * fx
                           + (c101 - c100) * fz
                           + (c111 - c101) * fy;
        } else {
            result = c000 + (c001 - c000) * fz
                           + (c101 - c001) * fx
                           + (c111 - c101) * fy;
        }
    } else {
        if (fz > fy) {
            result = c000 + (c001 - c000) * fz
                           + (c011 - c001) * fy
                           + (c111 - c011) * fx;
        } else if (fz > fx) {
            result = c000 + (c010 - c000) * fy
                           + (c011 - c010) * fz
                           + (c111 - c011) * fx;
        } else {
            result = c000 + (c010 - c000) * fy
                           + (c110 - c010) * fx
                           + (c111 - c110) * fz;
        }
    }

    return result;
}

float3 tetra_optimized(texture3d<float> lutTex, float3 color, sampler s) {
    float lutSize = float(lutTex.get_width());
    float3 scaled = color * (lutSize - 1.0);
    float3 index = floor(scaled);
    float3 frac  = scaled - index;

    float3 p000 = (index + float3(0.0, 0.0, 0.0)) / (lutSize - 1.0);
    float3 p001 = (index + float3(0.0, 0.0, 1.0)) / (lutSize - 1.0);
    float3 p010 = (index + float3(0.0, 1.0, 0.0)) / (lutSize - 1.0);
    float3 p011 = (index + float3(0.0, 1.0, 1.0)) / (lutSize - 1.0);
    float3 p100 = (index + float3(1.0, 0.0, 0.0)) / (lutSize - 1.0);
    float3 p101 = (index + float3(1.0, 0.0, 1.0)) / (lutSize - 1.0);
    float3 p110 = (index + float3(1.0, 1.0, 0.0)) / (lutSize - 1.0);
    float3 p111 = (index + float3(1.0, 1.0, 1.0)) / (lutSize - 1.0);

    float3 c000 = lutTex.sample(s, p000).rgb;
    float3 c001 = lutTex.sample(s, p001).rgb;
    float3 c010 = lutTex.sample(s, p010).rgb;
    float3 c011 = lutTex.sample(s, p011).rgb;
    float3 c100 = lutTex.sample(s, p100).rgb;
    float3 c101 = lutTex.sample(s, p101).rgb;
    float3 c110 = lutTex.sample(s, p110).rgb;
    float3 c111 = lutTex.sample(s, p111).rgb;

    float fx = frac.x;
    float fy = frac.y;
    float fz = frac.z;

    float3 c00 = mix(c000, c100, fx);
    float3 c01 = mix(c001, c101, fx);
    float3 c10 = mix(c010, c110, fx);
    float3 c11 = mix(c011, c111, fx);

    float3 c0 = mix(c00, c10, fy);
    float3 c1 = mix(c01, c11, fy);

    return mix(c0, c1, fz);
}

/*
fragment float4 compositeFS(
    FullscreenOut in [[stage_in]],
    texture2d<float> cameraTex [[texture(0)]],
    texture2d<float> arTex     [[texture(1)]],
    texture2d<float> pbrTex    [[texture(2)]],
    texture3d<float> lutTex    [[texture(3)]],
    sampler s [[sampler(0)]]
)
{
    float2 uv = in.uv;

    float4 cam = cameraTex.sample(s, uv);
    float4 pbr = pbrTex.sample(s, uv);

    // Linear alpha composite (OVER)
    float3 composited =
        cam.rgb * (1.0 - pbr.a) +
        pbr.rgb * pbr.a;

    // LUT in linear Rec.709
    //float3 graded =
    //    tetra_optimized(lutTex, saturate(composited), s);

    return float4(composited, 1.0);
}
*/

fragment float4 compositeFS(
    FullscreenOut in [[stage_in]],
    texture2d<float> cameraTex [[texture(0)]],
    texture2d<float> arTex     [[texture(1)]],
    texture2d<float> pbrTex    [[texture(2)]],
    texture3d<float> lutTex    [[texture(3)]],
    sampler s [[sampler(0)]]
)
{
    float2 uv = in.uv;

    float4 cam = cameraTex.sample(s, uv); // camera feed (opaque)
    float4 pbr = pbrTex.sample(s, uv);    // 3D render (alpha)
    float4 ar  = arTex.sample(s, uv);     // UI / indicators (alpha)

    // --- PBR over Camera ---
    float3 cam_pbr =
        pbr.rgb * pbr.a +
        cam.rgb * (1.0 - pbr.a);

    // --- AR over (Camera + PBR) ---
    float3 composited =
        ar.rgb * ar.a +
        cam_pbr * (1.0 - ar.a);

    // Final output is fully opaque
    
    return float4(composited, 1.0);
    
    //return float4(ar);
}
