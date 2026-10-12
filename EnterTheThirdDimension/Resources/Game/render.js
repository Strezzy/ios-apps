/* Original, dependency-free WebGL renderer and GLSL effects.
 * A real XYZ world, an animated orthographic camera, and extruded pixel meshes.
 * The post-process is decorative; movement and occlusion use actual 3D geometry.
 */
(() => {
  'use strict';
  const clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
  const lerp=(a,b,t)=>a+(b-a)*t;
  const hash=n=>{const v=Math.sin(n*127.1+311.7)*43758.5453;return v-Math.floor(v);};
  const rgb=c=>typeof c==='string'?[parseInt(c.slice(1,3),16)/255,parseInt(c.slice(3,5),16)/255,parseInt(c.slice(5,7),16)/255]:c;
  const tint=(c,n)=>rgb(c).map(v=>clamp(v*n,0,1));
  const mul=(a,b)=>{const o=new Float32Array(16);for(let c=0;c<4;c++)for(let r=0;r<4;r++)o[c*4+r]=a[r]*b[c*4]+a[4+r]*b[c*4+1]+a[8+r]*b[c*4+2]+a[12+r]*b[c*4+3];return o;};
  function matrix(target,aspect,dim){
    const yaw=dim*.72,el=dim*.49,sy=Math.sin(yaw),cy=Math.cos(yaw),se=Math.sin(el),ce=Math.cos(el);
    const right=[cy,0,-sy],up=[-sy*se,ce,-cy*se],back=[sy*ce,se,cy*ce];
    const eye=target.map((v,i)=>v+back[i]*900),dot=(a,b)=>a[0]*b[0]+a[1]*b[1]+a[2]*b[2];
    const view=new Float32Array([right[0],up[0],back[0],0,right[1],up[1],back[1],0,right[2],up[2],back[2],0,-dot(right,eye),-dot(up,eye),-dot(back,eye),1]);
    const h=lerp(248,288,dim),w=h*aspect;
    const proj=new Float32Array([2/w,0,0,0,0,2/h,0,0,0,0,-2/2199,0,0,0,-2201/2199,1]);
    return mul(proj,view);
  }
  class Mesh {
    constructor(){this.a=[];}
    vertex(p,c,n,g=0){this.a.push(p[0],p[1],p[2],c[0],c[1],c[2],n[0],n[1],n[2],g);}
    quad(a,b,c,d,color,normal,glow=0){color=rgb(color);for(const p of [a,b,c,a,c,d])this.vertex(p,color,normal,glow);}
    box(x,y,z,w,h,d,color,glow=0){
      if(w<=0||h<=0||d<=0)return;
      const X=x+w,Y=y+h,Z=z+d,c=rgb(color);
      this.quad([x,y,Z],[X,y,Z],[X,Y,Z],[x,Y,Z],c,[0,0,1],glow);
      this.quad([X,y,z],[x,y,z],[x,Y,z],[X,Y,z],c,[0,0,-1],glow);
      this.quad([x,Y,Z],[X,Y,Z],[X,Y,z],[x,Y,z],c,[0,1,0],glow);
      this.quad([x,y,z],[X,y,z],[X,y,Z],[x,y,Z],c,[0,-1,0],glow);
      this.quad([X,y,Z],[X,y,z],[X,Y,z],[X,Y,Z],c,[1,0,0],glow);
      this.quad([x,y,z],[x,y,Z],[x,Y,Z],[x,Y,z],c,[-1,0,0],glow);
    }
    diamond(x,y,z,size,color,angle=0){
      const s=Math.sin(angle),c=Math.cos(angle),rot=(xx,yy,zz)=>[x+xx*c+zz*s,y+yy,z-xx*s+zz*c];
      const top=rot(0,size,0),bot=rot(0,-size,0),ring=[rot(size*.65,0,0),rot(0,0,size*.65),rot(-size*.65,0,0),rot(0,0,-size*.65)];
      const col=rgb(color);
      for(let i=0;i<4;i++){const j=(i+1)%4;const n=[Math.cos(angle+i*Math.PI/2),.6,Math.sin(angle+i*Math.PI/2)];for(const p of [top,ring[i],ring[j]])this.vertex(p,tint(col,1-i*.06),n,.75);for(const p of [bot,ring[j],ring[i]])this.vertex(p,tint(col,.78),[n[0],-.6,n[2]],.5);}
    }
    sprite(frame,x,y,z,depth=1,face=1,scale=1,stretch=1){
      if(!frame)return;
      const rows=frame.rows,ww=frame.width||rows[0].length,hh=frame.height||rows.length;
      for(let row=0;row<hh;row++){
        let col=0;while(col<ww){const key=rows[row][col];if(!frame.palette[key]){col++;continue;}let end=col+1;while(end<ww&&rows[row][end]===key)end++;
          const xx=face>0?col-ww/2:ww/2-end;
          this.box(x+xx*scale,y+(hh-row-1)*scale*stretch,z-depth/2,(end-col)*scale,scale*stretch,depth,frame.palette[key]);col=end;
        }
      }
    }
    append(data,x=0,y=0,z=0,stretch=1,depth=1){
      // Cached boxes have axis-aligned normals. Positive Y/Z scaling changes
      // their positions without changing their lighting normals or face order.
      const out=this.a;
      for(let i=0;i<data.length;i+=10)out.push(x+data[i],y+data[i+1]*stretch,z+data[i+2]*depth,data[i+3],data[i+4],data[i+5],data[i+6],data[i+7],data[i+8],data[i+9]);
    }
    data(){return new Float32Array(this.a);}
  }
  const sceneVS=`
    attribute vec3 aPosition; attribute vec3 aColor; attribute vec3 aNormal; attribute float aGlow;
    uniform mat4 uMatrix; uniform vec3 uTarget; uniform float uDimension;
    varying vec3 vColor; varying float vFog; varying float vGlow;
    void main(){
      vec3 light=normalize(vec3(-.38,.8,.65));
      float lambert=max(0.0,dot(aNormal,light));
      float shade=mix(.94,.57+lambert*.5,uDimension);
      shade+=max(0.0,aNormal.y)*.06;
      vColor=aColor*mix(shade,1.15,clamp(aGlow,0.,1.)); vGlow=aGlow;
      vFog=clamp((-aPosition.z-110.)/680.,0.,.74);
      gl_Position=uMatrix*vec4(aPosition,1.0);
    }`;
  const sceneFS=`precision mediump float; varying vec3 vColor; varying float vFog; varying float vGlow;
    void main(){vec3 color=mix(vColor,vec3(.15,.22,.32),vFog);gl_FragColor=vec4(color,1.);}`;
  const screenVS=`attribute vec2 aPosition; varying vec2 vUV; void main(){vUV=aPosition*.5+.5;gl_Position=vec4(aPosition,0.,1.);}`;
  const skyFS=`precision mediump float; varying vec2 vUV; uniform float uTime; uniform float uDimension; uniform vec2 uResolution;
    float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
    void main(){
      vec2 uv=vUV;vec3 bottom=vec3(.16,.27,.35),top=vec3(.038,.063,.15);
      vec3 col=mix(bottom,top,smoothstep(.05,1.,uv.y));
      float band=.69+.10*sin(uv.x*5.1+uTime*.035)+.04*sin(uv.x*13.-uTime*.019);
      float aurora=exp(-abs(uv.y-band)*22.)*(.48+.28*sin(uv.x*21.+uTime*.06));
      col+=vec3(.075,.235,.185)*aurora*(.65+uDimension*.45);
      float band2=band+.055;col+=vec3(.13,.08,.24)*exp(-abs(uv.y-band2)*35.)*.7;
      vec2 grid=floor(uv*uResolution/3.);float star=step(.992,hash(grid));
      float twinkle=.6+.4*sin(uTime*.8+hash(grid+4.)*6.28);
      col+=star*twinkle*smoothstep(.48,.7,uv.y)*vec3(.38,.46,.48);
      vec2 m=(uv-vec2(.77,.78))*vec2(uResolution.x/uResolution.y,1.);
      float moon=1.-smoothstep(.048,.05,length(m));float cut=1.-smoothstep(.043,.046,length(m-vec2(.019,.007)));
      col+=max(0.,moon-cut)*vec3(.60,.64,.47);col+=exp(-length(m)*32.)*vec3(.05,.065,.06);
      gl_FragColor=vec4(col,1.);
    }`;
  const postFS=`precision mediump float; varying vec2 vUV; uniform sampler2D uScene; uniform vec2 uResolution; uniform float uTime; uniform float uPulse; uniform float uDimension; uniform float uReduced;
    void main(){
      vec2 uv=vUV;vec2 centered=(uv-vec2(.43,.49))*vec2(uResolution.x/uResolution.y,1.);
      float dist=length(centered);float wave=sin(dist*35.-uTime*10.)*exp(-dist*1.8);
      vec2 offset=normalize(centered+vec2(.0001))*wave*uPulse*.012*(1.-uReduced);
      offset.x*=uResolution.y/uResolution.x;uv+=offset;
      vec2 shift=vec2((.0035+.0015*sin(uTime*15.))*uPulse*(1.-uReduced),0.);
      vec3 col=vec3(texture2D(uScene,clamp(uv+shift,0.,1.)).r,texture2D(uScene,clamp(uv,0.,1.)).g,texture2D(uScene,clamp(uv-shift,0.,1.)).b);
      vec2 texel=1./uResolution;
      vec3 glow=vec3(0.);
      glow+=max(texture2D(uScene,uv+texel*vec2(2.,0.)).rgb-.68,0.);
      glow+=max(texture2D(uScene,uv-texel*vec2(2.,0.)).rgb-.68,0.);
      glow+=max(texture2D(uScene,uv+texel*vec2(0.,2.)).rgb-.68,0.);
      glow+=max(texture2D(uScene,uv-texel*vec2(0.,2.)).rgb-.68,0.);
      col+=glow*(.11+.12*uPulse)*(1.-uReduced*.65);
      col+=vec3(.025,.06,.052)*uPulse;
      float scan=mod(floor(vUV.y*uResolution.y),2.);col*=1.-scan*.013;
      gl_FragColor=vec4(col,1.);
    }`;
  class Renderer {
    constructor(canvas,world,art,hooks={}){
      this.canvas=canvas;this.world=world;this.art=art;this.hooks=hooks;this.frames=0;this.contextLost=false;this.restorations=0;this.errors=[];
      this.gl=canvas.getContext('webgl',{alpha:false,antialias:false,depth:true,stencil:false,preserveDrawingBuffer:false,powerPreference:'high-performance'});
      if(!this.gl)throw new Error('WebGL is unavailable on this device.');
      canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();this.contextLost=true;if(hooks.lost)hooks.lost();});
      canvas.addEventListener('webglcontextrestored',()=>{try{this.contextLost=false;this.init();this.restorations++;if(hooks.restored)hooks.restored();}catch(e){this.errors.push(String(e));if(hooks.error)hooks.error(e);}});
      this.init();
    }
    program(vs,fs){
      const gl=this.gl;
      const compile=(type,src)=>{const s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS)){const msg=gl.getShaderInfoLog(s);gl.deleteShader(s);throw new Error(msg);}return s;};
      const v=compile(gl.VERTEX_SHADER,vs),f=compile(gl.FRAGMENT_SHADER,fs),p=gl.createProgram();gl.attachShader(p,v);gl.attachShader(p,f);gl.linkProgram(p);gl.deleteShader(v);gl.deleteShader(f);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(p));
      const o={p};for(const n of ['aPosition','aColor','aNormal','aGlow'])o[n]=gl.getAttribLocation(p,n);for(const n of ['uMatrix','uTarget','uTime','uResolution','uDimension','uPulse','uScene','uReduced'])o[n]=gl.getUniformLocation(p,n);return o;
    }
    init(){
      this.cacheDynamicMeshes();
      const gl=this.gl;this.scene=this.program(sceneVS,sceneFS);this.sky=this.program(screenVS,skyFS);this.post=this.program(screenVS,postFS);
      this.quad=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,this.quad);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
      this.staticBuffer=gl.createBuffer();this.dynamicBuffer=gl.createBuffer();
      const geometry=this.buildWorld().data();this.staticCount=geometry.length/10;gl.bindBuffer(gl.ARRAY_BUFFER,this.staticBuffer);gl.bufferData(gl.ARRAY_BUFFER,geometry,gl.STATIC_DRAW);
      this.texture=gl.createTexture();this.fbo=gl.createFramebuffer();this.depth=gl.createRenderbuffer();this.fboW=0;this.fboH=0;this.resize();
      gl.disable(gl.CULL_FACE);gl.disable(gl.BLEND);gl.clearColor(.06,.1,.18,1);
    }
    cacheDynamicMeshes(){
      if(this.heroMeshes)return;
      // Both facings retain the sprite builder's exact surface ordering. CPU
      // meshes survive a WebGL context restore and are reused by every frame.
      this.heroMeshes=this.art.sprites.hero.map(frame=>[-1,1].map(face=>{const m=new Mesh();m.sprite(frame,0,0,0,1,face);return m.data();}));
    }
    resize(){
      const gl=this.gl,cssW=Math.max(1,this.canvas.clientWidth||innerWidth),cssH=Math.max(1,this.canvas.clientHeight||innerHeight);
      const ratio=Math.min(devicePixelRatio||1,1.5);this.canvas.width=Math.round(cssW*ratio);this.canvas.height=Math.round(cssH*ratio);
      this.aspect=cssW/cssH;const h=280,w=Math.min(1400,Math.round(h*this.aspect));
      if(w===this.fboW&&h===this.fboH)return;this.fboW=w;this.fboH=h;
      gl.bindTexture(gl.TEXTURE_2D,this.texture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,w,h,0,gl.RGBA,gl.UNSIGNED_BYTE,null);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      gl.bindRenderbuffer(gl.RENDERBUFFER,this.depth);gl.renderbufferStorage(gl.RENDERBUFFER,gl.DEPTH_COMPONENT16,w,h);gl.bindFramebuffer(gl.FRAMEBUFFER,this.fbo);gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,this.texture,0);gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_ATTACHMENT,gl.RENDERBUFFER,this.depth);if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw new Error('The game framebuffer is incomplete.');gl.bindFramebuffer(gl.FRAMEBUFFER,null);
    }
    paper(m,o,lift=0){
      const x=o.x,y=o.y+lift,z=o.z,c=o.kind==='gate'?'#84989c':'#798991';
      m.box(x,y,z,o.w,o.h,o.d,c);m.box(x-2,y,z-.2,3,o.h,2.4,'#c8d0b0');m.box(x+o.w-1,y,z-.2,3,o.h,2.4,'#c8d0b0');
      m.box(x-5,y+o.h-7,z-.2,o.w+10,7,2.4,'#dbcda9');m.box(x-3,y,z-.2,o.w+6,5,2.4,'#a9bbaa');
      for(let i=0;i<6;i++){const yy=y+14+i*16;m.box(x+5+(i%2)*4,yy,z+o.d+.12,7,3,.18,'#596f83');m.box(x+o.w-9,yy+6,z+o.d+.12,3,6,.18,'#a6b8b3');}
      m.box(x+o.w/2-2,y+o.h*.5-11,z+o.d+.3,4,22,.3,'#ffe0a0',.6);m.box(x+o.w/2-7,y+o.h*.5-2,z+o.d+.4,14,4,.3,'#ffe0a0',.6);
    }
    tree(m,x,y,z,size,seed){
      const s=size;const trunk='#243644';m.box(x-4*s,y,z-4*s,8*s,83*s,8*s,trunk);
      m.box(x-13*s,y+45*s,z-2*s,13*s,6*s,4*s,trunk);m.box(x+1*s,y+59*s,z-2*s,15*s,6*s,4*s,trunk);
      for(let k=0;k<5;k++){const w=(67-k*8+hash(seed+k)*16)*s,h=(14+hash(seed+k+3)*14)*s,yy=y+(63+k*12)*s;const xx=x-w/2+(hash(seed+k+7)-.5)*18*s;const colors=['#234958','#2c555d','#315e64','#386569','#386a68'];m.box(xx,yy,z-20*s,w,h,38*s,colors[k]);m.box(xx+5*s,yy+h-2*s,z-20*s,w*.6,2*s,38*s,tint(colors[k],1.14));}
      if(seed%3===0)m.box(x+3*s,y+30*s,z+5*s,2*s,21*s,1,'#77b09c');
    }
    lantern(m,x,y,z,lit=false){
      m.box(x-3,y,z-3,6,32,6,'#465b60');m.box(x-7,y+31,z-7,14,3,14,'#9b9a88');m.box(x-5,y+34,z-5,10,16,10,lit?'#ffe0a1':'#52737a',lit?.9:0);m.box(x-7,y+49,z-7,14,4,14,'#657e7b');m.box(x-4,y+53,z-4,8,3,8,'#adb7a0');
    }
    buildWorld(){
      const m=new Mesh(),world=this.world;
      // Distant islands and stepped silhouettes hold their real positions during the turn.
      for(let i=-4;i<30;i++){
        const x=i*126,z=-530-hash(i+64)*130,w=95+hash(i+7)*90,h=45+hash(i+18)*150;
        m.box(x,-65,z,w,h,45,'#263951');m.box(x+13,h-69,z+8,w-25,12,35,'#2c435a');
      }
      for(let i=-3;i<23;i++){const x=i*117+hash(i)*20,z=-195-hash(i+5)*150;this.tree(m,x,-10,z,.8+hash(i+5)*.62,i+50);}
      for(const p of world.platforms){
        if(p.kind==='bridge'){
          // This off-plane path unfolds with the perspective, so its projected
          // edge cannot be mistaken for a walkable bridge in the flat world.
          continue;
        }
        const top=p.y+p.h;
        m.box(p.x,p.y,p.z,p.w,p.h,p.d,p.kind==='stone'?'#667b84':'#2c3e55');
        m.box(p.x,top-5,p.z,p.w,5,p.d,p.kind==='stone'?'#91a49d':'#4c8c83');
        m.box(p.x,top-1.5,p.z,p.w,1.5,p.d,p.kind==='stone'?'#a8b8a7':'#8dbba0');
        if(p.kind==='earth'){
          m.box(p.x,top-10,p.z+p.d-.6,p.w,4,1,'#375f6d');
          for(let i=0;i<p.w/18;i++){const x=p.x+i*18;let yy=p.y+hash(i+p.x)*Math.max(1,p.h-20);m.box(x,yy,p.z+p.d+.05,7+hash(i+8)*9,3+hash(i+42)*8,.4,i%3===0?'#3f5667':'#25374f');if(i%4===0)m.box(x,top-19,p.z+p.d+.5,3,12,.4,'#437577');}
          for(let i=0;i<p.w/13;i++){const x=p.x+i*13,z=p.z+8+hash(i+p.x)*Math.max(1,p.d-16);const color=i%9===0?'#edc5a0':'#74a793';m.box(x,top,z,3,2+hash(i+2)*4,2,color);if(i%9===0)m.box(x-1,top+4,z,5,2,2,'#f3d5aa',.25);}
          for(let i=0;i<p.w/47;i++){const x=p.x+i*47;m.box(x,top-.25,23+hash(i)*42,20+hash(i+4)*16,.5,7,'#91aaa0');}
        }else{
          for(let i=0;i<p.w/16;i++)m.box(p.x+i*16,top-10,p.z+p.d+.1,11,2,.2,'#829598');
        }
      }
      for(const o of world.obstacles)if(o.kind!=='gate')this.paper(m,o);
      for(const n of world.npcs)m.sprite(this.art.sprites[n.sprite][0],n.x,n.y,n.z,n.depth,1,n.id==='keeper'?.92:1);
      if(this.art.sprites.fox)m.sprite(this.art.sprites.fox[0],550,0,42,.6,1,.7);
      // Small paper houses, off the walking plane.
      for(const x of [35,520,1080,1755,1950]){
        const z=-70;m.box(x-24,0,z,48,43,3,'#547075');m.box(x-30,39,z-.2,60,7,3.4,'#bb9790');m.box(x-23,46,z-.2,46,7,3.4,'#cbaba0');m.box(x-16,53,z-.2,32,7,3.4,'#bd9c97');m.box(x-9,60,z-.2,18,6,3.4,'#d3bca4');m.box(x-15,18,z+3.1,9,12,.3,'#e5c88a',.4);m.box(x+5,18,z+3.1,9,12,.3,'#e5c88a',.4);m.box(x-3,0,z+3.1,11,21,.3,'#324651');
      }
      for(let i=0;i<16;i++){const x=22+i*125;if(x>702&&x<985)continue;const z=-105-hash(i)*24;this.tree(m,x,0,z,.28+hash(i+5)*.2,i+90);}
      // A broken arch frames the destination, with deliberately flat ornament.
      m.box(1805,0,-42,12,74,12,'#708e91');m.box(1865,0,-42,12,74,12,'#708e91');m.box(1805,73,-42,72,9,12,'#a6bba9');m.box(1816,82,-40,50,6,8,'#8fa69e');m.box(1836,88,-38,10,7,4,'#b6ddbd',.3);
      for(const cp of world.checkpoints)this.lantern(m,cp.x+20,0,-26,false);
      return m;
    }
    dynamic(state){
      const m=new Mesh(),p=state.player,t=state.time,d=state.dimensionBlend;
      if(d>.03){
        const b=this.world.platforms.find(b=>b.kind==='bridge');
        m.box(b.x,-8*d,b.z,b.w,8*d,b.d,tint('#647379',.5+.5*d));
        for(let x=b.x;x<b.x+b.w;x+=12){m.box(x,-2*d,b.z,10,3*d,b.d,tint('#b09f9b',.45+.55*d));m.box(x,d,b.z+2,10,.4,2,'#a5d8c7',.15);}
        for(const x of [b.x+10,b.x+b.w-14]){m.box(x,-32,b.z+3,7,36*d,6,'#516e71');m.box(x,-32,b.z+b.d-9,7,36*d,6,'#516e71');}
      }
      // A physical ground-plane shadow and a dashed seam make depth readable.
      if(p.grounded){m.box(p.x-9,p.y+.18,p.z-5,18,.25,10,'#344e5a');}
      if(d>.02){for(let i=-9;i<22;i++){const x=Math.floor(state.cameraX/22)*22+i*22;const supported=this.world.platforms.some(b=>x>=b.x&&x<=b.x+b.w&&0>=b.z&&0<=b.z+b.d&&b.kind==='earth');if(supported)m.box(x,.27,-.65,9,.3,1.3,tint('#9bcfc2',.55+d*.27),.25);}}
      const frame=!p.grounded?4:(Math.abs(p.vx)+Math.abs(p.vz)>10?Math.floor(p.walk*9)%4:0);
      const stretch=1+Math.sin(state.transitionProgress*Math.PI)*.13*(state.transitioning?1:0);
      const thickness=lerp(.6,9,d);
      m.append(this.heroMeshes[frame][p.facing>0?1:0],p.x,p.y,p.z,stretch,thickness);
      if(d>.01){m.box(p.x-7,p.y+27*stretch,p.z-thickness/2-.6,14,1,1,'#b4ffe0',.6);}
      for(let i=0;i<this.world.shards.length;i++){
        if(state.collected.includes(i))continue;const c=this.world.shards[i];if(Math.abs(c.x-state.cameraX)>600)continue;
        const visible=Math.abs(c.z)<8?1:(.28+.72*d);m.diamond(c.x,c.y+Math.sin(t*2.4+i)*2,c.z,4.2,tint('#ffe0a2',visible),t*.8+i);
      }
      if(!state.hasPrism){const c=this.world.prism;m.diamond(c.x,c.y+Math.sin(t*1.8)*3,c.z,9,'#b3a0ff',t*.75);m.box(c.x-9,0,-9,18,5,18,'#718d94');m.box(c.x-13,0,-13,26,2,26,'#536e7c');}
      if(!state.hasSpark&&!state.beaconLit){const c=this.world.spark;m.diamond(c.x,c.y+Math.sin(t*2.2)*2,c.z,7,'#ffc77e',-t);}
      if(state.hasSpark&&!state.beaconLit){m.diamond(p.x-p.facing*15,p.y+34+Math.sin(t*3)*3,p.z-3,4,'#ffcf86',t);}
      this.lantern(m,this.world.beacon.x,0,0,state.beaconLit);
      for(let i=0;i<this.world.checkpoints.length;i++)if(state.checkpointIndex>=i)this.lantern(m,this.world.checkpoints[i].x+20,0,-26,true);
      for(const o of this.world.obstacles)if(o.kind==='gate')this.paper(m,o,state.gateOpen*145);
      if(state.beaconLit){
        for(let i=0;i<8;i++){const a=i*Math.PI/4+t*.12;m.box(1840+Math.cos(a)*19,35+Math.sin(a)*25,-33,3,3,2,'#a6ffe1',.8);}
      }
      for(let i=0;i<36;i++){
        const x=state.cameraX-340+hash(i+3)*730+Math.sin(t*.12+i)*12,y=8+hash(i+80)*125+Math.sin(t*.7+i)*6,z=-120+hash(i+6)*240;
        const col=i%4===0?'#e0b2af':'#a6ceae';const s=(.6+hash(i)*1.2)*(state.reduced?.6:1);m.box(x,y,z,s,s,s,col,.5);
      }
      for(const part of state.particles){const alpha=clamp(part.life/part.max,0,1);m.box(part.x,part.y,part.z,part.size*alpha,part.size*alpha,part.size*alpha,part.color,.65);}
      return m.data();
    }
    screen(program){
      const gl=this.gl;gl.useProgram(program.p);gl.bindBuffer(gl.ARRAY_BUFFER,this.quad);for(let i=0;i<4;i++)gl.disableVertexAttribArray(i);gl.enableVertexAttribArray(program.aPosition);gl.vertexAttribPointer(program.aPosition,2,gl.FLOAT,false,8,0);
    }
    bindScene(buffer){
      const gl=this.gl,p=this.scene;gl.bindBuffer(gl.ARRAY_BUFFER,buffer);const attrs=[['aPosition',3,0],['aColor',3,12],['aNormal',3,24],['aGlow',1,36]];for(const [name,size,offset]of attrs){if(p[name]>=0){gl.enableVertexAttribArray(p[name]);gl.vertexAttribPointer(p[name],size,gl.FLOAT,false,40,offset);}}
    }
    draw(state){
      if(this.contextLost)return false;const gl=this.gl;
      if(this.canvas.width===0||this.canvas.height===0)this.resize();
      gl.bindFramebuffer(gl.FRAMEBUFFER,this.fbo);gl.viewport(0,0,this.fboW,this.fboH);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.disable(gl.DEPTH_TEST);
      this.screen(this.sky);gl.uniform1f(this.sky.uTime,state.time);gl.uniform1f(this.sky.uDimension,state.dimensionBlend);gl.uniform2f(this.sky.uResolution,this.fboW,this.fboH);gl.drawArrays(gl.TRIANGLES,0,6);
      gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.useProgram(this.scene.p);
      const target=[state.cameraX,45+state.dimensionBlend*4,state.cameraZ*.45];
      this.lastMatrix=matrix(target,this.aspect,state.dimensionBlend);
      gl.uniformMatrix4fv(this.scene.uMatrix,false,this.lastMatrix);gl.uniform3fv(this.scene.uTarget,target);gl.uniform1f(this.scene.uDimension,state.dimensionBlend);
      this.bindScene(this.staticBuffer);gl.drawArrays(gl.TRIANGLES,0,this.staticCount);
      const dyn=this.dynamic(state);gl.bindBuffer(gl.ARRAY_BUFFER,this.dynamicBuffer);gl.bufferData(gl.ARRAY_BUFFER,dyn,gl.DYNAMIC_DRAW);this.bindScene(this.dynamicBuffer);gl.drawArrays(gl.TRIANGLES,0,dyn.length/10);this.dynamicCount=dyn.length/10;
      gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.viewport(0,0,this.canvas.width,this.canvas.height);gl.disable(gl.DEPTH_TEST);this.screen(this.post);gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,this.texture);gl.uniform1i(this.post.uScene,0);gl.uniform2f(this.post.uResolution,this.fboW,this.fboH);gl.uniform1f(this.post.uTime,state.time);gl.uniform1f(this.post.uPulse,state.pulse);gl.uniform1f(this.post.uDimension,state.dimensionBlend);gl.uniform1f(this.post.uReduced,state.reduced?1:0);gl.drawArrays(gl.TRIANGLES,0,6);
      this.frames++;if(this.frames===1){const error=gl.getError();if(error!==gl.NO_ERROR)throw new Error('WebGL first-frame error '+error);}
      return true;
    }
    project(x,y,z){if(!this.lastMatrix)return null;const m=this.lastMatrix,v=[x,y,z,1],p=[];for(let r=0;r<4;r++)p[r]=m[r]*v[0]+m[4+r]*v[1]+m[8+r]*v[2]+m[12+r];return{x:(p[0]/p[3]*.5+.5)*this.canvas.clientWidth,y:(1-(p[1]/p[3]*.5+.5))*this.canvas.clientHeight};}
    getState(){return{api:'webgl1',contextLost:this.contextLost,frames:this.frames,restorations:this.restorations,errors:[...this.errors],pixelResolution:[this.fboW,this.fboH],canvasResolution:[this.canvas.width,this.canvas.height],staticTriangles:this.staticCount/3,dynamicTriangles:(this.dynamicCount||0)/3,postEffects:['original GLSL ripple','chromatic separation','pixel glow'],camera:'orthographic XYZ',heroDepth:[.6,9],npcDepth:.6};}
  }
  window.TD_Renderer=Renderer;
})();
