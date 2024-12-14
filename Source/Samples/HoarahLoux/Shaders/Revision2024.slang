
// pathtracer with transparency, multi scattering volume

#define vec4 float4
#define vec3 float3
#define vec2 float2
#define ivec2 int2
#define ivec3 int3
#define ivec4 int4
#define uvec2 uint2
#define uvec3 uint3
#define uvec4 uint4

#define mix lerp
#define fract frac
#define mat3 float3x3
#define mat2 float2x2
#define floatBitsToUint asuint


float mod(float x, float y)
{
    return x - y * floor(x / y);
}

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

    float var0;
    float var1;
    float var2;
    float var3;
    float var4;
};


layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D iPass0Output : register(t0);

static float seed;

static int MAX_BOUNCES = 1;//  iCameraDirty > 0. ? 3 : 3;
static int MARCHING_STEPS = 128;// iCameraDirty > 0. ? 128 : 1024;
static float MARCHING_STEP_SCALE = 1.;// iCameraDirty > 0. ? 5. : 1.;
static vec3 ro, rd;

#define FAR 1000.
#define INTER_THRESHOLD .001
#define EPSILON 			0.0001

#define PI 3.1415926535
#define DE_ITER 14

#define MAX_SHININESS 2048.



uint baseHash(uvec2 p) {
    p = 1103515245U * ((p >> 1U) ^ (p.yx));
    uint h32 = 1103515245U * ((p.x) ^ (p.y >> 3U));
    return h32 ^ (h32 >> 16);
}

float hash1(inout float s) {
    uint n = baseHash(floatBitsToUint(vec2(s += .1, s += .1)));
    return float(n) / float(0xffffffffU);
}

vec2 hash2(inout float s) {
    uint n = baseHash(floatBitsToUint(vec2(s += .1, s += .1)));
    uvec2 rz = uvec2(n, n * 48271U);
    return vec2(rz.xy & uvec2(0x7fffffffU)) / float(0x7fffffff);
}

float hash11(float p)
{
    vec2 p2 = fract(vec2(p * 5.3983, p * 5.4427));
    p2 += dot(p2.yx, p2.xy + vec2(21.5351, 14.3137));
    return fract(p2.x * p2.y * 95.4337);
}

vec2 hash21(float p)
{
    vec2 p2 = fract(p * vec2(5.3983, 5.4427));
    p2 += dot(p2.yx, p2.xy + vec2(21.5351, 14.3137));
    return fract(vec2(p2.x * p2.y * 95.4337, p2.x * p2.y * 97.597));
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

float bump(vec3 p)
{
    return fbm(p * vec3(.1, .025, .1) * iResolution.x);
}

vec3 bump_mapping(vec3 p, vec3 n, float weight)
{
    vec2 e = vec2(2. / iResolution.y, 0);
    vec3 g = vec3(bump(p - e.xyy) - bump(p + e.xyy),
        bump(p - e.yxy) - bump(p + e.yxy),
        bump(p - e.yyx) - bump(p + e.yyx)) / (e.x * 2.);
    g = (g - n * dot(g, n));
    return normalize(n + g * weight);
}

mat2 rot(float r)
{
    return mat2(cos(r), sin(r), -sin(r), cos(r));
}

float smin(float a, float b, float k)
{
    float h = clamp(.5 + .5 * (b - a) / k, .0, 1.);
    return mix(b, a, h) - k * h * (1. - h);

}


void rz(inout vec3 p, float a)
{
    float c, s;
    vec3 q = p; c = cos(a); s = sin(a);  
    p.x = c * q.x - s * q.y;
    p.y = s * q.x + c * q.y;
}

//static const float ang = 1.;
static const float ang = var4;
static const mat2 rota = mat2(cos(ang), sin(ang),
    -sin(ang), cos(ang));

//==========  mandelbox ===========================
//static float fixed_radius2 = 2.0;
//static float min_radius2 = 0.1;
//static float folding_limit = 1.4;
//static float scale = 3.;

static float fixed_radius2 = var0;
static float min_radius2 = var1;
static float folding_limit = var2;
static float scale = var3;
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

float mb(vec3 z) {
    z.z = mod(z.z + 1.0, 2.0) - 1.0;
    vec3 offset = z;
    float dr = 1.0;
    for (int n = 0; n < 13; ++n) {
        //z.xy = rota * z.xy;
        z.xy = mul(rota, z.xy);

        box_fold(z, dr);
        sphere_fold(z, dr);

        z = scale * z + offset;
        dr = dr * abs(scale) + 1.;
        orb = min(orb, vec4(abs(z.xyz), dot(z, z)));
    }
    float r = length(z);
    return r / abs(dr);
}


vec2 fold(vec2 p, float s, out float id)
{
    float a = PI / s + atan2(p.x, p.y);
    float n = PI * 2. / s;
    a = floor(a / n);
    id = mod(a, s);
    p = mul(rot(-a * n), p);
    return p;
}

float dbar2(vec3 p, vec3 a, vec3 b, vec3 r)
{
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), .0, 1.);
    return (length((pa - ba * h) / r) - 1.) * min(min(r.x, r.y), r.z);
}


