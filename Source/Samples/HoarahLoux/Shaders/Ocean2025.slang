// Created by evilryu
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.


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
    return x - y * floor(x / y);
}

int mod(int x, int y)
{
    return x - y * (x / y);
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

//#define AA
#define WATER_DEPTH 0.5
#define ROUGH_SEA 1
#define PI 3.1415926535

#define LOOP 1
static float seed;

static vec3 sun_dir = normalize(vec3(0., .1, -.6));
static vec3 sun_col = vec3(0.9, 0.9, 0.95);
static vec3 skyCol = vec3(0.000, 0.035, 0.122);

#define MOD2 vec2(.16632,.17369)
#define MOD3 vec3(.16532,.17369,.15787)



//--------------------------------------------------------------------------

//--------------------------------------------------------------------------
float Hash(float p)
{
    vec2 p2 = fract(vec2(p) * MOD2);
    p2 += dot(p2.yx, p2.xy + 19.19);
    return fract(p2.x * p2.y);
}
float Hash(vec3 p)
{
    p = fract(p * MOD3);
    p += dot(p.xyz, p.yzx + 19.19);
    return fract(p.x * p.y * p.z);
}


vec2 hash2(vec2 p)
{
    const vec2 k = vec2(0.3183099, 0.3678794);
    p = p * k + k.yx;
    return fract(16.0 * k * fract(p.x * p.y * (p.x + p.y)));
}

vec2 hash2(float n)
{
    return fract(sin(vec2(n, n + 1.0)) * vec2(43758.5453123, 22578.1459123));
}

float hash1(vec2 p)
{
    p = 50.0 * fract(p * 0.3183099);
    return fract(p.x * p.y * (p.x + p.y));
}

vec2 hash21(float p)
{
    vec2 p2 = fract(p * vec2(5.3983, 5.4427));
    p2 += dot(p2.yx, p2.xy + vec2(21.5351, 14.3137));
    return fract(vec2(p2.x * p2.y * 95.4337, p2.x * p2.y * 97.597));
}


float hash12(vec2 p, float freq)
{
    //p = mod(p, 1./pow(freq,100.));
    p = mod(p, 1.*freq);
    uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673U, 3812015801U);
    uint n = (q.x ^ q.y) * 1597334673U;
    return float(n) * 2.328306437080797e-10;
}

float hash12(vec2 p)
{
    uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673U, 3812015801U);
    uint n = (q.x ^ q.y) * 1597334673U;
    return float(n) * 2.328306437080797e-10;
}

float hash122(vec2 p)
{
    p = fract(p * vec2(5.3983, 5.4427));
    p += dot(p.yx, p.xy + vec2(21.5351, 14.3137));
    return fract(p.x * p.y * 95.4337);
}

float noise(vec2 x)
{
    vec2 p = floor(x);
    vec2 w = fract(x);
    vec2 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);

    float a = hash12(p + vec2(0, 0));
    float b = hash12(p + vec2(1, 0));
    float c = hash12(p + vec2(0, 1));
    float d = hash12(p + vec2(1, 1));

    return -1.0 + 2.0 * (a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y);
}

float noise(vec2 x, float freq)
{
    vec2 p = floor(x);
    vec2 w = fract(x);
    vec2 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);

    float a = hash12(p + vec2(0, 0), freq);
    float b = hash12(p + vec2(1, 0), freq);
    float c = hash12(p + vec2(0, 1), freq);
    float d = hash12(p + vec2(1, 1), freq);

    return -1.0 + 2.0 * (a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y);
}

float fbm(vec2 p)
{
    float f = 0.0;
    f += .5 * noise(p); p = p * 2.01;
    f += .25 * noise(p); p = p * 2.1;
    f += .125 * noise(p); p = p * 2.03;
    return f;
}

#define METHOD 1
#if METHOD==0
float hash(in ivec2 p)  // this hash is not production ready, please
{                         // replace this by something better

    //p.x = mod(p.x, 10.);
    //p.y = mod(p.y, 10.);
    // 2D -> 1D
    int n = p.x * 3 + p.y * 113;

    // 1D hash by Hugo Elias
    n = (n << 13) ^ n;
    n = n * (n * n * 15731 + 789221) + 1376312589;
    return -1.0 + 2.0 * float(n & 0x0fffffff) / float(0x0fffffff);
}
#endif




