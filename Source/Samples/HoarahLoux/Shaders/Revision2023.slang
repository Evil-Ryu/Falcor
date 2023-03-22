
// pathtracer with transparency, multi scattering volume

#include "Include/GLSLDefines.slangh"

cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;
    float iFrame;
    float iCameraDirty;
    float iAccumulationRestart;
    float iMaxSPP;

    float3 RayOrigin;
    float3 RayTarget;
    float3 UpVector;
};


layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D iPass0Output : register(t0);

static float seed;

static int MAX_BOUNCES = 1;//  iCameraDirty > 0. ? 3 : 3;
static int MARCHING_STEPS = 128;// iCameraDirty > 0. ? 128 : 1024;
static float MARCHING_STEP_SCALE = 1.;// iCameraDirty > 0. ? 5. : 1.;

#define FAR 100.
#define INTER_THRESHOLD .001
#define EPSILON 			0.0001

#define PI 3.1415926535
#define DE_ITER 14

#define MAT_FRACTAL 0.
#define MAT_TREE_TRUNK 1.
#define MAT_TREE_LEAVES 2.
#define MAT_FLOWER 3.
#define MAT_FLOWER_LEAVES 4.
#define MAT_WALL 5.
#define HEIGHT(z) sin(z * .2  + 1.) * 2.

static float pixelSize;

struct Material
{
    vec3 albedo;
    float F0;
    float shininess;
    float id;
};

static vec3 globalCol = vec3(1.);

float hash11(float p)
{
    vec2 p2 = fract(vec2(p * 5.3983, p * 5.4427));
    p2 += dot(p2.yx, p2.xy + vec2(21.5351, 14.3137));
    return fract(p2.x * p2.y * 95.4337) * 0.5 + 0.5;
}

float wangHash(uint u, uint v, uint s)
{
    // https://www.reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
    // https://www.shadertoy.com/view/ldjczd
    uint seed = (u * 1664525u + v) + s;
    seed = (seed ^ 61u) ^ (seed >> 16u);
    seed *= 9u;
    seed = seed ^ (seed >> 4u);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15u);
    float value = float(seed) / (4294967296.0);
    return value;
}
static float randomState = 0.;
static vec2 gFragCoord;

float hqRandom()
{
    float rnd = wangHash(uint(randomState), uint(gFragCoord.x), uint(gFragCoord.y));
    randomState += float(iFrame) + iGlobalTime;
    return rnd;
}

float noise(vec2 x)
{
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0;
    return mix(mix(hash11(n + 0.0), hash11(n + 1.0), f.x),
        mix(hash11(n + 57.0), hash11(n + 58.0), f.x), f.y);
}

float fbm(vec2 p)
{
    float f = 0.0;
    f += .5 * noise(p);
    p = p * 2.01;
    f += .25 * noise(p);
    p = p * 2.02;
    f += .125 * noise(p);
    p = p * 2.03;
    return f;
}

float bump(vec3 p, vec3 n)
{
    p *= iResolution.x / 20.;
    p.y *= .5;
    p.xz *= 2.;
    return (fbm(p.xy) * abs(n.z) + noise(p.xz) * abs(n.y) + noise(p.yz) * abs(n.x)) / 3.;
}

vec3 bump_mapping(vec3 p, vec3 n, float weight)
{
    vec2 e = vec2(2. / iResolution.y, 0);
    vec3 g = vec3(bump(p - e.xyy, n) - bump(p + e.xyy, n),
        bump(p - e.yxy, n) - bump(p + e.yxy, n),
        bump(p - e.yyx, n) - bump(p + e.yyx, n)) / (e.x * 2.);
    g = (g - n * dot(g, n));
    return normalize(n + g * weight);
}

