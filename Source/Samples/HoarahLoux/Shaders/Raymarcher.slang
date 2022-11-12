
// pathtracer with transparency, multi scattering volume

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
#define MAT_GLASS_SINGLE_SCATTER 4.
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
static float debugBounce = 0.;
static vec4 debugVec = vec4(0.);

// https://github.com/Syntopia/Fragmentarium/blob/master/Fragmentarium-Source/Examples/Include/Sunsky.frag
//static float sunSize = 0.53; //degree
static float sunSize = .53;
static float sunAngularDiameterCos = cos(sunSize * PI / 180.0);
static vec3 sunCol = vec3(1.1, .8, .5) * 5.;
static vec3 skyCol = vec3(0.1, .5, 1.) * .2;
static vec3 sunDir = normalize(vec3(1., 1., -1.));
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

    mat.type = MAT_TYPE_OPAQUE;
    mat.albedo = vec3(1., 0., 1.);
    mat.specularCol = vec3(1);
    mat.shininess = 16.;
    mat.roughness = 1.;
    mat.F0 = 0.04;
    mat.anisotropy = 0.;
    mat.transparency = 0.;
    mat.eta = 1.;

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
    else if (id == MAT_GLASS_SINGLE_SCATTER)
    {
        mat.type = MAT_TYPE_TRANSLUCENT;
        mat.albedo = vec3(0.1);
        mat.specularCol = vec3(0.5);
        mat.roughness = 0.1;
        mat.shininess = 128.;
        mat.transparency = .5;
        mat.eta = 1. / 1.5;
        mat.extinction = vec3(0.5);
        mat.scatteringAlbedo = vec3(.9);
    }
    else if (id == MAT_GLASS)
    {
        mat.type = MAT_TYPE_TRANSLUCENT;
        mat.albedo = vec3(0.1);
        mat.specularCol = vec3(1.);
        mat.roughness = 0.1;
        mat.shininess = 128.;
        mat.transparency = .5;
        mat.eta = 1. / 1.5;
        mat.extinction = vec3(0.5);
        mat.scatteringAlbedo = vec3(.9);
    }


    return mat;
}



