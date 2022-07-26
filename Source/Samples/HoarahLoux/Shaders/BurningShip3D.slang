
#include "Include/GLSLDefines.slangh"


cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;

    float3 RayOrigin;
    float3 RayTarget;
};

#include "Include/Randoms.slangh"

// returns (a+bi) * (c+di)
vec2 complexMul(float a, float b, float c, float d)
{
    return vec2(a * c - b * d, a * d + b * c);
}

vec2 complexMul(vec2 a, vec2 b)
{
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// returns (a+bi+cj) * (d + ei + fj)
vec3 triplexMul(vec3 a, vec3 b)
{
    a = abs(a); b = abs(b);
    float ra = length(a.xy);
    float rb = length(b.xy);

    vec2 newXY = complexMul(a.xy / ra, b.xy / rb);
    vec2 newRZ = complexMul(vec2(ra, a.z), vec2(rb, b.z));

    newXY = newXY * newRZ.x;

    return vec3(newXY.x, newXY.y, newRZ.y);
}

vec3 triplexPow(vec3 z, float power)
{
    z = abs(z);
    float r = length(z);
    float a = asin(z.z / r) * power;
    float b = atan(z.y / z.x) * power;
    z = pow(r, power) * vec3(cos(a)*cos(b), cos(a)*sin(b), sin(a));
    return z;
}

static bool isJulia = true;
static vec3 juliaC = vec3(-1.81984, -0.006, -0.00684);
static float  bailOut = 2.;
float mapBurningShip(vec3 p, float power)
{
    vec3 eps = vec3(exp2(-18. + max(0., floor(log2(length(p))))), 0., 0.);

    vec3 p2 = p + eps.xyz, p3 = p + eps.yxz, p4 = p + eps.yzx;
    vec3 z = p, z2 = p2, z3 = p3, z4 = p4;

    int i = 0;
    float r = length(z);

    for (; i < 20; ++i)
    {
        if (r >= bailOut)
            break;

        z = triplexPow(z, power);
        z += mix(p, juliaC, isJulia);

        z2 = triplexPow(z2, power);
        z2 += mix(p2, juliaC, isJulia);

        z3 = triplexPow(z3, power);
        z3 += mix(p3, juliaC, isJulia);

        z4 = triplexPow(z4, power);
        z4 += mix(p4, juliaC, isJulia);

        r = length(z);
    }

    float dx = length(z2 - z),
        dy = length(z3 - z),
        dz = length(z4 - z);
    float dr = length(vec3(dx, dy, dz) / eps.x);

    return .5 * log(r) * r / dr;
}

float map(vec3 p)
{
    float d1 = mapBurningShip(p, 2.);
    float d2 = abs(p.y + .9);
    float d = d1;
    float id = 0.;

    //if (d2 < d) { d = d2; id = 1.; }

    return d;
}

vec3 getNormal(vec3 p)
{
    vec3 eps = vec3(0.001, 0, 0);

    return normalize(vec3(map(p + eps.xzy) - map(p - eps.xyz),
        map(p + eps.yxz) - map(p - eps.yxz),
        map(p + eps.zyx) - map(p - eps.zyx)));
}

float intersect(vec3 ro, vec3 rd)
{
    float d = 10., t = 0.1;

    for (int i = 0; i < 128; ++i)
    {
        if (d < 0.0001 || t > 100.)
        {
            break;
        }

        d = map(ro + t * rd);
        t += d;
    }

    return t;
}

vec3 scene(vec3 p)
{
    vec3 l = normalize(vec3(1., 1., -2.));

    vec3 n = getNormal(p);

    float dif = max(0., dot(n, l));

    vec3 col = 2. * dif * vec3(1);


    return col;
}

// basic truchet
vec4 mainImage(vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution;
    vec2 p = uv * 2. - 1.;

    p.x *= iResolution.x / iResolution.y;


    // note falcor's camera is right handed, so we need reverse x
    vec3 ro = vec3(-RayOrigin.x, RayOrigin.y, RayOrigin.z);
    vec3 ta = RayTarget;

    vec3 forward = normalize(RayTarget - RayOrigin);
    vec3 right = normalize(cross(vec3(0, 1, 0), forward));
    vec3 up = normalize(cross(forward, right));

    vec3 rd = normalize(mul(float3x3(right, up, forward), vec3(p.x, p.y, 1.8)));

    float t = intersect(ro, rd);

    vec3 col = vec3(0., 1., 0.);

    if (t < 100.)
    {
        vec3 pos = ro + t * rd;
        col = scene(pos);
    }

    return vec4(col, 1.);
}

float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    return mainImage(texC * iResolution);
}
