



#include "Include/GLSLDefines.slangh"
#include "Include/Randoms.slangh"

// copy the code here instead
//#include "Include/NoiseFunctions.slangh"

// useful reference:  https://www.shadertoy.com/view/4sfGzS


cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;
};


vec2 grad(vec2 n) { return sin(n.x * n.y * vec2(12, 17) + vec2(1, 2)); }

// wave noise
float noise(vec2 p)
{
    const float kF = 8.0;  // make 6 to see worms

    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(sin(kF * dot(p, grad(i + vec2(0, 0)))),
        sin(kF * dot(p, grad(i + vec2(1, 0)))), f.x),
        mix(sin(kF * dot(p, grad(i + vec2(0, 1)))),
            sin(kF * dot(p, grad(i + vec2(1, 1)))), f.x), f.y);
}


float fbm(vec2 p)
{
    float f = 0.0;
    mat2 m = mat2(1.6, 1.2, -1.2, 1.6);

    // convert back when in glsl

    /*f = 0.5000 * noise(p); p = m * p;
    f += 0.2500 * noise(p); p = m * p;
    f += 0.1250 * noise(p); p = m * p;
    f += 0.0625 * noise(p); p = m * p;*/

    f = 0.5000 * noise(p); p = mul(p, m);
    f += 0.2500 * noise(p); p = mul(p, m);
    f += 0.1250 * noise(p); p = mul(p, m);
    f += 0.0625 * noise(p); p = mul(p, m);
    return f;
}

// basic truchet
vec4 mainImage(vec2 fragCoord)
{
    vec2 p = fragCoord / iResolution.xy;

    vec2 uv = p * vec2(iResolution.x / iResolution.y, 1.0) + iGlobalTime * 0.25;

    float f = 0.0;

    // left: noise	
    if (p.x < 0.5)
    {
        f = noise(32.0 * uv);
    }
    // right: fractal noise (4 octaves)
    else
    {
        uv *= 8.0;
        f = fbm(uv);
    }
    f = 0.5 + 0.5 * f;

    f *= smoothstep(0.0, 0.005, abs(p.x - 0.5));

    return vec4(f, f, f, 1.0);
}

float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    return mainImage(texC * iResolution);
}

