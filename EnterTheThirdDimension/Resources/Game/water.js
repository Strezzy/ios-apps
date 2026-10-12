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
    uniform float uTime; uniform float uForm; uniform float uLook; uniform float uJelly; uniform float uReduced; uniform float uCreature;
    varying vec3 vNormal; varying vec3 vLocal; varying vec3 vSurface; varying float vPart;
    float oval(vec2 p,vec2 size){return 1.-smoothstep(.65,1.,length(p/size));}
    void main(){
      vec3 N=normalize(vNormal),V=normalize(uView);
      // Long, slow surface waves leave a silky highlight; impact jiggle adds
      // short waves only while the spring in the game is still settling.
      float waves=sin(vLocal.y*.7-uTime*3.1+sin(vLocal.x*.8))*.013;
      N=normalize(N+vec3(waves,sin(vLocal.x*.62+uTime*2.2)*.009,waves*.5)*(1.-uReduced*.6));
      float ndv=clamp(abs(dot(N,V)),0.,1.);
      float fresnel=pow(1.-ndv,3.6),thickness=sqrt(max(0.,ndv));
      vec2 uv=gl_FragCoord.xy/uResolution;
      vec2 lens=vec2(dot(N,uRight),dot(N,uUp))*(.006+.008*thickness);
      lens+=vec2(sin(vLocal.y*.6+uTime*2.),cos(vLocal.x*.65-uTime*1.8))*.0009*uJelly;
      vec2 edge=.5/uSceneResolution;
      vec3 behind=vec3(
        texture2D(uBackground,clamp(uv+lens*1.025,edge,1.-edge)).r,
        texture2D(uBackground,clamp(uv+lens,edge,1.-edge)).g,
        texture2D(uBackground,clamp(uv+lens*.975,edge,1.-edge)).b);
      vec3 transmitted=behind*vec3(.77,1.035,1.09)+vec3(.016,.082,.105);
      vec3 R=reflect(-V,N);
      vec3 reflection=mix(vec3(.085,.26,.27),vec3(.13,.24,.40),smoothstep(-.55,.6,R.y));
      float ribbon=exp(-abs(R.y-.28-.13*sin(R.x*5.4+uTime*.026))*16.);
      reflection+=vec3(.15,.40,.32)*ribbon;
      reflection+=vec3(.24,.12,.23)*exp(-abs(R.y-.56+.12*cos(R.z*5.))*19.);
      vec3 color=mix(transmitted,reflection,.10+fresnel*.51);
      color+=vec3(.42,.86,.94)*fresnel*.41;
      // Broad moon reflection plus a narrow pearly glint and warm lantern edge.
      vec3 L=normalize(vec3(-.42,.83,.58));
      float spec=pow(max(0.,dot(N,normalize(L+V))),83.);
      float softSpec=pow(max(0.,dot(N,normalize(vec3(.55,.73,.33)+V))),19.);
      float warmSpec=pow(max(0.,dot(N,normalize(vec3(-.85,.15,-.3)+V))),47.);
      color+=vec3(.73,.91,1.)*spec*.91+vec3(.38,.69,.73)*softSpec*.19;
      color+=vec3(.94,.68,.53)*warmSpec*.23;
      float caustic=pow(.5+.5*sin(vLocal.y*.92+sin(vLocal.x*.8)+uTime*.8),15.);
      color+=vec3(.10,.28,.31)*caustic*.09*(1.-fresnel);
      if(vPart>1.5&&vPart<2.5){color=mix(color,color*vec3(.75,.91,1.09)+vec3(.018,.025,.038),.36);}
      // A tiny face makes the first droplet a curious living character. Surface
      // coordinates follow its lift and shape independently of the stored
      // humanoid/animal coordinates, then fade before the limbs emerge.
      if(vPart<.5&&uForm<.25){
        vec2 face=vec2(vSurface.x-uLook*.48,vSurface.y-5.15);
        float front=smoothstep(.25,1.05,vSurface.z)*(1.-smoothstep(.035,.25,uForm));
        float eyes=max(oval(face-vec2(-1.02,0.),vec2(.28,.44)),oval(face-vec2(1.02,0.),vec2(.28,.44)));
        float glints=max(oval(face-vec2(-1.09,.13),vec2(.085,.11)),oval(face-vec2(.95,.13),vec2(.085,.11)));
        color=mix(color,vec3(.027,.12,.17),eyes*front*.95);
        color=mix(color,vec3(.88,1.,1.),glints*front);
        vec2 smile=vec2(face.x-uLook*.08,face.y+1.06);
        float mouth=(1.-smoothstep(.045,.105,abs(smile.y-.19*smile.x*smile.x)))*(1.-smoothstep(.36,.56,abs(smile.x)));
        color=mix(color,vec3(.06,.22,.27),mouth*front*.65);
      }
      // Features sit on the front of the water head and disappear into the
      // droplet during the morph. They move with the deformed surface itself.
      if(uCreature<.5&&vPart<.5&&vLocal.y>21.){
        vec2 face=vec2(vLocal.x-uLook*.65,vLocal.y-26.7);
        float front=smoothstep(1.3,2.7,vLocal.z)*smoothstep(.72,.98,uForm);
        float eye=max(oval(face-vec2(-1.90,0.),vec2(.61,.98)),oval(face-vec2(1.90,0.),vec2(.61,.98)));
        float glint=max(oval(face-vec2(-2.08,.32),vec2(.18,.23)),oval(face-vec2(1.72,.32),vec2(.18,.23)));
        color=mix(color,vec3(.038,.13,.19),eye*front*.94);
        color=mix(color,vec3(.91,1.,1.),glint*front);
        vec2 smile=vec2(face.x-uLook*.10,face.y+2.0);
        float mouth=(1.-smoothstep(.065,.14,abs(smile.y-.12*smile.x*smile.x)))*(1.-smoothstep(.43,.70,abs(smile.x)));
        color=mix(color,vec3(.10,.28,.35),mouth*front*.48);
      }
      if(uCreature>.5&&uCreature<1.5){
        color=mix(color,color*vec3(.84,1.08,.95),.38);
        float front=smoothstep(1.6,2.5,vLocal.z)*smoothstep(.72,.98,uForm);
        vec2 eyeL=vec2(vLocal.x+4.7,vLocal.y-14.15),eyeR=vec2(vLocal.x-4.7,vLocal.y-14.15);
        float eye=max(oval(eyeL,vec2(.71,1.05)),oval(eyeR,vec2(.71,1.05)));
        float glint=max(oval(eyeL-vec2(-.17,.3),vec2(.18,.23)),oval(eyeR-vec2(-.17,.3),vec2(.18,.23)));
        color=mix(color,vec3(.025,.16,.16),eye*front*.95);color=mix(color,vec3(.9,1.,.94),glint*front);
        float smile=(1.-smoothstep(.08,.18,abs(vLocal.y-7.65-.045*vLocal.x*vLocal.x)))*(1.-smoothstep(2.35,3.0,abs(vLocal.x)));
        color=mix(color,vec3(.07,.24,.24),smile*front*.75);
      }
      if(uCreature>1.5){
        float front=smoothstep(1.7,3.3,vLocal.z)*smoothstep(.72,.98,uForm);
        vec2 eyeL=vec2(vLocal.x-2.6,vLocal.y-19.2),eyeR=vec2(vLocal.x-5.9,vLocal.y-19.2);
        float eye=max(oval(eyeL,vec2(.48,.79)),oval(eyeR,vec2(.48,.79)));
        float glint=max(oval(eyeL-vec2(-.12,.23),vec2(.14,.18)),oval(eyeR-vec2(-.12,.23),vec2(.14,.18)));
        color=mix(color,vec3(.035,.12,.19),eye*front*.94);color=mix(color,vec3(.91,1.,1.),glint*front);
        if(vPart>1.5&&vLocal.y>25.)color+=vec3(.13,.08,.17)*smoothstep(25.,29.,vLocal.y)*.25;
        if(vPart>1.5&&vLocal.x< -7.&&vLocal.y>16.)color+=vec3(.13,.22,.24)*smoothstep(16.,20.,vLocal.y);
        if(vPart>1.5&&vLocal.x>7.25&&vLocal.y>14.&&vLocal.y<17.)color=mix(color,vec3(.035,.14,.19),front*.78);
      }
      gl_FragColor=vec4(clamp(color,0.,1.),1.);
    }`;

  class WaterRenderer {
    constructor(gl){
      this.gl=gl;this.initialized=false;this.draws=0;this.errors=[];this.surfaceResolution=[0,0];this.lastForm=1;this.worldDepth=.8;
      try{this.init();this.initialized=true;}catch(e){this.errors.push(String(e));throw e;}
    }
    init(){
      const gl=this.gl,compile=(type,source)=>{const shader=gl.createShader(type);gl.shaderSource(shader,source);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS)){const error=gl.getShaderInfoLog(shader);gl.deleteShader(shader);throw new Error('Water shader: '+error);}return shader;};
      const vs=compile(gl.VERTEX_SHADER,VS),fs=compile(gl.FRAGMENT_SHADER,FS),p=gl.createProgram();gl.attachShader(p,vs);gl.attachShader(p,fs);gl.linkProgram(p);gl.deleteShader(vs);gl.deleteShader(fs);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error('Water link: '+gl.getProgramInfoLog(p));
      this.program=p;this.loc={};for(const n of ['aPosition','aNormal','aLocal','aPart'])this.loc[n]=gl.getAttribLocation(p,n);
      for(const n of ['uMatrix','uOrigin','uBackground','uResolution','uSceneResolution','uView','uRight','uUp','uTime','uForm','uLook','uJelly','uReduced','uCreature'])this.loc[n]=gl.getUniformLocation(p,n);
      this.surfaces=[];this.vertexCount=0;const indices=[];
      const add=(kind,rings,segments,part)=>{
        const start=this.vertexCount,s={kind,rings,segments,part,start,cos:[],sin:[]};
        for(let j=0;j<segments;j++){s.cos[j]=Math.cos(j/segments*TAU);s.sin[j]=Math.sin(j/segments*TAU);}
        for(let i=0;i<rings;i++)for(let j=0;j<segments;j++){const a=start+i*segments+j,b=start+i*segments+(j+1)%segments,c=b+segments,d=a+segments;indices.push(a,b,c,a,c,d);}
        this.vertexCount+=(rings+1)*segments;this.surfaces.push(s);
      };
      add('body',48,32,0);add('legLeft',18,14,1);add('legRight',18,14,1);
      add('armLeft',18,14,1);add('armRight',18,14,1);
      add('hairBack',27,20,2);add('hairLeft',24,14,2);add('hairRight',24,14,2);add('fringe',18,14,2);
      this.data=new Float32Array(this.vertexCount*10);this.positions=new Float32Array(this.vertexCount*3);this.indices=new Uint16Array(indices);this.triangles=indices.length/3;
      this.buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferData(gl.ARRAY_BUFFER,this.data.byteLength,gl.DYNAMIC_DRAW);
      this.indexBuffer=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,this.indexBuffer);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,this.indices,gl.STATIC_DRAW);
    }
    geometry(state){
      const p=state.player,w=state.water||{},t=state.time||0,form=clamp(w.form===undefined?1:w.form,0,1),d=clamp(state.dimensionBlend||0,0,1),creature=w.creature==='frog'?1:w.creature==='fox'?2:0;
      const lift=w.lift||0,squash=clamp(w.squash===undefined?1:w.squash,.22,1.65),volume=1/Math.sqrt(squash),lean=clamp(w.lean||0,-.5,.5),jelly=clamp(Math.abs(w.wobble||0),0,3);
      const speed=clamp(Math.hypot(p.vx||0,p.vz||0)/132,0,1),phase=(p.walk||0)*TAU*1.65;
      const stride=Math.sin(phase)*3.8*speed,step=Math.cos(phase),air=p.grounded?0:clamp((p.vy||0)/330,-1,1),idle=Math.sin(t*1.7)*.12;
      const depth=mix(.65+.35*d,.07+.93*d,form),face=p.facing||1;
      const bob=(p.grounded?Math.abs(Math.cos(phase))*.55*speed:0)+idle;
      const trail=clamp((p.vx||0)/132,-1,1),hairWave=Math.sin(t*3.3-phase*.25)*(.33+speed*.5+jelly*.2);
      let bodyProfile=[
        [10.6,0,0],[10.9,4.4,2.8],[11.45,6.3,3.65],[12.55,6.0,3.65],[14.2,5.2,3.2],
        [15.8,4.25,2.65],[17.3,3.55,2.45],[18.8,4.65,2.7],[19.75,4.1,2.5],
        [20.2,1.8,1.75],[20.6,1.8,1.75],[21.1,3.5,2.7],[22.8,5.6,4.0],
        [25.3,6.55,4.7],[27.9,6.65,4.8],[30.2,5.55,4.3],
        [32.0,3.6,3.3],[33.0,0,0]
      ];
      const paths={
        legLeft:[[-2.65,13,0,0,0],[-2.55,11.9,0,1.3,1.3],[-2.0-stride*.22,7.4+Math.max(0,-step)*speed,-stride*.30,1.22,1.17],[-2.0+stride,1.5+Math.max(0,step)*1.5*speed+Math.max(0,air)*1.5,-stride*.15,1.22,1.3],[-1.35+stride,1.0+Math.max(0,step)*1.5*speed+Math.max(0,air)*1.5,.9,1.48,1.4],[stride-.6,.85+Math.max(0,step)*1.5*speed,.9,0,0]],
        legRight:[[2.65,13,0,0,0],[2.55,11.9,0,1.3,1.3],[2.0+stride*.22,7.4+Math.max(0,step)*speed,stride*.30,1.22,1.17],[2.0-stride,1.5+Math.max(0,-step)*1.5*speed+Math.max(0,air)*2,stride*.15,1.22,1.3],[2.6-stride,1.0+Math.max(0,-step)*1.5*speed+Math.max(0,air)*2,.9,1.48,1.4],[3.4-stride,.85+Math.max(0,-step)*1.5*speed,.9,0,0]],
        armLeft:[[-3.6,19.9,0,0,0],[-4.1,19.5,0,1.4,1.3],[-5.85-stride*.19,16.0+air*1.5,-stride*.18,1.06,1.02],[-6.6-stride*.41,12.5+air*4+Math.abs(stride)*.15,-stride*.34,1.00,1.02],[-6.6-stride*.41,11.65+air*4+Math.abs(stride)*.15,-stride*.34,0,0]],
        armRight:[[3.6,19.9,0,0,0],[4.1,19.5,0,1.4,1.3],[5.85+stride*.19,16.0+air*1.5,stride*.18,1.06,1.02],[6.6+stride*.41,12.5+air*4+Math.abs(stride)*.15,stride*.34,1.00,1.02],[6.6+stride*.41,11.65+air*4+Math.abs(stride)*.15,stride*.34,0,0]],
        hairBack:[[0,34,-.65,0,0],[0,32.8,-1.5,4.85,1.9],[0,29.3,-3.6,6.55,1.85],[-trail*.6,24.5,-4.5,5.9,1.4],[-trail*1.3+hairWave*.45,20.6,-3.9,5.1,1.3],[-trail*2.4+hairWave,16.2,-2.65,3.5,.95],[-trail*2.65+hairWave*1.6,13.4,-1.7,0,0]],
        hairLeft:[[-3.1,33.1,1.2,0,0],[-5.1,31.1,2.0,1.6,1.5],[-6.2,26.3,1.75,1.3,1.35],[-6.35-trail*.3,22.3,1.5,1.15,1.1],[-6.7-trail*1.3+hairWave,18.2,.7,1.1,.95],[-5.5-trail*2+hairWave*1.5,15.9,.6,.62,.62],[-4.1-trail*2.3+hairWave*1.6,15.65,.5,0,0]],
        hairRight:[[3.1,33.1,.85,0,0],[5.1,31.1,1.25,1.6,1.5],[6.35,26.0,1.0,1.3,1.35],[6.2-trail*.3,22.0,.5,1.15,1.1],[6.5-trail*1.3-hairWave*.8,18.8,0,1.1,.95],[5.5-trail*2-hairWave,16.4,.2,.62,.62],[4.0-trail*2.3-hairWave,16.2,.3,0,0]],
        fringe:[[-5.4,30.3,2.6,0,0],[-4.2,32.1,3.0,1.25,1.0],[-1.6,32.9,3.4,1.45,1.1],[1.3,32.2,3.9,1.25,1.0],[3.3,30.6,4.25,.85,.8],[3.85,29.5,4.1,0,0]]
      };
      const hidden=[[0,7,0,0,0],[0,8,0,.08,.08],[0,9,0,0,0]];
      if(creature===1){
        bodyProfile=[[1.0,0,0],[1.4,3.9,2.9],[3.2,6.2,4.15],[5.8,7.55,4.75],[8.4,7.3,4.85],[10.6,6.2,4.25],[12.4,4.8,3.4],[13.35,2.45,1.9],[13.65,0,0]];
        Object.assign(paths,{
          legLeft:[[-5.4,6.3,-1,0,0],[-7.2,5,-1,2.35,2.1],[-9,2.7,.3,2.65,1.9],[-7.9-stride*.22,1.2,2.5,1.4,1.3],[-9.6-stride*.30,.7,3.5,1.9,.75],[-11.2-stride*.3,.7,3.7,0,0]],
          legRight:[[5.4,6.3,-1,0,0],[7.2,5,-1,2.35,2.1],[9,2.7,.3,2.65,1.9],[7.9+stride*.22,1.2,2.5,1.4,1.3],[9.6+stride*.30,.7,3.5,1.9,.75],[11.2+stride*.3,.7,3.7,0,0]],
          armLeft:[[-3.9,7.5,3.3,0,0],[-4,5.5,3.8,.9,.9],[-4.5,2.2,4.5,.72,.7],[-4.4,.9,5.2,1.5,.6],[-5.3,.75,5.4,0,0]],
          armRight:[[3.9,7.5,3.3,0,0],[4,5.5,3.8,.9,.9],[4.5,2.2,4.5,.72,.7],[4.4,.9,5.2,1.5,.6],[5.3,.75,5.4,0,0]],
          hairLeft:[[-4.7,10.7,1.4,0,0],[-4.7,11.6,1.4,2.05,1.9],[-4.7,13.55,1.4,2.75,2.5],[-4.7,15.4,1.4,2.05,1.8],[-4.7,16.5,1.4,0,0]],
          hairRight:[[4.7,10.7,1.4,0,0],[4.7,11.6,1.4,2.05,1.9],[4.7,13.55,1.4,2.75,2.5],[4.7,15.4,1.4,2.05,1.8],[4.7,16.5,1.4,0,0]],
          hairBack:hidden,fringe:hidden
        });
      }else if(creature===2){
        bodyProfile=[[3.0,0,0,-2],[3.6,3.6,2.5,-2],[5.6,5.6,3.45,-1.7],[8.2,6.25,3.85,-1],[10.7,5.8,3.9,0],[12.9,4.75,3.7,2.1],[15.1,6.25,4.55,3.6],[17.8,6.85,4.9,4.1],[20.25,5.9,4.5,4.4],[22.2,4.1,3.45,4.5],[23.35,1.7,1.75,4.5],[23.65,0,0,4.5]];
        Object.assign(paths,{
          legLeft:[[-4.3,8.0,-2.15,0,0],[-4.4,6.2,-2.15,1.55,1.4],[-5.0+stride*.5,2.6,-2.15,1.1,1.05],[-4.4+stride*.5,1.1,-1.8,1.65,1.1],[-3.25+stride*.5,.8,-1.8,0,0]],
          legRight:[[2.9,8.8,-2.15,0,0],[3.0,6.2,-2.15,1.55,1.4],[3.0-stride*.5,2.6,-2.15,1.1,1.05],[3.55-stride*.5,1.1,-1.8,1.65,1.1],[4.5-stride*.5,.8,-1.8,0,0]],
          armLeft:[[-4.3,8.0,2.15,0,0],[-4.4,6.2,2.15,1.55,1.4],[-4.1-stride*.5,2.6,2.15,1.1,1.05],[-3.5-stride*.5,1.1,2.5,1.65,1.1],[-2.55-stride*.5,.8,2.5,0,0]],
          armRight:[[2.9,8.8,2.15,0,0],[3.0,6.2,2.15,1.55,1.4],[3.8+stride*.5,2.6,2.15,1.1,1.05],[4.4+stride*.5,1.1,2.5,1.65,1.1],[5.35+stride*.5,.8,2.5,0,0]],
          hairBack:[[-5.2,7.5,0,0,0],[-7.8,9.5,-.8,2.25,2.05],[-10.7+hairWave*.7,13.1,-1.4,3.0,2.65],[-11.5+hairWave,17,-1.5,2.85,2.4],[-10.15+hairWave*1.15,20.1,-1.5,1.8,1.55],[-7.7+hairWave*1.35,21.4,-1.5,0,0]],
          hairLeft:[[1.0,20.5,-.6,0,0],[.45,22.7,-.45,2.7,1.5],[-.3,24.6,-.3,2.0,1.2],[-1.0,26.5,-.1,1.0,.7],[-1.7,28.1,0,0,0]],
          hairRight:[[7.05,20.5,-.6,0,0],[7.8,22.7,-.45,2.7,1.5],[8.6,24.6,-.3,2.0,1.2],[9.3,26.5,-.1,1.0,.7],[10.0,28.1,0,0,0]],
          fringe:[[4.8,16.7,3.4,0,0],[5.7,16.2,3.8,1.7,1.6],[6.9,15.75,4.4,1.2,1.2],[7.65,15.7,4.65,.65,.67],[8.1,15.7,4.7,0,0]]
        });
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
              const hem=creature===0?1-smooth((pr[0]-11)/4):0,flute=1+hem*(.047*Math.cos(j/s.segments*TAU*6+t*1.25)+.024*Math.sin(phase-j*.3)*speed);
              x=(pr[3]||0)+Math.max(0,pr[1])*cos*flute;y=pr[0]+hem*Math.sin(j/s.segments*TAU*5+t*2)*.16;z=Math.max(0,pr[2])*sin*flute;
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
            const wave=Math.sin(Y*.48-t*8.2)*jelly*.023*(state.reduced?.4:1);
            X*=1+wave;Z*=1+wave;X+=lean*Y*.22+Math.sin(t*1.7+Y*.08)*.11*form;
            X*=volume*(creature===2?face:1);Y=Y*squash+bob*form;Z*=depth*volume;
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
    draw(state,matrix,background,width,height,sceneWidth,sceneHeight){
      const gl=this.gl,l=this.loc,shape=this.geometry(state),d=clamp(state.dimensionBlend||0,0,1),yaw=d*.72,el=d*.49,sy=Math.sin(yaw),cy=Math.cos(yaw),se=Math.sin(el),ce=Math.cos(el);
      gl.useProgram(this.program);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferSubData(gl.ARRAY_BUFFER,0,this.data);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,this.indexBuffer);
      for(let i=0;i<4;i++)gl.disableVertexAttribArray(i);
      for(const [name,size,offset]of [['aPosition',3,0],['aNormal',3,12],['aLocal',3,24],['aPart',1,36]])if(l[name]>=0){gl.enableVertexAttribArray(l[name]);gl.vertexAttribPointer(l[name],size,gl.FLOAT,false,40,offset);}
      gl.uniformMatrix4fv(l.uMatrix,false,matrix);gl.uniform2f(l.uResolution,width,height);gl.uniform2f(l.uSceneResolution,sceneWidth,sceneHeight);
      gl.uniform3f(l.uOrigin,state.player.x,state.player.y+((state.water&&state.water.lift)||0),state.player.z);
      gl.uniform3f(l.uView,sy*ce,se,cy*ce);gl.uniform3f(l.uRight,cy,0,-sy);gl.uniform3f(l.uUp,-sy*se,ce,-cy*se);
      gl.uniform1f(l.uTime,state.time||0);gl.uniform1f(l.uForm,shape.form);gl.uniform1f(l.uLook,clamp((state.water&&state.water.look)||shape.face,-1,1));gl.uniform1f(l.uJelly,shape.jelly);gl.uniform1f(l.uReduced,state.reduced?1:0);
      gl.uniform1f(l.uCreature,shape.creature);
      gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,background);gl.uniform1i(l.uBackground,0);
      gl.enable(gl.DEPTH_TEST);gl.depthMask(true);gl.disable(gl.BLEND);gl.disable(gl.CULL_FACE);gl.drawElements(gl.TRIANGLES,this.indices.length,gl.UNSIGNED_SHORT,0);
      this.surfaceResolution=[width,height];this.draws++;
      if(this.draws===1){const error=gl.getError();if(error!==gl.NO_ERROR){const message='Water first-frame GL error '+error;this.errors.push(message);throw new Error(message);}}
    }
    getState(){return{initialized:this.initialized,draws:this.draws,errors:[...this.errors],smooth:true,material:'original refractive water with Fresnel reflection and pearly specular light',backgroundSampling:'separate opaque scene texture',surfaceResolution:[...this.surfaceResolution],vertices:this.vertexCount,triangles:this.triangles,form:this.lastForm,creature:this.creature||'girl',worldDepth:this.worldDepth,meshBounds:this.meshBounds||null,animation:'connected liquid surface, volume-preserving squash, walking limbs and trailing water hair'};}
  }
  window.TD_WaterRenderer=WaterRenderer;
})();