float box(vec3 p, vec3 b)
{
    vec3 d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), .0) + length(max(d, .0));
}

float bSphere(vec4 sph)
{
    vec3 p = sph.xyz;
    float t = -100.;
    vec3  ce = ro - p;
    float b = dot(rd, ce);
    float c = dot(ce, ce) - sph.w * sph.w;
    float h = b * b - c;
    if (h > 0.0)
    {
        t = -b - sqrt(h);
    }
    return t;
}

void rot22(inout vec2 p, float a) {
    p = cos(a) * p + sin(a) * vec2(p.y, -p.x);
}

vec2 rot2(vec2 p, float a)
{
    float si = sin(a);
    float co = cos(a);
    return mul(mat2(co, si, -si, co), p);
}

void ry(inout vec3 p, float a) {
    float c, s; vec3 q = p;
    c = cos(a); s = sin(a);
    p.x = c * q.x + s * q.z;
    p.z = -s * q.x + c * q.z;
}
void rx(inout vec3 p, float a)
{
    float c, s; vec3 q = p;
    c = cos(a); s = sin(a);
    p.y = c * q.y - s * q.z;
    p.z = s * q.y + c * q.z;
}

float rbox(vec3 p, vec3 b, float r)
{
    return length(max(abs(p) - b, 0.0)) - r;
}

