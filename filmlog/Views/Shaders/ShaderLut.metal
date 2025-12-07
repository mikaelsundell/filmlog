// LUTShared.metal
#pragma once
#include <metal_stdlib>
using namespace metal;


inline float3 tetra_optimizedX(texture3d<float> lutTex, float3 color, sampler s) {
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
