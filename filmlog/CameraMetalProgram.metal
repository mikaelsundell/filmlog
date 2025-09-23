#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    packed_float2 viewSize;
    packed_float2 videoSize;
    int isCapture;
};

struct VSOut {
    float4 pos [[position]];
    float2 uv;
};

vertex VSOut fullscreenVS(uint vid [[vertex_id]],
                          const device float4* verts [[buffer(0)]],
                          constant Uniforms& U [[buffer(1)]])
{
    VSOut o;
    float4 v = verts[vid];

    float2 position = v.xy;
    float2 texCoord = v.zw;

    if (U.isCapture) {
        texCoord = float2(texCoord.x, texCoord.y);
        o.uv = texCoord;
    } else {
        float viewRatio = U.viewSize.y / U.viewSize.x; // to native
        float videoRatio = U.videoSize.x / U.videoSize.y;
        float scaleX = videoRatio / viewRatio;
        texCoord = (texCoord - 0.5) * float2(scaleX, 1.0) + 0.5;
        texCoord = float2(texCoord.y, 1.0 - texCoord.x); // portrait
        o.uv = texCoord;
    }

    o.pos = float4(position, 0.0, 1.0);
    return o;
}

// rec.709 Y'CbCr (full-range) - RGB
inline float3 ycbcr709_to_rgb(float y, float cb, float cr) {
    float r = y + 1.5748 * (cr - 0.5);
    float g = y - 0.1873 * (cb - 0.5) - 0.4681 * (cr - 0.5);
    float b = y + 1.8556 * (cb - 0.5);
    return float3(r, g, b);
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

#define USE_TETRA_HIGH_PRECISION 0
fragment float4 nv12ToLinear709FS(VSOut in [[stage_in]],
                                  texture2d<float> yTex   [[texture(0)]],
                                  texture2d<float> uvTex  [[texture(1)]],
                                  texture3d<float> lutTex [[texture(2)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float  y  = yTex.sample(s, in.uv).r;
    float2 uv = uvTex.sample(s, in.uv).rg;
    float3 color = float3(y, uv.x, uv.y);

#if USE_TETRA_HIGH_PRECISION
    // lut: input rec.709 - look - output linear, colorspace rec.709
    float3 lutColor = tetra_high_precision(lutTex, color, s);
#else
    float3 lutColor = tetra_optimized(lutTex, color, s);
#endif
    return float4(lutColor, 1.0);
}