float noise32(in vec2 p)
{
#if METHOD==0
    ivec2 i = ivec2(floor(p));
#else
    vec2 i = floor(p);
#endif
    vec2 f = fract(p);

    // cubic interpolant
    vec2 u = f * f * (3.0 - 2.0 * f);

#if METHOD==0
    return mix(mix(hash(i + ivec2(0, 0)),
        hash(i + ivec2(1, 0)), u.x),
        mix(hash(i + ivec2(0, 1)),
            hash(i + ivec2(1, 1)), u.x), u.y);
#else
    return mix(mix(hash12(i + vec2(0.0, 0.0)),
        hash12(i + vec2(1.0, 0.0)), u.x),
        mix(hash12(i + vec2(0.0, 1.0)),
            hash12(i + vec2(1.0, 1.0)), u.x), u.y);
#endif
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
        p = mul(p,m) * 2.01;
        s *= .5;
    }

    return f;
}




static mat2 m2 = mat2(0.80, 0.60,
    -0.60, 0.80);

float cloud(vec2 x)
{
    float f = 2.;
    float s = 0.5;
    float a = 0.0;
    float b = 0.5;
    for (int i = 0; i < 3 + min(0, iFrame); i++)
    {
        float n = noise(x);
        a += b * n;
        b *= s;
        x = f * mul(x, m2);
    }
    return a;
}




// return distance, and cell id
vec2 voronoi(vec2 x)
{
    vec2 n = floor(x);
    vec2 f = fract(x);

    vec3 m = vec3(1e9);
    for (int j = -1; j <= 1; j++)
    {
        for (int i = -1; i <= 1; i++)
        {
            vec2  g = vec2(i, j);
            vec2  o = hash2(n + g);
            //vec2  r = g - f + o;
            vec2  r = g - f + (0.5 + 0.5 * sin(iGlobalTime + 6.2831 * o));
            float d = dot(r, r);
            if (d < m.x)
                m = vec3(d, o);
        }
    }

    //return vec2( sqrt(m.x), m.y+m.z );
    return vec2(m.x, m.y + m.z);
}






float sabs(float x, float k)
{
    return sqrt(x * x + k) - 0.1;
}

vec2 vsabs(vec2 p, float k)
{
    return vec2(sabs(p.x, k), sabs(p.y, k));
}

float gerstner(vec2 p, float freq, vec2 phase, float sharpness)
{
    p += phase;
    p *= freq;
    p += noise(p, freq);
    //p=mod(p, 10.);
    vec2 wave = (1. - vsabs(sin(p), .01 - .01 * sharpness));
    return pow(wave.x + wave.y, 1.2);
}



float water(vec3 pos)
{
    vec2 p = pos.xz;

    p *= 0.08;

    //float h = gerstner(p, 2., 1., vec2(1.,0.), 1., iGlobalTime*0.2);
    float amp = 1.;
    float freq = 1.;
    float sharpness = 0.;
    float time = iGlobalTime * 1.2;
    vec2 offset = vec2(time);

    float h = 0.;

    for (int i = 0; i < 8; ++i)
    {
        //h += amp * gerstner(freq*(p+time));
        //h += amp * gerstner(freq*(p+time));
        h += amp * 1. * gerstner(p, 1., -offset * 2., .3);

        h += amp * gerstner(p, freq, offset, sharpness);
        h += amp * gerstner(p, freq, -offset, sharpness);
        //h += gerstner(p+noise(p+131.), amp/2., wavelen, dir, 1., -time*.5);
        //h += gerstner(p+noise(p*2.), amp, wavelen, dir, 1., -time);
        amp *= .3;

        freq *= 2.7;
        p = mul(m2, p);
        offset = mul(m2 * .6, offset);
        sharpness = .7;
        //dir = (m2 * dir);
    }
    //h=1.;
    //h += 1.*texture(iChannel2, p*5.-vec2(0.45,.2)).x * 1.;


    return h - 2.;
}



static float eps = 0.001;


vec3 waterNormal(vec3 pos, float t)
{
    vec2 e = vec2(eps * t, 0.0);
    return normalize(vec3(water(pos - e.xyy) - water(pos + e.xyy),
        2.0 * e.x,
        water(pos - e.yyx) - water(pos + e.yyx)));
}

