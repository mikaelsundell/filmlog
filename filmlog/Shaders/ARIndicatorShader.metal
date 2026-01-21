#include <metal_stdlib>
using namespace metal;

struct IndicatorUniforms {
    float4x4 modelViewProjectionMatrix;
    float    time;
    float    radius;
    float    thickness;
    float3   color;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];  // ignored
    float2 uv       [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut indicatorVS(VertexIn in [[stage_in]],
                            constant IndicatorUniforms& uni [[buffer(10)]])
{
    VertexOut out;
    out.position = uni.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.uv = in.uv;
    return out;
}

fragment float4 indicatorFS(VertexOut in               [[stage_in]],
                             constant IndicatorUniforms& uni [[buffer(10)]])
{
    float2 uv = in.uv * 2.0 - 1.0;
    float r = length(uv);
    float pulse = abs(sin(uni.time * 2.0));
    float radius = mix(uni.radius * 0.5,
                       uni.radius * 1.0,
                       pulse);

    float halfThickness = uni.thickness * 0.5;
    float inner = radius - halfThickness;
    float outer = radius + halfThickness;
    
    float innerEdge = smoothstep(inner - 0.01, inner, r);
    float outerEdge = 1.0 - smoothstep(outer, outer + 0.01, r);
    float alpha = innerEdge * outerEdge;

    if (alpha <= 0.001)
        discard_fragment();

    return float4(uni.color, alpha);
}

