

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
#define INTER_THRESHOLD .0001
#define PI 3.1415926535
#define EPSILON 			0.0001 


#include "Include/SDF-MandelBox.slangh"
//#include "Include/SDF-BurningShip3D.slangh"
#include "Include/Randoms.slangh"
#include "Include/Sampling.slangh"
#include "Include/Materials.slangh"
#include "Include/SDF-BasicShapes.slangh"


static float seed;

PhongMaterial getPhongMaterial(float id)
{
    PhongMaterial mat;
    mat.albedo = vec3(1., 0., 1.);
    mat.specularCol = vec3(1., 0., 1.);
    mat.shininess = 16.;
    mat.roughness = .5;
    mat.F0 = 0.03;

    if (id == 0.)
    {
        mat.albedo = vec3(.99, .99, .99);
        mat.specularCol = vec3(1);
        mat.roughness = .9;
    }
    else if (id == 1.)
    {
        mat.albedo = vec3(.2, 1., .1);
        mat.specularCol = vec3(1);
        mat.roughness = 0.2;
        mat.shininess = 64.;
    }
    else if (id == 2.)
    {
        mat.albedo = vec3(.8);
        mat.specularCol = vec3(1);
        mat.roughness = 0.5;
        mat.shininess = 64.;
    }
    return mat;
}



vec2 map(vec3 p)
{
    //float d1 = mapBurningShip(p, 2.);//mapMandelBox(p+vec3(1., -1.5, 0.));
    float d1 = mapMandelBox(p+vec3(1., -1.5, 0.));
    float d2 = length(p+vec3(-1.,0.,0.)) - 1.;
    float d3 = abs(p.y + .9);
    float d = d1;
    float id = 0.;

   // if (d2 < d) { d = d2; id = 1.; }
    //if (d3 < d) { d = d3; id = 2.; }

    return vec2(d, id);
}

vec3 getNormal(vec3 p)
{
    float t = 1.;
    vec3 n = vec3(0);
    for (int i = 0; i < 4; i++)
    {
        vec3 e = .5773 * (2. * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.);
        n += e * map(p + .001 * e * t).x;
    }
    return normalize(n);
}

vec2 intersect(vec3 ro, vec3 rd, float dist)
{
    float t = 0.0;
    vec2 res = vec2(10);

    for (int i = 0; i < 128; ++i)
    {
        if (res.x < INTER_THRESHOLD || t > dist)
        {
            break;
        }

        res = map(ro + t * rd);
        t += res.x;
    }

    return vec2(t, res.y);
}

// https://github.com/Syntopia/Fragmentarium/blob/master/Fragmentarium-Source/Examples/Include/Sunsky.frag
//static float sunSize = 0.53; //degree
static float sunSize = 10.;
static float sunAngularDiameterCos = cos(sunSize * PI / 180.0);
static vec3 sunCol = vec3(1.1, .8, .5) * 5.;
static vec3 skyCol = vec3(0.1, .5, 1.);
static vec3 sunDir = normalize(vec3(1., 1., -1.));


vec4 sampleLight(vec3 fromEye, vec3 pos, vec3 normal, float matid)
{
    vec3 col = vec3(0);
    float costheta = dot(sunDir, normal);
    if (costheta <= 0.)
        return vec4(col, 1.);

    vec3 rd = sunDir;// getConeSample(lightDir, 1. - sunAngularDiameterCos);
    float pdf = 1.f;

    if (pdf < EPSILON) return vec4(0);

    vec2 res = intersect(pos + (INTER_THRESHOLD * 2.) * normal, rd, 20.);

    if (res.x >= 20.)
    {
        PhongMaterial mat = getPhongMaterial(matid);
        col = costheta * sunCol * phongBrdf(rd, -fromEye, normal, pos, mat) / pdf;
    }

    return vec4(col, pdf);
}

// returns rd as the next event
vec4 sampleBrdf(vec3 fromEye, vec3 pos, vec3 normal, float matid, out vec3 rd, out vec3 brdf, out bool hit)
{
    float rnd = hash11(seed++);

    PhongMaterial mat = getPhongMaterial(matid);

    float pdf = 1.;

    if (rnd > mat.roughness)
    {
        //rd = normalize(getHemisphereSampleCosWeighted(normal, 1.), seed);
        rd = normalize(getHemisphereSampleCosWeighted(normal, seed));
        pdf = max(0., dot(rd, normal)) / PI;
    }
    else
    {
        rd = getPhoneSpecularSample(reflect(fromEye, normal), mat.shininess, seed);
        pdf = (mat.shininess + 1.) / (2.*PI) * pow(max(0., dot(rd, normal)), mat.shininess);
    }

    if (pdf < EPSILON) return vec4(0);

    vec3 lightCol = vec3(0), col = vec3(0);
    brdf = vec3(0.);

    vec2 res = intersect(pos + (INTER_THRESHOLD * 2.) * normal, rd, 20.);

    hit = true;
    // hit nothing, sample the infinite light
    if (res.x >= 20.)
    {
        lightCol = skyCol;
        if (max(0., dot(rd, sunDir)) > sunAngularDiameterCos)
            lightCol = sunCol;

        brdf = phongBrdf(rd, -fromEye, normal, pos, mat);
        col = max(0., dot(rd, normal)) * lightCol * brdf;
        col /= pdf;
        hit = false;
    }

    // TODO: if hit a physical light
    //if(res.y == )

    return vec4(col, pdf);
}