static float iterationCount = 0.;
float intersect_water(vec3 ro, vec3 rd)
{
    float nearT = 0.01;          // 更小的初始距离，避免起点在水面下方
    float farT = 2000.0;         // 最大距离，可根据场景调整

    // 检查最远距离处是否在水面上方
    vec3 p = ro + farT * rd;
    float farHeight = p.y - water(p);
    if (farHeight > 0.0) return farT; // 如果最远距离处仍在水面上方，直接返回

    p = ro + nearT * rd;
    float nearHeight = p.y - water(p); // 起点处的高度

    for (int i = 0; i < 256; i++)
    {
        // 通过比例插值计算中点距离
        float midT = mix(nearT, farT, nearHeight / (nearHeight - farHeight));

        // 获取中点处的高度
        p = ro + midT * rd;
        float midHeight = p.y - water(p);

        // 提前退出条件：如果高度接近水面，直接返回
        if (abs(midHeight) < 0.001) return midT;

        // 根据高度更新区间
        if (midHeight < 0.0)
        {
            farT = midT;   // 中点在水面下方，更新 farT
            farHeight = midHeight;
        }
        else
        {
            nearT = midT;  // 中点在水面上方，更新 nearT
            nearHeight = midHeight;
        }

        // 动态退出条件：如果区间足够小，提前退出
        if (abs(nearT - farT) < 0.001) break;

        iterationCount += 1.;
    }


    return nearT; // 返回射线与水面的交点距离
}


vec2 intersect_rough_water(vec3 ro, vec3 rd)
{
    // if the ro is under water,  t2 is the dist if the ray hits water surface again
    // so you can see the water surface from under a huge wave
    float t = 0., t2 = -1.;
    vec3 p = ro + t * rd;

    bool underwater = p.y - water(p) < 0.;
    int morehits = underwater ? 1 : 0;

    do
    {

        p = ro + t * rd;
        float d = p.y - water(p);

        float sgn = sign(d);
        float told = t;
        bool bisect = false;

        for (int i = 0; i < 256 + min(0, iFrame); i++)
        {
            if (abs(d) < 0.002 * t || t > 2000.) break;

            if (sign(d) != sgn)
            {
                bisect = true;
                break;
            }

            told = t;
            if (d > 1.)t += d;
            else t += log(abs(d) + 1.1) * 1.;
            p = ro + t * rd;
            d = p.y - water(p);
        }

        if (bisect)
        {
            float m = 0.;
            p = ro + told * rd;
            sgn = sign(p.y - water(p));
            for (int i = 0; i < 6; i++)
            {
                m = (told + t) * .5;
                p = ro + rd * m;
                d = p.y - water(p);
                if (abs(d) < 0.002 * t)break;
                //d* sgn < 0. ? t = m : told = m;
                if (d * sgn < 0.)
                {
                    t = m;
                }
                else
                {
                    told = m;
                }
            }
            t = (told + t) * .5;
        }

        if (underwater)
        {
            t2 = t;
            underwater = false;
            t += .1;

        }

    } while (morehits-- > 0);
    return vec2(t, t2);
}



float schlick(float f0, float NoV)
{
    return f0 + (1. - f0) * pow(1.0 - NoV, 5.);
}

// g = 0 isotropic
// g > 0 forward
// g < 0 backward
float HenyeyGreenstein(float LoV, float g)
{
    return (1. - g * g) / (4. * PI * pow(1. + g * g - 2.0 * g * LoV, 3. / 2.));
}




// sky from iq's rainforest  https://www.shadertoy.com/view/4ttSWf
vec3 render_sky(vec3 ro, vec3 rd)
{
    // darker on top of the head
    vec3 col = 0.9 * vec3(0.4, 0.65, 1.0) - rd.y * vec3(0.4, 0.36, 0.4);

    float t = (1000.0 - ro.y) / rd.y;
    if (t > 0.0)
    {
        vec2 uv = (ro + t * rd).xz - vec2(4710., 235.);
        float cl = cloud(uv * 0.0015);
        float dl = smoothstep(-0.2, 0.6, cl);
        col = mix(col, vec3(1.0), 0.6 * dl);
    }

    // sun glare    
    float sun = clamp(dot(sun_dir, rd), 0.0, 1.0);
    col += 0.6 * vec3(1.0, 0.6, 0.3) * pow(sun, 32.0);

    return col * 0.5;
}

