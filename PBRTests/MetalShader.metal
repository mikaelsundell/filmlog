// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

#include <metal_stdlib>
using namespace metal;

struct ModelUniforms {
    float4x4 modelMatrix;
    float4x4 mvp;
    float3x3 normalMatrix;
    float3   worldPosition;
    float    _pad0;
};

struct BlurUniforms {
    float2 direction;
    float  radius;
    float  _pad;
};

struct PBRFragmentUniforms {
    float4 baseColorFactor;
    float  metallicFactor;
    float  roughnessFactor;
    uint   hasBaseColorTexture;
    uint   hasMetallicTexture;
    uint   hasRoughnessTexture;
    uint   hasNormalTexture;
};

struct PBRShaderControls {
    float keyIntensity;
    float ambientIntensity;
    float specularIntensity;
    float roughnessBias;
};

struct ShadowDepthUniforms {
    float4x4 lightMVP;
};

struct GroundUniforms {
    float4x4 mvp;
    float4x4 modelMatrix;
    float4x4 lightVP;
    float4   baseColor;
    float    shadowStrength;
    float    maxHeight;
    float3   cameraWorldPos;
    float3   _pad0;
};

struct FullscreenVSOut {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenVSOut fullscreenVS(uint vid [[vertex_id]])
{
    float2 pos[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0),
        float2(-1.0,  1.0)
    };

    FullscreenVSOut out;
    out.position = float4(pos[vid], 0.0, 1.0);
    out.uv = pos[vid] * 0.5 + 0.5;
    return out;
}

struct VSIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 tangent  [[attribute(2)]];
    float2 uv       [[attribute(3)]];
};

struct VSOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normalW;
    float3 tangentW;
    float3 bitangentW;
    float2 uv;
};

vertex VSOut modelPBRVS(
    VSIn in [[stage_in]],
    constant ModelUniforms& U [[buffer(10)]]
) {
    VSOut out;
    out.position = U.mvp * float4(in.position, 1.0);
    out.worldPos = (U.modelMatrix * float4(in.position, 1.0)).xyz;

    float3 N = normalize(U.normalMatrix * in.normal);
    float3 T = normalize(U.normalMatrix * in.tangent.xyz);
    float3 B = normalize(cross(N, T) * in.tangent.w);

    out.normalW    = N;
    out.tangentW   = T;
    out.bitangentW = B;
    out.uv         = in.uv;
    return out;
}

float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a  = roughness * roughness;
    float a2 = a * a;
    float NdotH  = max(dot(N, H), 0.0);
    float denom = (NdotH * NdotH * (a2 - 1.0) + 1.0);
    return a2 / max(3.14159265 * denom * denom, 1e-4);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / max(NdotV * (1.0 - k) + k, 1e-4);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    return GeometrySchlickGGX(max(dot(N, V), 0.0), roughness) *
           GeometrySchlickGGX(max(dot(N, L), 0.0), roughness);
}

