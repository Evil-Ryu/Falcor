
#Toolbox for raymarching, but not limited to.

```cpp
// post processing
对户外场景， tongmapping 的方式：
col = 1.0-exp(-col); as suggested by @P_Malin

一个对 ACES 的简单模拟：
float contrast = 1.0;
vector color = tanh(log(color*2.0)*contrast)*0.5+0.5;


# 可以减少几倍编译时间的 normal function
vec3 calcNormal(vec3 p)
{
    // inspired by tdhooper and klems - a way to prevent the compiler from inlining map() 4 times
    vec3 n = vec3(0.0);
    for( int i=ZERO; i<4; i++ )
    {
        vec3 e = 0.5773*(2.0*vec3((((i+3)>>1)&1),((i>>1)&1),(i&1))-1.0);
        n += e*map(p+0.0001*e, true).x;
    }
    return normalize(n);
}


vec2 polarAbs(vec2 p,float n){
  n*=0.5;
  float a = asin(sin(atan(p.x,p.y)*n))/n;
  return vec2(sin(a),cos(a))*length(p);
}


vec2 polarSmoothAbs(vec2 p, float n, float k){
  n*=0.5;
  float a = asin(sin(atan(p.x,p.y)*n)/sqrt(k*k+1.0))/n;
  return vec2(sin(a),cos(a))*length(p);
}

float smin(float a, float b, float k)
{


float h = clamp ( 0.5 + 0.5 *( b - a )/ k , 0.0 , 1.0 );
return mix ( b , a , h ) - k * h *( 1.0 - h ); 
}

float smin(float a, float b, float k)
{
	return -(log(exp(k * -a) + exp(k * -b)) / k);
}

float smax(float a, float b, float k)
{

	return log(exp(k * a) + exp(k * b)) / k;
}


 void rotate_z ( inout vec3 p , float a )  
{
float c , s ;
 vec3 q = p ; c = cos ( a ); s = sin ( a );
 p . x = c * q . x - s * q . y ;
 p . y = s * q . x + c * q . y ;
 }

float parabola ( float x , float k )
{
    return pow ( 4.0 * x *( 1.0 - x ), k );
}

float sphere ( vec3 p , float r )
{
return length ( p )- r ;
}

float plane ( vec3 p , float y )
{
return length ( vec3 ( p . x , y , p . z ) - p );
}




float softshadow ( vec3 ro , vec3 rd , float k )
{
     float akuma = 1.0 , h = 0.0 ;
     float t = 0.01 ;
     for ( int i = 0 ; i < 10 ; ++ i )
     {  
        h = f_partial ( ro + rd * t ). x ;
        if ( h < 0.0001 ) return 0.02 ;
        akuma = min ( akuma , k * max ( h , 0.0 )/ t );  
     	t += clamp ( h , 0.01 , 2.0 );
    }
    return akuma ;
}



vec3 nor ( vec3 p )
{
     vec3 e = vec3 ( 0.001 , 0.0 , 0.0 );
    return normalize ( vec3 ( f ( p + e . xyy ). x - f ( p - e . xyy ). x , f ( p + e . yxy ). x - f ( p - e . yxy ). x , f ( p + e . yyx ). x - f ( p - e . yyx ). x ));
}

float phong ( vec3 light , vec3 incident , vec3 normal , float smoothness )
{
     float specpower = exp2 ( 2.0 + 2.0 * smoothness );
    return max ( 0.0 , pow ( clamp ( dot ( light , reflect ( incident , normal )), 0.0 , 1.0 ), specpower ));
}



vec3 intersect ( in vec3 ro , in vec3 rd )
{
    float t = 0.0 ;
    vec3 res = vec3 (- 1.0 , - 1.0 , 1e5 );
     vec3 h = vec3 ( 1.0 );
      for ( int i = 0 ; i < 64 ; i ++ )
      {
          if ( h . x < 0.0005 || t > 20.0 ) continue ;
         h = f ( ro + rd * t );
          res = vec3 ( t , h . y , min ( res . z , h . z ));
           t += h . x ;
    }
    if ( t > 20.0 ) res = vec3 (- 1.0 , - 1.0 , res . z );
    return res ;
}


 vec2 p = 2.0 *( gl_FragCoord . xy )/ iResolution . xy - 1.0 ; p . x *= iResolution . x / iResolution . y ;

 vec3 ta = vec3 ( 0.0 , 0.0 , 0.0 );
 vec3 ro = vec3 ( 0.0 , 1.0 , 5.5 );
 vec3 cf = normalize ( ta - ro );
 vec3 cs = normalize ( cross ( cf , vec3 ( 0.0 , 1.0 , 0.0 )));
 vec3 cu = normalize ( cross ( cs , cf ));
 vec3 rd = normalize ( p . x * cs + p . y * cu + fov * cf );


2d rotation


vec2 rotate(vec2 p, float angle)
{
    return vec2(p.x*cos(angle)-p.y*sin(angle), p.x*sin(angle)+p.y*cos(angle));
}



First the basics:

Add object to object
min(a,b)

Subtract object b from object a
max(a,-b)

Find intersection of 2 objects
max(a,b)

//Distance to tehrahedron
    float tetrahedron(vec3 p){//distance to tetrahedron
        return ( 
                max(
                    max( -p.x-p.y-p.z, p.x+p.y-p.z ), 
                    max( -p.x+p.y+p.z, p.x-p.y+p.z ) 
                   )
                -1.)/sqrt(3.0); 
    }


Distance to sphere

float sphere(float x, float y, float z, float r)
{
return sqrt(x * x + y * y + z * z) - r;
}

Distance to cube

float cube(float x,float y,float z,float size){
return max(max(abs(x)-size,abs(y)-size),abs(z)-size);
}

Signed distance to cube
float signedDistToBox( in vec3 p, in vec3 b )
{
const vec3 di = abs(p) - b;
return min( maxcomp(di), length(max(di,0.0)) );
}

//IQ's small jump dist march
pos += 0.25 * dir * dist;

//Calculate Normal
float e = …;

vec3 n = vec3(ƒ(p + {e, 0, 0}) - ƒ(p - {e, 0, 0}), ƒ(p + {0, e, 0}) - ƒ(p - {0, e, 0}), ƒ(p + {0, 0, e}) - ƒ(p - {0, 0, e}));
n = normalize(n);

//1.Decipher of Youth Uprisings AO algorithm

for (float i = 0.; i < 5.; ++i) {
colour -= vec3(i * k - ƒ(p + n * i * k)) / pow(2., i);
}






//2.  ao and sub surface scattering
float ao(vec3 p, vec3 n, float d, float i) { float o,v; for (o=1.;i>0.;i--) { o-=(i*d-f(p+n*i*d))/exp2(i); } return o; } 

float sss(vec3 p, vec3 n, float d, float i) { float o,v; for (o=0.;i>0.;i--) { o+=(i*d+f(p+n*i*d))/exp2(i); } return o; }

float ao(vec3 p, vec3 n)
{
    float r = 0.0, w = 1.0, d;
    for(float i=1.; i<5.0+1.1; i++)
    {
        d = i/5.0;
        r += w*(d - map(p + n*d).x);
        w *= 0.5;
    }
    return 1.0-clamp(r,0.0,1.0);
}


//Unk of Quite's awesome extrusion field code

for(float i=0; i<4; i++) {
float3 q=1+i*i*.18*(1+4*(1+.3*sin(t*.001))*sin(float3(5.7,6.4,7.3)*i*1.145+.3*sin(h.w*. 015)*(3+i))),g=(frac(p*q)-.5)/q;
d1=min(d1+.03,max(d1,max(abs(g.x),max(abs(g.y),abs(g.z)))-.148));
}

//Some shape generations:   http://www.viz.tamu.edu/faculty/ergun/research/implicitmodeling/papers/sm99.pdf
vec3 n1 = vec3(1.000,0.000,0.000);
vec3 n2 = vec3(0.000,1.000,0.000);
vec3 n3 = vec3(0.000,0.000,1.000);
vec3 n4 = vec3(0.577,0.577,0.577);
vec3 n5 = vec3(-0.577,0.577,0.577);
vec3 n6 = vec3(0.577,-0.577,0.577);
vec3 n7 = vec3(0.577,0.577,-0.577);
vec3 n8 = vec3(0.000,0.357,0.934);
vec3 n9 = vec3(0.000,-0.357,0.934);
vec3 n10 = vec3(0.934,0.000,0.357);
vec3 n11 = vec3(-0.934,0.000,0.357);
vec3 n12 = vec3(0.357,0.934,0.000);
vec3 n13 = vec3(-0.357,0.934,0.000);
vec3 n14 = vec3(0.000,0.851,0.526);
vec3 n15 = vec3(0.000,-0.851,0.526);
vec3 n16 = vec3(0.526,0.000,0.851);
vec3 n17 = vec3(-0.526,0.000,0.851);
vec3 n18 = vec3(0.851,0.526,0.000);
vec3 n19 = vec3(-0.851,0.526,0.000);



// p as usual, e exponent (p in the paper), r radius or something like that

float octahedral(vec3 p, float e, float r)
{
    float s = pow(abs(dot(p,n4)),e);
    s += pow(abs(dot(p,n5)),e);
    s += pow(abs(dot(p,n6)),e);
    s += pow(abs(dot(p,n7)),e);
    s = pow(s, 1./e);
    return s-r;
}

float dodecahedral(vec3 p, float e, float r)
{
    float s = pow(abs(dot(p,n14)),e);
    s += pow(abs(dot(p,n15)),e);
    s += pow(abs(dot(p,n16)),e);
    s += pow(abs(dot(p,n17)),e);
    s += pow(abs(dot(p,n18)),e);
    s += pow(abs(dot(p,n19)),e);
    s = pow(s, 1./e);
    return s-r;
}

float icosahedral(vec3 p, float e, float r)
{
    float s = pow(abs(dot(p,n4)),e);
    s += pow(abs(dot(p,n5)),e);
    s += pow(abs(dot(p,n6)),e);
    s += pow(abs(dot(p,n7)),e);
    s += pow(abs(dot(p,n8)),e);
    s += pow(abs(dot(p,n9)),e);
    s += pow(abs(dot(p,n10)),e);
    s += pow(abs(dot(p,n11)),e);
    s += pow(abs(dot(p,n12)),e);
    s += pow(abs(dot(p,n13)),e);
    s = pow(s, 1./e);
    return s-r;
}

float toctahedral(vec3 p, float e, float r)
{
    float s = pow(abs(dot(p,n1)),e);
    s += pow(abs(dot(p,n2)),e);
    s += pow(abs(dot(p,n3)),e);
    s += pow(abs(dot(p,n4)),e);
    s += pow(abs(dot(p,n5)),e);
    s += pow(abs(dot(p,n6)),e);
    s += pow(abs(dot(p,n7)),e);
    s = pow(s, 1./e);
    return s-r;
}

float ticosahedral(vec3 p, float e, float r)
{
    float s = pow(abs(dot(p,n4)),e);
    s += pow(abs(dot(p,n5)),e);
    s += pow(abs(dot(p,n6)),e);
    s += pow(abs(dot(p,n7)),e);
    s += pow(abs(dot(p,n8)),e);
    s += pow(abs(dot(p,n9)),e);
    s += pow(abs(dot(p,n10)),e);
    s += pow(abs(dot(p,n11)),e);
    s += pow(abs(dot(p,n12)),e);
    s += pow(abs(dot(p,n13)),e);
    s += pow(abs(dot(p,n14)),e);
    s += pow(abs(dot(p,n15)),e);
    s += pow(abs(dot(p,n16)),e);
    s += pow(abs(dot(p,n17)),e);
    s += pow(abs(dot(p,n18)),e);
    s += pow(abs(dot(p,n19)),e);
    s = pow(s, 1./e);
    return s-r;
}



Repeat
//repeat around y axis n times void rp(inout vec3 p, float n) { float w = 2.0*pi/n; float a = atan(p.z, p.x); float r = length(p.xz); a = mod(a+pi*.5, w)+pi-pi/n; p.xz = r*vec2(cos(a),sin(a)); } //sample rp(p, 6.0);
return box(p+vec3(0.5,0.0,0.0), vec3(0.15, 1.85, 1.85));:



Macro do the rotation
#define R(p,a) p=cos(a)*p+sin(a)*float2(-p.y,p.x); // hlsl:




void rX(inout vec3 p, float a)
{
 float c,s;vec3 q=p;
 c = cos(a); s = sin(a);
 p.y = c * q.y - s * q.z;
 p.z = s * q.y + c * q.z;
}


 void rY(inout vec3 p, float a)
 {
 float c,s;vec3 q=p;
 c = cos(a); s = sin(a);
 p.x = c * q.x + s * q.z;
 p.z = -s * q.x + c * q.z;
 }


 void rZ(inout vec3 p, float a)
{
 float c,s;vec3 q=p;
 c = cos(a); s = sin(a);
 p.x = c * q.x - s * q.y;
 p.y = s * q.x + c * q.y;
 }




mat4 rotationAxisAngle( vec3 v, float angle )
{
    float s = sin( angle );
    float c = cos( angle );
    float ic = 1.0 - c;
    return mat4( v.x*v.x*ic + c, v.y*v.x*ic - s*v.z, v.z*v.x*ic + s*v.y, 0.0,
                 v.x*v.y*ic + s*v.z, v.y*v.y*ic + c, v.z*v.y*ic - s*v.x, 0.0,
                 v.x*v.z*ic - s*v.y, v.y*v.z*ic + s*v.x, v.z*v.z*ic + c, 0.0,
        0.0, 0.0, 0.0, 1.0 );
}
mat4 translate( float x, float y, float z )
{
    return mat4( 1.0, 0.0, 0.0, 0.0,
     0.0, 1.0, 0.0, 0.0,
     0.0, 0.0, 1.0, 0.0,
     x, y, z, 1.0 );
}
mat4 inverse( in mat4 m )
{
 return mat4(
        m[0][0], m[1][0], m[2][0], 0.0,
        m[0][1], m[1][1], m[2][1], 0.0,
        m[0][2], m[1][2], m[2][2], 0.0,
        -dot(m[0].xyz,m[3].xyz),
        -dot(m[1].xyz,m[3].xyz),
        -dot(m[2].xyz,m[3].xyz),
        1.0 );
}




float plane(vec3 p, float y){ return distance(p, vec3(p.x, y, p.z)); }





Full shader sources
http://pastebin.com/9PRG1PfN - Cdak by Quite
http://pastebin.com/41hKL0qa - Slisesix by RGBA
```
