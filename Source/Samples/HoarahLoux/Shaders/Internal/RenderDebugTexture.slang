
#include "../Include/GLSLDefines.slangh"

cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;
    float iFrame;
    float iCameraDirty;
    float iMaxSPP;

    float3 RayOrigin;
    float3 RayTarget;
    float3 UpVector;
};


layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D debugTexture : register(t0);


vec3 mapToDebugColor(float val)
{
    vec3 col = vec3(0.);
    if (val <= 0.)
        col = vec3(1., 0., 1.);

    else if (val > 0. && val < 0.5)
        col = vec3(0., 0., .5);

    else if (val >= 0.5 && val < 1.)
        col = vec3(0., 0., 1.);

    else if (val >= 1. && val < 2.)
        col = vec3(0., 0.5, 0.);

    else if (val >= 2. && val < 3.)
        col = vec3(0., 1., 0.);

    else if (val >= 3. && val < 4.)
        col = vec3(.5, .5, 0.);

    else if (val >= 4. && val < 5.)
        col = vec3(1., 1., 0.);

    else col = vec3(.5, 0., 0.);
    return col;
}


float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    vec2 fragCoord = texC * iResolution;
    return debugTexture.Load(int3(fragCoord, 0));
}
