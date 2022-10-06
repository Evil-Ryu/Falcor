

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

RWTexture2D<float4> debugTexture;

layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D iPass0Output : register(t0);

#define FAR 100.
#define MAX_BOUNCES 10
#define INTER_THRESHOLD .001
#define EPSILON 			0.0001
#define MARCHING_STEPS 256
#define MARCHING_STEP_SCALE 1.

#define EVENT_REFLECTION 1.
#define EVENT_TRANSMISSION 2.

#define MAT_CHEKERBOARD 0.
#define MAT_HOMO_VOLUME 3.
#define MAT_HETER_VOLUME 4.
#define MAT_GLASS 5.

#include "Include/CommonDefines.slangh"
#include "Include/SDF-MandelBox.slangh"
//#include "Include/SDF-BurningShip3D.slangh"
#include "Include/Randoms.slangh"
#include "Include/Sampling.slangh"
#include "Include/Materials.slangh"
#include "Include/SDF-BasicShapes.slangh"


static float seed;
static float distanceFactor = 1.; // for marching through object
static vec2 debugFragCoord;


// https://github.com/Syntopia/Fragmentarium/blob/master/Fragmentarium-Source/Examples/Include/Sunsky.frag
//static float sunSize = 0.53; //degree
static float sunSize = .53;
static float sunAngularDiameterCos = cos(sunSize * PI / 180.0);
static vec3 sunCol = vec3(1.1, .8, .5) * 5.;
static vec3 skyCol = vec3(0.1, .5, 1.) * .2;
static vec3 sunDir = normalize(vec3(1., 1., -1.));

bool sameHemisphere(in vec3 n, in vec3 a, in vec3 b)
{
    return ((dot(n, a) * dot(n, b)) > 0.0);
}

bool sameHemisphere(in vec3 a, in vec3 b)
{
    return (a.z * b.z > 0.0);
}