float mapCloud(vec3 p)
{
    p *= .0005;
    return .6 - fbm3d(p * vec3(1, 1, 1.) + iGlobalTime * .14);// + .5 * fbm(p * 2.5)+ .25 * fbm(p * 5.5);
}

vec3 renderCloud(vec3 ro, vec3 rd, vec2 uv)
{
    rd += fbm3d(rd * 10.) * .1;
    //skycol = mix(skycol, vec3(0), smoothstep(.1, 1., fbm(vec3(uv * vec2(12, 60), 1))));
    vec4 sum = vec4(0, 0, 0, 1);

    // the moon
    //sum.xyz += 10.*pow(1.-smoothstep(.001, .002, 1.-dot(rd,sun_dir)), 1.)*sun_col;

#if 1
    float start = (2000.0 - ro.y) / rd.y;
    float end = (3000.0 - ro.y) / rd.y;

    vec3 pEnd = ro + end * rd;
    vec3 skyColLit = mix(skyCol * 0.1, vec3(1.5, 1.5, 2.), smoothstep(.6, 4.2, dot(rd, sun_dir)));
    //return skyColLit;//

    float tstep = .2;
    if (start < 0.) return skyColLit;

    float t = start;
    vec3 p = ro + t * rd;
    p.y = 0.;

    vec3 marchStep = rd * (end - start - Hash(p) * 100.) / 64.;

    float rnd = .95 + .05 * hash21(seed++).x;

    for (int i = 0; i < 64; ++i)
    {
        float d = mapCloud(p) * rnd;

        if (d > 0.)
        {
            float s = 0.;
            vec3 st = normalize(p + sun_dir);
            vec3 sp = p;
            for (int j = 0; j < 10; j++)
                s += mapCloud(sp += st) * .1;

            //sum.xyz += HenyeyGreenstein(dot(sun_dir, rd), 0.5) * sun_col * exp(-s * 2.);
            sum.xyz += exp(-s * 6.) * d * vec3(1.5)
                * (sun_col + 10.75 * sun_col * pow(clamp(dot(sun_dir, rd), 0.0, 1.0), 30.0))
                * vec3(0.075, 0.110, 0.125)
                * (1. - d) * sum.a;
            sum.a *= 1. - d;
        }

        if (sum.a < .1) break;

        p += marchStep;
    }
#endif
    //sum.xyz = mix(sum.xyz, skyCol, smoothstep(0., 3., t / 800.));

    //float dSun=length(ro+2000.*rd) - 100.;
    sum.xyz = mix(skyColLit, sum.xyz, 1. - sum.a);
    //sum.xyz= mix(skyColLit, sum.xyz, 1.-smoothstep(100.,4000.,t));
    // strong moon light
    sum.xyz += 1.75 * sun_col * pow(clamp(dot(sun_dir, rd), 0.0, 1.0), 100.0);
    sum.xyz = mix(sum.xyz, skyCol * 0.1, 1. - smoothstep(100., 400., (ro + 2000. * rd).y));
    return sum.xyz;
}

float drawObject(in vec3 p) { p = fract(p) - .5; return length(p) - .03 - fbm3d(p * 4.) * 0.3; }


// Repeat cellular tile routine. The operation count is extremely low when compared to conventional
// methods. No loops, no flooring, no hash calls, etc. Conceptually speaking, this is the fastest way 
// to produce a reasonable 3D cellular pattern... Although, there's one with three objects and no 
// rotation, but quality really suffers at that point. 
float cellTile(in vec3 p) {

    // Draw four overlapping objects (spheres, in this case) at various positions throughout the tile.
    vec4 d;
    d.x = drawObject(p - vec3(.81, .62, .53));
    p.xy = vec2(p.y - p.x, p.y + p.x) * .7071;
    d.y = drawObject(p - vec3(.39, .2, .11));
    p.yz = vec2(p.z - p.y, p.z + p.y) * .7071;
    d.z = drawObject(p - vec3(.62, .24, .06));
    p.xz = vec2(p.z - p.x, p.z + p.x) * .7071;
    d.w = drawObject(p - vec3(.2, .82, .64));

    // Obtain the minimum, and you're done.
    d.xy = min(d.xz, d.yw);

    return min(d.x, d.y) * 2.66; // Scale between zero and one... roughly.
}


