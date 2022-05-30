#define vec4 float4
#define vec3 float3
#define vec2 float2
#define mix lerp
#define fract frac


cbuffer ToyCB
{
    float2 iResolution;
    float iGlobalTime;
};

float hash12(vec2 p)
{
	p  = fract(p * vec2(5.3983, 5.4427));
    p += dot(p.yx, p.xy + vec2(21.5351, 14.3137));
	return fract(p.x * p.y * 95.4337);
}

// basic truchet
vec4 mainImage(vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution;
    vec2 p = uv * 2. - 1.;
    p.x *= iResolution.x / iResolution.y;

    float d = length(p) - .5;

    p *= 10.;

    vec2 f = 2.* (fract(p) - .5);
    vec2 g = floor(p);

    float rnd = hash12(g);

    d = abs(abs(f.x + f.y) - 1.) - .1;
    if(rnd > .5)
    	d = abs(abs(f.x - f.y) - 1.) - .1;

    d = smoothstep(0, .1, d);

    vec3 col = vec3(d);
    return vec4(col,1.);
}

float4 main(float2 texC : TEXCOORD) : SV_TARGET
{
    return mainImage(texC * iResolution);
}