bool isRayInVolume()
{
    return distanceFactor < 0.;
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
    return 1. - smoothstep(0.0, .3, fbm3d(p * 4.));
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

vec2 mapVolume(vec3 p)
{
    float d = length(p+vec3(0., -.1, 0.)) - 1.;
    //float d = sdTorus(p, vec2(1., .3));
    //float d = sdBox(p, vec3(1.));
    // thin shell and hollow inside
    //d = max(d, -(d + 0.1));

    return vec2(d, MAT_GLASS_SINGLE_SCATTER);
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


    vec2 res = mapVolume(p);
    float d = res.x, id = res.y;

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
    vec2 res = mapVolume(p);
    return res;
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


vec3 transmittanceHomogeneous(float distance, vec3 extinction);


// shadow ray with volume transmission
// return:  vec4(beamTransmittance.xyz, occluderDist)
vec3 shadowRay(vec3 ro, vec3 rd, float dist, RyuMaterial mat)
{
    vec2 hit = intersect(ro, rd, dist);
    float occluderDist = hit.x;

    vec3 beamTransmittance = vec3(1., 1., 1.);

    if (isRayInVolume())
    {
        float boundaryDist = intersectVolumeBoundary(ro, rd, dist).x;
        float transmissionDist = min(boundaryDist, occluderDist);

        beamTransmittance = transmittanceHomogeneous(transmissionDist, mat.extinction);
    }
    else
    {
        if (occluderDist < dist)
            beamTransmittance = vec3(0.);
    }

    return beamTransmittance;
}



vec4 sampleLight(vec3 pos, vec3 V, vec3 n, RyuMaterial mat, bool hitVolumeParticle)
{
    vec3 col = vec3(0);

    float costheta = 1.; 

    // there is no costheta term for volume particle lighting
    if (!hitVolumeParticle)
    {
        costheta = dot(sunDir, n);
        pos += (INTER_THRESHOLD * 2.) * n;

        if (costheta <= 0.)
            return vec4(col, 1.);
    }

    vec3 rd = sunDir;// getConeSample(lightDir, 1. - sunAngularDiameterCos);
    float lightSelectPdf = 1.f;

    if (lightSelectPdf < EPSILON) return vec4(0);

    vec3 shadow = shadowRay(pos, rd, 50., mat);

    vec3 brdfAndCos = vec3(0.);

    if (hitVolumeParticle)
    {
        brdfAndCos = evaluateIsotropicPhaseBsdf();
    }
    else
    {
        brdfAndCos = phongBrdf(rd, V, n, pos, mat) * costheta;
    }

    col = sunCol * brdfAndCos * shadow / lightSelectPdf;

    return vec4(col, lightSelectPdf);
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

vec4 sampleSurfaceBsdf(
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


vec4 sampleBsdf(
    vec3 pos,
    vec3 worldGeomNormal,
    vec3 worldNormal,
    vec3 V,
    RyuMaterial mat,
    bool hitVolumeParticle,
    out vec3 L
)
{
    vec4 brdfAndPdf = vec4(1.);

    if (hitVolumeParticle)
    {
        brdfAndPdf = sampleIsotropicPhaseBsdf(hash31(seed++), L);
    }
    else
    {
        brdfAndPdf = sampleSurfaceBsdf(pos, worldGeomNormal, worldNormal, V, mat, L);
    }

    return brdfAndPdf;
}



// feature begin volume

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
        float absorption = sampleVolume(p);

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



// returns lighting and light picking pdf
vec4 nee(vec3 rd, vec3 pos, vec3 n, RyuMaterial mat, bool hitVolumeParticle)
{
    vec4 directLighting = sampleLight(pos, -rd, n, mat, hitVolumeParticle);
    return directLighting;
}


// works for heterogeneous volume
// asumming volume is piecewise homogeneous
#if 0
vec3 raymarchingTransmittance(vec3 p0, vec3 p1, float stepSize)
{
    vec3 dir = p1 - p0;
    float distance = length(p1 - p0);
    dir *= 1. / distance;
    int nsteps = int(ceil(distance / stepSize));

    // 
    float adjustedStepSize = distance / float(nsteps);

    vec3 throughput = vec3(1.);
    float t = 0.;
    for (int i = 0; i < nsteps; ++i)
    {
        vec3 p = p0 + t * dir;
        vec3 extinction = vec3(sampleVolume(p));
        throughput *= transmittanceHomogeneous(adjustedStepSize, extinction);
        t += adjustedStepSize;
    }

    return throughput;
}
#endif


// using this form is to reduce computation cost, marching to find volumeboudary at each position is too costly
vec3 raymarchingTransmittance(vec3 p0, vec3 dir, int nsteps, float stepSize)
{
    // TODO: dither
    float adjustedStepSize = stepSize;

    vec3 throughput = vec3(1.);
    float t = 0.;
    for (int i = 0; i < nsteps; ++i)
    {
        vec3 p = p0 + t * dir;
        vec3 extinction = vec3(sampleVolume(p));
        throughput *= transmittanceHomogeneous(adjustedStepSize, extinction);
        t += adjustedStepSize;
    }

    return throughput;
}

#define VOLUME_MARCHING_STEPS 64
vec3 integrateVolume(vec3 ro, vec3 rd, vec3 scatteringAlbedo, out vec3 weight, out vec3 totalTransmittance, out vec2 hit)
{
    float rnd = hash11(seed++);
    vec4 L = vec4(0., 0., 0., 1.);

    // make sure ro is in volume already
    hit = intersectVolumeBoundary(ro, rd, FAR);
    float t = 0.;

    float stepSize = hit.x / float(VOLUME_MARCHING_STEPS);

    vec3 accTransmittance = vec3(1.);

    for (int i = 0; i < VOLUME_MARCHING_STEPS; ++i)
    {
        vec3 p = ro + t * rd;
        vec3 extinction = vec3(sampleVolume(p));

        if (any(extinction) > 0.)
        {
            // shadow ray transmittance
            vec3 beamTransmittance = raymarchingTransmittance(p, sunDir, 10, .1);

            vec3 bsdf = evaluateIsotropicPhaseBsdf();
            vec3 col = sunCol * bsdf.xyz * beamTransmittance;
            // scattering albedo * extinction =  scattering coefficient
            col *= scatteringAlbedo * extinction * accTransmittance;

            // transmittance for current step size
            accTransmittance *= transmittanceHomogeneous(stepSize, extinction);

            L.xyz += col;
        }

        if (all(accTransmittance) < .1 || t > hit.x) break;

        t += stepSize;
        //stepSize = max(.05, .02 * t);
    }

    totalTransmittance = accTransmittance;
    weight = vec3(1.);
    return L.xyz;
} 

vec3 scene(vec3 ro, vec3 rd)
{
    vec2 hit = intersect(ro, rd, FAR);

    vec3 throughput = vec3(1.);

    // for ray passing through a volume, the contribution of each scattering point along the ray
    // for surface hit the weight is always 1 for the first hit as there is no further hit
    vec3 weight = vec3(1.);
    vec3 Lo = vec3(0);

    // only will be true for multi scattering volume
    // single scattering volume will finish sampling the volume in one bounce, then the ray is out
    bool hitVolumeParticle = false;

    // bounces
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        debugBounce = float(i);

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
        vec4 directLightingAndPdf = nee(rd, pos, n, mat, hitVolumeParticle);

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
            if (isRayInVolume())
            {
                eta = 1. / eta;
            }

            vec3 refr = refract(rd, n, eta);

            // always pick transmission if possible
            // so the pdf of transimission event should be 1
            if (!hitVolumeParticle && mat.type == MAT_TYPE_TRANSLUCENT)
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
                btdfAndPdf = sampleBsdf(pos, n, n, -rd, mat, hitVolumeParticle, nextRd);
                nextEvent = EVENT_REFLECTION;
            }
        }


        if (btdfAndPdf.w < EPSILON) break;

        //if ((nextEvent == EVENT_TRANSMISSION && mat.volumeId >= 0.) || distanceFactor < 0.)
        if (isRayInVolume())
        {
            vec3 transmittance = vec3(1.);

            hitVolumeParticle = false;
            float maxExtinction = 1.;
            // vec3 LVolume = integrateBeersLawVolume(nextRo, nextRd, n, mat.extinction, transmittance, weight, hit);
            //Lo += LVolume * weight * throughput;

                //svec3 LVolume = integrateBeersLawHeterVolume(nextRo, nextRd, n, maxExtinction, transmittance, weight, hit);
                //Lo += LVolume * weight * throughput;

            /* vec3 LVolume = integrateHomogeneousVolume(nextRo, nextRd, n, mat.extinction, mat.scatteringAlbedo, transmittance, weight, hit);
                Lo += LVolume * weight * throughput;*/

            //vec3 LVolume = integrateHeterogeneousVolume(nextRo, nextRd, n, maxExtinction, mat.scatteringAlbedo, transmittance, weight, hit);
            //Lo += LVolume * weight * throughput;

            vec3 LVolume = integrateVolume(nextRo, nextRd, mat.scatteringAlbedo, weight, transmittance, hit);
            Lo += LVolume * weight * throughput;

            // for single scattering
            throughput *= transmittance;
            
            //return mapToDebugColor((transmittance * weight * btdfAndPdf.xyz / btdfAndPdf.w).x);
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