float map(vec3 p)
{

    float d = cellTile(p * .002) / 0.002;

    return d;
}



vec3 calcNormal(vec3 pos)
{
    vec2 e = vec2(1.0, -1.0) * 0.01;
    return normalize(e.xyy * map(pos + e.xyy) +
        e.yyx * map(pos + e.yyx) +
        e.yxy * map(pos + e.yxy) +
        e.xxx * map(pos + e.xxx));
}

float intersect(vec3 ro, vec3 rd)
{
    float t = 0.01;
    for (int i = 0; i < 256; ++i)
    {
        float d = map(ro + t * rd);
        if (d < 0.002 || t>100.)
            break;

        t += d;
    }
    return t;
}



// r is roughness
float directSpecular(vec3 V, vec3 L, vec3 N, float r)
{
    vec3 H = normalize(V + L);
    float NoH = max(0., dot(N, H));
    float NoV = max(0., dot(N, V));
    float NoL = max(0., dot(N, L));
    float VoH = max(0., dot(V, H));

    // D
    float r2 = r * r;
    float a = NoH * r2;
    float k = r2 / ((1.0 - NoH * NoH) + a * a);
    float d = k * k * (1.0 / PI);

    // Vis
    float v = 0.5 / (NoL * (NoV * (1. - r2) + r2) + NoV * (NoL * (1. - r2) + r2));

    // F
    float f = schlick(.02, NoV);

    return d * f;
}



vec3 render_water(vec3 ro, vec3 rd, float t, vec2 fragCoord, vec3 sky)
{
    vec3 pos = ro + t * rd;
    vec3 n = waterNormal(pos, t);
    vec3 col = vec3(0);

    vec3 refl = normalize(reflect(rd, n));
    vec3 reflCol = render_sky(pos, refl);

    //vec3 refrCol = vec3(.2,.5,1.2)*0.05;
    //vec3 refrCol = vec3(1.2,.5,.2)*0.05;
    vec3 refrCol = skyCol * 0.1;

    float fre = schlick(.02, max(0., dot(n, -rd)));

    float scatter = pow(1.0 * HenyeyGreenstein(dot(sun_dir, rd), .5), 1.);
    //vec3 scatterCol = scatter * 0.2*vec3(0.000,0.514,0.580) * 
    //                  max(0.0, pos.y+.5);    
    //vec3 scatterCol = scatter * 0.2*vec3(0.000,0.502,0.467) * 
    //                  max(0.0, pos.y+.5);  

    vec3 scatterCol = scatter * 0.2 * vec3(0.459, 0.000, 0.000) *
        max(0.0, pos.y + .5);



    col = mix(refrCol, reflCol, fre);


    vec3 speCol = sun_col * 1. * directSpecular(-rd, sun_dir, n, .2);

    float rnd = (.5 * fbm(pos.xz * 50.) + .5);
    vec3 foam = voronoi(pos.xz * .4 - iGlobalTime * .3).x * rnd * vec3(1.)
        //+ voronoi(m2*pos.xz*8.+2.+iGlobalTime*2.).x*.15 
        + voronoi(pos.xz * 5. + iGlobalTime * 4.).x * .5 * rnd;

    foam = mix(foam * .01, foam, smoothstep(0.5, 2., n.y) * smoothstep(0.9, 2., pos.y));


    return col + scatterCol + speCol + foam * .2;
}


vec3 render_underwater(vec3 ro, vec3 rd, float t, float t2, vec3 sceneCol)
{

    float scatter = pow(1.0 * HenyeyGreenstein(dot(sun_dir, rd), .5), 1.);
    vec3 refrCol = skyCol * 0.05;
    vec3 p = ro + t2 * rd;

    // deep part
    //if(t2>100.)
    //return vec3(0.,1.,0);


    //col = scatter*1.2*vec3(0.502,0.,0.) * exp(-t) +refrCol*10.+sky*exp(-t*4.);
    //return scatter * 1. * vec3(0.502,0.,0.) + refrCol * 5. + sceneCol*exp(-t2*1.);
    return //pow(1.-voronoi(rd.xy*60.-iGlobalTime*5.).x, 1000.)*vec3(.2)*smoothstep(.5,-1.,rd.y)
           //(scatter * 1. * vec3(0.502,0.,0.) + sceneCol*.3)* smoothstep(1., exp(-t2), smoothstep(10.,2000.,t2));
        (scatter * 1. * vec3(0.282, 0.039, 0.137) + sceneCol * .3) * smoothstep(1., exp(-t2), smoothstep(10., 3000., t2));

}


