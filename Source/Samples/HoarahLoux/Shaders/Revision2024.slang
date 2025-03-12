
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

#define radian radians


float mod(float x, float y)
{
    return x - y * floor(x / y);
}

vec2 mod(vec2 x, float y)
{
    return vec2(mod(x.x, y), mod(x.y, y));
}

vec3 mod(vec3 x, float y)
{
    return vec3(mod(x.x, y), mod(x.y, y), mod(x.z, y));
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

#define MAT_METAL 0.
#define MAT_GUN 1.
#define MAT_BONE 2.
#define MAT_SHELL 3.
#define MAT_DARKMETAL 4.
#define MAT_LAVA 5.
#define MAT_MIAO 6.
#define MAT_POWER 7.
#define MAT_SAW 8.




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
    float f = 0., s = .5;
    for (; s > .06; s*=.5) f += s * noise(p), p*=2.;
    return f;
}

float hash(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3. - 2. * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
        mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}


float bump(vec3 p)
{
    return fbm(p * vec3(.1, .025, .1) * iResolution.x);
}

vec3 bumpMapping(vec3 p, vec3 n, float weight)
{
    vec2 e = vec2(2. / iResolution.y, 0);
    vec3 g = vec3(bump(p - e.xyy) - bump(p + e.xyy),
        bump(p - e.yxy) - bump(p + e.yxy),
        bump(p - e.yyx) - bump(p + e.yyx)) / (e.x * 2.);
    g = (g - n * dot(g, n));
    return normalize(n + g * weight);
}


void rot22(inout vec2 p, float a) {
    p = cos(a) * p + sin(a) * vec2(p.y, -p.x);
}

float smin(float a, float b, float k)
{
    float h = clamp(.5 + .5 * (b - a) / k, .0, 1.);
    return mix(b, a, h) - k * h * (1. - h);

}

void opU(inout vec2 obj, float b, float matB)
{
    obj = obj.x < b ? obj : vec2(b, matB);
}

void opStairU(inout vec2 obj, float b, float r, float n, float matB)
{
    float s = r / n;
    float u = b - r;
    obj= vec2(min(min(obj.x, b), 0.5 * (u + obj.x + abs(mod(u - obj.x + s, 2. * s) - s))),
                obj.x < b ? obj.y : matB);
}
void opCut(inout vec2 obj, float b, float matB)
{
    obj = obj.x > -b ? obj : vec2(-b, matB);
}

float smax(float a, float b, float k)
{
    float h = max(k - abs(a - b), 0.0f);
    return max(a, b) + h * h * 0.25f / k;
}


float stairMin(float x, float y, float r, float n)
{
    float s = r / n;
    float u = y - r;
    return min(min(x, y), 0.5 * (u + x + abs(mod(u - x + s, 2. * s) - s)));
}

vec2 fold(vec2 p, float s)
{
    float a = PI / s + atan2(p.x, p.y);
    float n = PI * 2. / s;
    a = floor(a / n);
    rot22(p, -a * n);
    return p;
}

float box(vec3 p, vec3 b)
{
    vec3 d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), .0) + length(max(d, .0));
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

float cutSphere(vec3 p, float r)
{
    return max(length(p)-r, -p.y);
}


//-----------distance functions from iq----------------

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

static float legoLen = 1.;

vec2 lego(vec3 p)
{
    //vec2 res = vec2(max(abs(vcylinder(p.yzx + vec3(0, 1, 0), .7, .5)) - .1, -p.z - 1.5), MAT_POWER);
    //vec2 res2 = vec2(box(p, vec3(1, 1.3, legoLen)), MAT_GUN);
    //vec2 res3 = vec2(vcylinder(p, 2., .5), MAT_POWER);
    vec2 res = vec2(max(abs(vcylinder(p.yzx + vec3(0, 1, 0), .7, .5)) - .1, -p.z - 1.5), MAT_GUN);
    vec2 res2 = vec2(box(p, vec3(1, 1.3, legoLen)), MAT_GUN);
    vec2 res3 = vec2(vcylinder(p, 2., .5), MAT_GUN);

    opStairU(res2, res3.x, .3, 4., res3.y);
    opStairU(res, res2.x, .2, 2., res2.y);
    return res;
}

