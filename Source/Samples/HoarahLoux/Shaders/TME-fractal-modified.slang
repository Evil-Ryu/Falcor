
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

static vec2 debugFragCoord;
static float seed;

#define PATHTRACER 1
#define FAR 100.
#define MAX_BOUNCES 3
#define INTER_THRESHOLD .001
#define EPSILON 			0.0001
#define MARCHING_STEPS 256
#define MARCHING_STEP_SCALE 1.

#define EVENT_REFLECTION 1.
#define EVENT_TRANSMISSION 2.

#define PI 3.1415926535
#define DE_ITER 10

static float pixelSize;

struct Material
{
    vec3 albedo;
    float F0;
    float shininess;
};

Material getMaterial(float id, vec3 p)
{
    Material mate;
    mate.albedo = vec3(1.);
    mate.F0 = .04;
    mate.shininess = 16.;

    if (id == 1.)
    {
        mate.albedo = mix(fractalMate(p).zxy, vec3(1.1, 0.5, .0), .5);
    }
    return mate;
}

float hash12(vec2 p)
{
    p=fract(p*vec2(5.3983, 5.4427));
    p+=dot(p.yx, p.xy + vec2(21.5351, 14.3137));
	return fract(p.x * p.y * 95.4337);
}

vec2 hash21(float p)
{
    vec2 p2 = fract(p * vec2(5.3983, 5.4427));
    p2 += dot(p2.yx, p2.xy +  vec2(21.5351, 14.3137));
    return fract(vec2(p2.x * p2.y * 95.4337, p2.x * p2.y * 97.597));
}

float sphere(vec3 p)
{
    return length(p) - 1.;
}

float sponge(vec3 z0)
{
	vec4 z=vec4(z0,1.0);
    vec3 offset = vec3(1);
    float scale = 3.22;
    
	for (int n = 0; n < 4; n++) 
    {
		z = abs(z);
		if (z.x<z.y)z.xy = z.yx;
		if (z.x<z.z)z.xz = z.zx;
		if (z.y<z.z)z.yz = z.zy;
		z = z*scale;
		z.xyz -= offset*(scale-1.0);
		if(z.z<-0.5*offset.z*(scale-1.0))
            z.z+=offset.z*(scale-1.0);
	}
	return (length(max(abs(z.xyz)-vec3(1.0),0.0))-0.05)/z.w;
}

static float fixed_radius2 = 2.;
static float min_radius2 = 0.1;
static float folding_limit = 1.4;
static float scale = 3.;
static vec3 mtl = vec3(0.5, 0.5, 0.6);
static vec4 orb = vec4(1000);

void sphere_fold(inout vec3 z, inout float dz) {
    float r2 = dot(z, z);
    if (r2 < min_radius2) {
        float temp = (fixed_radius2 / min_radius2);
        z *= temp;
        dz *= temp;
    }
    else if (r2 < fixed_radius2) {
        float temp = (fixed_radius2 / r2);
        z *= temp;
        dz *= temp;
    }
}

void box_fold(inout vec3 z, inout float dz) {
    z = clamp(z, -folding_limit, folding_limit) * 2.0 - z;
}

static const float ang = 1.;
static const mat2 rot = mat2(cos(ang), sin(ang),
    -sin(ang), cos(ang));

float mb(vec3 z) {
    //z.x = mod(z.x + 1.0, 2.0) - 1.0;
    z.z = mod(z.z + 1.0, 2.0) - 1.0;

    orb = vec4(1000);
    vec3 offset = z;
    float dr = 1.0;
    for (int n = 0; n < 13; ++n) {
        z.xz = mul(rot, z.xz);

        box_fold(z, dr);
        sphere_fold(z, dr);

        z = scale * z + offset;
        dr = dr * abs(scale) + 1.;
        orb = min(orb, vec4(abs(z.xyz), dot(z, z)));
    }
    float r = length(z);
    return r / abs(dr);
}


static const vec4 param_min = vec4(-1.4661, -1.1076, -1.1844, 1.8886);
static const vec4 param_max = vec4(3.7324, 1.1972, 1.1204, 2.4136);