vec3 scene(vec3 ro, vec3 rd, vec2 fragCoord, vec2 uv, out float t)
{
    vec3 bg = skyCol * 0.1;
    //vec3 col=render_sky(ro, rd);




    bool underwater = ro.y - water(ro) < 0.;

    //fake refraction
    if (underwater)
    {
        float freq = 3.;
        rd.x += .05 * fbm3d(vec3(uv.x, iGlobalTime * .15, uv.y * 3.) * freq);
        rd.y += .15 * fbm3d((vec3(uv.x, iGlobalTime * 2.13, uv.y * 3.) - vec3(7, 115, 137)) * freq);
        //rd=normalize(refract(rd,vec3(-rd.x,-0.1,-rd.z),1.33));
        rd = normalize(rd);
    }

# if 1

    float t2 = -1.;
#if ROUGH_SEA
    vec2 res = intersect_rough_water(ro, rd);
    t = res.x, t2 = res.y;
#else
    t = intersect_water(ro, rd);
#endif

    vec3 sky = renderCloud(ro, rd, uv);
    vec3 col = sky;

    if (t < 2000.)
    {
        //float tShade = t2 > 0. ? t2 : t; // shade the second hit if start from under water
        col = render_water(ro, rd, t, fragCoord, col);
        col = mix(col, bg, (1.0 - exp(-1.5e-2 * t)) * (1. - smoothstep(-1., 400., (ro + t * rd).y)));
    }


    if (t2 > 0. && t2 < 2000.)// start from underwater
        col = render_underwater(ro, rd, t, t2, col);


    float sun = clamp(dot(sun_dir, rd), 0.0, 1.0);

    // strong moon light
    //col=mix(col, 1.25*sun_col, pow(sun, 1000.0));

    //



#else

    // test code
    t = intersect(ro, rd);

    if (t < 10.)
    {
        vec3 pos = ro + t * rd;
        vec3 n = calcNormal(pos);

        col = vec3(1.) * max(0., dot(sun_dir, n));
        col += vec3(.2) * max(0., dot(-sun_dir, n));

    }


#endif

    //if(smoothstep(40.,50.,(ro+t*rd).y) < .1)
    //col = vec3(1.,0,0);


    return col;
}


vec3 tonemap(vec3 x)
{
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}

mat3 camera(vec3 ro, vec3 ta)
{
    vec3 f = normalize(ta - ro);
    vec3 r = normalize(cross(f, vec3(0, 1, 0)));
    vec3 u = normalize(cross(r, f));
    return mat3(r, u, f);
}



static float FOVX = 360.0; //Max 360 deg
static float FOVY = 180.0; //Max 180 deg


mat3 rotX(float theta) {
    float s = sin(theta);
    float c = cos(theta);

    mat3 m =
        mat3(1, 0, 0,
            0, c, -s,
            0, s, c);
    return m;
}

mat3 rotY(float theta) {
    float s = sin(theta);
    float c = cos(theta);

    mat3 m =
        mat3(c, 0, -s,
            0, 1, 0,
            s, 0, c);
    return m;
}

mat3 rotZ(float theta) {
    float s = sin(theta);
    float c = cos(theta);

    mat3 m =
        mat3(c, -s, 0,
            s, c, 0,
            0, 0, 1);
    return m;
}

float deg2rad(float deg) {
    return deg * PI / 180.0;
}

static vec4 faceColors[6];

