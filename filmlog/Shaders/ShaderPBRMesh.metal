#include <metal_stdlib>
using namespace metal;

struct ModelUniforms {
    float4x4 mvp;
    float3x3 normalMatrix;
};

struct VSIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float3 normalW;
};

vertex VSOut modelPBRVS(VSIn in [[stage_in]],
                     constant ModelUniforms& U [[buffer(10)]])
{
    VSOut out;
    out.position = U.mvp * float4(in.position, 1.0);
    out.normalW = normalize(U.normalMatrix * in.normal);
    return out;
}

fragment float4 modelPBRFS(VSOut in [[stage_in]])
{
    float3 L = normalize(float3(0.4, 0.8, 0.3));
    float N = max(dot(in.normalW, L), 0.0);

    float3 baseColor = float3(0.8, 0.8, 0.8);   // temporary flat PBR base color
    float3 lit = baseColor * (0.2 + 0.8 * N);

    return float4(lit, 1.0);
}