vec2 sword(vec3 p)
{
    rot22(p.xy, -.6);
    float d = triPrism(vec3(p.x * 2., abs(p.y - 1.), p.z), vec2(.4-exp(p.z*2.-1.8) * 0.38, 2.)) / 2. - fbm(p * 10.) * 0.02;
    d = stairMin(d, vcylinder(p.xzy + vec3(0, 2.6, -1), 1., .1), .3, 4.);
    d = stairMin(d, vcylinder(p.xzy + vec3(0, 3.7, -1), .1, .2), .1, 3.);
    
    return vec2(d, 0);
}

float sdEllipsoid(vec3 p, vec3 r) {
    return (length(p / r) - 1.) * min(min(r.x, r.y), r.z);
}


float skull(vec3 p)
{
    float noi = (noise(p * 3.0) - 0.5) * 0.3;

    vec3 q = p;
    float d = sdEllipsoid(p, vec3(.6, .6, .55) + .2 * noi);
    d = smin(d,sdEllipsoid(p+vec3(0,.3,.35), vec3(.3, .4, .2) + .2 * noi), .1);


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
    d = smax(d, -sdEllipsoid(vec3(q.x, q.y+.15, q.z + .5), vec3(.2, .1, .4) - .2 * noi), .05);

    q = p;
    q.x = abs(q.x) +.15;
    rot22(q.xy, .45);
    d = smax(d, -sdEllipsoid(vec3(q.x, q.y+.35, q.z+.7), vec3(.05,.1,.45)), .05);

    // tooth
    q = p + vec3(0., .65, .19);
    rot22(q.yz, -.2);
    q.xz = polar_rep(q.xz, 8.);
    q.x += 0.23;

    float d1 = min(d, sdEllipsoid(q, vec3(.02,.25,.03)));
    d1 = max(d1, -sdEllipsoid(vec3(q.y-.02, q.x, q.z), vec3(.01, .25, .05)));
    d = min(d, d1);
    d = max(d, length(p) - 1.6);
    return d;
}


float blade(vec3 p)
{
    float d = smax(box(p, vec3(3,.01,.5)), -vcylinder(p + vec3(-.3, 0, .5), .1, 1.), .1);
    return d;
}


vec2 gun(vec3 p, float t)
{
    vec3 q = p;
    q.xy = polar_rep(p.xy, 3.);
    vec2 res = vec2(vcylinder(abs(q - vec3(.2, 0, 0)) - vec3(0.1, 0, 0), .1, .2), MAT_MIAO);

    q.xz = polar_rep(p.xz, 4.);
    vec2 res2 = lego((q - vec3(.2, 0, 0)) * 9);
    opStairU(res, res2.x/9., .1, 5., res2.y);
    if (t < 1.)
    {
        res.x = max(res.x, p.y-p.x*2.-.4)/2.;
    }
    return res;
}

float ball(vec3 p)
{
    p *= .1;
    p.y += .8;
    p.xz = polar_rep(p.xz, 4.);
    float d = stairMin(1e9, gun((p - vec3(5., 0., 0.)) * 1.,1.).x / 1., .05, 10.);
    d = min(d, vcylinder(p - vec3(5., 0, 0), 10., .2));
 
    return d / .1;
}

