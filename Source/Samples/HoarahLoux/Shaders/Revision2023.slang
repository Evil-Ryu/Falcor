
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
};


layout(binding = 0) SamplerState iChannel0Sampler : register(s0);
layout(binding = 1) texture2D iPass0Output : register(t0);

static float seed;

static int MAX_BOUNCES = 1;//  iCameraDirty > 0. ? 3 : 3;
static int MARCHING_STEPS = 128;// iCameraDirty > 0. ? 128 : 1024;
static float MARCHING_STEP_SCALE = 1.;// iCameraDirty > 0. ? 5. : 1.;
static vec3 ro, rd;

#define FAR 100.
#define INTER_THRESHOLD .001
#define EPSILON 			0.0001

#define PI 3.1415926535
#define DE_ITER 14

#define MAT_TREE_TRUNK 0.
#define MAT_TREE_LEAVES 1.
#define MAT_FLOWER 2.
#define MAT_FLOWER_LEAVES 3.
#define MAT_FRACTAL 4.
#define MAT_WALL 5.
#define HEIGHT(z) sin(z * .2  + 1.) * 2.


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

float mb(vec3 z, float y)
{
    //fixed_radius2 = 2.;
    //min_radius2 = .1;
    //folding_limit = 1.4;
    //scale = 3.;

    vec4 params = vec4(2., .1, 1.4, 3.);

    if(y<1.)z.x = mod(z.y + 1., 2.) - 1.;
    else
    {
        params.z = 1.8;
        params.x = 2.3;
        if (z.y > -3.16) return 100.;
        z.z = mod(z.z, 2.) - 1.;
    }
    vec3 offset = z;
    float dr = 1.;

    for (int n = 0; n < 9; ++n)
    {
        z.xy = mul(mat2(.54, .84, -.84, .54), z.xy);

        z = clamp(z, -params.z, params.z) * 2.0 - z;

        float r2 = dot(z, z);
        if (r2 < params.y)
        {
            float temp = (params.x / params.y);
            z *= temp;
            dr *= temp;
        }
        else if (r2 < params.x)
        {
            float temp = (params.x / r2);
            z *= temp;
            dr *= temp;
        }

        z = params.w * z + offset;
        dr = dr * abs(params.w) + 1.;
    }
    return length(z) / abs(dr);
}


static const vec3 c = vec3(.808, .22, 2.137);

