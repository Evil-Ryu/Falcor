#define vec4 float4
#define vec3 float3
#define vec2 float2
#define mix lerp
#define fract frac


cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;
    float iFrame;
    float iCameraDirty;
};

layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D iPass0Output : register(t0);


vec3 tonemap(vec3 x)
{
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}


vec4 mainImage(vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution;

    vec3 col = iPass0Output.Load(vec3(fragCoord, 0)).xyz;
    /*if (iFrame > 0.)
    {
        vec4 prevCol = iPass0Output.Load(vec3(fragCoord,0));
        col = prevCol.xyz;
        if(iCameraDirty == 0.)
            col /= prevCol.w;
    }*/


    col = tonemap(col);

    col = pow(col, vec3(0.45));


    col = col * 0.6 + 0.4 * col * col * (3.0 - 2.0 * col);  // contrast

    col = col * 0.6 + 0.4 * col * col * (3.0 - 2.0 * col);  // contrast
    //col = col * 0.6 + 0.4 * col * col * (3.0 - 2.0 * col);  // contrast
    //col = mix(col, vec3(dot(col, vec3(0.33))), 0.5);  // de-satuation
    col *= 0.5 + 0.5 * pow(16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y), 0.1);

    return vec4(col, 1.);
}

float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    return mainImage(texC * iResolution);
}