float cylinder(vec3 p, vec2 h)
{
    vec2 d = abs(vec2(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}


float sphere(vec3 p, float r)
{
    return length(p) - r;
}

float smax(float a, float b, float k)
{
    return smin(a, b, -k);
}

vec2 merge(vec2 d0, vec2 d1)
{
    if (d0.x < d1.x) return d0;
    else return d1;
}

vec2 smerge(vec2 d0, vec2 d1, float k)
{
    vec2 res = merge(d0, d1);
    return vec2(smin(d0.x, d1.x, k), res.y);
}
#define GR 1.618

float sabs(float x, float k)
{
    return sqrt(x * x + k) - 0.1;
}

vec2 plane(vec3 p, float y)
{
    return vec2(abs(p.y + y), 4.);
}

vec2 screw(vec3 p)
{
    float d0 = cylinder(p.xyz + vec3(0.08, 0.0, 0.0), vec2(.035, .46));
    p.xz = rot2(p.xz, -0.5);
    float d1 = box(p.xyz + vec3(0.07, 0.0, -0.04), vec3(0.012, 1., 0.033));
    float d = max(d0, -d1);
    return vec2(d, 0.);
}

float vcapsule(vec3 p, float h, float r)
{
    p.y -= clamp(p.y, .0, h);
    return length(p) - r;

}

float vcylinder(vec3 p, float h, float r)
{
    vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float cutSphere(vec3 p, float r, float h)
{
    float w = sqrt(r * r - h * h);

    vec2 q = vec2(length(p.xz), p.y);

    float s = max((h - r) * q.x * q.x + w * w * (h + r - 2. * q.y), h * q.x - w * q.y);

    return (s < 0.) ? length(q) - r :
        (q.x < w) ? h - q.y :
        length(q - vec2(w, h));
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
static vec3 g_hair_offset = vec3(0.0, -2.2, 0.8);
static float g_hair_scale = 2.0;

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


float hash(vec2 p)
{
    p = fract(p * vec2(5.3983, 5.4472));
    p += dot(p.yx, p.xy + vec2(21.5351, 14.3137));
    return fract(p.x * p.y * 95.4337);
}

float noise(vec2 p)
{
    vec2 f;
    f = fract(p);
    p = floor(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(p), hash(p + vec2(1.0, 0.0)), f.x),
        mix(hash(p + vec2(0.0, 1.0)), hash(p + vec2(1.0, 1.0)), f.x), f.y);
}


float jaw(vec3 p, vec3 ds, float s)
{
    p.y += 1.73;
    p.z -= 1.37;
    rp_rotate_x(p, 0.3);
    float d0 = round_box(p, vec3(s * sin((1.0 - p.y)), 0.4, 1.0) + ds, 0.1);
    p.x = abs(p.x) - 0.18;
    p.z -= 0.3;
    p.y += 0.3;
    float d1 = capsule(p, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.5, -0.23), 0.07);

    return smin(d0, d1, 0.2);
}

float nose(vec3 p)
{
    p.y += 0.6;
    p.z -= 1.25;
    float d0 = round_box(p, vec3(0.01,
        0.4,
        atan((1.0 - p.y * 2.) * (1.0 - p.y * p.y * 2.)) * 0.45), 0.05);

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
    float d0 = capsule(p + vec3(.9, -.15, 0), vec3(0, 0, -.1), vec3(.8, -.1, 0), .35);
    return d0;
}

float orbit(vec3 p)
{
    p.y += 0.16;
    p.z -= 1.23;
    p.x = abs(p.x) - 0.5;
    rp_rotate_z(p, -0.2);
    rp_rotate_y(p, -0.4);
    //float d0 = round_box(p, vec3(0.24, 0.04, 0.24), 0.13);
    float d0 = round_box(p, vec3(.2, .02, .2), 0.13);

    return d0;
}

float eye(vec3 p)
{
    p.y += 0.19;
    p.z -= 0.9;
    p.x = abs(p.x) - 0.47;
    //float d0 = sphere(p, 0.28);
    float d0 = sphere(p, 0.2);
    return d0;
}

float brow_ridge(vec3 p)
{
    p.y += 0.2;
    p.z -= 0.4;
    p.x = abs(p.x) - 0.2;
    rp_rotate_z(p, -0.3);
    rp_rotate_x(p, 0.3);

    float d0 = torus(p, vec2(0.83, 0.07));
    return d0;
}


float head(vec3 p)
{
    p.z *= -1.;
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
    vec3 jp = tp;
    float d7 = jaw(jp, vec3(-0.01, -0.1, -0.9), 0.3);
    float d8 = eye(tp);
    float d10 = sphere(p + vec3(0.0, -2.2, 2.2), 2.25);

    float d = smin(d1, d0, 0.5);
    d = smin(d, d2, 0.3);
    if (d4 < d) { g_mtl_id = MTL_CHEEK; g_cheek_pos = p; }
    d = smin(d, d4, 0.2);
    d = smax(d, -d3,.1);
    //d = max(d, -d6);
    if (d7 < d) { d = d7; g_mtl_id = MTL_JAW; g_lower_lip_pos = jp; }
   // d = max(d, -d10);
    if (d5 < d) { g_mtl_id = 1.0; }
    d = smin(d, d5, 0.2);

   // if (d8 < d) { d = d8; g_mtl_id = MTL_EYE; g_eye_pos = p; }
    g_upper_lip_pos = p;


    return d;
}

float triPrism(vec3 p, vec2 h)
{
    vec3 q = abs(p);
    return max(q.z - h.y, max(q.x * .866025 + p.y * .5, -p.y) - h.x * .5);
}

vec2 polar_rep(vec2 p, float n)
{
    n = PI * 0.5 / n;
    float a = atan2(p.y, p.x);
    float r = length(p);
    a = mod(a + n / 2.0, n) - n / 2.0;
    p = r * vec2(cos(a), sin(a));
    return 0.5 * (p + p - vec2(1, 0));
}

float fOpUnionStairs(float x, float y, float r, float n)
{
    float s = r / n;
    float u = y - r;
    return min(min(x, y), 0.5 * (u + x + abs(mod(u - x + s, 2. * s) - s)));
}

float fOpUnionChamfer(float a, float b, float r) {
    return min(min(a, b), (a - r + b) * sqrt(0.5));
}

vec2 lego(vec3 p)
{
    return fOpUnionStairs(max(abs(vcylinder(p.yzx+vec3(0,1,0),.7,.5))-.1,-p.z-1.5), fOpUnionStairs(box(p, vec3(1, 1.3, 1)), vcylinder(p, 2., .5), .3, 4.), .2, 2.);
}

vec2 sword(vec3 p)
{
    rot22(p.xy, -.6);
    float d = triPrism(vec3(p.x * 2., abs(p.y - 1.), p.z), vec2(.4-exp(p.z*2.-1.8) * 0.38, 2.)) / 2.;
    d = fOpUnionStairs(d, vcylinder(p.xzy+vec3(0,2.8,-1.), 1.2,.1), .3,4.);

    return vec2(d, 0);
}

float sdEllipsoid(vec3 p, vec3 r) {
    return (length(p / r) - 1.) * min(min(r.x, r.y), r.z);
}

float n3D(vec3 p) {
    const vec3 s = vec3(7, 157, 113);
    vec3 ip = floor(p);
    p -= ip;
    vec4 h = vec4(0., s.yz, s.y + s.z) + dot(ip, s);
    p = p * p * (3. - 2. * p);
    h = mix(fract(sin(h) * 43758.5453), fract(sin(h + s.x) * 43758.5453), p.x);
    h.xy = mix(h.xz, h.yw, p.y);
    return mix(h.x, h.y, p.z);
}
vec2 skull(vec3 p)
{
    float noise = (n3D(p * 3.0) - 0.5) * 0.3;

    vec3 q = p;
    float d = sdEllipsoid(p, vec3(.6, .6, .55) + .2 * noise);
    d = smin(d,sdEllipsoid(p+vec3(0,.3,.35), vec3(.3, .4, .2) + .2 * noise), .1);


    // jaw
    q.x = abs(q.x)-.2;
    q.z -= .2;
    rot22(q.xz, -.8);

    rot22(q.yz, .3);

    d = smin(d, sdEllipsoid(vec3(q.x-.3, q.y+.5, q.z-.1), vec3(.05, .4, .1)), .01);

    rot22(q.yz, 1.2);

    d = smin(d, sdEllipsoid(vec3(q.x- .3, q.y + .4, q.z - .8), vec3(.12, .3, .15)), .05);


    // meigu
    q = p;
    q.x = abs(q.x)+.2;
    rot22(q.xz, .5);
    rot22(q.xy, .2);
    d = smin(d, vcapsule(vec3(q.y,q.x, q.z+.6), .8, .04-0.1*sin(q.x)), .2);

    q = p;
    rot22(q.yz, .4);
    d = smin(d, vcapsule(vec3(q.x, q.y+.55, q.z + .45), .6, .06), .1);


    // eyes
    q = p;
    q.x = abs(q.x) - .3;
    d = smin(d, vcapsule(vec3(q.y + .3, q.x+.2, q.z + .3), .3, .08), .1);
    d = smax(d, -sdEllipsoid(vec3(q.x, q.y+.15, q.z + .5), vec3(.2, .1, .4) - .2 * noise), .05);

    q = p;
    q.x = abs(q.x) +.15;
    rot22(q.xy, .45);
    d = smax(d, -sdEllipsoid(vec3(q.x, q.y+.35, q.z+.7), vec3(.05,.1,.45)), .05);

    q = p + vec3(0., .65, .19);
    rot22(q.yz, -.2);
    q.xz = polar_rep(q.xz, 8.);
    q.x += 0.23;

    float d1 = min(d, sdEllipsoid(vec3(q.x,q.y,q.z), vec3(.02,.25,.03)));
    d1 = max(d1, -sdEllipsoid(vec3(q.y-.02, q.x, q.z), vec3(.01, .25, .05)));
    d = min(d, d1);
    return vec2(d,0.);
}


vec2 map(vec3 p)
{
    vec2 res; 
    vec2 d0 = vec2(cutSphere(vec3(sabs(p.x,.1)-.5,p.yz), 2.5, 0.), 0.);
    d0.x = smax(d0.x, -box(vec3(abs(p.x) - 3.8, p.yz), vec3(1,5,5)),.2);
     
    vec2 d1 = vec2(1e9, 0);
    vec3 q;// = p.xyz + vec3(0, -.2, 4.2);
    for (float i = 0.; i < 9.; i+=1.)
    {

        float a = PI / 9. * i;
        q = p.xyz + vec3(0,-.6,i>0.?.1:.4) - vec3(0, sin(a), -cos(a) * 1.3) * 1.8;

        q.yz = rot2(q.yz,i>0.?a:PI/3.);

        float k = 1. - .8 * sin(q.y*q.y);
        d1.x = min(d1.x, vcylinder(q * vec3(k, 1, k), .3, .3)/k -.03 - noise(q * 5.5 - vec3(i)) * .05 - .002 * noise(q * 50.));
        q.yz -= vec2(.4,.2);
        d1.x = min(d1.x, vcylinder(q, .2, .2)- .03 - .002 * noise(q * 50.));
      }

    if (d1.x < d0.x)d0 = d1;

    //q = p;
    //d0 = vec2(1e10, 0);
    //for (float i = 0.; i < 4.; i += 1.)
    //{
    //    //q = p;

    //    //q.yz = rot2(p.yz, iGlobalTime);
    //    q = p;
    //    q += vec3(0, i * 2., 0.);
    //    q.yz = rot2(q.yz, iGlobalTime);

    //    d0.x = min(d0.x,rbox(q, vec3(.5), 0.1));

    //    //q.y += 1.;

    //}
    //


    // skull
    //d0.x = min(head((p+vec3(0,.5,3.2))*2.)/2., d0.x);
    d0.x = min(d0.x, skull(p+vec3(0.,-.5,3.2)).x);


    d0.x = min(d0.x, box(p + vec3(3.1, -.4, 0), vec3(.6,.4,.6)));

    d1.x = vcylinder(p+vec3(3.2,-1.4,0), .8, .3);
    d0.x = fOpUnionStairs(d0.x, d1.x,.1,2.);

    q = p;
    rot22(q.yz, .6);
    d1.x = fOpUnionStairs(box(q + vec3(4., .1, .3), vec3(.15, 1., .4)), vcylinder(p.yxz + vec3(-.4, 3.9, 0), .2,.2), .1,2.);
    d0.x = fOpUnionStairs(d0.x, d1.x, .1,3.);
    rot22(q.yz, -1.3);
    d0.x = fOpUnionStairs(d0.x, min(vcylinder(q + vec3(4.4, -1, .6), 2.5, .1), vcylinder(q+vec3(4.4,-2.8,.6),.2,.2)), .1, 2.);

    // saw 附件
    d1.x = fOpUnionStairs(vcylinder(q.yxz + vec3(-4.3, 4.4, .6), .1, .5), vcylinder(q.xyz + vec3(4.4, -3.6, .6), .3, .2), .2,2.);
    d1.x = fOpUnionStairs(d1.x, max(vcylinder(q.yxz + vec3(-4.3, 4.4, .6), .5, .15), -vcylinder(q.yxz + vec3(-4.3, 4, .6), .3, .1)), .15, 3.);

    d0.x = min(d0.x,d1.x);


    // saw
    q = p.zyx + vec3(3.2, -2.9, 4.7);
    q.xy = polar_rep(q.xy, 5.);
    //q.x -= 1.;
    rot22(q.xy, 4.7);

    d0.x = min(d0.x,.8*max(triPrism(q.xyz*vec3(1,.6,1), vec2(.4, .04-sin(q.y*5.5+4.)*.037)), -vcylinder(q-vec3(.1,0,0), .5, .08)));
    //d0.x = max(vcylinder(q, .1, 1.), -vcylinder(q+vec3(.9,0,0), .2, .8));


    // cannon
    q = p + vec3(3.2,-2.2,0);
    rot22(q.xz, -.2); 
    d0.x = min(d0.x, lego(q*2.5).x/2.5);
    rot22(q.xz, 1.);
    d0.x = min(d0.x, lego((q+vec3(0,-1.2,0)) * 2.5).x / 2.5);
    d0.x = fOpUnionStairs(vcylinder(q.xzy+vec3(0,2.5,-1.2),.3,.3), fOpUnionStairs(d0.x, max(-q.z - 4.8, abs(vcylinder(q.xzy + vec3(0, 2., -1.2), 3., .2)) - .02), .5, 4.), .2, 2.);

    // right arm
    q = p - vec3(3.3, .7, -.8);
    d0.x = fOpUnionStairs(d0.x, lego(q.yxz*2.5).x/2.5, .3,2.);
    d0.x = fOpUnionStairs(d0.x, lego(q * 2.5-vec3(.3,3.,0)).x / 2.5, .2, 2.);
    d0.x = fOpUnionStairs(d0.x, vcylinder(q.yxz-vec3(1,1,0), 3., .2), .2, 3.);
    rot22(q.yz, -.5);
    d0.x = fOpUnionStairs(d0.x, lego(q.yxz * 2.5 - vec3(2.2, 9, 1.2)).x / 2.5, .2, 2.);
    d0.x = fOpUnionStairs(d0.x, min(lego(q * 2.5 - vec3(9,2,-.5)).x / 2.5, vcylinder(q.yzx-vec3(.8,0,3.6), 1.5, .15)), .2, 2.);
    rot22(q.xy, .8);
    d0.x = fOpUnionStairs(d0.x, lego(vec3(abs(q.x - 2.8), q.y, q.z * 2.) * 2.5 - vec3(1, -5.3, -7)).x / 5., .2, 2.);
    d0.x = fOpUnionStairs(d0.x, vcylinder(q.yxz+vec3(2.1,-2.5,1.2), 2., .1), .3, 18.);
    // sword
    d0.x = fOpUnionStairs(d0.x, vcylinder(q.yxz + vec3(2.1, -2.5, 1.5), 2., .1), .3, 4.);

    //d0.x = min(d0.x, lego(q.yxz * 2.5 - vec3(2.2, 9, 1.2)).x / 2.5);
    //rot22(q.xz, 1.);
    d0.x = fOpUnionStairs(d0.x, sword((q.zxy+vec3(2.1,.6,-1.5))*.8).x/.8, .3,2.);
    //d0.x = sword(p).x;
    //d0.x = lego(p).x;

    // belly and legs
    q = p;// +vec3(0., 2, 0);
    d0.x = fOpUnionStairs(d0.x, cutSphere(vec3(p.x,-p.y+.2,p.z), 1.5, .5), 1.3, 5.);
    rot22(q.xz, -.4);
    q.xz = polar_rep(q.xz, 2.);
    d0.x = fOpUnionStairs(d0.x, vcylinder(q.yxz - vec3(-1,1.5,0), 1.5, .15), .2, 3.);
    //d0.x = vcylinder(q.yxz-vec3(-1,1.5,0), 1.5, .15);
    rot22(q.xy, .4);
    d0.x = fOpUnionStairs(d0.x, vcylinder(q - vec3(2.5, -2.5, 0), 1., .1-.1*sin(q.y-.1)), .2, 4.);
    //d0.x = fOpUnion
    res = d0;
    return res;
}

vec2 map2(vec3 p) 
{ 
    vec3 pos = p;
    // It was iq's watermelon:  https://www.shadertoy.com/view/ldl3zl
    vec3 c = p;
    float r = 2.0 - 0.007 * sin(10.0 * (-c.x + c.y - c.z));
    vec2 d0 = vec2(0.65 * (length(3.0 * c * vec3(1., 1.5, 1.5)) - r) / 3.0, 3.0);

    vec3 q = vec3(p.x, abs(p.y) - .22, abs(p.z) - .22);
    q.yz = rot2(q.yz, -0.5);
    vec2 d1 = vec2(box(q + vec3(0.55, 0., 0.), vec3(0.22, 0.1, 0.01)), 1.); 

    float t1 = cylinder(vec3(p.z + 0., p.x + .8, p.y), vec2(.2, .09));
    float t2 = cylinder(vec3(p.z, p.x + .8, p.y), vec2(.18, .15));
    vec2 d2 = vec2(max(t1, -t2), 3.0);

    p.x += .7;
    t1 = cylinder(p.zxy, vec2(.45, .19));
    t2 = cylinder(p.zxy, vec2(.42, .21));
    rx(p, 0.785);
    q = vec3(p.x + .1, abs(p.y) - .26, abs(p.z) - .26);
    q.yz = rot2(q.yz, 0.785);
    float t3 = box(q, vec3(0.1, 0.12 + 0.02 * sin(10. * -q.x), 0.15));
    float t = max(t1, -t2);
    t = smax(t, -t3, 0.1);
    vec2 d3 = vec2(t, 3.0);

    p = pos;
    vec2 d4 = vec2(cylinder(p.yxz + vec3(0., -0.1, 0.),
        vec2(.46 - 0.02 * sin(10. * p.x), .07)), 1.);
    vec2 d5 = vec2(cylinder(p.yxz + vec3(0., 0.2, 0.),
        vec2(.41 - 0.04 * sin(10. * p.x), .04)), 3.);

    rx(p, -0.5);
    vec2 d6 = screw(p);
    vec2 d7 = screw(p.xzy);

    vec2 d = d0;
    d = smerge(d, d4, .07);
    d = smerge(d, d5, .06);
    d = merge(d, d6);
    d = merge(d, d7);
    d = merge(d, d1);
    d = merge(d, d2);
    d = merge(d, d3);
    return d;
}


void getMaterial(float id, vec3 p, out vec3 albedo, out float roughness, out float metallic)
{
   
    albedo = vec3(0.972, 0.960, 0.915);
    roughness = .99;
    metallic = 1.;
    
}

vec3 getNormal(vec3 p, float t)
{
    vec3 n = vec3(0);
    for (int i = 0; i < 4; i++)
    {
        vec3 e = .5773 * (2. * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.);
        n += e * map(p + .001 * e * t).x;
    }
    return normalize(n);
}

float shadow(vec3 sro, vec3 srd)
{
    float s = 1., t = .001;
    vec3 oro = ro, ord = rd;
    ro = sro; rd = srd;
    for (int i = 0; i < 32; i++)
    {
        vec2 h = map(ro + rd * t);
        s = min(s, 16. * h.x / t);
        if (h.x < 1e-4) break;
        t += clamp(h.x, .01, .05);
    }

    ro = oro; rd = ord;
    return clamp(s, 0., 1.);
}


static vec3 sunDir = normalize(vec3(-.7, 1, -.1));
static vec3 sunCol = vec3(1);

vec2 intersect()
{
    float rnd = .9 + .1 * hash21(seed++).x;
    float t = .01;
    vec2 res = vec2(1e9);
    bool hit = false;
    for (int i = 0; i < MARCHING_STEPS; ++i)
    {
        res = map(ro + t * rd);
        res.x = abs(res.x) * rnd * MARCHING_STEP_SCALE;
        float k = 1.;
        if (res.x < .0005 * k + .0002 * t)
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



vec3 phongBrdf(vec3 toLight, vec3 toEye, vec3 normal, vec3 albedo, vec3 F, float shininess, float metallic)
{
    vec3 wr = reflect(-toLight, normal);
    vec3 diff = (vec3(1) - F) * albedo / PI;
    vec3 spec = F * ((shininess + 2.) / (2. * PI)) *
        pow(max(0., dot(wr, toEye)), shininess);

    return diff * (1. - metallic) + spec;
}



// power = 1. becomes getHemisphereSampleCosWeighted
vec3 ImportanceSampleBlinn(vec3 n, vec2 E, float power, out float pdf)
{
    vec3 o1 = normalize(abs(n.x) > abs(n.z) ? vec3(-n.y, n.x, 0.0) : vec3(0.0, -n.z, n.y));
    vec3 o2 = normalize(cross(n, o1));

    float Phi = 2. * PI * E.x;
    float CosTheta = pow(E.y, 1. / (power + 1.));
    float SinTheta = sqrt(abs(1 - CosTheta * CosTheta));

    vec3 sampleDir = cos(Phi) * SinTheta * o1 + sin(Phi) * SinTheta * o2 + CosTheta * n;

    pdf = (power + 2.) / (2. * PI) * pow(CosTheta, power);

    return sampleDir;
}


vec3 schlick(float VoH, vec3 albedo, float metallic)
{
    vec3 f0 = mix(vec3(0.04), albedo, metallic);// metallic > 0.5 ? albedo : vec3(0.04);
    float f = pow(1. - VoH, 5.);
    return f0 + (vec3(1.) - f0) * f;
}

float mapCloud(vec3 p)
{
    p *= .01;
    return smoothstep(.1, 1., fbm(p * vec3(.5, 1, 1)) + .5 * fbm(p * 2.5));
}

vec3 renderCloud(vec2 uv)
{
    vec3 skycol = vec3(.01);
    skycol = mix(skycol, vec3(0), smoothstep(.1, 1., fbm(vec3(uv * vec2(12, 60), 1))));

    vec4 sum = vec4(0, 0, 0, 1);

    float t = (100.0 - ro.y) / rd.y, dt = .2;

    if (t < 0.) return skycol;

    float rnd = .95 + .05 * hash21(seed++).x;

    for (int i = 0; i < 64; ++i)
    {
        vec3 p = ro + t * rd;
        float d = mapCloud(p) * rnd;

        if (d > 0.)
        {
            float s = 0.;
            vec3 st = normalize(p + sunDir);
            vec3 sp = p;
            for (int j = 0; j < 10; j++)
                s += mapCloud(sp += st);

            sum.xyz += exp(-s * .1) * d * vec3(1.5) * sunCol * (1. - d) * sum.a;
            sum.a *= 1. - d;
        }

        if (sum.a < .1 || t > 1000.) break;

        t += dt;
        dt = max(1., .1 * t);
    }
    sum.xyz = mix(sum.xyz, skycol, smoothstep(0., 3., t / 800.));
    return sum.xyz;
}

vec3 getBackGround(float t)
{
    vec3 pos = ro + 1000. * rd;
    vec2 uv = pos.xz;
    vec3 cloud = renderCloud(uv);
    vec3 sky = cloud * vec3(.5,.5,.6);;
    sky = mix(sky, vec3(1, .2, 0), smoothstep(.1, 1., dot(cloud, cloud)));

    //sky = mix(vec3(0, .5, 1) * .0005, sky, smoothstep(0., 1., length((uv - vec2(.3, .4)) * vec2(.5, 1)) - .1));
    //return vec3(1.);
    return sky;
}

vec3 scene(vec2 uv)
{
    vec3 throughput = vec3(1.), Lo = vec3(0), pos, q, n, albedo, nextRd, direct;
    float roughness, metallic;

   

    //return sky;
    // 
    // bounces
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        vec2 hit = intersect();
        q = pos = ro + hit.x * rd;

        if (hit.x < 0.)
        {
            Lo += throughput * getBackGround(hit.x);// (i == 0 ? sky : vec3(.01, .5, 1.) * .01);
            //Lo *= sky;
            break;
        }

        n = getNormal(pos, hit.x);
        

        getMaterial(hit.y, pos, albedo, roughness, metallic);
        roughness = .3;
        metallic = 1.;
        //float shininess = 100. / (500. * roughness + .01);
        float shininess= max(2. / (roughness * roughness) - 2., .01) + 1.;

        // sample light sources
        vec3 refl = reflect(rd, n);
        float NoV = max(0., dot(n, -rd));
        vec3 F = schlick(NoV, albedo, metallic);

        float sha = shadow(pos + 0.001 * n, sunDir);
        direct = (sunCol * phongBrdf(sunDir, -rd, n, albedo, F, shininess, metallic) * max(0., dot(n, sunDir)) * sha);

        Lo += throughput * direct;

        // Sample brdf
        float pdf = 1.;
        //nextRd = normalize(ImportanceSampleBlinn(refl, hash2(seed), shininess, pdf));

        if (hash1(seed) < length(F) + metallic)
        {
            nextRd = normalize(ImportanceSampleBlinn(refl, hash2(seed), shininess, pdf));
        }
        else
        { // Diffuse
            nextRd = normalize(ImportanceSampleBlinn(n, hash2(seed), 1., pdf));

        }

        if (pdf < EPSILON || dot(nextRd, n) < 0.) break;
        if (throughput.x > 1. || throughput.y > 1. || throughput.z > 1.)
            break;
        throughput *= phongBrdf(nextRd, -rd, n, albedo, F, shininess, metallic) * dot(nextRd, n) / pdf;

        rd = nextRd;
        ro = pos + .002 * n;
    }

    return Lo;
}

vec4 mainImage(vec2 fragCoord)
{
    if (iCameraDirty > 0.)
    {
        MAX_BOUNCES = 1;//  iCameraDirty > 0. ? 3 : 3;
        MARCHING_STEPS = 128;// iCameraDirty > 0. ? 128 : 1024;
        MARCHING_STEP_SCALE = 1.;// iCameraDirty > 0. ? 5. : 1.;

        // only update 1 out of 4 pixels when moving camera
        if (any((uint2(fragCoord)) % 2 != 0))
            return vec4(0, 0, 0, 1);
    }
    else
    {
        MAX_BOUNCES = 2;//  iCameraDirty > 0. ? 3 : 3;
        MARCHING_STEPS = 1024;// iCameraDirty > 0. ? 128 : 1024;
        MARCHING_STEP_SCALE = 1.;// iCameraDirty > 0. ? 5. : 1.;
    }

    seed = iFrame + iResolution.y * fragCoord.x / iResolution.x + fragCoord.y / iResolution.y;

    vec2 offset = -.5 + hash21(seed++);
    vec2 p = (fragCoord + offset) / iResolution.xy; // (-iResolution.xy + 2.0 * (fragCoord + offset)) / iResolution.y;

    seed = float(baseHash(floatBitsToUint(p))) / float(0xffffffffU) + iGlobalTime;


    // origin is at the topleft corner for hlsl
    p.y = 1. - p.y;
    p = 2. * p - 1.;
    p.x *= iResolution.x / iResolution.y;

    ro = vec3(RayOrigin.x, RayOrigin.y, RayOrigin.z);
    vec3 ta = vec3(RayTarget.x, RayTarget.y, RayTarget.z);
    vec3 forward = normalize(ta - ro);
    vec3 right = normalize(cross(forward, UpVector));
    //vec3 right = normalize(cross(UpVector, forward));
    //vec3 up = normalize(cross(forward, right));
    vec3 up = normalize(cross(right, forward));

    rd = normalize(p.x * right + p.y * up + 1.8 * forward);

    vec3 finalCol = scene(p);
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
