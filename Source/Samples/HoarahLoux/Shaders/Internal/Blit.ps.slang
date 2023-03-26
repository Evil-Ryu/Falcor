
cbuffer CB
{
    float2 iResolution;
};

layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D iChannel0 : register(t0);

float4 main(float2 texC: TEXCOORD) : SV_TARGET
{
    return iChannel0.Load(float3(texC * iResolution, 0), 0);
    //return iChannel0.Sample(iChannel0Sampler, texC);
}