Material getMaterial(float id, vec3 p)
{
    Material mate;
    mate.albedo = vec3(1.);
    mate.F0 = .04;
    mate.shininess = 16.;
    mate.id = id;
    if (id == MAT_FRACTAL)
    {
        p = p + vec3(-35, 4.5, 16);
        p.y += HEIGHT(p.z);
        vec3 col = fractalMate(p.xzy);

        col = mix(vec3(1.1, .1, .0), col, smoothstep(3.5, 4.9, p.y));
        col = mix(vec3(.12, .3, .1), col, 1. - smoothstep(6., 25., p.y));

        mate.albedo = col;
    }
    else if (id == MAT_TREE_TRUNK)
    {
        mate.albedo = vec3(0.561, 0.459, 0.357) * .2;
    }
    else if (id == MAT_TREE_LEAVES)
    {
        mate.albedo = vec3(1.000, 0.400, 0.000) * 3.;
    }
    else if (id == MAT_FLOWER)
    {
        mate.albedo = vec3(0.9, 0.1, 0.008);
    }
    else if (id == MAT_FLOWER_LEAVES)
    {
        mate.albedo = vec3(0.353, 0.518, 0.102);
    }
    else if (id == MAT_WALL)
    {
        mate.albedo = vec3(0.690, 0.565, 0.451);
    }
    return mate;
}

vec2 hash21(float p)
{
    vec2 p2 = fract(p * vec2(5.3983, 5.4427));
    p2 += dot(p2.yx, p2.xy +  vec2(21.5351, 14.3137));
    return fract(vec2(p2.x * p2.y * 95.4337, p2.x * p2.y * 97.597));
}


static float fixed_radius2 = 2.;
static float min_radius2 = 0.1;
static float folding_limit = 1.4;
static float scale = 3.;
static vec3 mtl = vec3(0.5, 0.5, 0.6);
static vec4 orb = vec4(1000);

float mb(vec3 z, float y)
{
    fixed_radius2 = 2.;
    min_radius2 = 0.1;
    folding_limit = 1.4;
    scale = 3.;

    if(y<1.)z.x = mod(z.y + 1.0, 2.0) - 1.0;
    else
    {
        folding_limit = 1.8;
        if (z.y > -3.16) return 1e2;
        z.z = mod(z.z, 2.0) - 1.0;
    }
    orb = vec4(1000);
    vec3 offset = z;
    float dr = 1.0;
    for (int n = 0; n < 9.; ++n)
    {
        z.xy = mul(mat2(.54, .84, -.84, .54), z.xy);

        z = clamp(z, -folding_limit, folding_limit) * 2.0 - z;

        float r2 = dot(z, z);
        if (r2 < min_radius2)
        {
            float temp = (fixed_radius2 / min_radius2);
            z *= temp;
            dr *= temp;
        }
        else if (r2 < fixed_radius2)
        {
            float temp = (fixed_radius2 / r2);
            z *= temp;
            dr *= temp;
        }

        z = scale * z + offset;
        dr = dr * abs(scale) + 1.;
        orb = min(orb, vec4(abs(z.xyz), dot(z, z)));
    }
    globalCol = orb.xyz;// *.1;
    float r = length(z);
    return r / abs(dr);
}


static const vec3 c = vec3(.808, .22, 2.137);

float fractal(vec3 p)
{
    int iter = DE_ITER;
    bool yeah = false;
	float scale = 1.0;
    vec3 q = p;
	for(int i=0; i < iter;i++)
	{
        float a = 2.;
        if (i == 3 && q.x<-44.) a = 2.4;
		p = a*clamp(p, -c, c) - p;
		float k = max(1. / dot(p, p), 0.03);
		p *= k;
		scale *= k;
	}

    float l = min(length(p.xz), mb(p*1.8, 0.)/1.8+.01);  // 2.3
    
	float rxy = l - .4;
	float n = l * p.z;
	rxy = max(rxy, -n / length(p) - .01);
	return rxy / abs(scale * 1.5);
}

vec3 fractalMate(vec3 p)
{
    vec3 q = p;
    vec3 acc = vec3(0);
    for(int i = 0; i < 8; i++)
    {
        vec3 p1 = 2. * clamp(p, -c, c) - p;
        acc += distance(p, p1) * max(1./ dot(p, p), .3);
		p = p1 * max(1. / dot(p1, p1), 0.03);;
    }

    //return vec3(.4, .5, .25) + vec3(.3, .2, .1) * cos(6.28*(vec3(.4)*acc));
    vec3 k = vec3(.3, .2, .2);
    if (q.z < 4.8) k = vec3(.5, .4, .2);
    return vec3(.4, .4, .3) + k * cos(6. * (vec3(.5) * acc));

}