vec3 getDirectLightingMIS(vec3 fromEye, vec3 pos, vec3 normal, float matid, out vec3 rd, out vec3 brdf, out float brdfPdf, out bool hit)
{
    vec4 res1 = sampleLight(fromEye, pos, normal, matid);
    vec4 res2 = sampleBrdf(fromEye, pos, normal, matid, rd, brdf, hit);

    // combine with mis
    vec3 col = res1.xyz * misWeight(res1.w, res2.w) + res2.xyz * misWeight(res2.w, res1.w);

    brdfPdf = res2.w;

    return col;
}

vec3 getAlbedo(float id)
{
    if (id == 0.) { return vec3(.9, .9, .9); }
    else if (id == 1.) { return vec3(0.1, 1., 0.1); }
    else if (id == 2.) { return vec3(.5); }
    return vec3(0);
}


vec3 scene(vec3 ro, vec3 rd)
{
    vec3 pathWeight = vec3(1.);
    vec3 Lo = vec3(0);

    // only in hemisphere
    vec2 res;
    vec3 pos, n;

    // bounces
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        res = intersect(ro, rd, 100.);

        if (res.x >= 100.)
        {
            // indirect part
            // it has to finally hit a light or the sky to have color
            // or there will be only direct part
            Lo = Lo + pathWeight * skyCol;
            break;
        }

        pos = ro + res.x * rd;
        n = getNormal(pos);
        vec3 ord = rd;

        vec3 brdf;
        float brdfPdf;
        bool hit;
        // direct part, NEE, use MIS to optimize
        // returns the new rd for the next event and the brdf of the inirect part
        vec3 direct = getDirectLightingMIS(ord, pos, n, res.y, rd, brdf, brdfPdf, hit);

        // pathWeight = A0C0..An-1Cn-1,  direct = AnCnLn
        Lo += pathWeight * direct;

        if (brdfPdf < EPSILON || !hit) break;

        // Lo = A0C0L0 + A0C0A1C1L1 + ... + A0C0..AnCnLn  (A is the brdf, C is cos, L is directLight)
        // accumulate the new brdf*cos for this round,  brdf * cos / pdf
        pathWeight *= brdf * max(0., dot(rd, n)) / brdfPdf;

        ro = pos + (INTER_THRESHOLD * 2.) * n;
    }

    return Lo;
}


// basic truchet
vec4 mainImage(vec2 fragCoord)
{
    seed = iGlobalTime + iResolution.y * fragCoord.x / iResolution.x + fragCoord.y / iResolution.y;

    vec2 offset = -0.5 + hash21(seed++);
    vec2 p = (fragCoord + offset) / iResolution.xy; // (-iResolution.xy + 2.0 * (fragCoord + offset)) / iResolution.y;


    // origin is at the topleft corner for hlsl
    p.y = 1. - p.y;
    p = 2. * p - 1.;
    p.x *= iResolution.x / iResolution.y;

    // note falcor's camera is right handed, so we need reverse x
    vec3 ro = vec3(RayOrigin.x, RayOrigin.y, RayOrigin.z);
    vec3 ta = vec3(RayTarget.x, RayTarget.y, RayTarget.z);

    vec3 forward = normalize(ta - ro);
    //vec3 right = normalize(cross(vec3(0, 1, 0), forward));
    vec3 right = normalize(cross(forward, UpVector));
    vec3 up = normalize(cross(right, forward));

    vec3 rd = normalize(p.x * right + p.y * up + 1.8 * forward);


    vec3 finalCol = scene(ro, rd);
    float k = 1.;

    if (iFrame > 0. && iCameraDirty == 0.)
    {
        vec4 prevCol = iPass0Output.Load(vec3(fragCoord, 0));
        k = prevCol.w;

        finalCol.xyz = prevCol.xyz * (k / (k + 1.)) + finalCol.xyz * (1. / (k + 1.));

        if (k >= iMaxSPP)
        {
            finalCol = prevCol.xyz;
        }
    }

   
    return vec4(finalCol.xyz, k + 1.);
}

float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    return mainImage(texC * iResolution);
}
