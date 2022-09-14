

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
#define EPSILON 			0.0001 

#include "Include/CommonDefines.slangh"
#include "Include/SDF-MandelBox.slangh"
//#include "Include/SDF-BurningShip3D.slangh"
#include "Include/Randoms.slangh"
#include "Include/Sampling.slangh"
#include "Include/Materials.slangh"
#include "Include/SDF-BasicShapes.slangh"


static float seed;

bool sameHemisphere(in vec3 n, in vec3 a, in vec3 b)
{
    return ((dot(n, a) * dot(n, b)) > 0.0);
}

bool sameHemisphere(in vec3 a, in vec3 b)
{
    return (a.z * b.z > 0.0);
}

PhongMaterial getPhongMaterial(float id)
{
    PhongMaterial mat;
    mat.albedo = vec3(1., 0., 1.);
    mat.specularCol = vec3(1., 0., 1.);
    mat.shininess = 16.;
    mat.roughness = .5;
    mat.F0 = 0.03;
    mat.anisotropy = 0.;

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
    float d1 = mapBurningShip(p, 2.);//mapMandelBox(p+vec3(1., -1.5, 0.));
    //float d1 = mapMandelBox(p+vec3(1., -1.5, 0.));
    //float d1 = sdSphere(p, 1.);
    float d2 = abs(p.y + .9);
    float d = d1;
    float id = 2.;

    if (d2 < d) { d = d2; id = 1.; }
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
static float sunSize = .53;
static float sunAngularDiameterCos = cos(sunSize * PI / 180.0);
static vec3 sunCol = vec3(1.1, .8, .5) * 5.;
static vec3 skyCol = vec3(0.1, .5, 1.);
static vec3 sunDir = normalize(vec3(1., 1., -1.));


vec4 sampleLight(vec3 pos, vec3 toEye, vec3 normal, float matid)
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
        col = costheta * sunCol * phongBrdf(rd, toEye, normal, pos, mat) / pdf;
    }

    return vec4(col, pdf);
}

vec4 brdfEvaluate(
    float matid,
    vec3 worldGeomNormal,
    vec3 worldNormal,
    vec3 V,
    vec3 L,
    float lobePdf
    )
{
    if (!sameHemisphere(worldGeomNormal, V, L) ||
        !sameHemisphere(worldNormal, V, L))
    {
        return vec4(0.);
    }

    PhongMaterial mat = getPhongMaterial(matid);

    float3x3 tangentBasis = GetTangentBasis(worldNormal);

    vec3 tangentV = mul(tangentBasis, V);
    vec3 tangentL = mul(tangentBasis, L);
    vec3 tangentH = normalize(tangentV + tangentL);

    float NoV = clamp(tangentV.z, 0., 1.);
    float NoL = clamp(tangentL.z, 0., 1.);
    float VoH = clamp(dot(tangentV, tangentH), 0., 1.);
    float NoH = clamp(tangentH.z, 0., 1.);

    float F = schlickFresnel(mat.F0, dot(tangentL, tangentH));

    vec3 outWeight = vec3(0.);
    float outPdf = 0.;

    // diffuse lobe
    vec3 diff = mat.albedo / PI;// / PI * (1. - F);
    AddLobeWithMIS(outWeight, outPdf, diff, NoL / PI, lobePdf);

    // specular lobe
#if 1
    vec2 alpha = vec2(0);
    GetAnisotropicRoughness(mat.roughness * mat.roughness,
        mat.anisotropy, alpha.x, alpha.y);
    vec2 GGXResult = GGXEvalReflection(tangentL, tangentV, tangentH, alpha);
    vec3 spec = F * GGXResult.x * mat.specularCol;
    AddLobeWithMIS(outWeight, outPdf, spec, GGXResult.y, 1. - lobePdf);
#endif
    return vec4(outWeight, outPdf);
}

vec4 sampleLambert(
    vec3 pos,
    vec3 worldGeomNormal,
    vec3 worldNormal,
    vec3 V,
    float matid,
    bool bUseMis,
    out vec3 L)
{
    vec2 rnd = hash21(seed++);

    PhongMaterial mat = getPhongMaterial(matid);

    L = normalize(getHemisphereSampleCosWeighted(worldNormal, rnd, 1.));
    vec3 diff = mat.albedo / PI;

    float pdf = max(0., dot(worldNormal, L)) / PI;
    return vec4(diff, pdf);
}

vec4 sampleBsdf(
    vec3 pos,
    vec3 worldGeomNormal,
    vec3 worldNormal,
    vec3 V,
    float matid,
    bool bUseMis,
    out vec3 L
)
{
    PhongMaterial mat = getPhongMaterial(matid);

    float alpha = mat.roughness;

    float3x3 tangentBasis = GetTangentBasis(worldNormal);
    vec3 tangentV = worldToTangent(V, tangentBasis);

    // sample specular or diffuse lobe
    const float lobePdf = LobeASelectionProb(mat.albedo * (1. - mat.F0), mat.F0);

    vec2 rnd = hash21(seed++);
    if (rnd.x < lobePdf)
    {
        L = normalize(getHemisphereSampleCosWeighted(worldNormal, rnd, 1.));
    }
    else
    {
        vec4 GGXSample = ImportanceSampleVisibleGGX(UniformSampleDisk(rnd), alpha * alpha, tangentV);
        vec3 worldH = tangentToWorld(GGXSample.xyz, tangentBasis);
        L = reflect(-V, worldH);
    }
    
    return brdfEvaluate(matid, worldGeomNormal, worldNormal, V, L, lobePdf);
}


vec4 evaluateLightingAndMisSampling(
    vec3 rayDir,
    vec3 pos,
    vec3 normal,
    float matid,
    out vec3 rd,
    out vec3 brdf)
{
    bool useMis = true;
   
    vec4 res1 = sampleLight(pos, -rayDir, normal, matid);
    //vec4 res2 = sampleLambert(pos, normal, normal, -rayDir, matid, useMis, rd);
    vec4 res2 = sampleBsdf(pos, normal, normal, -rayDir, matid, useMis, rd);

    brdf = res2.xyz;

    // combine with mis
    vec3 col = res1.xyz * misWeight(res1.w, res2.w) + res2.xyz * misWeight(res2.w, res1.w);

    return vec4(col, res2.w);
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

        float matId = res.y;

        pos = ro + res.x * rd;
        n = getNormal(pos);
        vec3 ord = rd;

        vec3 brdf = vec3(0);

        // direct part, NEE, use MIS to optimize
        // returns the new rd for the next event and the brdf of the inirect part
        vec4 lightingAndPdf = evaluateLightingAndMisSampling(ord, pos, n, matId, rd, brdf);

        // pathWeight = A0C0..An-1Cn-1,  direct = AnCnLn
        Lo += pathWeight * lightingAndPdf.xyz;

        if (lightingAndPdf.w < EPSILON) break;

        // Lo = A0C0L0 + A0C0A1C1L1 + ... + A0C0..AnCnLn  (A is the brdf, C is cos, L is directLight)
        // accumulate the new brdf*cos for this round,  brdf * cos / pdf
        pathWeight *= brdf * max(0., dot(rd, n)) / lightingAndPdf.w;

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