static const vec3 c = vec3(.808, .22, 2.137);
//static const vec3 c = vec3(.808, .12, 2.137);
float fractal(vec3 p)
{
	float scale = 1.0;
	
	for(int i=0; i < DE_ITER;i++)
	{
		p = 2.0*clamp(p, -c, c) - p;
		float r2 = dot(p, p);
		float k = max(1. / r2, 0.03);
		p *= k;
		scale *= k;
	}
    // scale: 1. - 4.  负号可交换, max->min
	//float l = max(-length(p.xy), sponge(p*3.7)/3.7);
    //float l = length(p.xy);
    //float l = max(-length(p.xy), sponge(p*4.)/4.);
    //float l = max(-length(p.xy), length(p)-.45);
    float l = min(length(p.xz), mb(p*1.8)/1.8+.01);  // 2.3
    //float l = min(length(p.xz), sponge(p*2.3)/2.3);
    //float l = length(p.xz);
	float rxy = l - .41;
	float n = l * p.z;
	rxy = max(rxy, -n / length(p) - .01);
    //rxy = min(rxy, sponge(p*2.3) / 2.3);
    //rxy = rxy - sphere(p * 1.5) / 1.5;//sponge(p*2.3)/2.3;
    //rxy = rxy - sponge(p*2.3)/2.3;
	return rxy / abs(scale * 1.5);
}

vec3 fractalMate(vec3 p)
{
    float acc = 0.;
    
    vec3 acc3 = vec3(0);
    for(int i = 0; i < DE_ITER + 4; i++)
    {
        float r2Old = dot(p, p);
        vec3 p0 = 2. * clamp(p, -c, c) - p;
        acc += abs(p.x - p0.x);
        
        acc3 += dot(p,p0) * max(1./r2Old, 0.03);
        p = p0;
        float r2 = dot(p, p);
        float k = max(1. / r2, 0.03);
		p *= k;
    }
    return .7 + .3 * sin(1. + 1.2 * acc + vec3(0.0, 0.5, 1.));
    //return .5 + .5 * sin(1. + 1.2 * acc3 + vec3(1., 0.5, 0.));
    //return pow(vec3(.003) * abs(acc3.xyz * acc), vec3(1.));
    //return .7 + .3 * sin(acc * vec3(1.3, .5, .7));
}


float map(vec3 p)
{
    //return length(p) - 1.;
    float d0 = fractal(p.xzy);
    return d0;
}

vec3 getNormal(vec3 p, float t)
{
    vec2 e = vec2(0.001 * t, 0.);
    
    return normalize(vec3(map(p + e.xyy) - map(p - e.xyy),
                          map(p + e.yxy) - map(p - e.yxy),
                          map(p + e.yyx) - map(p - e.yyx)));
}

float shadow(vec3 ro, vec3 rd)
{
    float s = 1.,t = .01, h;
    for(int i = 0; i < 32; i++)
    {
        h = map(ro + rd * t);
        s = min(s, 16. * h / t);
        if(s < 1e-4) break;
        t += clamp(h, .01, .05);
    }
    return clamp(s, 0., 1.);
}

float ao(vec3 p, vec3 n)
{
    float r = 0.0, w = 1.0, d;
    for(float i = 1.0; i < 5.0 + 1.1; i++)
    {
        d = i / 5.;
        r += w * (d - map(p + n * d));
        w *= 0.5;
    }
    return 1.0 - clamp(r, 0., 1.);
}

static vec3 sunDir = normalize(vec3(1., 1., -1.));
static vec3 sunCol = vec3(1.);

float ggx(float roughness, vec3 rd, vec3 W, vec3 n)
{
    vec3 H = normalize(W - rd);
    float NoH = max(0., dot(n, H));
    vec3 NxH = cross(n, H);
    float a = roughness * roughness;
    float b = NoH * a;
    float c = a / ((1. - NoH * NoH) + b * b);
    float d = c * c;
    return d;
}


vec3 shading(vec3 p, vec3 n, vec3 ro, vec3 rd)
{
    vec3 w0 = normalize(vec3(1., 1., -1.));
    vec3 L0 = vec3(1.);
    
    float dif = max(0., dot(n, w0));
    float bac = max(0., dot(n, -w0));
    float amb = 0.5 + 0.5 * n.y;
    float amb2 = 0.5 - 0.5 * n.y;
    float spe = ggx(.64, rd, w0, n) * max(0., dot(n, w0));

    Material mate = getMaterial(1., p);
    //return mate;
    float occ = ao(p, n);
    
    vec3 radi = (2. * dif + .5 * bac + 0.5 * amb + 0.1*amb2) * mate.albedo * L0 + spe * L0 * .25;
    //vec3 radi = (6. * dif + 5.5 * bac + 1.5 * amb + 1.*amb2) * mate * L0 + spe * L0 * .25;
        
    radi *= shadow(p, w0) * occ;
    //return vec3(pow(occ,4.));
    //return mate;
      //return shadow(p, w0) * vec3(1.); 	
    return radi * 0.2;
}