mat2 rot(float r)
{
    return mat2(cos(r), sin(r), -sin(r), cos(r));
}

float smin(float a, float b, float k)
{
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);

}

vec2 fold(vec2 p, float s, out float id)
{
    float a = PI / s + atan2(p.x, p.y);
    float n = PI * 2. / s;
    a = floor(a / n);
    id = mod(a, s);
    p = mul(p, rot(a * n));
    return p;
}

float dbar2(vec3 p, vec3 a, vec3 b, vec3 r)
{
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return (length((pa - ba * h) / r) - 1.) * min(min(r.x, r.y), r.z);
}

vec4 dBranches(vec3 p, float i, float id, float len)
{
    p.x += sin(p.y * 4.) * 0.1 * hash11(id * 17. + i + 1.);
    vec3 dir = normalize(vec3(0., 2., -1));
    float k = .1 - smoothstep(.6, 2.5, p.y) * .07;
    float l = 3.;
    if (i >= 4.)
    {
        p.x *= .3; p.z += abs(sin(p.x * 25.)) * .05;
        p.x += abs(sin(p.y * 15.)) * .02;
        k = .1 - sin(p.y * 2. + 2.5) * .1;
        l = 3.;
    }
    else if (i > 0.) k *= 0.2;

    float dcap = dbar2(p + vec3(0., 0., len),
        vec3(0., 0., len),
        vec3(0., 0., len) + len * l * dir,
        vec3(k));

    return vec4(p, dcap);
}

vec2 tree(vec3 z0)
{
    z0.xz = mul(rot(-.2), z0.xz);

    vec4 z = vec4(z0, 1.0);

    vec3 p = z.xyz;
    //p.xz = mul(rot(.5), p.xz);

    p.x -= sin(p.y * 2.) * 0.2;

    float d = max(abs(p.y - 0.1) - 1., length(p.xz) - 0.23 + smoothstep(0., 2., p.y) * 0.3);

    float id = 0.;

    float numLayers = 7.;

    float mateid = MAT_TREE_TRUNK;

    vec4 branchClonePos = z;
    float branchCloneIndex = 3.;
    float branchLayer = 4.;

    vec4 leafClonePos = z;
    float leafCloneIndex = 4.;

    for (float layerIndex = 1., i = 0.; layerIndex <= numLayers; layerIndex += 1.)
    {
        for (; i < 5.; i += 1.)
        {
            float f = 5. + (layerIndex > 1. ? 4. : 0.);
            //float f = 2.;
            float spread = -.95 - i / 7.;//+ .5*(layerIndex == 1. ? id / 15. : id / 27.);

            if (i == branchCloneIndex)
            {
                branchClonePos = z;
            }

            if (layerIndex == 1. && i == leafCloneIndex)
                //if(i == leafCloneIndex)
                    //{leafClonePos = z; z.xyz = abs(z.xyz)-.5;}            
            {
                leafClonePos = z;
            }


            z.xz = fold(z.xz, f, id);
            z.yz = mul(z.yz, rot(spread));


            float len = 1. + id / f / 3.;
            vec4 res = dBranches(z.xyz, i, id, len);
            float dcap = res.w / z.w;

            if (i >= 4.)
            {
                float d1 = dcap + 0.011;
                if (d1 < d)
                {
                    d = d1;
                    mateid = MAT_TREE_LEAVES;
                }
            }
            else
            {
                float d1 = dcap;
                if (d1 < d)
                {
                    d = smin(d, d1, 0.05 - 0.04 * step(2., float(i)));
                    mateid = MAT_TREE_TRUNK;
                }
            }

            z.zy += vec2(1., -2.) * len;
            z *= 2.;
        }


        if (layerIndex < branchLayer)
        {
            z = branchClonePos;
            // place more branches uniformly on the parent branch
            z.zy -= normalize(vec2(1., -2.)) * (2. * hash11(layerIndex * 17.)) * branchCloneIndex * 2. / branchLayer;;
            //z *= 4. - branchCloneIndex + 1.;
            i = branchCloneIndex;

        }
        else
        {
            z = leafClonePos;
            z.zy -= normalize(vec2(1., -2.)) * (layerIndex - 2.) * leafCloneIndex / (numLayers - branchLayer);//  / (numLeafLayers);
            i = leafCloneIndex;

            // folding to add more leaves in each layer
            z.xzy = abs(z.xzy) - 1.;
        }
        z.xy = mul(rot(.2 * (numLayers - layerIndex)), z.xy);
    }

    return vec2(d * .5, mateid);
}

