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

vertex VSOut cameraVS(uint vid [[vertex_id]],
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

fragment float4 cameraFS(
    VSOut in [[stage_in]],
    texture2d<float> yTex  [[texture(0)]],
    texture2d<float> uvTex [[texture(1)]]
)
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float  y  = yTex.sample(s, in.uv).r;
    float2 uv = uvTex.sample(s, in.uv).rg;

    float3 rgb = ycbcr709_to_rgb(y, uv.x, uv.y);
    rgb = saturate(rgb);

    return float4(rgb, 1.0);
    
    //return float4(0.0, 0.0, 1.0, 1.0);
}