vec2 intersect(vec3 ro, vec3 rd, vec2 uv)
{
    float rnd = 0.9 + 0.1 * hash12(uv.xy);
    float t = 0.01, d = 1e10;
    
    for(int i = 0; i < 256; ++i)
    {
        d = abs(map(ro + t * rd)) * rnd;
        
        if(d < 0.0005 + 0.0002 * t || t > FAR)
        	break;
        
        t += d;
    }

    return vec2(t, 1.);
}

#if !PATHTRACER
vec3 scene(vec3 ro, vec3 rd, vec2 uv)
{
    vec3 col = vec3(0.);
    float rnd = 0.9 + 0.1 * hash12(uv.xy);
    
    float t = 0.01, d = 1e10;
    
    vec2 res = intersect(ro, rd, uv);

    t = res.x;
    
    if(t < FAR)
    {
        vec3 p = ro + t * rd;
        vec3 n = getNormal(p, t);
        col = shading(p, n, ro, rd);
    }
    
    col=mix(col, vec3(0.4,0.7,1.), 1.-exp(-.0001*t*t));
    //col=mix(col, vec3(0), 1.-exp(-.004*t*t));

    return col;
}
#else

float schlickFresnel(float F0, float lightDotHalf)
{
    return F0 + (1. - F0) * pow(1.0 - lightDotHalf, 5.);
}

vec3 ortho(vec3 v)
{
    return abs(v.x) > abs(v.z) ? vec3(-v.y, v.x, 0.0) : vec3(0.0, -v.z, v.y);
}

vec3 phongBrdf(vec3 toLight, vec3 toEye, vec3 normal, vec3 pos, Material mate)
{
    float shininess = 16.;
    vec3 albedo = mate.albedo;
    vec3 specularCol = vec3(1.);

    vec3 wr = reflect(-toLight, normal);
    vec3 wh = normalize(toLight + toEye);

    float F = schlickFresnel(mate.F0, max(0., dot(toLight, wh)));

    float diff = (1. - F) * 1. / PI;
    float spec = F * ((mate.shininess + 2.) / (2. * PI)) *
        pow(max(0., dot(wr, toEye)), mate.shininess);

    

    vec3 diff_refl = diff * albedo;
    vec3 spec_refl = spec * specularCol;

    // thrid param is roughness
    return mix(spec_refl, diff_refl, .5);
}


vec4 sampleLight(vec3 pos, vec3 V, vec3 n, Material mate)
{
    vec3 col = vec3(0);

    float lightSelectPdf = 1.f;

    if (lightSelectPdf < EPSILON) return vec4(0);

    vec3 sha = shadow(pos, sunDir);

    //float occ = ao(pos, n);

    col = sunCol * phongBrdf(sunDir, V, n, pos, mate) * max(0., dot(n, sunDir)) * sha / lightSelectPdf;

    return vec4(col, lightSelectPdf);
}

vec3 getHemisphereSampleCosWeighted(vec3 dir, vec2 randSample, float power = 1.)
{
    dir = normalize(dir);
    vec3 o1 = normalize(ortho(dir));
    vec3 o2 = normalize(cross(dir, o1));
    randSample.x = randSample.x * 2. * PI;
    randSample.y = pow(randSample.y, 1.0 / (power + 1.0));
    float oneminus = sqrt(1.0 - randSample.y * randSample.y);
    return cos(randSample.x) * oneminus * o1 + sin(randSample.x) * oneminus * o2 + randSample.y * dir;
}


vec3 getConeSampleCosWeighted(vec3 dir, float power, vec2 randSample)
{
    dir = normalize(dir);
    vec3 o1 = normalize(ortho(dir));
    vec3 o2 = normalize(cross(dir, o1));

    randSample.x = 2. * PI * randSample.x;
    randSample.y = 1.0 - pow(randSample.y, 1. / (power + 1.));

    float oneminus = sqrt(1.0 - randSample.y * randSample.y);
    return cos(randSample.x) * oneminus * o1 + sin(randSample.x) * oneminus * o2 + randSample.y * dir;
}

vec3 getPhoneSpecularSample(vec3 dir, float power, inout float seed)
{
    return getConeSampleCosWeighted(dir, power, seed);
}