float3 fresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fragment float4 modelPBRFS(
    VSOut in [[stage_in]],
    constant ModelUniforms& U [[buffer(10)]],
    constant PBRFragmentUniforms& P [[buffer(0)]],
    constant PBRShaderControls& C [[buffer(1)]],
    texture2d<float> baseColorTex  [[texture(0)]],
    texture2d<float> metallicTex   [[texture(1)]],
    texture2d<float> roughnessTex  [[texture(2)]],
    texture2d<float> normalTex     [[texture(3)]],
    texturecube<float> environmentTex [[texture(9)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float3 albedo = P.baseColorFactor.rgb;
    if (P.hasBaseColorTexture != 0 && baseColorTex.get_width() > 0) {
        float3 texColor = baseColorTex.sample(s, uv).rgb;
        texColor = pow(texColor, float3(2.2));
        albedo *= texColor;
    }

    float metallic = P.metallicFactor;
    if (P.hasMetallicTexture != 0)
        metallic *= metallicTex.sample(s, uv).r;

    float roughness = P.roughnessFactor;
    if (P.hasRoughnessTexture != 0)
        roughness *= roughnessTex.sample(s, uv).g;

    roughness = clamp(roughness + C.roughnessBias, 0.04, 1.0);

    float3 N = normalize(in.normalW);
    if (P.hasNormalTexture != 0 && normalTex.get_width() > 0) {
        float3 nTS = normalTex.sample(s, uv).xyz * 2.0 - 1.0;
        float3x3 TBN = float3x3(
            normalize(in.tangentW),
            normalize(in.bitangentW),
            normalize(in.normalW)
        );
        N = normalize(TBN * nTS);
    }

    float3 V = normalize(U.worldPosition - in.worldPos);
    float3 L = normalize(V);
    float3 H = normalize(V + L);

    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);

    float3 F0 = mix(float3(0.04), albedo, metallic);
    float3 F  = fresnelSchlick(max(dot(H, V), 0.0), F0);
    float  D  = DistributionGGX(N, H, roughness);
    float  G  = GeometrySmith(N, V, L, roughness);

    float3 specular = (D * G * F) / max(4.0 * NdotL * NdotV, 1e-4);
    specular *= C.specularIntensity;

    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float3 diffuse = (albedo / 3.14159265) * NdotL;

    float3 Lo = (kD * diffuse + specular) * NdotL;
    Lo *= C.keyIntensity;

    float3 R = reflect(-V, N);
    float mip = roughness * float(environmentTex.get_num_mip_levels() - 1);
    float3 envSpec = environmentTex.sample(s, R, level(mip)).rgb;

    float3 ambient =
        (0.03 * albedo + envSpec * (0.2 + 0.8 * metallic))
        * C.ambientIntensity;

    float3 color = ambient + Lo;
    color = color / (color + 1.0);
    return float4(color, P.baseColorFactor.a);
}

struct ShadowDepthOut { float4 pos [[position]]; };

vertex ShadowDepthOut shadowDepthVS(
    VSIn in [[stage_in]],
    constant ShadowDepthUniforms& S [[buffer(1)]]
) {
    ShadowDepthOut o;
    o.pos = S.lightMVP * float4(in.position, 1.0);
    return o;
}

fragment void shadowDepthFS() {}

struct GroundVSOut {
    float4 pos [[position]];
    float4 worldPos;
    float4 lightPos;
};

vertex GroundVSOut groundVS(
    uint vid [[vertex_id]],
    const device float3* verts [[buffer(0)]],
    constant GroundUniforms& G [[buffer(1)]]
) {
    GroundVSOut o;
    float3 p = verts[vid];
    float4 wp = G.modelMatrix * float4(p, 1.0);
    o.pos      = G.mvp * float4(p, 1.0);
    o.worldPos = wp;
    o.lightPos = G.lightVP * wp;
    return o;
}

fragment float contactShadowMaskFS(
    GroundVSOut in [[stage_in]],
    constant GroundUniforms& G [[buffer(1)]],
    depth2d<float> heightMap [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float3 ndc = in.lightPos.xyz / max(in.lightPos.w, 1e-6);
    float2 uv  = ndc.xy * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;

    if (any(uv < 0.0) || any(uv > 1.0))
        return 0.0;

    float d = heightMap.sample(s, uv);
    return saturate(1.0 - d);
}

fragment float blurFS(
    FullscreenVSOut in [[stage_in]],
    constant BlurUniforms& B [[buffer(0)]],
    texture2d<float> src [[texture(0)]],
    sampler s [[sampler(0)]]
){
    float2 texel = B.direction / float2(src.get_width(), src.get_height());

    float w0 = 0.227027;
    float w1 = 0.316216;
    float w2 = 0.070270;
    float2 uv = in.uv;
    float sum = src.sample(s, uv).r * w0;
    sum += src.sample(s, uv + texel * 1.3846 * B.radius).r * w1;
    sum += src.sample(s, uv - texel * 1.3846 * B.radius).r * w1;
    sum += src.sample(s, uv + texel * 3.2308 * B.radius).r * w2;
    sum += src.sample(s, uv - texel * 3.2308 * B.radius).r * w2;

    return sum;
}

fragment float4 groundFS(
    GroundVSOut in [[stage_in]],
    constant GroundUniforms& G [[buffer(1)]],
    texture2d<float> shadowMask [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float3 viewDir = normalize(G.cameraWorldPos - in.worldPos.xyz);
    float3 planeNormalW = float3(0.0, 0.0, 1.0);

    if (dot(planeNormalW, viewDir) <= 0.0)
        discard_fragment();
    
    float3 ndc = in.lightPos.xyz / max(in.lightPos.w, 1e-6);
    float2 uv  = ndc.xy * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;

    if (any(uv < 0.0) || any(uv > 1.0))
        discard_fragment();

    float alpha = shadowMask.sample(s, uv).r;
    alpha = alpha * 0.5;
    
    return float4(0.0, 0.0, 0.0, alpha);
}