vec4 dPedals(vec3 p, float i, float id, float len, float scale)
{
    p.z += sin(p.y * id / 2.) * 0.05;
    vec3 dir = normalize(vec3(0., 2., -1));

    p.z += sin(p.y * 2.) * (.65 - i / 5.);

    float k = .1 - sin(p.y * 2. + 2.5) * .1;

    if (i == 1.)
    {
        p.z += abs(sin(p.x * 5.)) * .08;
        p.z += abs(sin((p.y - abs(p.x)) * 15.)) * .01;
        p.x += sin(p.z * 60.) * .01;

    }
    float l = 2.8;


    float dcap = dbar2(p + vec3(0., 0., len),
        vec3(0., 0., len),
        vec3(0., 0., len) + len * l * dir,
        vec3(k * 3., k, .03)) + 0.01;
    return vec4(p, dcap);
}

vec2 flower(vec3 z0, float fid)
{
    z0.xz = mul(rot(fid * .5), z0.xz);
    z0.z *= -1.;
    vec4 z = vec4(z0, 1.0);

    vec3 p = z.xyz;
    z.yz = mul(rot(-.5), z.yz);
    p.z -= sin(p.y * 1.5) * 0.1;

    float mateid = MAT_TREE_TRUNK;
    float d = max(abs(p.y + 1.8) - 2., length(p.xz) - 0.1 + smoothstep(0., 2., p.y) * 0.1);

    float id = 0.;
    float f = 5. + fid * 4;
    //float f = 2.;
    float spread = 1.8;//+ .5*(layerIndex == 1. ? id / 15. : id / 27.);

    z.xz = fold(z.xz, f, id);
    z.yz = mul(rot(spread), z.yz);

    for (float i = 1.; i <= 6.; i += 1.)
    {
        float len = 1.;
        vec4 res = dPedals(z.xyz, i, id, len, z.w);
        float dcap = res.w / z.w;

        if (dcap < d)
        {
            if (i < 2.) mateid = MAT_FLOWER_LEAVES;
            else mateid = MAT_FLOWER;
            d = dcap;
        }


        z = vec4(z0, 1.);
        z.yz = mul(rot(-.5), z.yz);
        z.xz = mul(rot(0.3 * i), z.xz);
        z.xz = fold(z.xz, 7. + i + fid * 4., id);
        z.yz = mul(rot(1.2),z.yz);// - (i+1.)/100.);

        if (i >= 2.)z.zy += vec2(.1 * i, 0) * len;
        //z.z *= -1.;
        z *= 1. + i * .5;// + 2.*i - 2.;
    }

    return vec2(d * .5, mateid);
}

float box(vec3 p, vec3 b)
{
    vec3 d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}
