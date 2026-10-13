/* Original, dependency-free WebGL renderer and GLSL effects.
 * A real XYZ world, an animated orthographic camera, and a smooth water heroine.
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
  function matrix(target,aspect,dim,height){
    const yaw=dim*.72,el=dim*.49,sy=Math.sin(yaw),cy=Math.cos(yaw),se=Math.sin(el),ce=Math.cos(el);
    const right=[cy,0,-sy],up=[-sy*se,ce,-cy*se],back=[sy*ce,se,cy*ce];
    const eye=target.map((v,i)=>v+back[i]*900),dot=(a,b)=>a[0]*b[0]+a[1]*b[1]+a[2]*b[2];
    const view=new Float32Array([right[0],up[0],back[0],0,right[1],up[1],back[1],0,right[2],up[2],back[2],0,-dot(right,eye),-dot(up,eye),-dot(back,eye),1]);
    const h=height||lerp(248,288,dim),w=h*aspect;
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
    crystal(x,y,z,size,color,angle=0){
      const c=rgb(color),sides=6,levels=[[-size,0],[-size*.24,size*.50],[size*.23,size*.56],[size,0]];
      const rings=levels.map(([yy,r])=>Array.from({length:sides},(_,j)=>{const a=j/sides*Math.PI*2+angle;return[x+Math.cos(a)*r,y+yy,z+Math.sin(a)*r];}));
      for(let k=0;k<3;k++)for(let j=0;j<sides;j++){
        const next=(j+1)%sides,A=rings[k][j],B=rings[k][next],C=rings[k+1][next],D=rings[k+1][j];
        const tris=k===0?[[A,C,D]]:k===2?[[A,B,C]]:[[A,B,C],[A,C,D]];
        for(const [a,b,d]of tris){const u=b.map((v,i)=>v-a[i]),v=d.map((q,i)=>q-a[i]);let n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];const len=Math.hypot(...n)||1;n=n.map(q=>-q/len);for(const pt of [a,b,d])this.vertex(pt,tint(c,.90+j*.024),n,-10);}
      }
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
  const copyFS=`precision mediump float;varying vec2 vUV;uniform sampler2D uScene;void main(){gl_FragColor=texture2D(uScene,vUV);}`;
  function shadowMatrix(target,width,height){
    const normalize=v=>{const n=Math.hypot(...v);return v.map(x=>x/n);};
    const back=normalize([-.48,.78,.40]),right=normalize([back[2],0,-back[0]]);
    const up=[back[1]*right[2],back[2]*right[0]-back[0]*right[2],-back[1]*right[0]];
    const dot=(a,b)=>a[0]*b[0]+a[1]*b[1]+a[2]*b[2],eye=target.map((v,i)=>v+back[i]*900);
    const view=new Float32Array([right[0],up[0],back[0],0,right[1],up[1],back[1],0,right[2],up[2],back[2],0,-dot(right,eye),-dot(up,eye),-dot(back,eye),1]);
    const projection=new Float32Array([2/width,0,0,0,0,2/height,0,0,0,0,-2/1800,0,0,0,-1802/1800,1]);
    return mul(projection,view);
  }
  function inFrustum(bounds,m){
    const points=[];
    for(let i=0;i<8;i++){
      const x=bounds[i&1?3:0],y=bounds[i&2?4:1],z=bounds[i&4?5:2];
      points.push([m[0]*x+m[4]*y+m[8]*z+m[12],m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]]);
    }
    for(let axis=0;axis<3;axis++)if(points.every(p=>p[axis]<-p[3])||points.every(p=>p[axis]>p[3]))return false;
    return true;
  }
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
      const o={p};for(const n of ['aPosition','aColor','aNormal','aGlow'])o[n]=gl.getAttribLocation(p,n);for(const n of ['uMatrix','uLightMatrix','uTime','uResolution','uDimension','uPulse','uScene','uReduced','uShadowMap','uShadowTexel','uView','uHero','uDirection','uBloom','uRays','uHeroUV'])o[n]=gl.getUniformLocation(p,n);return o;
    }
    init(){
      const gl=this.gl,v=window.TD_VISUALS;
      if(!v)throw new Error('The rainforest lighting shaders are missing.');
      if(!window.TD_WaterRenderer)throw new Error('The water character renderer is missing.');
      if(!window.TD_RAINFOREST)throw new Error('The rainforest scenery renderer is missing.');
      this.scene=this.program(v.sceneVS,v.sceneFS);this.shadow=this.program(v.shadowVS,v.shadowFS);
      this.sky=this.program(v.screenVS,v.skyFS);this.post=this.program(v.screenVS,v.postFS);this.copy=this.program(v.screenVS,copyFS);
      this.bright=this.program(v.screenVS,v.brightFS);this.blur=this.program(v.screenVS,v.blurFS);this.rays=this.program(v.screenVS,v.raysFS);
      this.maxAttributes=gl.getParameter(gl.MAX_VERTEX_ATTRIBS);
      this.water=new window.TD_WaterRenderer(gl);
      this.quad=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,this.quad);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
      this.dynamicBuffer=gl.createBuffer();
      this.buildBatches(this.buildWorld().data());
      this.texture=gl.createTexture();this.fbo=gl.createFramebuffer();this.depth=gl.createRenderbuffer();
      this.compositeTexture=gl.createTexture();this.compositeFbo=gl.createFramebuffer();
      this.shadowTarget={texture:gl.createTexture(),fbo:gl.createFramebuffer(),depth:gl.createRenderbuffer()};
      this.effects=Array.from({length:4},()=>({texture:gl.createTexture(),fbo:gl.createFramebuffer()}));
      this.fboW=0;this.fboH=0;this.compositeW=0;this.compositeH=0;this.shadowSize=0;this.effectW=0;this.effectH=0;
      this.shadowReady=false;this.effectsReady=false;this.initFrames=0;this.resize();
      gl.disable(gl.CULL_FACE);gl.disable(gl.BLEND);gl.clearColor(.06,.1,.18,1);
    }
    buildBatches(geometry){
      // Spatial batches retain every original triangle and its full bounds.
      // Both cameras cull whole batches; no platform or collision is altered.
      const gl=this.gl,bins=new Map(),keyAt=i=>Math.floor((geometry[i]+geometry[i+10]+geometry[i+20])/768)+':'+Math.floor((geometry[i+2]+geometry[i+12]+geometry[i+22])/768);
      for(let i=0;i<geometry.length;i+=30){
        const key=keyAt(i);let bin=bins.get(key);
        if(!bin){bin={count:0,bounds:[Infinity,Infinity,Infinity,-Infinity,-Infinity,-Infinity]};bins.set(key,bin);}
        bin.count+=30;
        for(let j=0;j<30;j+=10)for(let axis=0;axis<3;axis++){const v=geometry[i+j+axis];bin.bounds[axis]=Math.min(bin.bounds[axis],v-1);bin.bounds[axis+3]=Math.max(bin.bounds[axis+3],v+1);}
      }
      for(const bin of bins.values()){bin.data=new Float32Array(bin.count);bin.cursor=0;}
      for(let i=0;i<geometry.length;i+=30){const bin=bins.get(keyAt(i));bin.data.set(geometry.subarray(i,i+30),bin.cursor);bin.cursor+=30;}
      this.batches=[];this.staticCount=geometry.length/10;
      for(const bin of bins.values()){
        const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,bin.data,gl.STATIC_DRAW);
        this.batches.push({buffer,count:bin.count/10,bounds:bin.bounds});
      }
    }
    allocate(target,width,height,depth,filter){
      const gl=this.gl;gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,target.texture);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,width,height,0,gl.RGBA,gl.UNSIGNED_BYTE,null);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,filter);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,filter);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      gl.bindFramebuffer(gl.FRAMEBUFFER,target.fbo);gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,target.texture,0);
      if(depth){
        // Standard WebGL 1 packed depth/stencil gives the thin inhabitants'
        // closely layered eyes, hair and clothing enough depth precision.
        gl.bindRenderbuffer(gl.RENDERBUFFER,depth);gl.renderbufferStorage(gl.RENDERBUFFER,gl.DEPTH_STENCIL,width,height);
        if(depth===this.depth)this.sceneDepthBits=gl.getRenderbufferParameter(gl.RENDERBUFFER,gl.RENDERBUFFER_DEPTH_SIZE);
        if(depth===this.shadowTarget.depth)this.shadowDepthBits=gl.getRenderbufferParameter(gl.RENDERBUFFER,gl.RENDERBUFFER_DEPTH_SIZE);
        gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_STENCIL_ATTACHMENT,gl.RENDERBUFFER,depth);
      }
      if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw new Error('A rainforest lighting framebuffer is incomplete.');
    }
    resize(){
      const gl=this.gl,cssW=Math.max(1,this.canvas.clientWidth||innerWidth),cssH=Math.max(1,this.canvas.clientHeight||innerHeight);
      const ratio=Math.min(devicePixelRatio||1,this.reducedQuality?1.25:2);
      const w=Math.round(cssW*ratio),h=Math.round(cssH*ratio);this.renderRatio=ratio;this.aspect=cssW/cssH;
      if(this.canvas.width!==w)this.canvas.width=w;if(this.canvas.height!==h)this.canvas.height=h;
      if(w!==this.fboW||h!==this.fboH){
        this.fboW=w;this.fboH=h;this.compositeW=w;this.compositeH=h;
        this.allocate({texture:this.texture,fbo:this.fbo},w,h,this.depth,gl.LINEAR);
        // Independent color targets share the world depth, preserving correct
        // refraction and occlusion without optional depth-copy extensions.
        this.allocate({texture:this.compositeTexture,fbo:this.compositeFbo},w,h,this.depth,gl.LINEAR);
      }
      const shadowSize=Math.min(gl.getParameter(gl.MAX_TEXTURE_SIZE),this.reducedQuality?768:1536);
      if(shadowSize!==this.shadowSize){this.shadowSize=shadowSize;this.shadowReady=false;this.allocate(this.shadowTarget,shadowSize,shadowSize,this.shadowTarget.depth,gl.NEAREST);}
      const ew=Math.max(1,Math.ceil(w/4)),eh=Math.max(1,Math.ceil(h/4));
      if(ew!==this.effectW||eh!==this.effectH){this.effectW=ew;this.effectH=eh;this.effectsReady=false;for(const target of this.effects)this.allocate(target,ew,eh,null,gl.LINEAR);}
      gl.bindFramebuffer(gl.FRAMEBUFFER,null);
    }
    buildWorld(){const m=new Mesh();window.TD_RAINFOREST.buildWorld(m,this.world);return m;}
    dynamic(state){return this.rainforestDynamic(state);}
    rainforestDynamic(state){
      const m=new Mesh(),r=window.TD_RAINFOREST,p=state.player,t=state.time,d=state.dimensionBlend;
      r.dynamic(m,this.world,state);
      for(let i=0;i<this.world.shards.length;i++){
        if(state.collected.includes(i))continue;const c=this.world.shards[i];if(Math.abs(c.x-state.cameraX)>600)continue;
        m.crystal(c.x,c.y+Math.sin(t*2.4+i)*2,c.z,4.7,tint('#e8c476',Math.abs(c.z)<8?1:.28+.72*d),t*.6+i);
      }
      if(!state.hasPrism){const c=this.world.prism;m.crystal(c.x,c.y+Math.sin(t*1.8)*3,c.z,10.5,'#bba0e8',t*.55);}
      if(!state.hasSpark&&!state.beaconLit){const c=this.world.spark;m.crystal(c.x,c.y+Math.sin(t*2.2)*2,c.z,7.1,'#f4bd6c',-t*.7);}
      if(state.hasSpark&&!state.beaconLit)r.orb(m,p.x-p.facing*15,p.y+34+(state.water?.lift||0)+Math.sin(t*3)*3,p.z-3,3.5,'#ffcf86',.9);
      // Short luminous ribbons orbit the gathering drop in real world space.
      // Their tapered ends and depth occlusion leave the face and silhouette clear.
      if(state.transitioning&&!state.reduced){
        const phase=clamp(state.transitionProgress,0,1),strength=Math.sin(phase*Math.PI),lift=state.water?.lift||0;
        const centerY=p.y+lift+8+10*(state.water?.form??1);
        if(strength>.02)for(let trail=0;trail<2;trail++){
          const point=u=>{
            const angle=t*3.2+trail*Math.PI-u*3.7,radius=(11+strength*7)*(1-u*.24);
            return[p.x+Math.cos(angle)*radius,centerY+(u-.5)*22*strength+Math.sin(angle*.5)*3,p.z+Math.sin(angle)*radius*.72];
          };
          for(let i=0;i<28;i++){
            const u=i/28,v=(i+1)/28,a=point(u),b=point(v),wa=.25*strength*Math.sin(Math.PI*u),wb=.25*strength*Math.sin(Math.PI*v);
            m.quad([a[0],a[1]-wa,a[2]],[b[0],b[1]-wb,b[2]],[b[0],b[1]+wb,b[2]],[a[0],a[1]+wa,a[2]],trail?'#d8c8eb':'#b6f3e5',[0,0,1],.65);
          }
        }
      }
      for(const part of state.particles){const alpha=clamp(part.life/part.max,0,1);if(alpha>.03)r.orb(m,part.x,part.y,part.z,Math.max(.12,part.size*alpha*.55),part.color,.7);}
      return m.data();
    }
    resetAttributes(){const gl=this.gl;for(let i=0;i<this.maxAttributes;i++)gl.disableVertexAttribArray(i);}
    screen(program){
      const gl=this.gl;gl.useProgram(program.p);gl.bindBuffer(gl.ARRAY_BUFFER,this.quad);this.resetAttributes();gl.enableVertexAttribArray(program.aPosition);gl.vertexAttribPointer(program.aPosition,2,gl.FLOAT,false,8,0);
    }
    bindMesh(buffer,program){
      const gl=this.gl;gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
      const attrs=[['aPosition',3,0],['aColor',3,12],['aNormal',3,24],['aGlow',1,36]];
      for(const [name,size,offset]of attrs)if(program[name]>=0){gl.enableVertexAttribArray(program[name]);gl.vertexAttribPointer(program[name],size,gl.FLOAT,false,40,offset);}
    }
    drawBatches(program,view){
      const gl=this.gl;let count=0,draws=0;
      for(const batch of this.batches)if(inFrustum(batch.bounds,view)){this.bindMesh(batch.buffer,program);gl.drawArrays(gl.TRIANGLES,0,batch.count);count+=batch.count;draws++;}
      return{triangles:count/3,draws};
    }
    bindTexture(program,name,texture,unit){const gl=this.gl;gl.activeTexture(gl.TEXTURE0+unit);gl.bindTexture(gl.TEXTURE_2D,texture);gl.uniform1i(program[name],unit);}
    effectPass(program,source,target){
      const gl=this.gl;gl.bindFramebuffer(gl.FRAMEBUFFER,target.fbo);gl.viewport(0,0,this.effectW,this.effectH);this.screen(program);this.bindTexture(program,'uScene',source,0);
    }
    draw(state){
      if(this.contextLost)return false;const gl=this.gl;
      if(this.reducedQuality!==!!state.reduced){this.reducedQuality=!!state.reduced;this.resize();}
      if(this.canvas.width===0||this.canvas.height===0)this.resize();
      const p=state.player,target=[state.cameraX,state.cameraY===undefined?45+state.dimensionBlend*4:state.cameraY,state.cameraZ*.45];
      this.lastMatrix=matrix(target,this.aspect,state.dimensionBlend,state.cameraHeight);
      this.lightMatrix=shadowMatrix([state.cameraX,40,-80],Math.max(800,(state.cameraHeight||232)*this.aspect*1.3),660);
      const dyn=this.dynamic(state);this.dynamicCount=dyn.length/10;
      gl.bindBuffer(gl.ARRAY_BUFFER,this.dynamicBuffer);gl.bufferData(gl.ARRAY_BUFFER,dyn,gl.DYNAMIC_DRAW);
      this.water.prepare(state);
      // The same current deformed water mesh casts and receives world depth.
      gl.disable(gl.BLEND);gl.disable(gl.CULL_FACE);gl.enable(gl.DEPTH_TEST);gl.depthMask(true);gl.depthFunc(gl.LEQUAL);
      gl.bindFramebuffer(gl.FRAMEBUFFER,this.shadowTarget.fbo);gl.viewport(0,0,this.shadowSize,this.shadowSize);gl.clearColor(1,1,1,1);gl.clearDepth(1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
      gl.disable(gl.DITHER);this.resetAttributes();gl.useProgram(this.shadow.p);gl.uniformMatrix4fv(this.shadow.uMatrix,false,this.lightMatrix);gl.uniform1f(this.shadow.uTime,state.time);gl.uniform1f(this.shadow.uReduced,state.reduced?1:0);
      this.shadowDraws=this.drawBatches(this.shadow,this.lightMatrix);
      this.bindMesh(this.dynamicBuffer,this.shadow);gl.drawArrays(gl.TRIANGLES,0,this.dynamicCount);
      if(this.shadow.aGlow>=0){gl.disableVertexAttribArray(this.shadow.aGlow);gl.vertexAttrib1f(this.shadow.aGlow,0);}
      this.water.drawShadow(this.lightMatrix,{positionLocation:this.shadow.aPosition,matrixLocation:this.shadow.uMatrix});this.shadowReady=true;
      // World color is captured before liquid refraction samples it.
      gl.enable(gl.DITHER);gl.bindFramebuffer(gl.FRAMEBUFFER,this.fbo);gl.viewport(0,0,this.fboW,this.fboH);gl.clearColor(.06,.1,.18,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.disable(gl.DEPTH_TEST);
      this.screen(this.sky);gl.uniform1f(this.sky.uTime,state.time);gl.uniform1f(this.sky.uDimension,state.dimensionBlend);gl.uniform2f(this.sky.uResolution,this.fboW,this.fboH);gl.drawArrays(gl.TRIANGLES,0,6);
      gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);this.resetAttributes();gl.useProgram(this.scene.p);
      gl.uniformMatrix4fv(this.scene.uMatrix,false,this.lastMatrix);gl.uniformMatrix4fv(this.scene.uLightMatrix,false,this.lightMatrix);
      gl.uniform1f(this.scene.uDimension,state.dimensionBlend);gl.uniform1f(this.scene.uTime,state.time);gl.uniform1f(this.scene.uPulse,state.pulse);gl.uniform1f(this.scene.uReduced,state.reduced?1:0);
      const yaw=state.dimensionBlend*.72,el=state.dimensionBlend*.49;
      gl.uniform3f(this.scene.uView,Math.sin(yaw)*Math.cos(el),Math.sin(el),Math.cos(yaw)*Math.cos(el));
      gl.uniform3f(this.scene.uHero,p.x,p.y+(state.water?.lift||0)+14,p.z);
      this.bindTexture(this.scene,'uShadowMap',this.shadowTarget.texture,1);gl.uniform2f(this.scene.uShadowTexel,1/this.shadowSize,1/this.shadowSize);
      this.visibleDraws=this.drawBatches(this.scene,this.lastMatrix);this.bindMesh(this.dynamicBuffer,this.scene);gl.drawArrays(gl.TRIANGLES,0,this.dynamicCount);
      gl.bindFramebuffer(gl.FRAMEBUFFER,this.compositeFbo);gl.viewport(0,0,this.compositeW,this.compositeH);gl.clear(gl.COLOR_BUFFER_BIT);gl.disable(gl.DEPTH_TEST);
      this.screen(this.copy);this.bindTexture(this.copy,'uScene',this.texture,0);gl.drawArrays(gl.TRIANGLES,0,6);
      this.water.draw(state,this.lastMatrix,this.texture,this.compositeW,this.compositeH,this.fboW,this.fboH);
      gl.disable(gl.DEPTH_TEST);gl.disable(gl.BLEND);gl.depthMask(false);
      this.effectPass(this.bright,this.compositeTexture,this.effects[0]);gl.uniform2f(this.bright.uResolution,this.compositeW,this.compositeH);gl.drawArrays(gl.TRIANGLES,0,6);
      this.effectPass(this.blur,this.effects[0].texture,this.effects[1]);gl.uniform2f(this.blur.uDirection,1/this.effectW,0);gl.drawArrays(gl.TRIANGLES,0,6);
      this.effectPass(this.blur,this.effects[1].texture,this.effects[2]);gl.uniform2f(this.blur.uDirection,0,1/this.effectH);gl.drawArrays(gl.TRIANGLES,0,6);
      this.effectPass(this.rays,this.effects[0].texture,this.effects[3]);gl.uniform1f(this.rays.uTime,state.time);gl.uniform1f(this.rays.uReduced,state.reduced?1:0);gl.drawArrays(gl.TRIANGLES,0,6);this.effectsReady=true;
      gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.viewport(0,0,this.canvas.width,this.canvas.height);this.screen(this.post);
      this.bindTexture(this.post,'uScene',this.compositeTexture,0);this.bindTexture(this.post,'uBloom',this.effects[2].texture,1);this.bindTexture(this.post,'uRays',this.effects[3].texture,2);
      gl.uniform2f(this.post.uResolution,this.compositeW,this.compositeH);gl.uniform1f(this.post.uTime,state.time);gl.uniform1f(this.post.uPulse,state.pulse);gl.uniform1f(this.post.uDimension,state.dimensionBlend);gl.uniform1f(this.post.uReduced,state.reduced?1:0);
      const hero=this.project(p.x,p.y+(state.water?.lift||0)+14,p.z);
      gl.uniform2f(this.post.uHeroUV,hero?hero.x/(this.canvas.clientWidth||1):.43,hero?1-hero.y/(this.canvas.clientHeight||1):.49);
      gl.drawArrays(gl.TRIANGLES,0,6);gl.depthMask(true);
      this.frames++;this.initFrames++;if(this.initFrames===1){const error=gl.getError();if(error!==gl.NO_ERROR)throw new Error('WebGL first-frame error '+error);}
      return true;
    }
    project(x,y,z){if(!this.lastMatrix)return null;const m=this.lastMatrix,v=[x,y,z,1],p=[];for(let r=0;r<4;r++)p[r]=m[r]*v[0]+m[4+r]*v[1]+m[8+r]*v[2]+m[12+r];return{x:(p[0]/p[3]*.5+.5)*this.canvas.clientWidth,y:(1-(p[1]/p[3]*.5+.5))*this.canvas.clientHeight};}
    getState(){return{
      api:'webgl1',contextLost:this.contextLost,frames:this.frames,restorations:this.restorations,errors:[...this.errors],artStyle:'smooth mystical rainforest',visualVersion:'2.3',
      sceneResolution:[this.fboW,this.fboH],pixelResolution:[this.fboW,this.fboH],canvasResolution:[this.canvas.width,this.canvas.height],renderRatio:this.renderRatio,quality:this.reducedQuality?'reduced':'full',sceneDepthBits:this.sceneDepthBits,depthFormat:'DEPTH_STENCIL',
      staticTriangles:this.staticCount/3,dynamicTriangles:(this.dynamicCount||0)/3,visibleWorldTriangles:this.visibleDraws?.triangles||0,staticBatches:this.batches.length,visibleBatches:this.visibleDraws?.draws||0,
      shadows:{enabled:true,ready:this.shadowReady,resolution:[this.shadowSize,this.shadowSize],packedDepth:true,depthBits:this.shadowDepthBits,waterCaster:true,filter:'nine-tap PCF',worldTriangles:this.shadowDraws?.triangles||0},
      bloom:{enabled:true,ready:this.effectsReady,passes:3,resolution:[this.effectW,this.effectH]},fxaa:{enabled:true,ready:this.effectsReady},shafts:{enabled:!this.reducedQuality,ready:this.effectsReady},
      postEffects:['soft dynamic cast shadows','per-fragment material lighting','quarter-resolution Gaussian bloom','FXAA edge smoothing','restrained light shafts','hero-centered liquid ripple','smooth refractive water pass','procedural rainforest surfaces'],
      camera:'orthographic XYZ',heroDepth:[.77,11.0],npcDepth:.6,water:this.water?this.water.getState():null
    };}

  }
  window.TD_Renderer=Renderer;
})();