vec4 mainImage(vec2 fragCoord)
{
    seed = float(iFrame) + iResolution.y * fragCoord.x / iResolution.x + fragCoord.y / iResolution.y;


    vec2 p = (fragCoord) / iResolution.xy; // (-iResolution.xy + 2.0 * (fragCoord + offset)) / iResolution.y;

    // origin is at the topleft corner for hlsl
    p.y = 1. - p.y;
    vec2 q = p;
    p = 2. * p - 1.;
    p.x *= iResolution.x / iResolution.y;

    vec3 ro = vec3(RayOrigin.x, RayOrigin.y, RayOrigin.z);
    vec3 ta = vec3(RayTarget.x, RayTarget.y, RayTarget.z);
    vec3 forward = normalize(ta - ro);
    vec3 right = normalize(cross(forward, UpVector));
    //vec3 right = normalize(cross(UpVector, forward));
    //vec3 up = normalize(cross(forward, right));
    vec3 up = normalize(cross(right, forward));

    vec3 rd = normalize(p.x * right + p.y * up + 2.3 * forward);


    vec2 interp = fragCoord.xy / iResolution.xy;
    //Mouse coordinates in [-1, 1] range
    //vec2 mp = iMouse.xy / iResolution.xy * vec2(2.0) + vec2(1.0);    
    vec2 mp = vec2(0);

    interp.y = 1.0 - interp.y;
    mp.y = 1.0 - mp.y;

    //360 degrees around the x-axis, 180 degrees on the y-axis
    //The frustum can be split into several parts:
    //The very top is +y, the north pole, and the very bottom
    //is -y, i.e the south pole.
    //The middle consists of +z, -z, +x and -x, where -z
    //is the center of the frustum, and the left and right
    //frustum edges show +z, i.e what is behind you

    float fovX = deg2rad(FOVX);
    float fovY = deg2rad(FOVY);
    float hOffset = (2.0 * PI - fovX) * 0.5;
    float vOffset = (PI - fovY) * 0.5;
    float hAngle = hOffset + interp.x * fovX;
    float vAngle = vOffset + interp.y * fovY;
    vec3 n;
    n.x = sin(vAngle) * sin(hAngle);
    n.y = cos(vAngle);
    n.z = sin(vAngle) * cos(hAngle);

    //Normal pitch-yaw camera controlled with the mouse
   // rd = rotY(mp.x * 2.0 * PI) * rotX(mp.y * 2.0 * PI) * n;


    vec3 col = vec3(0.6, 0.8, 1.1);

    float t = 0.;

    eps = 1. / iResolution.x;


    col = scene(ro, rd, fragCoord.xy, p, t);

    // rain by Dave Hoskins
#if 0
//if(iGlobalTime > RAIN_START_TIME)
    {
        vec2 st = 256. * (p * vec2(.5, .01) + vec2(iGlobalTime * .13 - q.y * .1, iGlobalTime * .13));
        float f = noise(st) * noise(st * 0.773) * 1.55;
        f = 0.1 + clamp(pow(abs(f), 10.0) * 13.0, 0.0, q.y * .14);
        col += 0.2 * f * vec3(1.) * smoothstep(RAIN_START_TIME - .5, RAIN_START_TIME + .5, iGlobalTime);
    }
#endif

    //vec2 x = p * 10.;
    //vec2 pp = floor(x);
    //vec2 w = fract(x);
    //vec2 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);

    //float a = hash12(pp + vec2(0, 0));
    //float b = hash12(pp + vec2(1, 0));
    //float c = hash12(pp + vec2(0, 1));
    //float d = hash12(pp + vec2(1, 1));

    ////float noi= -1.0 + 2.0 * (a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y);

    //float n1 = a + (b - a) * u.x;
    //float n2 = (c - a) * u.y;
    //float n3 = (a - b - c + d) * u.x * u.y;
    //float noi = n1+n2+n3;
    //noi= -1.0 + 2.0 * (a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y);

    ////float noi = noise(p*10.);
    ////float noi = hash12(p * 5.);
    //col = vec3(1) * noi;

    col = tonemap(col);
    col = pow(clamp(col, 0.0, 1.0), vec3(0.45));
    //col=pow(col,vec3(0.85,1.,0.95));
    //col = voronoi(p).x * vec3(1.) + voronoi(m2*p*4.+2.).x*.5 + voronoi(p*8.).x*.25;
    col = col * 0.6 + 0.4 * col * col * (3.0 - 2.0 * col);
    //col=pow(col,vec3(0.85,0.9,1.));
    col *= pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.2);


    return vec4(col.xyz, 1.);
}


float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    return mainImage(texC * iResolution);
}