vec2 map(vec3 p)
{
    float mateid = MAT_FRACTAL;

    vec3 q = p - vec3(0.87, 3., 1.82);

    vec2 r0 = tree((q - vec3(0,.1,2)) * .37); r0.x /= .37;
    r0.x = smin(r0.x, (length(q*vec3(1,.5,1) - vec3(.4, .5, 2.3)) - .4), .05);

    vec2 r1 = flower(1.9*(q + vec3(2.8, 2.3, -8)), 0.); r1.x /= 1.9;
    
    vec2 r2 = flower(1.9 * (q + vec3(4, .5, -6)), 1.); r2.x /= 1.9;

    q = p + vec3(-35, 4.5, 16);
    q.y += HEIGHT(q.z);
    vec2 r4 = vec2(fractal(q.xzy), MAT_FRACTAL);

    p.xz = mul(rot(.1), p.xz);
    vec2 r6 = vec2(box(p + vec3(79,0,0), vec3(70, 1e5, 1e5)), MAT_FRACTAL);

    if (p.z > 6.)p.y -= sin(p.z * .3 + 2.) * 2.;
    else p.y -= sin(p.z * .1);
    
    vec2 r5 = vec2(max(r6.x, mb((p * 0.1 - vec3(-3., 3.4+smoothstep(10.,-1.,p.z)*0.4, 0.)), 1.) / 0.1), MAT_WALL);

    vec2 r = r0;
    if (r1.x < r.x) r = r1;
    if (r2.x < r.x) r = r2;
    if (r4.x < r.x) r = r4;
    if (r5.x < r.x) r = r5;

    return r;

}

vec3 getNormal(vec3 p, float t)
{
    vec2 e = vec2(0.001, 0.);
    
    return normalize(vec3(map(p + e.xyy).x - map(p - e.xyy).x,
                          map(p + e.yxy).x - map(p - e.yxy).x,
                          map(p + e.yyx).x - map(p - e.yyx).x));
}

float shadow(vec3 ro, vec3 rd)
{
    float s = 1.,t = .001;
    for(int i = 0; i < 32; i++)
    {
        vec2 h = map(ro + rd * t);
        if (h.y == MAT_FLOWER_LEAVES) h.x *= .35;
        s = min(s, 16. * h.x / t);
        if (h.x < 1e-4) break;
        t += clamp(h.x, .01, .05);
    }
    return clamp(s, 0., 1.);
}


static vec3 sunDir = normalize(vec3(-.5, 1., -.2));
//static vec3 sunDir = normalize(vec3(0., 1., 0.));
//static vec3 sunCol = vec3(253., 184., 19.) / 256.;
static vec3 sunCol = vec3(1.);


vec2 intersect(vec3 ro, vec3 rd, vec2 uv)
{
    float rnd = 0.9 + 0.1 * hqRandom();
    float t = 0.01;
    vec2 res = vec2(1e9);
    bool hit = false;
    
    for(int i = 0; i < MARCHING_STEPS; ++i)
    {
        res = map(ro + t * rd);
        res.x = abs(res.x) * rnd * MARCHING_STEP_SCALE;
        float k = res.y == MAT_WALL ? 10. : 1.;
        if (res.x < 0.0005 * k + 0.0002 * t)
        {
            hit = true;
            break;
        }
        if (t > FAR)
        {
            break;
        }
        
        t += res.x;
    }
    if (!hit) t = -1.;

    return vec2(t, res.y);
}


float schlickFresnel(float F0, float lightDotHalf)
{
    return F0 + (1. - F0) * pow(1.0 - lightDotHalf, 5.);
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
    return mix(spec_refl, diff_refl, .8);
}


vec3 sampleLight(vec3 pos, vec3 V, vec3 n, Material mate)
{
    vec3 col = vec3(0);

    vec3 sha = shadow(pos + 0.001*n, sunDir);

    //float occ = ao(pos, n);
    col = (sunCol * phongBrdf(sunDir, V, n, pos, mate) * max(0., dot(n, sunDir)) * sha);

    if (mate.id == MAT_TREE_LEAVES)
        col += sunCol * max(0., dot(-n, sunDir)) * mate.albedo * 0.1;
   
    return col;
}

