#include <metal_stdlib>
using namespace metal;

struct ModelUniforms {
    float4x4 modelMatrix;
    float4x4 mvp;
    float3x3 normalMatrix;
    float3   cameraWorldPos;
    float    _pad0; // 16-byte alignment
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

struct VSIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 tangent  [[attribute(2)]]; // xyz = tangent, w = handedness
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

vertex VSOut modelPBRVS_UVDebug(
    VSIn in [[stage_in]],
    constant ModelUniforms& U [[buffer(10)]]
) {
    VSOut out;
    out.position = U.mvp * float4(in.position, 1.0);
    out.worldPos = (U.modelMatrix * float4(in.position, 1.0)).xyz;
    out.normalW  = normalize(U.normalMatrix * in.normal);
    out.tangentW = float3(1,0,0);
    out.bitangentW = float3(0,1,0);
    out.uv = in.uv;
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
    texture2d<float> baseColorTex  [[texture(0)]],
    texture2d<float> metallicTex   [[texture(1)]],
    texture2d<float> roughnessTex  [[texture(2)]],
    texture2d<float> normalTex     [[texture(3)]],
    texturecube<float> environmentTex [[texture(9)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);

    // --- Base color ---
    /*
    float3 albedo = P.baseColorFactor.rgb;
    if (P.hasBaseColorTexture != 0 && baseColorTex.get_width() > 0) {
        albedo *= baseColorTex.sample(s, uv).rgb;
    }*/
    
    float3 albedo = P.baseColorFactor.rgb;

    if (P.hasBaseColorTexture != 0 && baseColorTex.get_width() > 0) {
        float3 texColor = baseColorTex.sample(s, uv).rgb;

        // Explicit sRGB → linear decode
        texColor = pow(texColor, float3(2.2));

        albedo *= texColor;
    }
    
    
    

    
    
    // --- Metallic / roughness ---
    float metallic = P.metallicFactor;
    if (P.hasMetallicTexture != 0)
        metallic *= metallicTex.sample(s, uv).r;

    float roughness = clamp(P.roughnessFactor, 0.04, 1.0);
    if (P.hasRoughnessTexture != 0)
        roughness = clamp(roughness * roughnessTex.sample(s, uv).g, 0.04, 1.0);

    // --- Normal mapping (TBN) ---
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

    // --- Lighting vectors ---
    float3 V = normalize(U.cameraWorldPos - in.worldPos);
    
    //float3 L = normalize(float3(0.4, 0.8, 0.3));
    //float3 L = normalize(float3(0.0, 0.6, 0.8));
    
    float3 L = normalize(V);
    
    float3 H = normalize(V + L);

    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);

    // --- BRDF ---
    float3 F0 = mix(float3(0.04), albedo, metallic);
    float3 F  = fresnelSchlick(max(dot(H, V), 0.0), F0);
    float  D  = DistributionGGX(N, H, roughness);
    float  G  = GeometrySmith(N, V, L, roughness);

    float3 specular = (D * G * F) / max(4.0 * NdotL * NdotV, 1e-4);

    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float3 diffuse = (albedo / 3.14159265) * NdotL;

    float3 Lo = (kD * diffuse + specular) * NdotL;

    // --- Environment reflection ---
    float3 R = reflect(-V, N);
    float mip = roughness * float(environmentTex.get_num_mip_levels() - 1);
    float3 envSpec = environmentTex.sample(s, R, level(mip)).rgb;

    float3 ambient = 0.03 * albedo + envSpec * (0.2 + 0.8 * metallic);

    float3 color = ambient + Lo;

    // --- Tone mapping + gamma ---
    color = color / (color + 1.0);
    //color = pow(color, float3(1.0 / 2.2));

    return float4(color, P.baseColorFactor.a);
}

fragment float4 modelPBRFS_UVDebug(
    VSOut in [[stage_in]]
) {
    return float4(in.uv, 0.0, 1.0);
}