vec2 map(vec3 p)
{
    vec2 res = vec2(1e9), res2;
    vec3 q, op = p;

   
#if 1

    p *= .5;
  
    opU(res, cutSphere(vec3(abs(p.x)-.5,p.yz), 2.5), MAT_SHELL);
    
    //opCut(res, box(vec3(abs(p.x) - 3.8, p.yz), vec3(1,5,5)), MAT_SHELL);
    for (float i = 0.; i < 6.; i+=1.)
    {
        float a = PI / 9. * i;
        q = p.xyz + vec3(0,-.6,i>0.?.1:.4) - vec3(0, sin(a), -cos(a) * 1.3) * 1.8;

        rot22(q.yz,i>0.?a:PI/3.);

        float k = 1. - .8 * sin(q.y*q.y);
        //opU(res, vcylinder(q * vec3(k, 1, k), .3, .3)/k -.03 - noise(q * 5.5 - vec3(i)) * .05 - .002 * noise(q * 50.), MAT_BONE);
        opU(res, vcylinder(q * vec3(k, 1, k), .3, .3)/k -.03 - noise(q * 6. - vec3(i)) * .05, MAT_BONE);
        //q.yz -= vec2(.4,.2);
        //opU(res, vcylinder(q, .2, .2)- .03 - .002 * noise(q * 50.), MAT_BONE);
     }

    // skull
    opU(res, skull(p+vec3(0., -.5, 3.2)), MAT_METAL);
 
    // left arm
    opU(res, lego((p.xzy + vec3(3.2,0,-.4))*2.).x/2., MAT_METAL);

    opStairU(res, vcylinder(p + vec3(3.2, -1.4, 0), .8, .3), .2, 2., MAT_METAL);

    q = p;
    rot22(q.yz, .6);

    opStairU(res, lego((q + vec3(4.4, .1, .0)) * 2.).x / 2., .1, 3., MAT_METAL);
    opStairU(res, vcylinder(p.yxz + vec3(-.4, 3.9, 0), .2, .2), .5, 10., MAT_METAL);

    rot22(q.yz, -1.3);
    opStairU(res, min(vcylinder(q + vec3(4.4, -1, .3), 2.5, .1), vcylinder(q + vec3(4.4, -2.8, .3), .2, .2)), .4, 10., MAT_METAL);

    // saw 连杆与转盘
    opStairU(res, vcylinder(q.yxz + vec3(-4.3, 4.4, .3), .1, .5), .2, 2., MAT_METAL);
    opStairU(res, vcylinder(q.xyz + vec3(4.4, -3.6, .3), .3, .2), .2, 2., MAT_METAL);
    opStairU(res, max(vcylinder(q.yxz + vec3(-4.3, 4.4, .3), .5, .15),
        -vcylinder(q.yxz + vec3(-4.3, 4, .3), .3, .1)), .15, 3., MAT_METAL);
   

    // saw
    q = p.zyx + vec3(3., -3.1, 4.9);
    vec3 qq = q;
    q.x *= -1.;
    q.xy = polar_rep(q.xy, 5.);
    qq.xy = polar_rep(qq.xy, 5.);
    q.xy = polar_rep(q.xy, 2.);

    rot22(q.xy, 4.7);
    q.z = abs(q.z) - .1;

    opU(res, .8 * max(triPrism(q * vec3(1, .6, 1), vec2(.4, .04 - sin(q.y * 5.5 + 4.) * .037)), -vcylinder(q - vec3(.1, 0, 0), .5, .08)), MAT_SAW);
    opStairU(res, lego(qq.xzy*15.).x/15., .1, 5., MAT_SAW);
       
    // cannon
    q = p + vec3(3.2,-2.2,0);
    rot22(q.xz, -.2); 
    opU(res, lego(q*2.5).x/2.5, MAT_METAL);
    rot22(q.xz, 1.);
    opU(res, lego((q + vec3(0, -1.2, 0)) * 2.5).x / 2.5, MAT_DARKMETAL);
    opStairU(res, vcylinder(q.xzy + vec3(0, 2.5, -1.2), .3, .3), .2, 2., MAT_DARKMETAL);
    opStairU(res, max(-q.z - 4.8, abs(vcylinder(q.xzy + vec3(0, 2., -1.2), 3., .2)) - .02), .5, 4., MAT_DARKMETAL);

    // right arm
    q = p - vec3(3.3, .7, -.8);
    opStairU(res, lego(q.yxz*2.5).x/2.5, .3,2., MAT_METAL);
    opStairU(res, lego(q * 2.5-vec3(.3,3.,0)).x / 2.5, .2, 2., MAT_METAL);
    opStairU(res, vcylinder(q.yxz-vec3(1,1,0), 3., .2), .2, 3., MAT_METAL);
    rot22(q.yz, -.5);
    opStairU(res, lego(q.yxz * 2.5 - vec3(2.2, 9, 1.2)).x / 2.5, .2, 2., MAT_METAL);
    opStairU(res, min(lego(q * 2.5 - vec3(9,2,-.5)).x / 2.5, vcylinder(q.yzx-vec3(.8,0,3.6), 2., .15)), .3, 5., MAT_METAL);
    rot22(q.xy, .8);
    legoLen=.5;
    // right fore arm
    q.z += .6;
    opStairU(res, lego(vec3(abs(q.x - 2.8), q.y, q.z) * 2.5 - vec3(1.3, -5.3, -3.5)).x / 2.5, .6, 10., MAT_METAL);
    legoLen=1.;
    opStairU(res, vcylinder(q.yxz+vec3(2.1,-2.5,1.2), 2., .1), .5, 18., MAT_METAL);
    // sword
    opStairU(res, vcylinder(q.yxz + vec3(2.1, -2.5, 1.5), 2., .1), .3, 4., MAT_METAL);

    opStairU(res, sword((q.zxy+vec3(2.1,.6,-1.5))*.8).x/.8, .3,2., MAT_METAL);

    // belly and legs
    q = p;// +vec3(0., 2, 0);
    opStairU(res, cutSphere(vec3(p.x,-p.y,p.z), 1.45), 1.3, 5., MAT_METAL);
    rot22(q.xz, -.4);
    q.xz = polar_rep(q.xz, 2.);
    opStairU(res, vcylinder(q.yxz - vec3(-1.2,1.5,0), 1.5, .15), .2, 3., MAT_METAL);
    rot22(q.xy, .4);
    opStairU(res, vcylinder(q - vec3(2.5, -2.7, 0), 1., .1-.1*sin(q.y-.5)), .2, 4., MAT_METAL);

    res.x /= .5;
    p /= .5;
//#else
#endif

    p.xz -= 248.;
    p.xz = mod(p.xz, 500.) - 250.;
    p.y += 0.55;
    res2 =vec2( vcylinder(p + vec3(0, 14.35, 0), 10., 50.), MAT_DARKMETAL);

    q = p;
    q.xz = fold(q.xz, 5.);
    q.z -= 20.;
    q.xz = fold(q.xz, 5.);
    q.z -= 7.;

    opCut(res2, box(vec3(mod(q.x, 10.) - 5., q.y+4., q.z), vec3(.4, 1.5, 100.)), MAT_DARKMETAL);
    opCut(res2, box(vec3(q.x, q.y+4., q.z), vec3(100., 1.5, .4)), MAT_DARKMETAL);
    opStairU(res2, max(p.y, abs(vcylinder(p - vec3(0, 3, 0), 10., 50.)) - 1.)
        , 1., 3., MAT_DARKMETAL);
    opU(res2, vcylinder(p + vec3(0, 14.8, 0), 10., 50.), MAT_LAVA);
    //res2.x += fbm(p * .5) * 0.5;
    //res2.x -= sin(p.x * 2.5 + cos(p.z * 2.5 )) * .1;
    //res2.x += noise(p * 5.) * 0.01;

    opStairU(res2, ball(p), 1., 5., MAT_METAL);
    opCut(res2, -p.y+10.-p.x*.2+p.z*.2, MAT_METAL);
    opU(res, res2.x, res2.y);


//#endif
    // gun
    p = op.yzx-ro.yzx+vec3(.4,-.5, .5);
    rot22(p.yz, -.1);
    res2 = gun(p * 5., 0.);
    res2.x /= 5.;
    //opU(res2, vcylinder(p-vec3(.1,0,0), 0.55, .03), MAT_MIAO);
    opU(res, res2.x, res2.y);


    return res;
}

