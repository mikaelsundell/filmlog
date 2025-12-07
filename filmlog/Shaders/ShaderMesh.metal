#include <metal_stdlib>
#include "ShaderLut.metal"
using namespace metal;

struct ModelUniforms {
    float4x4 mvp;
    float3x3 normalMatrix;
};

struct VSIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct VSOut {
    float4 position [[position]];
    float3 normalW;
    float4 color;
};

vertex VSOut modelVS(VSIn in [[stage_in]],
                     constant ModelUniforms& U [[buffer(10)]])
{
    VSOut out;
    out.position = U.mvp * float4(in.position, 1.0);
    out.normalW = normalize(U.normalMatrix * in.normal);
    out.color = in.color;
    return out;
}

fragment float4 modelFS(VSOut in [[stage_in]],
                        texture3d<float> lutTex [[texture(2)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    
    float3 L = normalize(float3(0.4, 0.8, 0.3));
    float N = max(dot(in.normalW, L), 0.0);
    float3 litColor = in.color.rgb * (0.3 + 0.7 * N);
    return float4(litColor, 1.0);
}
