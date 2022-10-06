#include "Include/GLSLDefines.slangh"



cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;

    float3 RayOrigin;
    float3 RayTarget;
};


#include "Include/Randoms.slangh"


float map(vec3 p)
{
    float d1 = length(p) - 1.;
    float d2 = abs(p.y + 1.1);

    float d = d2, id = 0.;

    if (d1 < d2) { d = d1; id = 1.; }

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
        if (d < 0.002 || t > 100.)
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
    vec3 right = normalize(cross(vec3(0,1,0), forward));
    vec3 up = normalize(cross(forward, right));

    vec3 rd = normalize(mul(float3x3(right, up, forward), vec3(p.x, p.y, 1.8)));

    float t = intersect(ro, rd);

    vec3 col = vec3(0., 0.5, 1.);

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
