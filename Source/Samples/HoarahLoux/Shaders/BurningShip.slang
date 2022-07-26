

#include "Include/GLSLDefines.slangh"

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
layout(binding = 1) texture2D iPass0Output : register(t0);

#define MAX_BOUNCES 5
#define INTER_THRESHOLD .001
#define PI 3.1415926535
#define EPSILON 			0.0001 


#include "Include/Randoms.slangh"

// returns (a+bi) * (c+di)
vec2 complexMul(float a, float b, float c, float d)
{
    return vec2(a*c - b*d, a*d + b*c);
}

vec2 complexMul(vec2 a, vec2 b)
{
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

vec2 complexSqr(vec2 a)
{
    return  vec2(a.x * a.x - a.y * a.y, 2.0 * a.x * a.y);
}

// returns (a+bi) / (c+di)
// (ac+bd)/(c^2+d^2) + (bc-ad)/(c^2+d^2)i
vec2 complexDiv(float a, float b, float c, float d)
{
    return vec2((a * c + b * d) / (c * c + d * d),
        (b * c - a * d) / (c * c + d * d));
}

vec2 complexDiv(vec2 a, vec2 b)
{
    return vec2((a.x * b.x + a.y * b.y) / (b.x * b.x + b.y * b.y),
        (a.y * b.x - a.x * b.y) / (b.x * b.x + b.y * b.y));
}

#define BURNINGSHIP_MAX_ITER 1024.
#define BAILOUT 16.
// zn+1 = (|Re(zn)|+i|Im(zn)|)^2 + c
float burningShip(vec2 p)
{
    vec2 c = .1 * p - vec2(1.74, 0.035);
    vec2 z = vec2(0);

    float i = 0.;
    for (;i <= BURNINGSHIP_MAX_ITER; i+=1.)
    {
        z = abs(z);
        z = complexSqr(z) + c;
        if (dot(z, z) > BAILOUT)
        {
            break;
        }
    }

   return i - log(log(length(z))) / log(2.);

    //return i - log(log(dot(z, z)) / log(2.)) / log(2.);
}


#define SAMPLES 8.

vec4 mainImage(vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;

    //vec2 p = uv * 2. - 1.;
    //p.x *= iResolution.x / iResolution.y;

    vec3 col = vec3(0);

    for (float i = 0.; i < SAMPLES; i++) {
        vec2 p = 0.5 * (2. * fragCoord - iResolution.xy + hash21(float(i*17))) / iResolution.y;
        float orbit = burningShip(p) / BURNINGSHIP_MAX_ITER;
        col += vec3(orbit);
    }

    col /= SAMPLES;

    //float d = burningShip(p);
    //d = smoothstep(0.1, 0.82, d);

    //vec3 col = vec3(d*0.01);


    return vec4(col, 1.);
}

float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    return mainImage(texC * iResolution);
}