float getPhongSpecularPdf(float shininess, vec3 worldNormal, vec3 worldRefl)
{
    return (shininess + 1.) / (2. * PI) * pow(max(0., dot(worldRefl, worldNormal)), shininess);
}

float LobeASelectionProb(vec3 A, vec3 B)
{
    const float SumA = A.x + A.y + A.z;
    const float SumB = B.x + B.y + B.z;
    return SumA / (SumA + SumB + 1e-6);
}


void AddLobeWithMIS(inout vec3 Weight, inout float Pdf, float3 LobeWeight, float LobePdf, float LobeProb)
{
    const float MinLobeProb = 1.1754943508e-38; // smallest normal float
    if (LobeProb > MinLobeProb)
    {
        LobePdf *= LobeProb;
        LobeWeight *= 1 / LobeProb;

        // basically: LobePdf / (Pdf + LobePdf), but robust version
        float MISWeight;
        if (Pdf < LobePdf)
            MISWeight = 1 / (1 + Pdf / LobePdf);
        else if (LobePdf < Pdf)
            MISWeight = 1 - 1 / (1 + LobePdf / Pdf);
        else
            MISWeight = 0.5f; // avoid (rare) inf/inf

        Weight = lerp(Weight, LobeWeight, MISWeight);
        Pdf += LobePdf;
    }
}

vec4 sampleBsdf(
    vec3 pos,
    vec3 worldNormal,
    vec3 V,
    Material mate,
    out vec3 L
)
{
    // sample specular or diffuse lobe
    const float lobePdf = LobeASelectionProb(mate.albedo * (1. - mate.F0), mate.F0);
    float pdf = 1.;
    vec2 rnd = hash21(seed++);
    if (rnd.x < lobePdf)
    {
        L = normalize(getHemisphereSampleCosWeighted(worldNormal, hash21(seed++), 1.));
    }
    else
    {
        L = reflect(-V, worldNormal);
        L = normalize(getConeSampleCosWeighted(L, mate.shininess, hash21(seed++)));
    }

    pdf = max(0., dot(worldNormal, L)) / PI + (mate.shininess + 1.) / (2. * PI) * pow(max(0., dot(worldNormal, L)), mate.shininess);

    return vec4(phongBrdf(L, V, worldNormal, pos, mate), pdf);
}

vec3 scene(vec3 ro, vec3 rd, vec2 uv)
{
    vec2 hit = intersect(ro, rd, FAR);

    float t = hit.x;

    vec3 throughput = vec3(1.);

    vec3 Lo = vec3(0);

    // bounces
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        if (hit.x > FAR)
        {
            // indirect part
            // it has to finally hit a light or the sky to have color
            // or there will be only direct part
            Lo = Lo + throughput * vec3(0., .5, 1.) * .5;
            break;
        }

        vec3 pos = ro + hit.x * rd; 

        vec3 n = getNormal(pos, hit.x);

        Material mate = getMaterial(hit.y, pos);

        vec3 nextRd = rd, nextRo = pos;

        // can use mis to optimize
        vec4 directLightingAndPdf = sampleLight(pos, -rd, n, mate);

        // throughput = A0C0..An-1Cn-1,  direct = AnCnLn
        Lo += throughput * directLightingAndPdf.xyz;

        float nextEvent = EVENT_REFLECTION;

        vec4 btdfAndPdf = vec4(0., 0., 0., 1.);

        // Sample btdf
        
        {
            btdfAndPdf = sampleBsdf(pos, n, -rd, mate, nextRd);
            nextEvent = EVENT_REFLECTION;
        }

        if (btdfAndPdf.w < EPSILON) break;


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

    Lo = mix(Lo, vec3(0.4, 0.7, 1.), 1. - exp(-.00001 * t * t));

    return Lo;

}
#endif


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

    vec3 ro = vec3(RayOrigin.x, RayOrigin.y, RayOrigin.z);
    vec3 ta = vec3(RayTarget.x, RayTarget.y, RayTarget.z);

    vec3 forward = normalize(ta - ro);
    vec3 right = normalize(cross(forward, UpVector));
    //vec3 right = normalize(cross(UpVector, forward));
    //vec3 up = normalize(cross(forward, right));
    vec3 up = normalize(cross(right, forward));

    vec3 rd = normalize(p.x * right + p.y * up + 1.8 * forward);


    vec3 finalCol = scene(ro, rd, p);
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
