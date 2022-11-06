



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

vec2 hash(vec2 p) // can't use the better hash from dave for simplex noise
{
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}
float noise(vec2 p)
{
    const float K1 = 0.366025404; // (sqrt(3)-1)/2;
    const float K2 = 0.211324865; // (3-sqrt(3))/6;

    vec2  i = floor(p + (p.x + p.y) * K1);
    vec2  a = p - i + (i.x + i.y) * K2;
    float m = step(a.y, a.x);
    vec2  o = vec2(m, 1.0 - m);
    vec2  b = a - o + K2;
    vec2  c = a - 1.0 + 2.0 * K2;
    vec3  h = max(0.5 - vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
    vec3  n = h * h * h * h * vec3(dot(a, hash(i + 0.0)), dot(b, hash(i + o)), dot(c, hash(i + 1.0)));
    return dot(n, vec3(70.0));
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