float fractal(vec3 p)
{
	float scale = 1.;
    vec3 q = p;
	for(int i=0; i < 14;i++)
	{
        float a = 2.;
        if (i == 3 && q.x<-44.) a = 2.4;
 		p = a*clamp(p, -c, c) - p;
		float k = max(1. / dot(p, p), .03);
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
		p = p1 * max(1. / dot(p1, p1), .03);;
    }

    //return vec3(.4, .5, .25) + vec3(.3, .2, .1) * cos(6.28*(vec3(.4)*acc));
    vec3 k = vec3(.3, .2, .2);
    if (q.z < 4.8) k = vec3(.5, .4, .2);
    q.xy = mul(rot(.2), q.xy);
    if (q.y < 34. && q.y > -5. && q.z > 4.5 && abs(q.x+32.7)<3.) k = vec3(2,.9,.8);
    return vec3(.4, .4, .3) + k * cos(3. * acc);
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

vec4 dBranches(vec3 p, float i, float id, float len)
{
    p.x += sin(p.y * 4.) * (.2 - .1 * step(4., i)) * (hash21(id * 17. + i + 3.).x * .5 + .5) * smoothstep(.5, 1., p.y);
    vec3 dir = normalize(vec3(0, 2, -1));
    float k = .1 - smoothstep(.6, 2.5, p.y) * .07;
    float l = 3.;
    if (i >= 4.)
    {
        p.x *= .4;
        p.z += abs(sin(p.x * 25.)) * .05;
        //p.x += abs(sin(p.y * 30.)) * .005;
        k = .1 - sin(p.y * 2. + 2.5) * .1;
        l = 3.;
    }
    else if (i > 0.) k *= 0.2;
    else k -= noise(p*vec3(50,10,50))*.02 - .01;

    float dcap = dbar2(p + vec3(0, 0, len),
        vec3(0, 0, len),
        vec3(0, 0, len) + len * l * dir,
        vec3(k));

    return vec4(p, dcap);
}

vec2 tree(vec3 z0)
{
    z0.xz = mul(rot(-.2), z0.xz);

    vec4 z = vec4(z0, 1.);
    vec3 p = z.xyz;

    p.x -= sin(p.y * 2.) * .1;
    float d = max(abs(p.y - .1) - 1., length(p.xz) - .22 - noise(p.zyx * vec3(50, 10, 50)) * .02 + smoothstep(0., 1.3, p.y) * .3);

    float id = 0., numLayers = 7., mateid = MAT_TREE_TRUNK;

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
            float spread = -.95 - i / 7.;

            if (i == branchCloneIndex)
                branchClonePos = z;

            if (layerIndex == 1. && i == leafCloneIndex)
                leafClonePos = z;


            z.xz = fold(z.xz, f, id);
            z.yz = mul(rot(-spread), z.yz);


            float len = 1. + id / f / 3.;
            vec4 res = dBranches(z.xyz, i, id, len);
            float dcap = res.w / z.w;

            if (i >= 4.)
            {
                float d1 = dcap +.011;
                if (d1 < d)
                {
                    d = d1;
                    mateid = MAT_TREE_LEAVES;
                }
            }
            else
            {
                if (dcap < d)
                {
                    d = smin(d, dcap, .05 - .04 * step(2., float(i)));
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
            z.zy -= normalize(vec2(1., -2.)) * (hash21(layerIndex * 17.).x+1.) * branchCloneIndex * 2. / branchLayer;;

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

vec4 dPedals(vec3 p, float i, float id, float fid)
{
    p.z += sin(p.y * id / 2.) * .05;
    p.z += sin(p.y * 2.) * (.65 - i / 5.);
    float k = .1 - sin(p.y * 2. + 2.5) * .1;

    if (i == 1.)
    {
        p.z += abs(sin(p.x * 5.)) * .15;
        p.z += abs(sin((p.y - abs(p.x)) * 15.)) * .01;
        p.x += sin(p.z * 60.) * .01;
    }

    float dcap = dbar2(p + vec3(0, 0, 1),
        vec3(0, 0, 1),
        vec3(0, 0, 1) + 2.8 * normalize(vec3(0, 2, -1)),
        vec3(k * (3.-fid), k, .03)) + .01;
    return vec4(p, dcap);
}

vec2 flower(vec3 z0, float fid)
{
    z0.xz = mul(rot(fid), z0.xz);
    z0.z *= -1.;
    vec4 z = vec4(z0, 1);

    vec3 p = z.xyz;
    z.yz = mul(rot(-.5), z.yz);
    p.z -= sin(p.y * 1.5) * .1;

    float mateid = MAT_TREE_TRUNK;
    float d = max(abs(p.y + 1.8) - 2., length(p.xz) - .1 + smoothstep(0., 2., p.y) * 0.1);

    float id = 0., f = 5. + fid * 4., spread = 1.8, dcap, i;
    //z.xz = mul(rot(fid*.3), z.xz);

    z.xz = fold(z.xz, f, id);
    z.yz = mul(rot(spread), z.yz);

    for (i = 1.; i <= 6.; i += 1.)
    {
        vec4 res = dPedals(z.xyz, i, id, fid);
        dcap = res.w / z.w;

        if (dcap < d)
        {
            mateid = i < 2. ? MAT_FLOWER_LEAVES : MAT_FLOWER;
            d = dcap;
        }

        z = vec4(z0, 1);
        z.yz = mul(rot(-.5), z.yz);
        z.xz = mul(rot(0.3 * i), z.xz);
        z.xz = fold(z.xz, 7. + i + fid * 4., id);
        z.yz = mul(rot(1.2),z.yz);// - (i+1.)/100.);

        if (i > 1.)z.zy += vec2(.1 * i, 0);
        //z.z *= -1.;
        z *= 1. + i * .5;// + 2.*i - 2.;
    }

    return vec2(d * .5, mateid);
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


vec2 map(vec3 p)
{
    vec3 q = p - vec3(.87, 3., 1.82);

    float t = bSphere(vec4(.87, 8, 1.82, 12.));
    
    vec2 r=vec2(100), r0, r1, r2, r4, r5, r6;

    if (t != -100.)
    {
        r0 = tree((q - vec3(.3, .1, 2)) * .37); r0.x /= .37;
        r1 = flower(1.8 * (q + vec3(4.3, 1.8, -7)), 0.); r1.x /= 1.8;
        r2 = flower(1.2 * (q + vec3(4.5, -.2, -3)), 1.); r2.x /= 1.2;
        r = r0;
        if (r1.x < r.x) r = r1;
        if (r2.x < r.x) r = r2;
    }   

    {
        q = p + vec3(-35, 4.5, 16);
        q.y += HEIGHT(q.z);
        r4 = vec2(fractal(q.xzy), MAT_FRACTAL);
        //if (q.z < -40.) r4.x = 10900.;
        float s0 = box(p - vec3(6., 5, -23.5), vec3(1.5));
        r4.x = max(r4.x, -s0);
        //r4.x = min(r4.x, s0);

        p.xz = mul(rot(.1), p.xz);
        p.x = -abs(p.x + 11.) - 9.8;
        r6 = vec2(box(p + vec3(79, 0, 0), vec3(70, 1e5, 1e5)), MAT_FRACTAL);

        if (p.z > 5.)p.y -= sin(p.z * .2 + 3.) * 2.;
        else p.y -= (abs(fract(p.z * .037) - .5) * 4. - 1.) * .5;
        r5 = vec2(max(r6.x, mb((p * .1 - vec3(-3., 3.5 + smoothstep(10., 0., p.z) * .3, 1.)), 2.) / .1), MAT_WALL);

        if (r4.x < r.x) r = r4;
        if (r5.x < r.x) r = r5;
    }

    return r;
}


vec3 getMaterial(float id, vec3 p)
{
    if (id == MAT_FRACTAL)
    {
        p = p + vec3(-35, 4.5, 16);
        p.y += HEIGHT(p.z);
        vec3 col = fractalMate(p.xzy);

        col = mix(vec3(1.1, .1, 0), col, smoothstep(3.5, 4.9, p.y));
        col = mix(vec3(.12, .3, .1), col, 1. - smoothstep(5., 25., p.y));

        return col;
    }
    else if (id == MAT_TREE_TRUNK)
    {
        return  vec3(.169, .114, .081)*2.;
    }
    else if (id == MAT_TREE_LEAVES)
    {
        return vec3(2, .8, 0);
    }
    else if (id == MAT_FLOWER)
    {
        return vec3(.9, .1, .1);
    }
    else if (id == MAT_FLOWER_LEAVES)
    {
        return mix(vec3(.1, .25, .1), vec3(.8),fbm(p*5.)*.5);
    }
    else if (id == MAT_WALL)
    {
        return vec3(.69, .565, .451);
    }
    return vec3(1);
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
    float s = 1.,t = .001;
    vec3 oro = ro, ord = rd;
    ro = sro; rd = srd;
    for(int i = 0; i < 32; i++)
    {
        vec2 h = map(ro + rd * t);
        if (h.y == MAT_FLOWER_LEAVES) h.x *= .35;
        s = min(s, 16. * h.x / t);
        if (h.x < 1e-4) break;
        t += clamp(h.x, .01, .05);
    }

    ro = oro; rd = ord;
    return clamp(s, 0., 1.);
}


static vec3 sunDir = normalize(vec3(-.7, 1, -.1));
static vec3 sunCol = vec3(1.);

vec2 intersect()
{
    float rnd = .9 + .1 * hash21(seed++).x;
    float t = .01;
    vec2 res = vec2(1e9);
    bool hit = false;
    for(int i = 0; i < MARCHING_STEPS; ++i)
    {
        res = map(ro + t * rd);
        res.x = abs(res.x) *rnd* MARCHING_STEP_SCALE;
        float k = res.y == MAT_WALL ? 10. : 1.;
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

vec3 phongBrdf(vec3 toLight, vec3 toEye, vec3 normal, vec3 pos, vec3 albedo)
{
    float fre = .04 + .96 * pow(1. - max(0., dot(toLight, normalize(toLight + toEye))), 5.);

    float spec = fre * 9. * pow(max(0., dot(reflect(-toLight, normal), toEye)), 16.);

    return (.2 * spec + .8 * (1. - fre) * albedo) / PI;
}

vec3 getHemisphereSampleCosWeighted(vec3 n, vec2 s)
{
    vec3 o1 = normalize(abs(n.x) > abs(n.z) ? vec3(-n.y, n.x, 0.0) : vec3(0.0, -n.z, n.y));
    vec3 o2 = normalize(cross(n, o1));
    s.x = s.x * 2. * PI;
    float oneminus = sqrt(1. - s.y);
    return cos(s.x) * oneminus * o1 + sin(s.x) * oneminus * o2 + s.y * n;
}

float mapCloud(vec3 p)
{
    p *= .01;
    return smoothstep(.1, 1., fbm(p * vec3(.5, 1, 1)) + .5 * fbm(p * 2.5));
}

vec3 renderCloud(vec2 uv)
{
    vec3 skycol = vec3(.053, .001, .0001);
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

vec3 scene(vec2 uv)
{
    vec3 throughput = vec3(1.), Lo = vec3(0), pos, q, n, albedo, nextRd, direct;

    vec3 cloud = renderCloud(uv);
    vec3 sky = cloud * vec3(.585, .014, .0015);;
    sky = mix(sky, vec3(1, .2, 0), smoothstep(.1,1.,dot(cloud,cloud)));

    sky = mix(vec3(0,.5,1) * .0005, sky, smoothstep(0.,1.,length((uv-vec2(.3,.4))*vec2(.5,1))-.1));

    //return sky;
    // 
    // bounces
    for (int i = 0; i < MAX_BOUNCES; ++i)
    {
        vec2 hit = intersect();
        q = pos = ro + hit.x * rd;

        if (hit.x < 0.)
        {
            Lo = Lo + throughput * sky;
            break;
        }

        n = getNormal(pos, hit.x);

        albedo = getMaterial(hit.y, pos);

        q.y -= HEIGHT(q.z);

        float a = 0., b = 0.;
        if (hit.y == MAT_TREE_TRUNK) a = .2, b = 30.;
        if (q.y <= .05) a = .5, b = 100.;
        if(a > 0.)
            n = bump_mapping(q * a, n, b / max(iResolution.x, iResolution.y));

        if (hit.y == MAT_TREE_LEAVES)
            sunDir = normalize(vec3(-1, 1, 1));

        float sha = shadow(pos + 0.001 * n, sunDir);
        if (hit.y == MAT_TREE_LEAVES)
            sha = smoothstep(.1, .8, sha);
        
        direct = (sunCol * phongBrdf(sunDir, -rd, n, pos, albedo) * max(0., dot(n, sunDir)) * sha);

        if (hit.y == MAT_TREE_LEAVES)
            direct += sunCol * max(0., dot(-n, sunDir)) * albedo * 0.3 *sha;

        Lo += throughput * direct;

        if (hit.y > MAT_FLOWER) break;

        // Sample brdf
        nextRd = normalize(getHemisphereSampleCosWeighted(n, hash21(seed++)));
        float pdf = max(0., dot(n, nextRd)) / PI;
        if (pdf < EPSILON) break;

        throughput *= phongBrdf(nextRd, -rd, n, pos, albedo) * max(0., dot(nextRd, n)) / pdf * (hit.y == MAT_TREE_TRUNK ? .2 : 1.);
                                  
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

    seed = iFrame + iResolution.y * fragCoord.x / iResolution.x + fragCoord.y / iResolution.y;

    vec2 offset = -.5 + hash21(seed++);
    vec2 p = (fragCoord + offset) / iResolution.xy; // (-iResolution.xy + 2.0 * (fragCoord + offset)) / iResolution.y;


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
