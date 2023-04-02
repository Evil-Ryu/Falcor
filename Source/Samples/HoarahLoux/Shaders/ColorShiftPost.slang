#define vec4 float4
#define vec3 float3
#define vec2 float2
#define ivec2 int2
#define ivec3 int3
#define ivec4 int4
#define uvec2 uint2
#define uvec3 uint3
#define uvec4 uint4

#define mix lerp
#define fract frac
#define mat3 float3x3
#define mat2 float2x2


cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;
    float iFrame;
    float iCameraDirty;
};

layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D iPass0Output : register(t0);

vec3 ca(vec2 u) {
    const int n = 10;
    vec3 c = vec3(0);
    float rf = 1., gf = 1., bf = 1.;
    for (int i = 0; i < n; ++i) {
        c.r += iPass0Output.Sample(iChannel0Sampler, .5 + .5 * (u * rf)).r;
        c.g += iPass0Output.Sample(iChannel0Sampler, .5 + .5 * (u * gf)).g;
        c.b += iPass0Output.Sample(iChannel0Sampler, .5 + .5 * (u * bf)).b;
        rf *= .9988;
        gf *= .9982;
        bf *= .996;
    }
    return c / float(n);
}
void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 c = fragCoord.xy / iResolution.xy;
    //if (c.y > .13 && c.y < .87)
    vec3 col = ca(-1. + 2. * c);
    col = pow(col, vec3(.45));
    fragColor.xyz = col;
}


float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    vec4 fragColor;
    mainImage(fragColor, texC * iResolution);
    return fragColor;
}