vec3 firecolor(float f)
{
    f = f * f * (3.0 - 2.0 * f);
    return  min(vec3(f + .8, f * f * 1.4 + .1, f * f * f * .7) * f, 1.0);
}

float getAO(vec3 p, vec3 n)
{
    float
        occ = .0, sca = 4., h, d;
    for (int i = 0; i < 5 && occ < .35; i++, sca *= .95)
    {
        h = 1e-5 + .2 * float(i) / 4.;
        d = map(p + h * n).x;
        occ += (h - d) * sca;
    }

    occ = clamp(1. - 3. * occ, .1, 1.);
    return occ;
}
void getMaterial(float id, vec3 p, inout vec3 n, out vec3 albedo, out vec3 emissive, out float roughness, out float metallic)
{
    albedo = emissive = vec3(0);
    roughness = .9;
    metallic = 1.;
    if (id == MAT_METAL || id == MAT_SAW)
    {
        //albedo = vec3(0.972, 0.960, 0.915);
        // gold
        //albedo = vec3(242, 192, 86)/255.;
        // steel
        //albedo = vec3(220, 220, 220)/255.;
        //raw gold
        //albedo = vec3(255, 180, 66)/255.;
        // 24k gold
        //albedo = vec3(218, 178, 115)/255.;
        // iron
        albedo = vec3(118, 119, 120) / 255.;
        roughness = .1;
        if (id == MAT_SAW) metallic = .99;
    }
    else if (id == MAT_SHELL)
    {
        //albedo = vec3(.4, .0, .0);
        vec3 q = p;
        q.xz = mod(q.xz, 2.) - 1.;
        q.z += 0.5;
        albedo = mix(vec3(.01), vec3(.7,.1,.1), smoothstep(.1, .11, length(q.xz) - .3));
        roughness = 0.4;
    }
    else if (id == MAT_GUN)
    {
        //albedo = vec3(.55,.56,.58);
        albedo = vec3(0.972, 0.960, 0.915) * 0.1;
        //albedo = vec3(218, 178, 115)/255.;
        roughness = .1;
        metallic = .99;

        //float ff = fbm(p * vec3(1, 1e3, 1));
        //ff=smoothstep(.5, .6, ff);
        //emissive = mix(emissive, firecolor(.8).zyx*1., min(1., ff));
        //albedo = mix(albedo, firecolor(.8).zyx*1., min(1., ff));


        // scratch
        //float kf = fbm(p * vec3(10, 100, 5));
        //kf = smoothstep(.5, .51, kf);
        //roughness = min(1., mix(roughness * 2., roughness, kf));

    }
    else if (id == MAT_MIAO)
    {
        //albedo = vec3(0.972, 0.960, 0.915);
        albedo = vec3(.01);
        roughness = .3;
        metallic = .99;
    }
    else if (id == MAT_POWER)
    {
        float ff = fbm(p * vec3(5, 20, 5)*10.);
        //emissive = vec3(.1,.2,.0) * 5. * ff;
        emissive = vec3(.0,.1,.3) * 10. * ff;
        metallic = 0.;
    }
    else if (id == MAT_BONE)
    {
        albedo = vec3(0.972, 0.960, 0.915)*.5;
        roughness = .5;
        metallic = 0.;
    }
    else if (id == MAT_DARKMETAL)
    {
        albedo = vec3(.1);// mix(vec3(.1, .1, .1), vec3(.2, .1, .0), d * 2.);
        roughness = mix(0.01, .8, max(0.,fbm(p*.5)-.5));
        n = normalize(n + (2. * fbm(p * 1.) - 1.) * 0.1);
    }
    else if (id == MAT_LAVA)
    {
        emissive = vec3(.2,.0,.0) * 10. * max(fbm(p * 40.)-.4,0.);
        emissive = mix(emissive, vec3(.2, .005, .0) * 1e3, max(0.,fbm(p * 7.)-.4));
    }
    else
    {
        albedo = vec3(1, 0,1);
        roughness = 0.4;
    }

    if (metallic == 1.)
    {
        float f = fbm(p * vec3(3, 1, 3)),
            occ = .0, sca = 4., h, d;
        for (int i = 0; i < 5 && occ < .35; i++, sca *= .95)
        {
            h = 1e-5 + .15 * float(i) / 4.;
            d = map(p + h * n).x;
            occ += (h - d) * sca;
        }

        occ=(id==MAT_DARKMETAL)?1.:clamp(1. - 3. * occ, .1, 1.);
        f = (id == MAT_SHELL) ? smoothstep(.2, 3., f)  : 
                                smoothstep(.3, .4, f) * max(0., 1. - occ);
        roughness += f*2.;
        albedo = mix(albedo, vec3(.6, .12, .02)*0.3, min(1.,f));
        metallic =mix(metallic,0.,min(1.,f*5.));
        n = bumpMapping(p, n, 0.05*f);

        // scratch
        float k = fbm(p * vec3(300, 1, 1));
        k = smoothstep(.4, .5, k);
        roughness = min(1., mix(roughness * 2., roughness, k));
    }
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


//static vec3 sunDir = normalize(vec3(1.,.5,-.5));
static vec3 sunDir = normalize(vec3(.3,1,-1));
static vec3 sunCol = vec3(.7, .6, .5) * 4.;
static float glow;

vec2 intersect()
{
    glow = 0.;
    float rnd = .9 + .1 * hash1(seed), t = .01, hit = 0.;
    vec2 res;
    for (int i = 0; i < MARCHING_STEPS; ++i)
    {
        res = map(ro + t * rd);
        res.x = abs(res.x) * rnd * MARCHING_STEP_SCALE;

        if (res.x < .0005 + .0002 * t)
        {
            hit = 1.;
            break;
        }
        if (t > FAR)
            break;

        if (res.y == MAT_LAVA)
        {
            glow += 0.2 / (0.15 + abs(res.x));
        }

        t += res.x;
    }
    if (hit<1.) t = -1.;

    return vec2(t, res.y);
}



vec3 phongBrdf(vec3 toLight, vec3 toEye, vec3 normal, vec3 albedo, vec3 F, float shininess, float metallic)
{
    vec3 wr = reflect(-toLight, normal);
    vec3 diff = (vec3(1) - F) * albedo / PI;
    vec3 spec = min(vec3(.99),F * ((shininess + 2.) / (2. * PI)) *
        pow(max(0., dot(wr, toEye)), shininess));

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


vec3 getBackGround(vec3 rd, float t)
{
    rd += fbm(rd * 9.) * .5;

    vec3 p = ro + FAR * rd;
    vec3 sky = 2.*mix(firecolor(.2), firecolor(.8).zxy, max(0.,fbm(p * .01)-.3));
    //vec3 sky = 2.*mix(firecolor(.2), firecolor(.8).xyz, max(0.,fbm(p * .01)-.3));
    sky *= smoothstep(-90., 500., p.y);
    //sum.xyz = mix(sum.xyz, skyCol * 0.1, 1. - smoothstep(-1., 400., (ro + 2000. * rd).y));
    //sky += 10.75 * sunCol * pow(clamp(dot(sunDir, rd), 0.0, 1.0), 10.0);
        //sky = mix(vec3(0, .5, 1) * .0005, sky, smoothstep(0., 1., length((uv - vec2(.3, .4)) * vec2(.5, 1)) - .1));
    //return vec3(1.);
    return sky;
}

vec3 scene(vec2 uv)
{
    vec3 throughput = vec3(1.), Lo = vec3(0), pos, q, n, albedo, nextRd, direct, emissive;
    float roughness, metallic;

    //return sky;
    // 
    // bounces
    float t = 0.;
    vec2 prevHit=vec2(-1);
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        vec2 hit = intersect();
        if (i == 0)
            t = hit.x;
        if (i != 0 && hit.y == MAT_LAVA && prevHit.y!=MAT_DARKMETAL)
            break;
        if (i != 0 && hit.y == MAT_POWER)
            break;

        q = pos = ro + hit.x * rd;

        if (hit.x < 0.)
        {
            //Lo += throughput * (prevHit.y==MAT_GUN ? vec3(0.01) : getBackGround(rd, hit.x));// (i == 0 ? sky : vec3(.01, .5, 1.) * .01);
            Lo += throughput *  getBackGround(rd, hit.x);// (i == 0 ? sky : vec3(.01, .5, 1.) * .01);
            //Lo *= sky;
            break;
        }

        prevHit = hit;
        n = getNormal(pos, hit.x);
        

        getMaterial(hit.y, pos, n, albedo, emissive, roughness, metallic);
        //roughness = .3;
        //metallic = 1.;
        //float shininess = 100. / (500. * roughness + .01);
        float shininess= max(2. / (roughness * roughness) - 2., .01) + 1.;

        // sample light sources
        vec3 refl = reflect(rd, n);
        float NoV = max(0., dot(n, -rd));
        vec3 F = schlick(NoV, albedo, metallic);

        float sha = shadow(pos + 0.001 * n, sunDir);
        direct = (sunCol * phongBrdf(sunDir, -rd, n, albedo, F, shininess, metallic) * max(0., dot(n, sunDir)) * sha + emissive);

        Lo += throughput * direct;

        // Sample brdf
        float pdf = 1.;
        //nextRd = normalize(ImportanceSampleBlinn(refl, hash2(seed), shininess, pdf));

        if (hash1(seed) < length(F) + metallic)
        {
#if 0
            if (roughness < 0.01)
            {
                nextRd = normalize(refl);
            }
            else
#endif
            nextRd = normalize(ImportanceSampleBlinn(refl, hash2(seed), shininess, pdf));
        }
        else
        {
            // Diffuse
            nextRd = normalize(ImportanceSampleBlinn(n, hash2(seed), 1., pdf));
        }

        if (pdf < EPSILON || dot(nextRd, n) < 0.) break;
        
        throughput *= phongBrdf(nextRd, -rd, n, albedo, F, shininess, metallic) * dot(nextRd, n) / min(1.,pdf);

        // 还是得放在 throughput 赋值之后, 不然还是会有超小 pdf 导致的大 throughput, 出现亮点
        if (throughput.x > 1. || throughput.y > 1. || throughput.z > 1.)
            break;
        rd = nextRd;
        ro = pos + .002 * n;


        //float ao = getAO(pos, n);
        //Lo = vec3(1) * ao; break;
        //Lo = vec3(q); break;
    }

        //Lo = mix(Lo, firecolor(.3).yxz*.9, (1. - exp(-.001  * t)));
    return Lo;
}

float sdRoundedX(in vec2 p, in float w, in float r)
{
    p = abs(p);
    return length(p - min(p.x + p.y, w) * 0.5) - r;
}

vec4 mainImage(vec2 fragCoord)
{
    if (iCameraDirty > 0.)
    {
        MAX_BOUNCES = 1;//  iCameraDirty > 0. ? 3 : 3;
        MARCHING_STEPS = 64;// iCameraDirty > 0. ? 128 : 1024;
        MARCHING_STEP_SCALE = 1.;// iCameraDirty > 0. ? 5. : 1.;

        // only update 1 out of 4 pixels when moving camera
        if (any((uint2(fragCoord)) % 4 != 0))
            return vec4(0, 0, 0, 1);
    }
    else
    {
        MAX_BOUNCES = 2;//  iCameraDirty > 0. ? 3 : 3;
        MARCHING_STEPS = 256;// iCameraDirty > 0. ? 128 : 1024;
        MARCHING_STEP_SCALE = 1.;// iCameraDirty > 0. ? 5. : 1.;
    }

    seed = iFrame + iResolution.y * fragCoord.x / iResolution.x + fragCoord.y / iResolution.y;

    vec2 offset = -.5 + hash2(seed);
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

    rd = normalize(p.x * right + p.y * up + 1.5 * forward);

    vec3 finalCol = scene(p);
    rot22(p, PI/4.);
    float d = sdRoundedX(p, .05, .001);
    finalCol = mix(vec3(0,1,0), finalCol, smoothstep(0., .001, d));
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
