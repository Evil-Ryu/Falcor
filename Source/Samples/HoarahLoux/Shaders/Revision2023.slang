
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

#define PATHTRACER 1
#define FAR 530.
//#define MAX_BOUNCES 3
#define INTER_THRESHOLD .001
#define EPSILON 			0.0001

#define EVENT_REFLECTION 1.
#define EVENT_TRANSMISSION 2.

#define PI 3.1415926535
#define DE_ITER 14

#define MAT_FRACTAL 0.
#define MAT_TREE_TRUNK 1.
#define MAT_TREE_LEAVES 2.
#define MAT_FLOWER 3.
#define MAT_FLOWER_LEAVES 4.
#define MAT_WALL 5.

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

float terrianHeight(float z)
{
    return sin(z * .2  + 1.) * 2.;
    //return -smoothstep(30., 13., z) * 3.;
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
        p.y += terrianHeight(p.z);
        vec3 col = fractalMate(p.xzy);

        col = mix(vec3(1.1, .1, .0), col, smoothstep(3.5, 4.9, p.y));
        //col = mix(vec3(.12, .3, .1), col, 1. - smoothstep(6., 25., p.y));

        mate.albedo = col;
    }
    else if (id == MAT_TREE_TRUNK)
    {
        mate.albedo = vec3(0.561, 0.459, 0.357) * .2;
    }
    else if (id == MAT_TREE_LEAVES)
    {
        /*mate.albedo = mix(vec3(0.353, 0.518, 0.152)*.5,
            vec3(0.655, 0.384, 0.004), smoothstep(8.,17.,length(p.xy)));*/
        mate.albedo = mix(vec3(1.000, 0.400, 0.000) * .5, vec3(1.000, 0.635, 0.000),smoothstep(8., 17., length(p.xy)));
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
        mate.albedo = vec3(0.690, 0.565, 0.451)*.7;
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
static float haha = 1.;
float mb(vec3 z, bool yeah)
{
    haha = 1.;
    fixed_radius2 = 2.;
    min_radius2 = 0.1;
    folding_limit = 1.4;
    scale = 3.;
    float iter = 9.;
    if(!yeah)z.x = mod(z.y + 1.0, 2.0) - 1.0;
    else
    {
        folding_limit = 1.8;
        //if (z.x < 0.) folding_limit = 2.;
        if (z.y > -3.16) return 1e2;
        z.z = mod(z.z, 2.0) - 1.0;
    }
    orb = vec4(1000);
    vec3 offset = z;
    float dr = 1.0;
    for (int n = 0; n < iter; ++n)
    {
        z.xy = mul(mat2(.54, .84, -.84, .54), z.xy);

        box_fold(z, dr);
        sphere_fold(z, dr);

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
        if (i == 3 && q.x<-44.) a = 2.2;
		p = a*clamp(p, -c, c) - p;
        float b = 1.;
		float k = max(b / dot(p, p), 0.03);
		p *= k;
		scale *= k;
	}

    float l = min(length(p.xz), mb(p*1.8, false)/1.8+.01);  // 2.3
    
	float rxy = l - .4;
	float n = l * p.z;
	rxy = max(rxy, -n / length(p) - .01);
	return rxy / abs(scale * 1.5);
}

vec3 fractalMate(vec3 p)
{
    vec3 q = p;
    float acc = 100.;
    vec3 acc3 = vec3(0);
    for(int i = 0; i < 8; i++)
    {
        float r2Old = dot(p, p);
        vec3 p0 = 2. * clamp(p, -c, c) - p;
        
        acc3 += distance(p,p0) * max(1./r2Old, .3);
        p = p0;
        float r2 = dot(p, p);
        acc = min(acc, r2Old + r2);

        float k = max(1. / r2, 0.03);
		p *= k;
        //acc += length(p0.xz - p.xz);
    }

    vec3 res = vec3(.4, .5, .25) + vec3(.25, .2, .1) * cos(6.28*(vec3(.4)*acc3));
    //vec3 k = vec3(.3, .2, .2);
   
    return res;
}


float sabs(float x, float k)
{
    return sqrt(x * x + k) - 0.1;
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

float smax(float a, float b, float k)
{
    return smin(a, b, -k);
}







#define MTL_EYE 2.0
#define MTL_CHEEK 3.0
#define MTL_JAW 4.0
#define MTL_HAIR 5.0
#define MTL_ORBIT 6.0

static float g_d;
static float g_mtl_id;
static vec3 g_eye_pos;
static vec3 g_upper_lip_pos;
static vec3 g_lower_lip_pos;
static vec3 g_cheek_pos;


void rp_rotate_y(inout vec3 p, float a)
{
    float c, s; vec3 q = p;
    c = cos(a); s = sin(a);
    p.x = c * q.x + s * q.z;
    p.z = -s * q.x + c * q.z;
}

void rp_rotate_z(inout vec3 p, float a)
{
    float c, s; vec3 q = p;
    c = cos(a); s = sin(a);
    p.x = c * q.x - s * q.y;
    p.y = s * q.x + c * q.y;
}


void rp_rotate_x(inout vec3 p, float a)
{
    float c, s; vec3 q = p;
    c = cos(a); s = sin(a);
    p.y = c * q.y - s * q.z;
    p.z = s * q.y + c * q.z;
}


//-----------distance functions from iq----------------
float sphere(vec3 p, float r)
{
    return length(p) - r;
}

float round_box(vec3 p, vec3 b, float r)
{
    return length(max(abs(p) - b, 0.0)) - r;
}

float torus(vec3 p, vec2 t)
{
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float tri_prism(vec3 p, vec2 h)
{
    vec3 q = abs(p);
    return max(q.z - h.y, max(q.x * 0.866025 + p.y * 0.5, -p.y) - h.x * 0.5);
}

float capsule(vec3 p, vec3 a, vec3 b, float r)
{
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
//----------------------------------------------------------------------
float hash(vec2 p)
{
    p = fract(p * vec2(5.3983, 5.4472));
    p += dot(p.yx, p.xy + vec2(21.5351, 14.3137));
    return fract(p.x * p.y * 95.4337);
}


#if 0
float jaw(vec3 p, vec3 ds, float s)
{
    p.y += 1.2;
    p.z -= 1.3;
    //rp_rotate_x(p, 0.2);
    float d0 = round_box(p, vec3(s * sin((1.0 - p.y)), 0.2 , 1.) + ds, 0.1);
    p.y = abs(p.y) - 0.18;
    p.z -= 0.2;
    p.y += 0.3;
    float d1 = capsule(p, vec3(0.0, 0.0, 0.0), vec3(0.5, 0.0, 0.), 0.1);

    return d0;// smin(d0, d1, 0.2);
}
#else

float triPrism(vec3 p, vec2 h)
{
    const float k = sqrt(3.0);
    h.x *= 0.5 * k;
    p.xy /= h.x;
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0 / k;
    if (p.x + k * p.y > 0.0) p.xy = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0, 0.0);
    float d1 = length(p.xy) * sign(-p.y) * h.x;
    float d2 = abs(p.z) - h.y;
    return length(max(vec2(d1, d2), 0.0)) + min(max(d1, d2), 0.);
}

float ellipsoid(in vec3 p, in vec3 r) // approximated
{
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}


float jaw(vec3 p, vec3 ds, float s)
{
    vec3 q = p;
    p.x = abs(p.x) - .25;
    p.xy = mul(rot(-.1), p.xy);

    p.y += 1.2; 
    p.z -= 1.4;
    float d0 = triPrism(p*vec3(.18,1,1), vec2(.1, .1));


    p = q;
    p.y += 1.3;
    p.z -= 1.4;
    float d1 = ellipsoid(p, vec3(.4,.1,.1));
    float d = min(d0, d1);
    return d;
}

#endif
float nose(vec3 p)
{
    p.y += 0.5;
    p.z -= 1.25;
    float d0 = round_box(p,
        vec3(0.01,
             0.3,
             atan((1.0 - p.y * 2.) * (1.0 - p.y * p.y * 2.)) * 0.45),
        0.1);

    p.z -= 0.3;
    p.y += 0.4;
    p.x = abs(p.x) - 0.02;
    float d1 = capsule(p, vec3(0.0, 0.0, 0.0), vec3(0.3, 0.15, -0.4) * 0.4, 0.07);
    return smin(d0 / 2., d1, 0.2);
}

float cheek(vec3 p)
{
    p.y += 0.7;
    p.z -= 1.1;
    p.x = abs(p.x) - 0.7;
    float d0 = capsule(p + vec3(1.0, -0.15, 0.0), vec3(0.0, 0.0, -0.1), vec3(.9, -0.1, -.1), 0.35);
    return d0;
}

float orbit(vec3 p)
{
    p.y += 0.16;
    p.z -= 1.23;
    p.x = abs(p.x) - 0.5;
    rp_rotate_z(p, -0.2);
    rp_rotate_y(p, -0.4);
    float d0 = round_box(p, vec3(0.24, 0.04, 0.24), 0.01);

    return d0;
}

float eye(vec3 p)
{
    p.y += 0.19;
    p.z -= 0.9;
    p.x = abs(p.x) - 0.47;
    float d0 = sphere(p, 0.28);
    return d0;
}

float brow_ridge(vec3 p)
{
    p.y += 0.2;
    p.z -= 0.3;
    p.x = abs(p.x) - 0.1;
    rp_rotate_z(p, -0.3);
    rp_rotate_x(p, 0.3);

    float d0 = torus(p, vec2(0.83, 0.1));
    return d0;
}


float head(vec3 p, float id)
{
    vec3 tp = p;
    rp_rotate_x(tp, 0.3);
    tp.y -= 1.7;
    tp.z -= 0.6;
    float d0 = round_box(tp, vec3(0.87 * (0.3 * sin(tp.y) + 0.5),
        0.6,
        0.04 + (tp.y * 0.15 + 0.1)), 0.4);
    tp = p;
    tp.y -= 3.0;
    tp.z += .599;
    float d1 = sphere(tp, 1.0);
    float d2 = brow_ridge(tp);
    float d3 = orbit(tp);
    float d4 = cheek(tp);
    float d5 = nose(tp);
    float d6 = jaw(tp, vec3(0.0), 0.4);

    // movement of jaw
    vec3 jp = tp + vec3(0.0,
        0.015 * floor(2.0 * sin(46.0 * smoothstep(7.0, 12.0, mod(0., 12.0)))),
        0.2);
    float d7 = jaw(jp, vec3(-0.01, -0.1, -0.9), 0.3);
    float d8 = eye(tp) + 0.05;
    float d10 = sphere(p + vec3(0.0, -2.2, 2.2), 2.25);

    float d = smin(d1, d0, 0.5);
    d = smin(d, d2, 0.3);
    if (d4 < d) { g_mtl_id = MTL_CHEEK; g_cheek_pos = p; }
    d = smin(d, d4,.2);
    d = smax(d, -d3, .1);
    //d = smax(d, -d6, .2);
    if (d7 < d) {g_mtl_id = MTL_JAW; g_lower_lip_pos = jp; }
    d = smin(d, d7, .05);

    d = max(d, -d10);
    //d -= texture(iChannel0, tp.xy * 0.1 - vec2(0.3, 0.3)).y * 0.025;
    if (d5 < d) { g_mtl_id = 1.0; }
    d = smin(d, d5, 0.2);

    if (id < 2.)
    {
        if (d8 < d) { g_mtl_id = MTL_EYE; g_eye_pos = p; }
        d = min(d, d8);
    }
    
    g_upper_lip_pos = p;

    d += fbm(p * 10.) * 0.03;
    return d;
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

float dbar(vec3 p, vec3 a, vec3 b, float r)
{
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
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

    float dcap = dbar(p + vec3(0., 0., len),
        vec3(0., 0., len),
        vec3(0., 0., len) + len * l * dir,
        k);

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

float dbar2(vec3 p, vec3 a, vec3 b, vec3 r)
{
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return (length((pa - ba * h) / r) - 1.) * min(min(r.x, r.y), r.z);
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
    //return length(p) - 1.;
    float mateid = MAT_FRACTAL;


    vec3 q = (p - vec3(0.87, 3., 1.82));


    vec3 q1 = q + vec3(0,-.1,-2.);
    vec2 r0 = tree(q1 * .37); r0.x /=.37;

    q1 = q;
    vec2 r1 = flower(1.9*(q1 + vec3(2.8, 2.3, -8.)), 0.); r1.x /= 1.9;
    
    q1 = q;
    vec2 r2 = flower(1.9 * (q1 + vec3(4., 0.5, -6.)), 1.); r2.x /= 1.9;

    q = p + vec3(-35, 4.5, 16);
    q.y += terrianHeight(q.z);
    vec2 r4 = vec2(fractal(q.xzy), MAT_FRACTAL);


    // begin skybox,  for build skybox for espen
    float s0 = box(p - vec3(6., 4, -23.5), vec3(1.2));
    r4.x = max(r4.x,-s0);

    s0 = box(p - vec3(6.5, 2., -8.5), vec3(1.4));
    //r4.x = min(r4.x, s0);
    r4.x = max(r4.x, -s0);

    //if (p.z < -79.) r4.x = 10000.;
    //if (p.z > 45.) r4.x = 10000.;
    if (p.y > 70.) r4.x = 10000.;
    // end skybox

    /*q = p;
    q.yz = mul(rot(1.), q.yz);
    vec2 r7 = vec2(head((q-vec3(0,-310,-220.)) * .01, 0.) / .01, MAT_WALL);*/

    vec2 r7 = vec2(head((p - vec3(0, -20, -108)) * .05, 0.) / .05, MAT_WALL); 

    q = p;
    q.xz = q.zx;
    q.yz = mul(rot(-.3), q.yz);
    vec2 r8 = vec2(head((q - vec3(-10, -12, -18)) * .1, 1.) / .1, MAT_WALL);


    q = p;
    q.xz = mul(rot(3.15), q.xz);
    q.xz = q.zx;
    q.xy = mul(rot(.5), q.xy);
    q.yz = mul(rot(-.2), q.yz);
    vec2 r9 = vec2(head((q - vec3(10, -13, -28)) * .15, 2.) / .15, MAT_WALL);





    //p.x -= sin(p.z * .2+3.) * 1.55;
    p.xz = mul(rot(.1), p.xz);
    vec2 r6 = vec2(box(p + vec3(79,0,0), vec3(70, 1e5, 1e5)), MAT_FRACTAL);
    //r4.x = max(r4.x, -r6.x);

    if (p.z > 6.)p.y -= sin(p.z * .3 + 2.) * 2.;
    else p.y -= sin(p.z * .1);
    
    vec2 r5 = vec2(max(r6.x, mb((p * 0.1 - vec3(-3., 3.4+smoothstep(10.,-1.,p.z)*0.4, 0.)), true) / 0.1), MAT_WALL);

    //return r4;

    vec2 r = r4;
    //if (r1.x < r.x) r = r1;
    //if (r2.x < r.x) r = r2;
    //if (r4.x < r.x) r = r4;
    if (r7.x < r.x) r = r7;
    if (r8.x < r.x) r = r8;
    if (r9.x < r.x) r = r9;

    //if (r5.x < r.x) r = r5;

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

float ao(vec3 p, vec3 n)
{
    float r = 0.0, w = 1.0, d;
    for (float i = 1.0; i < 5.0 + 1.1; i++)
    {
        d = i / 5.;
        r += w * (d - map(p + n * d).x);
        w *= 0.5;
    }
    return 1.0 - clamp(r, 0., 1.);
}

//static vec3 sunDir = normalize(vec3(-.5, 1., -.2));
static vec3 sunDir = normalize(vec3(-1, .5, 1));
//static vec3 sunDir = normalize(vec3(1,1,0));
//static vec3 sunCol = vec3(253., 184., 19.) / 256.;
static vec3 sunCol = vec3(1.,.8,.3);


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
    //if (!hit) t = -1.;

    return vec2(t, res.y);
}


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
    return mix(spec_refl, diff_refl, .8);
}


vec4 sampleLight(vec3 pos, vec3 V, vec3 n, Material mate)
{
    vec3 col = vec3(0);

    float lightSelectPdf = 1.f;

    if (lightSelectPdf < EPSILON) return vec4(0);

    vec3 sha = shadow(pos + 0.001*n, sunDir);

    //float occ = ao(pos, n);

    if(mate.id == MAT_TREE_LEAVES)
    col = (sunCol * phongBrdf(sunDir, V, n, pos, mate) * max(0., dot(n, sunDir)) * sha + sunCol*max(0.,dot(-n, sunDir)* mate.albedo * 0.1)) / lightSelectPdf;
    else
    col = (sunCol * phongBrdf(sunDir, V, n, pos, mate) * max(0., dot(n, sunDir)) * sha) / lightSelectPdf;

    // begin skybox
#if 1
    float occ = ao(pos, n);
    col *= 2;
    //occ = smoothstep(.1, .8, occ);
    vec3 skycol = vec3(0., .5, 1.) * .003;
    col += .1 * (sunCol * phongBrdf(-sunDir, V, n, pos, mate) * max(0., dot(n, -sunDir))) / lightSelectPdf;
    col += max(0., n.y) * skycol * 1.;
    col *= occ;
#endif
    //col = .05 + .95 * smoothstep(0.3, 1., occ) * vec3(1);
    //col = occ * occ * vec3(1);
    //end skybox
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

vec3 background(vec3 ro, vec3 rd)
{
    vec3 pos = ro + FAR * rd;
    vec3 skyCol = vec3(1.) * smoothstep(.0,.5, fbm(rd.xy*2.));
    return skyCol;
    //float d = length(pos.xy + vec2(0, 30.)) - 60.;
    float d = length(pos.xy+vec2(50,-20.)) - 10.;
    d = smoothstep(0., 1., d);
    return mix(vec3(.9, .9, 1.)*.1, skyCol, d);
}


float noise(vec3 p)
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

float fbm(vec3 p)
{
    mat3 m = mat3(.0, .8, .6,
        -.8, .36, -.48,
        -.6, -.48, .64);
    float f = 0., s = .5;
    for (int i = 0; i < 4; ++i)
    {
        f += s * noise(p);
        p = mul(p, m) * 2.01;
        s *= .5;
    }

    return f;
}


float mapCloud(vec3 p)
{
    p *= .5;
    return smoothstep(.0, 1., fbm(p * vec3(1, 1, .2)) + .5 * fbm(p * vec3(2.5,2.5,1.)));
}

vec3 renderCloud(vec3 ro, vec3 rd, vec2 uv)
{
    vec4 sum = vec4(0, .125, .25, 1);
    sum.xyz *= .125;
   // float t = (300.0 - ro.y) / rd.y;
    //if (t < 0.) return sum.xyz;
    float t = 10.;
    float dt = .2;


    float rnd = .95 + .05 * hash21(seed++).x;

    for (int i = 0; i < 128; ++i)
    {
        vec3 p = ro + t * rd;
        float d = mapCloud(p);

        if (d > 0.)
        {
            float s = 0.;
            vec3 st = normalize(p + sunDir);
            vec3 sp = p;
            for (int j = 0; j < 20; j++)
                s += mapCloud(sp += st);

            sum.xyz += exp(-s * .015) * d * vec3(1.5) * sunCol * (1. - d) * sum.a;
            sum.a *= 1. - d;
        }

        if (sum.a < .05 || t > 1000.) break;

        t += dt;
        dt = max(1., .05 * t);
    }
    return sum.xyz;
}


vec3 scene(vec3 ro, vec3 rd, vec2 uv)
{
    vec2 hit = intersect(ro, rd, FAR);

    float t = hit.x;

    vec3 throughput = vec3(1.);

    vec3 Lo = vec3(0);

    //vec3 cloud = vec3(0, .125, .25) * 0.125;// renderCloud(ro, rd, uv);
    vec3 cloud =  renderCloud(ro, rd, uv);
    vec3 skycol = cloud * vec3(.8,.5,.5) * .2;// *vec3(.585, .014, .0015);;

    //return sky;

    // bounces
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        vec3 pos = ro + hit.x * rd;

        //if (hit.x < 0.)
        if(hit.x >= FAR)
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
        q.y -= terrianHeight(q.z);
        if (mate.id == MAT_TREE_TRUNK || (q.y <= .05))
        {
            
            n = bump_mapping(q * .5, n, 100. / max(iResolution.x, iResolution.y));
        }

        if (mate.id == MAT_TREE_LEAVES)
        {
         //   n += sunDir, n = normalize(n);
            sunDir = normalize(vec3(-1, 1, 1));
        }

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

    vec3 fog = vec3(0, .125, .25) * 0.125;
    fog = mix(fog, skycol, smoothstep(70., 90., t));
    Lo = mix(Lo, skycol, (1. - exp(-.0001 * t * t)));
    //Lo = mix(Lo, vec3(0., .5, 1.) * .003, smoothstep(8.,2.,4.*(length(uv*vec2(1.,2) + vec2(1.3, -2)))));

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
    //vec3 upvec = vec3(0, 1, 0);
    vec3 upvec = UpVector;
    vec3 forward = normalize(ta - ro);
    vec3 right = normalize(cross(forward, upvec));
    //vec3 right = normalize(cross(UpVector, forward));
    //vec3 up = normalize(cross(forward, right));
    vec3 up = normalize(cross(right, forward));

    vec3 rd = normalize(p.x * right + p.y * up + 1. * forward);


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
