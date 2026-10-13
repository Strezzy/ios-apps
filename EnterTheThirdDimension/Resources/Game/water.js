/* Original liquid character renderer. No third-party shader code or assets.
 * The girl is a smooth, animated water surface rather than a pixel sprite.
 * Refraction reads a separate opaque scene texture; it never samples its own
 * framebuffer. A matching high-resolution world depth pass provides occlusion.
 */
(() => {
  'use strict';
  const TAU=Math.PI*2,clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
  const mix=(a,b,t)=>a+(b-a)*t;
  const normalize=a=>{const l=Math.hypot(a[0],a[1],a[2])||1;return[a[0]/l,a[1]/l,a[2]/l];};
  const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
  const smooth=t=>{t=clamp(t,0,1);return t*t*(3-2*t);};
  const gaussian2=(x,y,cx,cy,sx,sy)=>{const a=(x-cx)/sx,b=(y-cy)/sy;return Math.exp(-a*a-b*b);};
  // Catmull-Rom sweeps keep the neck, water hem and long hair fluid and joined.
  function spline(points,t){
    const n=points.length-1,q=clamp(t,0,.999999)*n,i=Math.floor(q),f=q-i,f2=f*f,f3=f2*f;
    const p0=points[Math.max(0,i-1)],p1=points[i],p2=points[Math.min(n,i+1)],p3=points[Math.min(n,i+2)];
    return p1.map((v,k)=>.5*((2*v)+(-p0[k]+p2[k])*f+(2*p0[k]-5*v+4*p2[k]-p3[k])*f2+(-p0[k]+3*v-3*p2[k]+p3[k])*f3));
  }
  const VS=`
    attribute vec3 aPosition; attribute vec3 aNormal; attribute vec3 aLocal; attribute float aPart;
    uniform mat4 uMatrix; uniform vec3 uOrigin; varying vec3 vNormal; varying vec3 vLocal; varying vec3 vSurface; varying float vPart;
    void main(){vNormal=aNormal;vLocal=aLocal;vSurface=aPosition-uOrigin;vPart=aPart;gl_Position=uMatrix*vec4(aPosition,1.);}`;
  const FS=`
    precision highp float;
    uniform sampler2D uBackground; uniform vec2 uResolution; uniform vec2 uSceneResolution;
    uniform vec3 uView; uniform vec3 uRight; uniform vec3 uUp;
    uniform float uTime; uniform float uForm; uniform float uLook; uniform float uJelly; uniform float uReduced; uniform float uCreature; uniform float uCameraHeight;
    varying vec3 vNormal; varying vec3 vLocal; varying vec3 vSurface; varying float vPart;
    float oval(vec2 p,vec2 size){return 1.-smoothstep(.78,1.,length(p/size));}
    float gaussian(vec2 p,vec2 size){p/=size;return exp(-dot(p,p));}
    float ggx(vec3 N,vec3 V,vec3 L,float rough){
      vec3 H=normalize(V+L);float nl=max(0.,dot(N,L)),nv=max(.06,dot(N,V)),nh=max(0.,dot(N,H));
      float a=rough*rough,a2=a*a,den=nh*nh*(a2-1.)+1.,D=a2/(3.141593*den*den+.0001);
      float k=(rough+1.)*(rough+1.)*.125,G=(nl/(nl*(1.-k)+k))*(nv/(nv*(1.-k)+k));
      float F=.024+.976*pow(1.-max(0.,dot(V,H)),5.);return min(3.,D*G*F/(4.*nl*nv+.003))*nl;
    }
    float blink(float phase){float a=fract((uTime+phase)/5.7);return exp(-pow((a-.84)/.018,2.))*.97;}
    void glassEye(inout vec3 color,vec2 point,vec2 center,vec2 size,vec2 gaze,float closed,float front,vec3 iris){
      vec2 q=(point-center)/size;float lid=max(.065,1.-closed);q.y/=lid;
      float r=length(q),rim=1.-smoothstep(.95,1.055,r),inside=1.-smoothstep(.82,.94,r);
      vec3 ink=vec3(.015,.060,.086);
      color=mix(color,ink,rim*front*.95);
      // The pale sclera, concave radial iris and two corneal catches remain
      // readable at the normal phone camera distance; all art is analytic.
      vec3 sclera=mix(vec3(.91,.975,.96),vec3(.44,.66,.71),smoothstep(-.35,1.,q.y)*.36);
      vec2 iq=(q-gaze*vec2(.22,.13))*vec2(1.04,.92);float ir=length(iq);
      float ring=1.-smoothstep(.60,.73,ir),angle=atan(iq.y,iq.x);
      float rays=.5;
      vec3 irisColor=mix(iris*1.2,iris*.24,smoothstep(.36,.73,ir));
      irisColor+=iris*rays*.22*(1.-smoothstep(.38,.69,ir));
      irisColor+=vec3(.11,.30,.28)*exp(-pow((ir-.42)/.13,2.))*(.5-.5*iq.y);
      vec3 eye=mix(ink,irisColor*.65,ring*.6);
      float pupil=1.-smoothstep(.44,.57,length(iq*vec2(1.,1.03)));eye=mix(eye,ink*.48,pupil);
      eye=mix(eye,vec3(1.),oval(q-vec2(-.28,.34),vec2(.26,.29))*.96);
      eye=mix(eye,vec3(.64,.96,1.),oval(q-vec2(.30,-.25),vec2(.09,.12))*.85);
      eye+=vec3(.10,.19,.20)*gaussian(q-vec2(-.1,-.6),vec2(.6,.22));
      color=mix(color,eye,inside*front);
      // Upper lid and its slight wing give the eyes shape even during a blink.
      float lash=(1.-smoothstep(.035,.105,abs(q.y-.76+.22*q.x*q.x)))*(1.-smoothstep(.74,1.05,abs(q.x)));
      color=mix(color,ink,lash*front*.78);
    }
    void main(){
      vec3 N=normalize(vNormal),V=normalize(uView);if(dot(N,V)<0.)N=-N;
      vec3 P=mix(vSurface,vLocal,smoothstep(0.,.75,uForm));
      float hair=max(step(1.5,vPart)*step(vPart,2.5),step(3.5,vPart)*(1.-step(.5,uCreature))*smoothstep(16.,20.,vLocal.y))*smoothstep(.3,.95,uForm);
      float wave=sin(P.y*.52-uTime*2.3+sin(P.x*.58))*.008;
      N=normalize(N+vec3(wave,sin(P.x*.55+uTime*1.7)*.005,wave*.7)*(1.-uReduced*.65));
      float ndv=clamp(dot(N,V),0.,1.),edgeF=pow(1.-ndv,4.0),F=.024+.976*pow(1.-ndv,5.);
      float thickness=(1.4+7.2*pow(ndv,.72))*mix(1.,.76,hair);
      vec2 uv=gl_FragCoord.xy/uResolution,screenN=vec2(dot(N,uRight),dot(N,uUp));
      float bend=clamp(thickness*.27/max(60.,uCameraHeight),.002,.042);
      vec2 lens=screenN*bend*(1.-edgeF*.42);
      lens+=vec2(sin(P.y*.54+uTime*1.8),cos(P.x*.57-uTime*1.35))*.00035*uJelly;
      vec2 margin=.5/uSceneResolution;
      vec3 behind=vec3(texture2D(uBackground,clamp(uv+lens*1.010,margin,1.-margin)).r,
        texture2D(uBackground,clamp(uv+lens,margin,1.-margin)).g,
        texture2D(uBackground,clamp(uv+lens*.990,margin,1.-margin)).b);
      vec3 absorption=exp(-vec3(.035,.012,.009)*thickness);
      vec3 transmitted=behind*absorption+vec3(.045,.105,.115)*(1.-absorption+.38);
      // A clear lower body, pearly face, and slightly deeper watery hair form a
      // deliberate material hierarchy instead of one uniformly cyan blob.
      float faceBody=(1.-step(.5,vPart))*smoothstep(18.5,24.,vLocal.y)*(1.-step(.5,uCreature))*smoothstep(.4,.95,uForm);
      vec3 key=normalize(vec3(-.48,.78,.40));
      float wrap=.68+.32*max(0.,dot(N,key));
      vec3 waterColor=mix(vec3(.18,.53,.59),vec3(.34,.65,.68),faceBody*.68)*wrap;
      // A pearly suspended core gives the living water enough local contrast
      // to read in the bright forest while scene detail still bends through it.
      transmitted=mix(transmitted,waterColor,.41+faceBody*.17);
      vec3 R=reflect(-V,N);
      vec3 environment=mix(vec3(.22,.40,.30),vec3(.62,.80,.83),smoothstep(-.5,.8,R.y));
      float skyWindow=exp(-pow((R.y-.42-.13*sin(R.x*4.1))/ .13,2.));
      environment+=vec3(.21,.36,.31)*skyWindow;
      environment+=vec3(.22,.12,.24)*exp(-pow((R.y-.72+.11*cos(R.z*4.))/ .10,2.));
      vec3 nearby=texture2D(uBackground,clamp(uv+screenN*.17,margin,1.-margin)).rgb;
      environment=mix(environment,nearby,.17);
      vec3 color=mix(transmitted,environment,.12+F*.68);
      vec3 pearl=.5+.5*cos(vec3(.4,2.25,4.3)+edgeF*3.7+P.y*.065);
      color+=(vec3(.40,.72,.81)+pearl*.13)*edgeF*.52;
      float keyGloss=pow(max(0.,dot(N,normalize(key+V))),72.);
      float softGloss=pow(max(0.,dot(N,normalize(vec3(.60,.70,.42)+V))),17.);
      float ribbonGloss=pow(max(0.,dot(N,normalize(vec3(-.75,.28,.30)+V))),39.);
      color+=vec3(.83,.94,1.)*keyGloss*.58+vec3(.27,.51,.60)*softGloss*.22;
      color+=vec3(.67,.60,.78)*ribbonGloss*.14;
      color+=vec3(1.,.94,.80)*ggx(N,V,key,mix(.23,.27,hair))*.64;
      color+=vec3(.57,.82,1.)*ggx(N,V,normalize(vec3(.55,.35,.76)),.32)*.44;
      color+=vec3(.70,.94,.88)*pow(max(0.,dot(N,normalize(vec3(-.6,.6,-.3)+V))),30.)*.105;
      // Very soft caustic filaments and sparse little bubbles travel through
      // the water. Their intensity stays below the facial/outer highlights.
      float caustic=abs(sin(P.x*.58+uTime*.31)+sin(P.y*.63-uTime*.24)+sin(P.z*.85+uTime*.19));
      float thread=pow(1.-smoothstep(.035,.22,caustic),2.);
      color+=vec3(.065,.15,.16)*thread*(.18+.13*uJelly)*(1.-edgeF)*(1.-faceBody*.82);
      float bubbles=0.;
      for(int i=0;i<4;i++){
        float f=float(i),by=mod(uTime*.63+f*6.45,25.)+4.;
        vec2 q=P.xy-vec2(sin(f*2.2+uTime*.17)*3.6,by);
        float radius=.10+f*.023;
        bubbles+=(1.-smoothstep(.018,.075,abs(length(q)-radius)))*smoothstep(.4,2.,vLocal.z);
      }
      color+=vec3(.10,.19,.22)*bubbles*.20*(1.-faceBody*.8);
      if(hair>.5){color=mix(color,color*vec3(.88,1.,1.035)+vec3(.018,.024,.032),.62);}
      if(uCreature<.5&&vPart<.5){
        float hem=exp(-pow((vLocal.y-9.05)/.38,2.));
        color+=vec3(.12,.23,.24)*hem*.36*smoothstep(.5,1.,uForm);
        float waist=exp(-pow((vLocal.y-14.25)/.20,2.));color+=vec3(.07,.15,.16)*waist*.17*smoothstep(.5,1.,uForm);
      }
      vec2 gaze=vec2(mix(uLook*.48,uCreature>1.5?.48:uLook*.48,smoothstep(.5,.9,uForm))+sin(uTime*.51)*.10,sin(uTime*.37)*.14);
      float reveal=smoothstep(.73,.98,uForm);
      if(vPart<.5&&uForm<.25){
        vec2 face=vec2(vSurface.x-uLook*.35,vSurface.y-5.1);
        float front=smoothstep(.25,1.05,vSurface.z)*(1.-smoothstep(.035,.25,uForm));
        glassEye(color,face,vec2(-1.05,0.),vec2(.38,.53),gaze,blink(1.3),front,vec3(.17,.60,.68));
        glassEye(color,face,vec2(1.05,0.),vec2(.38,.53),gaze,blink(1.3),front,vec3(.17,.60,.68));
        vec2 smile=vec2(face.x,face.y+1.15);
        float mouth=(1.-smoothstep(.04,.095,abs(smile.y-.22*smile.x*smile.x)))*(1.-smoothstep(.36,.57,abs(smile.x)));
        color=mix(color,vec3(.05,.20,.25),mouth*front*.72);
      }
      if(uCreature<.5&&vPart<.5&&vLocal.y>19.){
        vec2 face=vec2(vLocal.x-uLook*.24,vLocal.y-25.65);
        float front=smoothstep(2.15,3.95,vLocal.z)*reveal,closed=blink(0.);
        glassEye(color,face,vec2(-2.37,0.),vec2(1.05,1.57),gaze,closed,front,vec3(.11,.47,.64));
        glassEye(color,face,vec2(2.37,0.),vec2(1.05,1.57),gaze,closed,front,vec3(.11,.47,.64));
        float cheeks=max(gaussian(face-vec2(-4.35,-1.8),vec2(1.35,.69)),gaussian(face-vec2(4.35,-1.8),vec2(1.35,.69)));
        color+=vec3(.11,.032,.070)*cheeks*front*.27;
        float browL=(1.-smoothstep(.06,.14,abs(face.y-2.43+.12*pow(face.x+2.37,2.))))*(1.-smoothstep(.73,1.18,abs(face.x+2.37)));
        float browR=(1.-smoothstep(.06,.14,abs(face.y-2.47+.12*pow(face.x-2.37,2.))))*(1.-smoothstep(.73,1.18,abs(face.x-2.37)));
        color=mix(color,vec3(.07,.24,.30),max(browL,browR)*front*.56);
        vec2 smile=vec2(face.x-uLook*.07,face.y+3.0);
        float mouth=(1.-smoothstep(.06,.13,abs(smile.y-.16*smile.x*smile.x)))*(1.-smoothstep(.63,.94,abs(smile.x)));
        color=mix(color,vec3(.06,.19,.24),mouth*front*.66);
        color+=vec3(.12,.20,.20)*gaussian(face-vec2(-.18,-2.0),vec2(.22,.13))*front*.45;
      }
      if(uCreature>.5&&uCreature<1.5){
        color=mix(color,color*vec3(.88,1.06,.985),.35*reveal);
        float front=smoothstep(1.5,2.9,vLocal.z)*reveal;
        glassEye(color,vLocal.xy,vec2(-4.8,14.35),vec2(1.05,1.36),gaze,blink(.9),front,vec3(.32,.60,.27));
        glassEye(color,vLocal.xy,vec2(4.8,14.35),vec2(1.05,1.36),gaze,blink(.9),front,vec3(.32,.60,.27));
        float throat=gaussian(vLocal.xy-vec2(0.,5.5),vec2(5.0,3.4))*smoothstep(2.2,4.,vLocal.z);
        color=mix(color,color*.88+vec3(.065,.095,.057),throat*.55*reveal);
        float smile=(1.-smoothstep(.075,.16,abs(vLocal.y-8.05-.057*vLocal.x*vLocal.x)))*(1.-smoothstep(2.9,3.55,abs(vLocal.x)));
        color=mix(color,vec3(.065,.21,.19),smile*front*.72);
        float nostrils=max(oval(vLocal.xy-vec2(-1.15,10.15),vec2(.18,.13)),oval(vLocal.xy-vec2(1.15,10.15),vec2(.18,.13)));
        color=mix(color,vec3(.08,.25,.24),nostrils*front*.6);
      }
      if(uCreature>1.5){
        float front=smoothstep(2.5,4.0,vLocal.z)*reveal;
        glassEye(color,vLocal.xy,vec2(7.5,17.45),vec2(1.10,1.43),gaze,blink(.4),front,vec3(.30,.57,.68));
        float farFace=smoothstep(10.0,11.6,vLocal.x)*reveal;
        glassEye(color,vec2(-vLocal.z,vLocal.y),vec2(1.55,17.45),vec2(.89,1.38),gaze,blink(.4),farFace,vec3(.30,.57,.68));
        float muzzle=smoothstep(9.6,12.2,vLocal.x)*(1.-smoothstep(14.7,16.3,vLocal.y))*reveal;
        color=mix(color,color*.85+vec3(.11,.15,.14),muzzle*.65);
        float bib=gaussian(vLocal.xy-vec2(5.8,9.3),vec2(3.4,3.2))*front;
        color=mix(color,color*.87+vec3(.06,.10,.10),bib*.6);
        if(vPart>1.5&&vLocal.y>22.5){float inner=exp(-pow(vLocal.z/.90,2.));color+=vec3(.12,.062,.12)*inner*.20*reveal;}
        if(vPart>1.5&&vLocal.x< -12.&&vLocal.y>13.)color=mix(color,color*.9+vec3(.15,.19,.18),smoothstep(13.,17.,vLocal.y)*.55*reveal);
        if(vPart>3.5&&vLocal.x>13.3&&vLocal.y>11.6&&vLocal.y<14.8){color=mix(color,vec3(.025,.092,.12),reveal*.9);color+=vec3(.42,.69,.72)*gaussian(vLocal.xy-vec2(14.3,14.0),vec2(.23,.13))*reveal;}
      }
      gl_FragColor=vec4(clamp(color,0.,1.),1.);
    }`;

  class WaterRenderer {
    constructor(gl){
      this.gl=gl;this.initialized=false;this.draws=0;this.prepares=0;this.shadowDraws=0;this.errors=[];this.surfaceResolution=[0,0];this.lastForm=1;this.worldDepth=.8;
      try{this.init();this.initialized=true;}catch(e){this.errors.push(String(e));throw e;}
    }
    init(){
      const gl=this.gl,compile=(type,source)=>{const shader=gl.createShader(type);gl.shaderSource(shader,source);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS)){const error=gl.getShaderInfoLog(shader);gl.deleteShader(shader);throw new Error('Water shader: '+error);}return shader;};
      const vs=compile(gl.VERTEX_SHADER,VS),fs=compile(gl.FRAGMENT_SHADER,FS),p=gl.createProgram();gl.attachShader(p,vs);gl.attachShader(p,fs);gl.linkProgram(p);gl.deleteShader(vs);gl.deleteShader(fs);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error('Water link: '+gl.getProgramInfoLog(p));
      this.program=p;this.loc={};for(const n of ['aPosition','aNormal','aLocal','aPart'])this.loc[n]=gl.getAttribLocation(p,n);
      for(const n of ['uMatrix','uOrigin','uBackground','uResolution','uSceneResolution','uView','uRight','uUp','uTime','uForm','uLook','uJelly','uReduced','uCreature','uCameraHeight'])this.loc[n]=gl.getUniformLocation(p,n);
      this.surfaces=[];this.vertexCount=0;const indices=[];
      const add=(kind,rings,segments,part)=>{
        const start=this.vertexCount,s={kind,rings,segments,part,start,cos:[],sin:[]};
        for(let j=0;j<segments;j++){s.cos[j]=Math.cos(j/segments*TAU);s.sin[j]=Math.sin(j/segments*TAU);}
        for(let i=0;i<rings;i++)for(let j=0;j<segments;j++){const a=start+i*segments+j,b=start+i*segments+(j+1)%segments,c=b+segments,d=a+segments;indices.push(a,b,c,a,c,d);}
        this.vertexCount+=(rings+1)*segments;this.surfaces.push(s);
      };
      add('body',64,48,0);add('legLeft',18,14,1);add('legRight',18,14,1);
      add('armLeft',18,14,1);add('armRight',18,14,1);
      add('hairBack',30,24,2);add('hairLeft',26,16,2);add('hairRight',26,16,2);add('fringe',22,16,2);
      for(let i=0;i<8;i++)add('detail'+i,12,12,4);
      this.data=new Float32Array(this.vertexCount*10);this.positions=new Float32Array(this.vertexCount*3);this.indices=new Uint16Array(indices);this.triangles=indices.length/3;
      this.buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferData(gl.ARRAY_BUFFER,this.data.byteLength,gl.DYNAMIC_DRAW);
      this.indexBuffer=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,this.indexBuffer);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,this.indices,gl.STATIC_DRAW);
    }
    geometry(state){
      const p=state.player,w=state.water||{},t=state.time||0,form=clamp(w.form===undefined?1:w.form,0,1),d=clamp(state.dimensionBlend||0,0,1),creature=w.creature==='frog'?1:w.creature==='fox'?2:0;
      const lift=w.lift||0,squash=clamp(w.squash===undefined?1:w.squash,.22,1.65),volume=1/Math.sqrt(squash),lean=clamp(w.lean||0,-.5,.5),jelly=clamp(Math.abs(w.wobble||0),0,3);
      const speed=clamp(Math.hypot(p.vx||0,p.vz||0)/(creature===2?168:132),0,1),phase=(p.walk||0)*TAU*(creature===1?.97:creature===2?1.35:1.25);
      const stride=Math.sin(phase)*(creature===2?3.2:3.05)*speed,step=Math.cos(phase),air=p.grounded?0:clamp((p.vy||0)/330,-1,1);
      const depth=mix(.65+.35*d,.07+.93*d,form),face=p.facing||1;
      const idle=Math.sin(t*1.58)*.10,bob=(p.grounded?(1-Math.cos(phase*2))*(creature===1?.60:.23)*speed:0)+idle;
      const trail=clamp((p.vx||0)/(creature===2?168:132),-1,1),hairWave=Math.sin(t*2.4-phase*.22)*(.22+speed*.52+jelly*.4);
      const liftL=Math.max(0,step)*2.15*speed+Math.max(0,air)*1.75,liftR=Math.max(0,-step)*2.15*speed+Math.max(0,air)*2.15;
      const armAir=Math.max(0,air)*3.5,hidden=[[0,6,0,0,0],[0,7,0,.035,.035],[0,8,0,0,0]];
      let bodyProfile=[
        [8.35,0,0],[8.55,4.6,2.9],[9.15,6.7,3.85],[10.3,6.25,3.70],[12.2,5.05,3.15],
        [14.3,3.55,2.45],[16.2,3.6,2.5],[17.75,4.0,2.65],[18.6,3.35,2.3],[19.05,1.9,1.7],
        [19.55,2.7,2.45],[20.45,4.55,3.65],[22.1,6.75,4.85],[24.5,7.60,5.42],
        [27.0,7.65,5.48],[29.5,6.70,5.05],[31.8,4.65,4.0],[33.2,2.2,2.1],[33.65,0,0]
      ];
      const leftHand=[-5.8-stride*.36,10.7+armAir+Math.abs(stride)*.16,.55-stride*.23];
      const rightHand=[5.8+stride*.36,10.7+armAir+Math.abs(stride)*.16,.55+stride*.23];
      const paths={
        legLeft:[[-2.15,10.3,-.15,0,0],[-2.15,8.85,-.15,1.38,1.3],[-2.15+stride*.33,4.7+liftL*.45,-stride*.23,1.15,1.08],[-2.15+stride,1.55+liftL,-stride*.08,.97,.97],[-1.48+stride,.96+liftL,.92,.68,1.35],[-.25+stride,.91+liftL,1.02,0,0]],
        legRight:[[2.15,10.3,-.15,0,0],[2.15,8.85,-.15,1.38,1.3],[2.15-stride*.33,4.7+liftR*.45,stride*.23,1.15,1.08],[2.15-stride,1.55+liftR,stride*.08,.97,.97],[2.84-stride,.96+liftR,.92,.68,1.35],[4.0-stride,.91+liftR,1.02,0,0]],
        armLeft:[[-3.15,18.3,0,0,0],[-3.75,17.9,.1,1.3,1.18],[-4.72-stride*.15,14.1+armAir*.36,.35-stride*.13,1.03,.95],[leftHand[0],leftHand[1]+1.05,leftHand[2],.82,.84],[leftHand[0]-.16,leftHand[1],leftHand[2]+.19,1.04,.9],[leftHand[0]-.05,leftHand[1]-.74,leftHand[2]+.30,0,0]],
        armRight:[[3.15,18.3,0,0,0],[3.75,17.9,.1,1.3,1.18],[4.72+stride*.15,14.1+armAir*.36,.35+stride*.13,1.03,.95],[rightHand[0],rightHand[1]+1.05,rightHand[2],.82,.84],[rightHand[0]+.16,rightHand[1],rightHand[2]+.19,1.04,.9],[rightHand[0]+.05,rightHand[1]-.74,rightHand[2]+.30,0,0]],
        hairBack:[[0,34.45,-.75,0,0],[0,33.45,-2.1,5.05,1.62],[0,30.45,-4.2,7.55,1.53],[-trail*.23,26.1,-5.14,7.15,1.38],[-trail*.6,21.9,-4.7,6.1,1.15],[-trail*1.2+hairWave*.5,17.4,-3.7,4.95,1.03],[-trail*2+hairWave,13.5,-2.7,3.0,.68],[-trail*2.6+hairWave*1.3,11.8,-2.0,0,0]],
        hairLeft:[[-4.1,33.5,1.1,0,0],[-6.55,30.8,2.05,1.9,1.08],[-7.5,26.7,1.8,1.55,1.06],[-7.65-trail*.2,22.2,1.4,1.40,.93],[-7.4-trail*.7+hairWave*.3,18.1,.9,1.5,.91],[-6.3-trail*1.7+hairWave*.9,14.2,1.2,1.2,.71],[-4.4-trail*2.3+hairWave,12.3,1.35,.55,.43],[-3.6-trail*2.5+hairWave,12.65,1.3,0,0]],
        hairRight:[[4.3,33.3,.8,0,0],[6.75,30.1,1.0,1.75,1.05],[7.50,26.3,.65,1.40,.95],[7.3-trail*.3,21.7,.28,1.24,.80],[6.65-trail*.85-hairWave*.5,18.0,.20,1.31,.80],[6.0-trail*1.5-hairWave*.8,14.6,.4,1.16,.62],[4.65-trail*2.1-hairWave,12.75,.5,.58,.38],[3.6-trail*2.3-hairWave,13.2,.3,0,0]],
        fringe:[[-6.45,30.8,2.8,0,0],[-4.4,33.0,3.35,1.68,.78],[-1.45,33.6,4.4,1.86,.85],[1.4,32.3,5.25,1.66,.78],[3.2,30.3,5.6,1.18,.58],[3.7,28.65,5.20,.60,.38],[3.30,28.35,4.98,0,0]],
        detail0:[[leftHand[0]+.40,leftHand[1]+.68,leftHand[2]+.35,0,0],[leftHand[0]+.86,leftHand[1]+.40,leftHand[2]+.62,.40,.37],[leftHand[0]+.92,leftHand[1]-.08,leftHand[2]+.79,.35,.34],[leftHand[0]+.68,leftHand[1]-.43,leftHand[2]+.87,0,0]],
        detail1:[[rightHand[0]-.40,rightHand[1]+.68,rightHand[2]+.35,0,0],[rightHand[0]-.86,rightHand[1]+.40,rightHand[2]+.62,.40,.37],[rightHand[0]-.92,rightHand[1]-.08,rightHand[2]+.79,.35,.34],[rightHand[0]-.68,rightHand[1]-.43,rightHand[2]+.87,0,0]],
        detail2:[[-5.8,32.3,3.9,0,0],[-6.2,30.35,4.85,1.13,.61],[-5.05,28.8,5.25,1.12,.52],[-3.25,28.3,5.25,.58,.35],[-2.20,28.55,5.0,0,0]],
        detail3:[[4.5,32.4,-1.4,0,0],[7.2,29.7,-1.85,1.1,.66],[8.25-trail*.2,25.3,-1.25,.86,.5],[8.18-trail*.6+hairWave*.5,21.1,-.45,.59,.39],[7.2-trail*1.4+hairWave,18.6,0,0,0]],
        detail4:[[-5.6,23.1,-2.2,0,0],[-7.0-trail*.4,19.9,-1.6,.91,.54],[-8.0-trail*1.1-hairWave*.35,17.3,-1.0,.80,.44],[-7.15-trail*1.7-hairWave*.7,14.8,.3,.47,.33],[-5.8-trail*2.1-hairWave*.8,14.0,.75,0,0]],
        detail5:[[5.3,23.5,-2.5,0,0],[6.7-trail*.4,20.4,-1.6,.96,.51],[7.35-trail*1.2+hairWave*.4,17.8,-.7,.74,.45],[6.6-trail*1.8+hairWave*.7,15.7,.1,.44,.28],[5.5-trail*2.0+hairWave*.8,15.2,.4,0,0]],
        detail6:[[-3.1,14.5,2.2,0,0],[-4.1,12.1,3.1,.63,.35],[-4.4,10.2,3.6,.82,.38],[-3.6,8.85,3.3,.47,.30],[-2.55,8.45,2.9,0,0]],
        detail7:[[3.1,14.5,2.2,0,0],[4.1,12.1,3.1,.63,.35],[4.4,10.2,3.6,.82,.38],[3.6,8.85,3.3,.47,.30],[2.55,8.45,2.9,0,0]]
      };
      if(creature===1){
        const extend=Math.max(0,air)*2.3,reach=Math.max(0,air)*1.5,hop=Math.max(0,Math.sin(phase))*speed;
        bodyProfile=[[.9,0,0],[1.3,4.2,2.9],[2.9,6.45,4.2],[5.1,7.85,4.88],[7.4,7.65,5.15],[9.7,6.6,4.8],[11.5,5.45,4.0],[12.9,3.2,2.6],[13.45,0,0]];
        Object.assign(paths,{
          legLeft:[[-5.0,7.4,-1.15,0,0],[-7.3,6.1,-1.2,2.65,2.2],[-9.3,3.9-extend*.35,-.5,2.85,2.30],[-8.05-stride*.2,1.7-extend*.25,2.4,1.72,1.45],[-9.75-stride*.3,.72,3.95-reach,1.13,.63],[-11.4-stride*.3,.61,4.3-reach,0,0]],
          legRight:[[5.0,7.4,-1.15,0,0],[7.3,6.1,-1.2,2.65,2.2],[9.3,3.9-extend*.35,-.5,2.85,2.30],[8.05+stride*.2,1.7-extend*.25,2.4,1.72,1.45],[9.75+stride*.3,.72,3.95-reach,1.13,.63],[11.4+stride*.3,.61,4.3-reach,0,0]],
          armLeft:[[-3.85,7.4,3.35,0,0],[-4.6,5.6,3.95,.93,.87],[-5.0,3.0+hop*.4+reach*.3,4.2,.71,.67],[-4.25,1.12+reach*.5,5.45,.67,.52],[-3.50,.85+reach*.5,5.8,0,0]],
          armRight:[[3.85,7.4,3.35,0,0],[4.6,5.6,3.95,.93,.87],[5.0,3.0+hop*.4+reach*.3,4.2,.71,.67],[4.25,1.12+reach*.5,5.45,.67,.52],[3.50,.85+reach*.5,5.8,0,0]],
          hairLeft:[[-4.8,10.5,1.75,0,0],[-4.8,11.75,1.75,2.34,2.18],[-4.8,13.7,1.75,2.94,2.70],[-4.8,15.55,1.75,2.04,1.95],[-4.8,16.7,1.75,0,0]],
          hairRight:[[4.8,10.5,1.75,0,0],[4.8,11.75,1.75,2.34,2.18],[4.8,13.7,1.75,2.94,2.70],[4.8,15.55,1.75,2.04,1.95],[4.8,16.7,1.75,0,0]],
          hairBack:hidden,fringe:hidden
        });
        for(let side=0;side<2;side++)for(let toe=0;toe<3;toe++){
          const sign=side===0?-1:1,x=sign*(3.50+toe*.68),toeY=.82+reach*.5;
          paths['detail'+(side*3+toe)]=[[sign*4.15,1.36+reach*.5,5.15,0,0],[x,1.03+reach*.5,5.80,.26,.27],[x+sign*.12,toeY,6.8-toe*.18,.31,.31],[x+sign*.08,toeY,7.18-toe*.18,0,0]];
        }
        paths.detail6=[[-9.4-stride*.3,1.06,3.4-reach,0,0],[-10.5-stride*.3,.76,4.4-reach,.46,.36],[-11.45-stride*.3,.66,5.05-reach,.43,.32],[-12.1-stride*.3,.65,5.14-reach,0,0]];
        paths.detail7=[[9.4+stride*.3,1.06,3.4-reach,0,0],[10.5+stride*.3,.76,4.4-reach,.46,.36],[11.45+stride*.3,.66,5.05-reach,.43,.32],[12.1+stride*.3,.65,5.14-reach,0,0]];
      }else if(creature===2){
        const tailWave=Math.sin(t*2.5-phase*.4)*(.35+speed*.65+jelly*.8);
        bodyProfile=[[2.7,0,0,-2.9],[3.35,4.85,2.95,-2.9],[5.8,7.2,3.78,-2.5],[8.1,7.55,4.0,-1.85],[10.3,6.6,3.92,-.35],[12.0,4.3,3.6,2.65],[13.7,4.9,4.0,5.2],[15.75,6.45,4.85,6.1],[18.2,6.13,4.90,6.6],[20.45,4.78,4.20,6.8],[22.0,2.65,2.60,6.85],[22.7,0,0,6.85]];
        const paw=(x,z,offset)=>{
          const swing=Math.sin(phase+offset)*3.0*speed,up=Math.max(0,Math.cos(phase+offset))*1.85*speed+Math.max(0,air)*1.2;
          return[[x,8.0,z,0,0],[x,6.4,z,1.55,1.38],[x+swing*.35,3.55+up*.35,z,1.14,1.02],[x+swing,1.25+up,z+.18,.91,1.12],[x+swing+.85,.82+up,z+.35,.72,1.36],[x+swing+2.0,.72+up,z+.40,0,0]];
        };
        Object.assign(paths,{
          legLeft:paw(-6.1,-2.25,Math.PI),legRight:paw(5.9,-2.25,0),armLeft:paw(-6.1,2.25,0),armRight:paw(5.9,2.25,Math.PI),
          hairBack:[[-7.6,7.5,-.5,0,0],[-10.8,8.25,-1.0,2.15,1.95],[-14.45+tailWave*.32,10.2,-1.3,3.3,2.8],[-16.5+tailWave*.6,13.5,-1.3,3.8,2.96],[-15.7+tailWave*.88,16.7,-1.0,2.97,2.30],[-13.6+tailWave*1.1,18.3,-.7,1.52,1.31],[-11.45+tailWave*1.3,18.0,-.3,0,0]],
          hairLeft:[[2.9,19.7,-.7,0,0],[2.4,21.85,-.65,2.7,1.54],[2.0,24.4,-.45,1.94,1.10],[1.45,26.35,-.2,.80,.53],[1.05,27.4,-.05,0,0]],
          hairRight:[[8.95,19.5,-.8,0,0],[9.55,21.7,-.68,2.7,1.54],[10.15,24.1,-.47,1.94,1.10],[10.7,26.15,-.2,.80,.53],[11.1,27.1,-.05,0,0]],
          fringe:[[9.65,15.35,1.1,0,0],[11.0,14.55,1.15,2.4,2.15],[12.7,13.72,1.0,1.58,1.48],[14.2,13.50,.9,.71,.74],[14.85,13.6,.9,0,0]],
          detail0:[[9.5,13.55,2.25,0,0],[10.5,13.25,2.75,1.44,1.16],[11.7,12.95,2.65,1.16,1.02],[12.9,13.2,1.9,.56,.57],[13.4,13.45,1.5,0,0]],
          detail1:[[9.5,13.55,-1.9,0,0],[10.5,13.25,-2.25,1.44,1.16],[11.7,12.95,-2.05,1.16,1.02],[12.9,13.2,-1.2,.56,.57],[13.4,13.45,-.7,0,0]],
          detail2:[[13.65,13.48,.80,0,0],[14.1,13.48,.80,.67,.79],[14.6,13.57,.8,.56,.67],[14.95,13.59,.8,0,0]],
          detail3:[[9.6,11.65,.3,0,0],[11.4,11.95,.65,1.24,1.43],[13.1,12.5,.8,.70,.91],[13.8,12.95,.8,0,0]]
        });
        for(let i=0;i<4;i++){
          const near=i>1,z=near?2.25:-2.25,x=i%2===0?-6.1:5.9,offset=(i===0||i===3)?Math.PI:0;
          const swing=Math.sin(phase+offset)*3.0*speed,up=Math.max(0,Math.cos(phase+offset))*1.85*speed+Math.max(0,air)*1.2;
          paths['detail'+(i+4)]=[[x+swing+.60,1.02+up,z+.88,0,0],[x+swing+1.26,.71+up,z+1.03,.36,.42],[x+swing+1.94,.65+up,z+1.0,0,0]];
        }
      }
      const data=this.data,pos=this.positions,boundsMin=[Infinity,Infinity,Infinity],boundsMax=[-Infinity,-Infinity,-Infinity];
      for(const s of this.surfaces){
        const centers=[];
        if(s.kind!=='body')for(let i=0;i<=s.rings;i++)centers.push(spline(paths[s.kind],i/s.rings));
        for(let i=0;i<=s.rings;i++){
          const v=i/s.rings,pr=s.kind==='body'?spline(bodyProfile,v):null;
          let U,V,c;
          if(s.kind!=='body'){
            c=centers[i];const before=centers[Math.max(0,i-1)],after=centers[Math.min(s.rings,i+1)];
            const tangent=normalize([after[0]-before[0],after[1]-before[1],after[2]-before[2]]);U=normalize(cross(tangent,Math.abs(tangent[2])>.95?[0,1,0]:[0,0,1]));V=normalize(cross(U,tangent));
          }
          for(let j=0;j<s.segments;j++){
            const cos=s.cos[j],sin=s.sin[j];let x,y,z,dx,dy,dz;
            if(pr){
              const hem=creature===0?1-smooth((pr[0]-9)/5):0,theta=j/s.segments*TAU;
              const flute=1+hem*(.072*Math.cos(theta*5)+.025*Math.sin(phase-theta*1.7)*speed);
              x=(pr[3]||0)+Math.max(0,pr[1])*cos*flute;y=pr[0]+hem*(Math.cos(theta*5)*.33+Math.sin(theta*3+t*1.7)*.055);z=Math.max(0,pr[2])*sin*flute;
              if(creature===0&&y>19&&sin>0){
                // Sculpted cheeks, eye sockets, and a small rounded nose make
                // the face a soft volume rather than a decal on an egg.
                const front=Math.pow(sin,5);
                z+=front*(.62*gaussian2(x,y,0,23.8,.94,.95)+.24*gaussian2(x,y,-4.55,23.2,1.7,1.35)+.24*gaussian2(x,y,4.55,23.2,1.7,1.35)-.15*gaussian2(x,y,-2.37,25.65,1.5,1.8)-.15*gaussian2(x,y,2.37,25.65,1.5,1.8));
              }
              const dropR=Math.pow(Math.max(0,Math.sin(v*Math.PI)),.70)*(1.20-.55*v)*4.7;
              dx=cos*dropR;dy=v*10.6;dz=sin*dropR;
            }else{
              const r=Math.max(0,c[3]),rz=Math.max(0,c[4]);
              x=c[0]+U[0]*cos*r+V[0]*sin*rz;y=c[1]+U[1]*cos*r+V[1]*sin*rz;z=c[2]+U[2]*cos*r+V[2]*sin*rz;
              // Limbs/hair retreat inside the one closed body droplet, avoiding
              // several intersecting visible droplets at the end of the morph.
              const vv=clamp(y/34,.08,.92),rr=Math.pow(Math.sin(vv*Math.PI),.70)*(1.20-.55*vv)*4.7;
              dx=clamp(x/9,-1,1)*rr*.44;dy=1.15+vv*7.5;dz=clamp(z/6,-1,1)*rr*.40;
            }
            const n=s.start+i*s.segments+j,k=n*10,q=n*3;
            data[k+6]=x;data[k+7]=y;data[k+8]=z;data[k+9]=s.part;
            let X=mix(dx,x,form),Y=mix(dy,y,form),Z=mix(dz,z,form);
            // A low neck and forward head keep the fox's silhouette distinctly
            // quadrupedal, including in the camera's foreshortened depth view.
            if(creature===2)Y-=3.4*smooth((y-8)/5.5)*form;
            if(creature===0){
              const headWeight=smooth((y-18.5)/6),turn=(clamp(w.look===undefined?face:w.look,-1,1)*.075+Math.sin(t*.64)*.025)*headWeight*form;
              const rotatedX=X*Math.cos(turn)+Z*Math.sin(turn);Z=Z*Math.cos(turn)-X*Math.sin(turn);X=rotatedX;
              if(s.part===2||s.kind==='detail3'||s.kind==='detail4'||s.kind==='detail5'){
                const trailing=(1-smooth((y-12)/18))*form;
                X+=Math.sin(t*2.8-y*.27+s.start*.013)*(.09+speed*.12+jelly*.25)*trailing;
                Z+=Math.sin(t*2.15-y*.23+s.start*.017)*.15*trailing;
              }
            }
            if(creature===0){
              const head=smooth((Y-17)/8)*form;X*=1+.18*head;Z*=1+.12*head;
              Y=mix(Y,Y*.87+Math.max(0,Y-18)*.25,form);
            }
            const wave=Math.sin(Y*.48-t*8.2)*jelly*.023*(state.reduced?.4:1);
            X*=1+wave;Z*=1+wave;X*=creature===2?face:1;
            X+=lean*Y*.22+Math.sin(t*1.7+Y*.08)*.11*form;
            X*=volume;Y=Y*squash+bob*form*smooth(Math.max(0,y)/(creature===1?5:8));Z*=depth*volume;
            pos[q]=data[k]=p.x+X;pos[q+1]=data[k+1]=p.y+lift+Y;pos[q+2]=data[k+2]=p.z+Z;
            for(let axis=0;axis<3;axis++){boundsMin[axis]=Math.min(boundsMin[axis],pos[q+axis]);boundsMax[axis]=Math.max(boundsMax[axis],pos[q+axis]);}
          }
        }
        // Central differences produce continuous normals, including across the
        // ring seam. Non-uniform squash/depth scaling is already in positions.
        for(let i=0;i<=s.rings;i++)for(let j=0;j<s.segments;j++){
          const n=s.start+i*s.segments+j,k=n*10;
          const a=(s.start+Math.max(0,i-1)*s.segments+j)*3,b=(s.start+Math.min(s.rings,i+1)*s.segments+j)*3;
          const c=(s.start+i*s.segments+(j+s.segments-1)%s.segments)*3,e=(s.start+i*s.segments+(j+1)%s.segments)*3;
          // In the flat world the silhouette is physically thin, while its
          // painted-in liquid surface retains curvature for readable glass
          // highlights. Both lighting and geometry become fully XYZ in 3D.
          const normalDepth=(.75+.25*d)/Math.max(.07,depth);
          const uy=pos[b]-pos[a],vy=pos[b+1]-pos[a+1],wy=(pos[b+2]-pos[a+2])*normalDepth,ut=pos[e]-pos[c],vt=pos[e+1]-pos[c+1],wt=(pos[e+2]-pos[c+2])*normalDepth;
          let nx=vy*wt-wy*vt,ny=wy*ut-uy*wt,nz=uy*vt-vy*ut,l=Math.hypot(nx,ny,nz);
          if(l<.00001){nx=0;ny=i<s.rings/2?-1:1;nz=0;l=1;}
          const orientation=creature===2?face:1;
          data[k+3]=nx/l*orientation;data[k+4]=ny/l*orientation;data[k+5]=nz/l*orientation;
        }
      }
      this.lastForm=form;this.worldDepth=boundsMax[2]-boundsMin[2];this.meshBounds={min:boundsMin,max:boundsMax,width:boundsMax[0]-boundsMin[0],height:boundsMax[1]-boundsMin[1],depth:this.worldDepth};this.creature=creature===1?'frog':creature===2?'fox':'girl';return{form,face,jelly,creature};
    }
    prepare(state){
      const p=state.player,w=state.water||{},key=[state.time,state.dimensionBlend,state.reduced,p.x,p.y,p.z,p.vx,p.vy,p.vz,p.facing,p.walk,p.grounded,w.creature,w.form,w.lift,w.squash,w.lean,w.wobble,w.ripple,w.look].join('|');
      if(key===this.preparedKey)return this.preparedShape;
      const shape=this.geometry(state),gl=this.gl;gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferSubData(gl.ARRAY_BUFFER,0,this.data);
      this.preparedKey=key;this.preparedShape=shape;this.prepares++;return shape;
    }
    drawShadow(matrix,locations={}){
      if(!this.preparedShape)return false;
      const gl=this.gl,program=gl.getParameter(gl.CURRENT_PROGRAM),position=locations.positionLocation===undefined?gl.getAttribLocation(program,'aPosition'):locations.positionLocation;
      const transform=locations.matrixLocation===undefined?gl.getUniformLocation(program,'uMatrix'):locations.matrixLocation;
      gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,this.indexBuffer);
      for(let i=0;i<4;i++)gl.disableVertexAttribArray(i);
      if(position>=0){gl.enableVertexAttribArray(position);gl.vertexAttribPointer(position,3,gl.FLOAT,false,40,0);}
      if(transform!==null&&transform!==undefined)gl.uniformMatrix4fv(transform,false,matrix);
      gl.drawElements(gl.TRIANGLES,this.indices.length,gl.UNSIGNED_SHORT,0);this.shadowDraws++;return true;
    }
    draw(state,matrix,background,width,height,sceneWidth,sceneHeight){
      const gl=this.gl,l=this.loc,shape=this.prepare(state),d=clamp(state.dimensionBlend||0,0,1),yaw=d*.72,el=d*.49,sy=Math.sin(yaw),cy=Math.cos(yaw),se=Math.sin(el),ce=Math.cos(el);
      gl.useProgram(this.program);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,this.indexBuffer);
      for(let i=0;i<4;i++)gl.disableVertexAttribArray(i);
      for(const [name,size,offset]of [['aPosition',3,0],['aNormal',3,12],['aLocal',3,24],['aPart',1,36]])if(l[name]>=0){gl.enableVertexAttribArray(l[name]);gl.vertexAttribPointer(l[name],size,gl.FLOAT,false,40,offset);}
      gl.uniformMatrix4fv(l.uMatrix,false,matrix);gl.uniform2f(l.uResolution,width,height);gl.uniform2f(l.uSceneResolution,sceneWidth,sceneHeight);
      gl.uniform3f(l.uOrigin,state.player.x,state.player.y+((state.water&&state.water.lift)||0),state.player.z);
      gl.uniform3f(l.uView,sy*ce,se,cy*ce);gl.uniform3f(l.uRight,cy,0,-sy);gl.uniform3f(l.uUp,-sy*se,ce,-cy*se);
      gl.uniform1f(l.uTime,state.time||0);gl.uniform1f(l.uForm,shape.form);gl.uniform1f(l.uLook,clamp(state.water&&state.water.look!==undefined?state.water.look:shape.face,-1,1));gl.uniform1f(l.uJelly,shape.jelly);gl.uniform1f(l.uReduced,state.reduced?1:0);
      gl.uniform1f(l.uCreature,shape.creature);gl.uniform1f(l.uCameraHeight,state.cameraHeight||mix(248,288,d));
      gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,background);gl.uniform1i(l.uBackground,0);
      gl.enable(gl.DEPTH_TEST);gl.depthMask(true);gl.disable(gl.BLEND);gl.disable(gl.CULL_FACE);gl.drawElements(gl.TRIANGLES,this.indices.length,gl.UNSIGNED_SHORT,0);
      this.surfaceResolution=[width,height];this.draws++;
      if(this.draws===1){const error=gl.getError();if(error!==gl.NO_ERROR){const message='Water first-frame GL error '+error;this.errors.push(message);throw new Error(message);}}
    }
    getState(){return{visualGeneration:'2.3',initialized:this.initialized,draws:this.draws,prepares:this.prepares,shadowDraws:this.shadowDraws,errors:[...this.errors],smooth:true,material:'clear pearly water with thickness absorption, Fresnel reflection, GGX highlights and restrained chromatic refraction',materialFeatures:['independent scene refraction','directional warm key and cool fill','soft pearlescent edges','internal caustic filaments and drifting bubbles','distinct face, hair and petal-hem finish'],modelFeatures:['sculpted chibi cheeks, sockets and nose','layered curved bangs and separate flowing locks','rounded hands and short planted feet','frog crouched haunches and separate web toes','quadruped fox with cheek muzzle, nose, ears and brush tail'],eyeFeatures:['layered radial iris and deep pupil','pale sclera and two corneal catchlights','soft upper lids and synchronized blinks','gentle gaze and expressive brows'],backgroundSampling:'separate opaque scene texture',surfaceResolution:[...this.surfaceResolution],vertices:this.vertexCount,triangles:this.triangles,form:this.lastForm,creature:this.creature||'girl',worldDepth:this.worldDepth,meshBounds:this.meshBounds||null,animation:'volume-preserving spring response, planted-foot walk, frog hop/tuck, diagonal fox trot, head turn and delayed liquid-hair/tail follow-through'};}
  }
  window.TD_WaterRenderer=WaterRenderer;
})();
