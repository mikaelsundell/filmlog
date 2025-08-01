#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 viewSize;
    float2 videoSize;
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

    float viewRatio = U.viewSize.y / U.viewSize.x; // to native
    float videoRatio = U.videoSize.x / U.videoSize.y;
    float scaleX = videoRatio / viewRatio;

    texCoord = (texCoord - 0.5) * float2(scaleX, 1.0) + 0.5;
    texCoord = float2(texCoord.y, 1.0 - texCoord.x); // to potrait

    o.pos = float4(position, 0.0, 1.0);
    o.uv = texCoord;
    return o;
}

// Rec.709 Y'CbCr (full-range) (to RGB)
inline float3 ycbcr709_to_rgb(float y, float cb, float cr) {
    float r = y + 1.5748 * (cr - 0.5);
    float g = y - 0.1873 * (cb - 0.5) - 0.4681 * (cr - 0.5);
    float b = y + 1.8556 * (cb - 0.5);
    return float3(r, g, b);
}

// Inverse Rec.709 OETF (to linear)
inline float inv_oetf_709(float v) {
    return (v < 0.081f) ? (v / 4.5f) : pow((v + 0.099f) / 1.099f, 1.0f / 0.45f);
}

fragment float4 nv12ToLinear709FS(VSOut in [[stage_in]],
                                  texture2d<float> yTex   [[texture(0)]],
                                  texture2d<float> uvTex  [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float  y  = yTex.sample(s, in.uv).r;     // 0..1
    float2 uv = uvTex.sample(s, in.uv).rg;   // Cb,Cr interleaved

    float3 rgb709 = ycbcr709_to_rgb(y, uv.x, uv.y);
    float3 rgbLin = float3(inv_oetf_709(rgb709.r),
                           inv_oetf_709(rgb709.g),
                           inv_oetf_709(rgb709.b));

    // Return linear to an sRGB view; the store will handle encoding.
    float3 disp = clamp(rgbLin, 0.0f, 1.0f);

    return float4(disp, 1.0);
}