vec3 ortho(vec3 v)
{
    return abs(v.x) > abs(v.z) ? vec3(-v.y, v.x, 0.0) : vec3(0.0, -v.z, v.y);
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


vec4 sampleBsdf(
    vec3 pos,
    vec3 worldNormal,
    vec3 V,
    Material mate,
    out vec3 L
)
{
    L = normalize(getHemisphereSampleCosWeighted(worldNormal, hash21(seed++), 1.));
    float pdf = max(0., dot(worldNormal, L)) / PI;
    return vec4(phongBrdf(L, V, worldNormal, pos, mate), pdf);
}

vec3 scene(vec3 ro, vec3 rd, vec2 uv)
{
    vec3 throughput = vec3(1.);
    vec3 Lo = vec3(0);

    float f = smoothstep(.4, 1., fbm(uv * vec2(4., 10.)));
    vec3 skycol = vec3(195, 30, 10) / 255. * .5;
    skycol = mix(vec3(0), mix(skycol*skycol, vec3(0.), (1. - f * f) * smoothstep(-1., .8, uv.y)), smoothstep(-.0, 2., uv.y));

    //return skycol;
    // 
    // bounces
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        vec2 hit = intersect(ro, rd, FAR);
        float t = hit.x;

        vec3 pos = ro + hit.x * rd;

        if (hit.x < 0.)
        {
            // indirect part
            // it has to finally hit a light or the sky to have color
            // or there will be only direct part
            Lo = Lo + throughput * skycol;
            //Lo += background(ro, rd);
            break;
        }

        vec3 n = getNormal(pos, hit.x);

        Material mate = getMaterial(hit.y, pos);
        vec3 q = pos;
        q.y -= HEIGHT(q.z);

        float a = 0., b = 0.;
        if (mate.id == MAT_TREE_TRUNK)
            a = .2, b = 200.;
        if (q.y <= .05)
            a = .5, b = 100.;
        if(a > 0.)
            n = bump_mapping(q * a, n, b / max(iResolution.x, iResolution.y));

        if (mate.id == MAT_TREE_LEAVES)
            sunDir = normalize(vec3(-1, 1, 1));

        vec3 nextRd = rd, nextRo = pos;

        // can use mis to optimize
        vec3 directLighting = sampleLight(pos, -rd, n, mate);

        // throughput = A0C0..An-1Cn-1,  direct = AnCnLn
        Lo += throughput * directLighting;
        if (mate.id != MAT_TREE_LEAVES) break;


        vec4 btdfAndPdf = vec4(0., 0., 0., 1.);

        // Sample btdf
        btdfAndPdf = sampleBsdf(pos, n, -rd, mate, nextRd);
        

        if (btdfAndPdf.w < EPSILON) break;


        
        // Lo = A0C0L0 + A0C0A1C1L1 + ... + A0C0..AnCnLn  (A is the brdf, C is cos, L is directLight)
        // accumulate the new brdf*cos for this round,  brdf * cos / pdf
        throughput *= btdfAndPdf.xyz * max(0., dot(nextRd, n)) / btdfAndPdf.w * .5;
                                  
        rd = nextRd;
        ro = pos + 0.002 * n;
    }

    //Lo = mix(Lo, skycol*0.1, (1. - exp(-.00003 * t * t)));

    return Lo;

}

vec4 mainImage(vec2 fragCoord)
{
    if (iCameraDirty > 0.)
    {
        MAX_BOUNCES = 1;//  iCameraDirty > 0. ? 3 : 3;
        MARCHING_STEPS = 128;// iCameraDirty > 0. ? 128 : 1024;
        MARCHING_STEP_SCALE = 5.;// iCameraDirty > 0. ? 5. : 1.;

        // only update 1 out of 4 pixels when moving camera
        if (any( (uint2(fragCoord) ) % 2 != 0))
            return vec4(0,0,0,1);
    }
    else
    {
        MAX_BOUNCES = 3;//  iCameraDirty > 0. ? 3 : 3;
        MARCHING_STEPS = 1024;// iCameraDirty > 0. ? 128 : 1024;
        MARCHING_STEP_SCALE = 1.;// iCameraDirty > 0. ? 5. : 1.;
    }
    gFragCoord = fragCoord;

    randomState = (fragCoord.x + fragCoord.y * iResolution.x) + float(uint(uint(iFrame) * 123u) % 32768u);
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

    if (iFrame > 0. && iCameraDirty == 0. && iAccumulationRestart == 0.)
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