RyuMaterial getMaterial(float id, vec3 pos)
{
    RyuMaterial mat;
    //MakeDefaultMaterial(mat);

    mat.albedo = vec3(1., 0., 1.);
    mat.specularCol = vec3(1);
    mat.shininess = 16.;
    mat.roughness = 1.;
    mat.F0 = 0.04;
    mat.anisotropy = 0.;
    mat.transparency = 0.;
    mat.eta = 1.;
    mat.volumeId = -1.;

    if (id == 0.)
    {
        vec2 l = floor(pos.xz * 2.);
        mat.albedo = mix(vec3(.5, .1, .1), vec3(.9), mod(l.x + l.y, 2.));
        mat.specularCol = vec3(1);
        mat.roughness = .3;
    }
    else if (id == 1.)
    {
        mat.albedo = vec3(.0, .1, .3);
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
    else if (id == MAT_HOMO_VOLUME)
    {
        mat.albedo = vec3(.7);
        mat.specularCol = vec3(1.); // extinction
        mat.roughness = 0.5;  
        mat.shininess = 64.;
    }
    else if (id == MAT_GLASS)
    {
        mat.albedo = vec3(0.1);
        mat.specularCol = vec3(1.);
        mat.roughness = 0.1;
        mat.shininess = 128.;
        mat.transparency = .5;
        mat.eta = 1. / 1.5;
        mat.volumeId = 0.;
    }


    return mat;
}


float noise3d(vec3 p)
{
    const vec3 s = vec3(7, 157, 113);
    vec3 ip = floor(p);
    vec4 h = vec4(0., s.yz, s.y + s.z) + dot(ip, s);
    p -= ip;
    p = p * p * (3. - 2. * p);
    h = mix(fract(sin(h) * 43758.5453), fract(sin(h + s.x) * 43758.5453), p.x);
    h.xy = mix(h.xz, h.yw, p.y);
    return mix(h.x, h.y, p.z);
}


float fbm3d(vec3 p)
{
    mat3 m = mat3(.0, .8, .6,
        -.8, .36, -.48,
        -.6, -.48, .64);
    float f = 0., s = .5;
    for (int i = 0; i < 4; ++i)
    {
        f += s * noise3d(p);
        // p = m * p * 2.01;
        p = mul(p, m) * 2.01;
        s *= .5;
    }
    return f;

}

float sampleVolume(vec3 p)
{
    return fbm3d(p);
}


vec2 mandelbulb(vec3 p)
{
    p.xyz = p.xzy;
    vec3 z = p;
    vec3 dz = vec3(0.0);
    float power = 8.0;
    float r, theta, phi;
    float dr = 1.0;

    float t0 = 1.0;
    for (int i = 0; i < 7; ++i) {
        r = length(z);
        if (r > 2.0) continue;
        theta = atan(z.y / z.x);
        phi = asin(z.z / r);


        dr = pow(r, power - 1.0) * dr * power + 1.0;

        r = pow(r, power);
        theta = theta * power;
        phi = phi * power;

        z = r * vec3(cos(theta) * cos(phi), sin(theta) * cos(phi), sin(phi)) + p;

        t0 = min(t0, r);
    }
    return vec2(0.5 * log(r) * r / dr, t0);
}

float apollonian(vec3 p)
{
    float scale = 1.0;
    //orb = vec4(1000.0);

    for (int i = 0; i < 8; i++)
    {
        p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
        float r2 = dot(p, p);
        //orb = min(orb, vec4(abs(p), r2));
        float k = 1.2 / r2;
        p *= k;
        scale *= k;
    }

    return 0.25 * abs(p.y) / scale;
}

vec2 map(vec3 p)
{
    //float d1 = mapBurningShip(p, 2.);//mapMandelBox(p+vec3(1., -1.5, 0.));
    //float d1 = mandelbulb(p).x;
    //float d1 = mapMandelBox(p + vec3(1., -1.5, 0.));

    //float d0 = apollonian(p * 0.2) * 5.;;
    //float d3 = sdBox(p + vec3(0., -2., 0.), 2.9 * vec3(3., 2., 2.3));
    //float d = max(d0, d3);
    //float d = d0;
    //float id = MAT_GLASS;

    float d1 = length(p+vec3(0., -.1, 0.)) - 1.;
    //float d1 = sdTorus(p, vec2(1., .2));
    // thin shell and hollow inside
    //d1 = max(d1, -(d1 + 0.05));
    float d = d1, id = MAT_GLASS;

    float d2 = abs(p.y + 1.1)-0.1;

    //if (d2 < d) { d = d2; id = 1.; }

    if (distanceFactor < 0.)
    {
        if (abs(d) > abs(d2)) { d = -d2; id = 0.; }

    }
    else
    {
        if (d2 < d) { d = d2; id = 0.; }
    }

    return vec2(d, id);
}

vec2 mapVolumeBoundary(vec3 p)
{
    float d = length(p + vec3(0., -.1, 0.)) - 1.;

    return vec2(d, MAT_GLASS);
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

#if 1
vec2 intersect(vec3 ro, vec3 rd, float dist)
{
    float t = INTER_THRESHOLD;
    vec2 res = vec2(1000);
     
    for (int i = 0; i < MARCHING_STEPS; ++i)
    {
        res = map(ro + t * rd);
        res.x *= distanceFactor;

        //if ((res.x < 0. && abs(res.x) < INTER_THRESHOLD) || t > dist)
        if (res.x < INTER_THRESHOLD || t > dist)
        {
            break;
        }
        
        t += res.x * MARCHING_STEP_SCALE;
    }

    return vec2(t, res.y);
}
#else

vec2 intersect(in vec3 ro, in vec3 rd, float dist)
{
    float t = 0.0001;
    float res_t = 0.0;
    float res_d = 1000.0;
    vec2 c, res_c;
    float max_error = 1000.0;
    float d = 1.0;
    float pd = FAR0;
    float os = 0.0;
    float step = 0.0;
    float error = 1000.0;

    for (int i = 0; i < MARCHING_STEPS; i++)
    {
        if (error < INTER_THRESHOLD || t > dist)
        {
        }
        else {  // avoid broken shader on windows

            c = map(ro + rd * t);
            d = c.x;

            if (d > os)
            {
                os = 0.4 * d * d / pd;
                step = d + os;
                pd = d;
            }
            else
            {
                step = -os; os = 0.0; pd = FAR0; d = 1.0;
            }

            error = d / t;

            if (error < max_error)
            {
                max_error = error;
                res_t = t;
                res_c = c;
            }

            t += step;
        }

    }
    if (t > dist/* || max_error > pixel_size*/) res_t = 1000.0;
    return vec2(res_t, res_c.y);
}
#endif


vec4 sampleLight(vec3 pos, vec3 V, vec3 n, RyuMaterial mat)
{
    vec3 col = vec3(0);
    float costheta = dot(sunDir, n);
    if (costheta <= 0.)
        return vec4(col, 1.);

    vec3 rd = sunDir;// getConeSample(lightDir, 1. - sunAngularDiameterCos);
    float pdf = 1.f;

    if (pdf < EPSILON) return vec4(0);

    vec2 res = intersect(pos + (INTER_THRESHOLD * 2.) * n, rd, 20.);

    if (res.x > 20.)
    {
        col = costheta * sunCol * phongBrdf(rd, V, n, pos, mat) / pdf;
    }

    return vec4(col, pdf);
}

vec4 brdfEvaluate(
    RyuMaterial mat,
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
    float matId,
    bool bUseMis,
    out vec3 L)
{
    vec2 rnd = hash21(seed++);

    RyuMaterial mat = getMaterial(matId, pos);

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
    RyuMaterial mat,
    out vec3 L
)
{
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
    
    return brdfEvaluate(mat, worldGeomNormal, worldNormal, V, L, lobePdf);
}

// feature begin volume

bool IsVolume(float matId)
{
    return (matId == MAT_HOMO_VOLUME || matId == MAT_HETER_VOLUME);
}

vec2 intersectVolumeBoundary(vec3 ro, vec3 rd, float maxDist)
{
    float t = INTER_THRESHOLD;
    vec2 res = vec2(1000);

    for (int i = 0; i < MARCHING_STEPS; ++i)
    {
        res = mapVolumeBoundary(ro + t * rd);
        res.x *= distanceFactor;
        t += res.x * MARCHING_STEP_SCALE;

        if (res.x < INTER_THRESHOLD || t > maxDist)
        {
            break;
        }
    }
    return vec2(t, res.y);
}


float avgChannels(vec3 v)
{
    return (v.x + v.y + v.z) / 3.;
}

// return vec4(valueOfBsdf, pdf)
vec4 evaluateIsotropicPhaseBsdf()
{
    float pdf = 0.25 / PI;
    return vec4(pdf, pdf, pdf, pdf);
}

// returns the sampled direction and its pdf
vec4 sampleIsotropicPhaseBsdf()
{
    float2 rnd = hash21(seed++);
    vec3 sampleDir = vec3(0.);

    sampleDir.z = rnd.x * 2.0 - 1.0; // cosTheta

    float sinTheta = 1.0 - sampleDir.z * sampleDir.z; // square of sinTheta

    if (sinTheta > 0.0)
    {
        sinTheta = sqrt(sinTheta);
        float phi = rnd.y * 2.0 * PI;

        sampleDir.x = sinTheta * cos(phi);
        sampleDir.y = sinTheta * sin(phi);
    }
    else
    {
        sampleDir.x = sampleDir.y = 0.0;
    }

    float pdf = 0.25 / PI;

    return vec4(sampleDir, pdf);
}


// Beer's Law volume
// only constant absorbtion

vec3 BeersLawTransmittance(float dist, vec3 absorption)
{
    return exp(absorption * -dist);
}

vec3 BeersLawTransmittance(vec3 p0, vec3 p1, vec3 absorption)
{
    float dist = length(p0 - p1);
    return exp(absorption * -dist);
}

vec3 integrateBeersLawVolume(vec3 ro, vec3 rd, vec3 n, vec3 absorption, inout vec3 transmittance, out vec3 weight, inout vec2 hit)
{
    hit = intersect(ro, rd, FAR);
    float t = hit.x;

    // problematic, the bound geometry of the volume may not be water tight?
    // which is not likely in raymarching
    if (t > FAR)
        return vec3(0.);

    transmittance = BeersLawTransmittance(t, absorption);
    weight = vec3(1.);

    return vec3(0.0);
}

// Beer's Law volume, heterogeneous
// Delta tracking from p0 to p1
// maxAbsorption is user defined, better to be a majorant of the extinction coefficient
vec3 BeersLawHeterTransmittance(vec3 p0, vec3 p1, float maxAbsorption)
{
    float dist = length(p0 - p1);
    vec3 dir = (p1 - p0) / dist;

    bool terminated = false;
    float t = 0;
    while (!terminated)
    {
        float zeta = hash11(seed++);
        t = t + (- log(1 - zeta) / maxAbsorption);
        if (t > dist)
        {
            break; // outside volume
        }

        vec3 p = p0 + t * dir;
        float absorption = clamp(smoothstep(0.5, .6,sampleVolume(p * 8.)), 0., 1.);

        float rnd = hash11(seed++);
        if (rnd < absorption / maxAbsorption)
        {
            terminated = true;
        }
    }

    if (terminated)
        return vec3(0.);
    else
        return vec3(1.);
}

vec3 integrateBeersLawHeterVolume(vec3 ro, vec3 rd, vec3 n, float maxAbsorption, inout vec3 transmittance, out vec3 weight, out vec2 hit)
{
    hit = intersect(ro, rd, FAR);
    float t = hit.x;
    // problematic, the bound geometry of the volume may not be water tight?
    // which is not likely in raymarching
    if (t > FAR)
        return vec3(0.);

    transmittance = BeersLawHeterTransmittance(ro, ro + t * rd, maxAbsorption);
    weight = vec3(1.);
    return vec3(0.0);
}

// Homogeneous volume
// parameterization:
// vec3 extinction:   constant
// vec3 scatteringAlbedo
// T(t) = exp(extinction * -t)
// 
// pdf for sampling T(t):  p(t) = extinction * exp(extinction * -t)
// sample from p(t):  t' = -ln(1 - rnd) / extinction
// note: above extincion is rgb, but a single value is expected, so we can use avg(extinction.rgb) instead

// version 2:  t remapped into range [0, d]
// p(t) = (extinction * exp(extinction * -t)) / (1 - exp(extinction * -t))
// sample from p(t):  t' = -ln(1 - rnd * (1 - exp(extinction * -d))) / extinction
//                       = -ln(1 - rnd * (1 - T(d)) / extinction

vec3 transmittanceHomogeneous(float distance, vec3 extinction)
{
    return exp(extinction * -distance);
}

// get transmittance from p0 to p1
vec3 transmittanceHomogeneous(vec3 p0, vec3 p1, vec3 extinction)
{
    float dist = length(p0 - p1);

    return exp(extinction * -dist);
}


// integrate the whole volume
// weight: inverse of the pdf of sampling the scattering point in the volume
// return: integrated incoming radiance at pos
vec3 integrateHomogeneousVolume(vec3 ro, vec3 rd, vec3 n, vec3 extinction, vec3 scatteringAlbedo, inout vec3 totalTransmittance, out vec3 weight, out vec2 hit)
{
    // hit surface inside the volume or we reach the boundary of the volume
    // for calculating the total transmittance in between
    hit = intersect(ro, rd, FAR);
    float t = hit.x;
    // problematic, the bound geometry of the volume may not be water tight?
    // which is not likely in raymarching
    if (t > FAR)
        return vec3(0.);

    vec3 posd = ro + t * rd;

    totalTransmittance = transmittanceHomogeneous(ro, posd, extinction);
    float totalTrans = avgChannels(totalTransmittance);

    // randomly sample a point between ro and hit
    float rnd = hash11(seed++);
    float scatterDist = -log(1. - rnd * (1. - totalTrans)) / avgChannels(extinction);
    vec3 scatterPos = ro + scatterDist * rd;

    // sample direct lighting for this point
    vec3 lightDir = sunDir;

    // Shadow ray,  either hit an occluder inside the volume or the volume boundary
    float occluderDist = intersect(scatterPos, lightDir, FAR).x;

    vec3 occulder = scatterPos + occluderDist * lightDir;
    vec3 beamTransmittance = transmittanceHomogeneous(scatterPos, occulder, extinction);
    vec4 bsdfAndPdf = evaluateIsotropicPhaseBsdf();
    // the contribution of direct lighting
    vec3 L = sunCol * bsdfAndPdf.xyz * beamTransmittance;

    // sample bsdf for direct lighting, mis combined with above, currently does not apply
    // generate next ray based on phase bsdf
    //vec4 dirAndPdf = sampleIsotropicPhaseBsdf();

    // the contribution of sample position back to pos
    vec3 transmittance = transmittanceHomogeneous(scatterDist, extinction);
    // scattering albedo * extinction =  scattering coefficient
    L *= scatteringAlbedo * extinction * transmittance;

    weight = (1. - totalTrans) / (transmittance * extinction);

    return L;
}

// end volume




//vec4 evaluateLightingAndMisSampling(
//    vec3 rayDir,
//    vec3 pos,
//    vec3 normal,
//    float matId,
//    out vec3 rd,
//    out vec3 brdf)
//{
//    // TODO: refine
//    if(IsVolume(matId))
//    {
//        rd = rayDir;
//        brdf = vec3(1.);
//        return vec4(0., 0., 0., 1.);
//    }
//
//    bool useMis = true;
//   
//    vec4 res1 = sampleLight(pos, -rayDir, normal, matId);
//    //vec4 res2 = sampleLambert(pos, normal, normal, -rayDir, matid, useMis, rd);
//    vec4 res2 = sampleBsdf(pos, normal, normal, -rayDir, matId, rd);
//
//    brdf = res2.xyz;
//
//    // combine with mis
//    //vec3 col = res1.xyz * misWeight(res1.w, res2.w) + res2.xyz * misWeight(res2.w, res1.w);
//
//    // there's still only directional light, so bsdf sampling contributes no lighting
//    vec3 col = res1.xyz;
//    return vec4(col, res2.w);
//}

// returns lighting and light picking pdf
vec4 nee(vec3 rd, vec3 pos, vec3 n, RyuMaterial mat)
{
    vec4 directLighting = sampleLight(pos, -rd, n, mat);
    return directLighting;
}

vec4 sampleBtdf(
    vec3 rd,
    vec3 pos,
    vec3 worldGeomNormal,
    vec3 worldNormal,
    RyuMaterial mat,
    float matId,
    int i,
    out vec3 nextRd,
    out vec3 nextRo,
    out float nextEvent,
    out bool inVolume
)
{    
    if (i == 0)
    {
        debugTexture[debugFragCoord] = float4(matId, mat.transparency, mat.roughness, 0.);
    }


    vec4 btdfAndPdf = vec4(0., 0., 0., 1.);

    vec3 n = worldNormal;

    float eta = mat.eta;
    if (distanceFactor < 0.)
    {
        eta = 1. / eta;
    }

    vec3 refr = refract(rd, n, eta);

  
    // always pick transmission if translucent
    // so the pdf of transimission event should be 1
    if (mat.transparency > 0.01)
    {
        // internal reflection
        if (dot(refr, refr) < 0.001)
        {
            nextRd = reflect(rd, n);  // perfect reflection atm
            nextRo = pos + 0.01 * n;

            btdfAndPdf.xyz = mat.transparency;
            nextEvent = EVENT_REFLECTION;
        }
        else
        {
            distanceFactor = -distanceFactor;
            inVolume = distanceFactor < 0;

            eta = 1. / eta;

            nextRd = refr;
            nextRo = pos - 0.01 * n;

            btdfAndPdf.xyz = mat.transparency;
            nextEvent = EVENT_TRANSMISSION;
        }
    }
    else
    {
        btdfAndPdf = sampleBsdf(pos, worldGeomNormal, worldNormal, -rd, mat, nextRd);
        nextEvent = EVENT_REFLECTION;
    }

    return btdfAndPdf;
}


vec3 scene(vec3 ro, vec3 rd)
{
    vec2 hit = intersect(ro, rd, FAR);

    // bounces
    vec3 throughput = vec3(1.);
    vec3 Lo = vec3(0);
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        if (hit.x > FAR)
        {
            // indirect part
            // it has to finally hit a light or the sky to have color
            // or there will be only direct part
            Lo = Lo + throughput * skyCol;
            break;
        }

        vec3 pos = ro + hit.x * rd; 

        vec3 n = getNormal(pos) * distanceFactor;

        float matId = hit.y;
        RyuMaterial mat = getMaterial(matId, pos);

        vec3 nextRd = rd, nextRo = pos;

        // can use mis to optimize
        vec4 directLightingAndPdf = nee(rd, pos, n, mat);

        // direct part, NEE, use MIS to optimize
        // returns the new rd for the next event and the brdf of the inirect part
 //       vec4 lightingAndPdf = evaluateLightingAndMisSampling(rd, pos, n, matId, nextRd, brdf);

        // throughput = A0C0..An-1Cn-1,  direct = AnCnLn
        Lo += throughput * directLightingAndPdf.xyz;


        float nextEvent = EVENT_REFLECTION;
        
        /*vec4 btdfAndPdf = sampleBtdf(rd,
                                    pos,
                                    n,
                                    n,
                                    mat,
                                    i,
                                    matId,
                                    nextRd,
                                    nextRo,
                                    nextEvent,
                                    inVolume);*/

        vec4 btdfAndPdf = vec4(0., 0., 0., 1.);

        // Sample btdf
        {
            float eta = mat.eta;
            if (distanceFactor < 0.)
            {
                eta = 1. / eta;
            }

            vec3 refr = refract(rd, n, eta);

          /*  if (i == 0)
            {
                debugTexture[debugFragCoord] = float4(matId, mat.transparency, mat.roughness, 0.);
            }*/

            // always pick transmission if translucent
            // so the pdf of transimission event should be 1
            if (mat.transparency > 0.01)
            {
                // internal reflection
                if (dot(refr, refr) < 0.001)
                {
                    nextRd = reflect(rd, n);  // perfect reflection atm
                    nextRo = pos + 0.01 * n;

                    btdfAndPdf.xyz = mat.transparency;
                    nextEvent = EVENT_REFLECTION;
                }
                else
                {
                    distanceFactor = -distanceFactor;

                    nextRd = refr;
                    nextRo = pos - 0.01 * n;

                    btdfAndPdf.xyz = mat.transparency;
                    nextEvent = EVENT_TRANSMISSION;
                }
            }
            else
            {
                btdfAndPdf = sampleBsdf(pos, n, n, -rd, mat, nextRd);
                nextEvent = EVENT_REFLECTION;
            }
        }


        if (btdfAndPdf.w < EPSILON) break;


        //if ((nextEvent == EVENT_TRANSMISSION && mat.volumeId >= 0.) || distanceFactor < 0.)
        // is inside volume ?
        if(distanceFactor < 0.)
        {
            vec3 weight = vec3(0.), transmittance = vec3(1.);

            VolumeMaterial vmat;
            vmat.extinction = vec3(0.5);
            vmat.scatteringAlbedo = vec3(.8);

            vec3 LVolume = integrateHomogeneousVolume(nextRo, nextRd, n, vmat.extinction, vmat.scatteringAlbedo, transmittance, weight, hit);
            Lo += LVolume * weight * throughput;

           // vec3 LVolume = integrateBeersLawVolume(nextRo, nextRd, n, vmat.extinction, transmittance, weight, hit);
           //Lo += LVolume * weight * throughput;

            //svec3 LVolume = integrateBeersLawHeterVolume(nextRo, nextRd, n, 1., transmittance, weight, hit);
            //Lo += LVolume * weight * throughput;


            throughput *= transmittance;
        }
        else
        {
            if (nextEvent != EVENT_TRANSMISSION)
            {
                // Lo = A0C0L0 + A0C0A1C1L1 + ... + A0C0..AnCnLn  (A is the brdf, C is cos, L is directLight)
                // accumulate the new brdf*cos for this round,  brdf * cos / pdf
                throughput *= btdfAndPdf.xyz * max(0., dot(nextRd, n)) / btdfAndPdf.w;
                // this is important
                nextRo = pos + (INTER_THRESHOLD * 2.) * n;
            }

            hit = intersect(nextRo, nextRd, FAR);
        }


        rd = nextRd;
        ro = nextRo;
    }

    return Lo;
}


// basic truchet
vec4 mainImage(vec2 fragCoord)
{
    debugFragCoord = fragCoord;
    debugTexture[debugFragCoord] = float4(0., 0., 0., 0.);

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
