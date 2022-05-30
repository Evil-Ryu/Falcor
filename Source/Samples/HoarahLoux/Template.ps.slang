#define vec4 float4
#define vec3 float3
#define vec2 float2
#define mix lerp

cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;
};

layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D iChannel0 : register(t0);

vec4 mainImage(vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.y;
    vec2 p = uv * 2. - 1.;
    //svec3 col = vec3(sin(iGlobalTime* .1), cos(iGlobalTime * .5), length(p));
    float d = mix(1., 0., uv.x);
    vec3 col = iChannel0.Sample(iChannel0Sampler, uv).xyz;
    return vec4(col,1.);
}

vec4 main(vec2 texC : TEXCOORD) : SV_TARGET
{
    return mainImage(texC * iResolution);
}
