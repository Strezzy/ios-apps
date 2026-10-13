/* Original 2.2 lighting and finishing shaders. No external shader assets.
 * The shadow map stores packed depth in a normal RGBA8 texture, so the game
 * does not need optional depth-texture or floating-point framebuffer support.
 */
(() => {
  'use strict';
  const wind = `
    vec3 forestWind(vec3 p,float material,float time,float reduced){
      if(material>-.5||material< -1.5)return p;
      float height=smoothstep(0.,38.,max(p.y,0.));
      float breeze=sin(time*1.12+p.x*.037+p.z*.031)+.34*sin(time*2.04+p.x*.079-p.z*.041);
      p.x+=breeze*(.19+height*.46)*(1.-reduced*.65);
      p.z+=sin(time*.87+p.x*.043)*(.09+height*.24)*(1.-reduced*.65);
      return p;
    }`;
  const screenVS=`attribute vec2 aPosition;varying vec2 vUV;void main(){vUV=aPosition*.5+.5;gl_Position=vec4(aPosition,0.,1.);}`;
  const sceneVS=`
    attribute vec3 aPosition;attribute vec3 aColor;attribute vec3 aNormal;attribute float aGlow;
    uniform mat4 uMatrix;uniform mat4 uLightMatrix;uniform float uTime;uniform float uReduced;
    varying vec3 vColor;varying vec3 vWorld;varying vec3 vNormal;varying vec4 vShadow;varying float vMaterial;
    ${wind}
    void main(){
      vec3 p=forestWind(aPosition,aGlow,uTime,uReduced);
      vColor=aColor;vWorld=p;vNormal=aNormal;vMaterial=aGlow;vShadow=uLightMatrix*vec4(p,1.);
      gl_Position=uMatrix*vec4(p,1.);
    }`;
  const shadowVS=`
    attribute vec3 aPosition;attribute float aGlow;
    uniform mat4 uMatrix;uniform float uTime;uniform float uReduced;
    ${wind}
    void main(){gl_Position=uMatrix*vec4(forestWind(aPosition,aGlow,uTime,uReduced),1.);}`;
  const shadowFS=`precision highp float;
    void main(){
      // Promote the built-in before arithmetic: on some WebGL 1 drivers
      // gl_FragCoord's inherited precision otherwise discards lower bytes.
      highp float preciseDepth=gl_FragCoord.z;
      highp vec4 encodedDepth=fract(preciseDepth*vec4(1.,256.,65536.,16777216.));
      encodedDepth-=encodedDepth.yzww*vec4(1./256.,1./256.,1./256.,0.);
      // UNORM8 stores k/255. Convert the base-256 digits so round-to-byte
      // storage preserves them exactly instead of introducing depth bands.
      gl_FragColor=encodedDepth*(256./255.);
    }`;
  const sceneFS=`
    precision highp float;
    uniform highp sampler2D uShadowMap;uniform vec2 uShadowTexel;uniform vec3 uView;uniform vec3 uHero;
    uniform float uTime;uniform float uReduced;uniform float uDimension;uniform float uPulse;
    varying vec3 vColor;varying vec3 vWorld;varying vec3 vNormal;varying vec4 vShadow;varying float vMaterial;
    const vec3 LIGHT=vec3(-.480769,.78125,.400641);
    float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
    float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+1.),f.x),f.y);}
    float fbm(vec2 p){return noise(p)*.57+noise(p*2.07+17.)*.28+noise(p*4.13-31.)*.15;}
    float depthAt(vec2 uv){return dot(texture2D(uShadowMap,uv),vec4(1.,1./256.,1./65536.,1./16777216.))*(255./256.);}
    float sampleShadow(vec3 p,vec2 offset,float bias){return step(p.z-bias,depthAt(p.xy+offset*uShadowTexel));}
    float softShadow(vec3 N,float material){
      vec3 p=vShadow.xyz/vShadow.w*.5+.5;
      if(p.x<.003||p.x>.997||p.y<.003||p.y>.997||p.z<0.||p.z>1.)return 1.;
      float bias=.00034+.00072*(1.-max(dot(N,LIGHT),0.));
      if(material>1.5&&material<4.5)bias+=.00055;
      float shadow=sampleShadow(p,vec2(0.),bias)*2.;
      shadow+=sampleShadow(p,vec2(-1.7,-.8),bias)+sampleShadow(p,vec2(.4,-1.9),bias);
      shadow+=sampleShadow(p,vec2(1.7,-.3),bias)+sampleShadow(p,vec2(-1.3,1.4),bias);
      shadow+=sampleShadow(p,vec2(.8,1.5),bias)+sampleShadow(p,vec2(-.35,.72),bias);
      shadow+=sampleShadow(p,vec2(.74,-.58),bias)+sampleShadow(p,vec2(-.78,-.25),bias);
      return shadow*.1;
    }
    vec3 film(vec3 x){x=max(vec3(0.),x);return clamp((x*(2.51*x+.03))/(x*(2.43*x+.59)+.14),0.,1.);}
    void main(){
      float material=floor(max(0.,-vMaterial)+.5),emission=max(vMaterial,0.);
      vec3 N=normalize(vNormal),V=normalize(uView),base=vColor;
      float roughness=.76,sheen=.06,translucency=0.;
      if(material>.5&&material<1.5){roughness=.39;sheen=.16;translucency=.34;}
      if(material>1.5&&material<2.5){roughness=.48;sheen=.065;translucency=.10;}
      if(material>2.5&&material<3.5){roughness=.27;sheen=.22;}
      if(material>3.5&&material<4.5){roughness=.87;sheen=.035;}
      if(material>4.5&&material<5.5){roughness=.7;sheen=.08;}
      if(material>5.5&&material<6.5){roughness=.86;sheen=.035;}
      if(material>7.5&&material<8.5){roughness=.15;sheen=.8;}
      if(material>9.5&&material<10.5){roughness=.19;sheen=.46;translucency=.12;}
      bool ground=(material>6.5&&material<7.5)||(material>8.5&&material<9.5);
      if(ground){
        vec2 uv=vWorld.xz;
        float broad=fbm(uv*.045),grain=noise(uv*.95),fleck=noise(uv*2.85);
        bool path=material>8.5;
        base*=.96+broad*.065;
        if(path){
          float pebbles=smoothstep(.76,.9,noise(uv*.58));
          base=mix(base,base*1.22+vec3(.035,.022,.010),pebbles*.30);
          roughness=.74;
        }else{
          float moss=fbm(uv*.073+51.);
          base=mix(base,base*vec3(.9,1.11,.84),moss*.38);
          float dirt=smoothstep(.70,.89,fbm(uv*.039-7.));
          base=mix(base,vec3(.63,.65,.39),dirt*.035);roughness=.84;
          if(N.y<.55)base=mix(vec3(.49,.37,.24),vec3(.68,.53,.34),smoothstep(-85.,0.,vWorld.y))*(.98+.02*sin(vWorld.y*.28));
        }
        vec2 slope=vec2(noise(uv*.7+vec2(.7,0.))-noise(uv*.7-vec2(.7,0.)),noise(uv*.7+vec2(0.,.7))-noise(uv*.7-vec2(0.,.7)));
        N=normalize(N+vec3(slope.x*.015,0.,slope.y*.015));
      }
      if(material>5.5&&material<6.5){
        float bark=fbm(vec2(vWorld.x*.8+sin(vWorld.y*.06)*.4,vWorld.y*.055)+vWorld.z*.31);
        float grooves=smoothstep(.43,.58,bark);
        base*=.95+grooves*.055;
      }
      if(material>4.5&&material<5.5){
        float stone=fbm(vWorld.xz*.17+vWorld.y*.11);
        base*=.95+stone*.08;
        float moss=smoothstep(.38,.84,N.y)*smoothstep(.36,.75,fbm(vWorld.xz*.14+83.));
        base=mix(base,base*vec3(.81,1.04,.76),moss*.38);
      }
      if(material>3.5&&material<4.5){
        float weave=sin(vWorld.x*13.)*sin(vWorld.y*16.);
        base*=1.+weave*.002;
      }
      if(material>.5&&material<1.5){
        float vein=pow(.5+.5*sin(vWorld.x*1.8+vWorld.y*.45+vWorld.z*.9),14.);
        base*=.985+vein*.022;
      }
      float ndl=max(dot(N,LIGHT),0.),ndv=max(abs(dot(N,V)),.07);
      float shadow=softShadow(N,material);
      if((material>1.5&&material<4.5)||(material>7.5&&material<8.5))shadow=mix(.94,1.,shadow);
      if(material>10.5&&material<11.5){
        float rip=sin(vWorld.x*.24+uTime*.8+sin(vWorld.z*.22-uTime*.42));
        base=mix(vec3(.35,.66,.64),vec3(.69,.84,.74),.5+.5*rip);
        float glint=pow(max(0.,sin(vWorld.x*.47+uTime)*cos(vWorld.z*.5-uTime*.4)),28.);
        base+=vec3(.35,.36,.25)*glint;roughness=.28;sheen=.3;
      }
      float wrap=max((dot(N,LIGHT)+.22)/1.22,0.);
      if((material>.5&&material<1.5)||ground){
        float broadLuma=dot(base,vec3(.299,.587,.114));base=mix(vec3(broadLuma),base,.87);
      }
      vec3 albedo=pow(max(base,vec3(.001)),vec3(2.2));
      float upward=N.y*.5+.5;
      vec3 ambient=mix(vec3(.45,.44,.30),vec3(.65,.78,.80),upward)*.57;
      vec3 direct=vec3(1.0,.92,.76)*(wrap*.80)*mix(.62,1.,shadow);
      vec3 illumination=ambient+direct;
      float rim=pow(1.-ndv,2.8)*max(dot(N,normalize(vec3(.6,.4,-.72))),0.);
      vec3 color=albedo*illumination+vec3(.10,.21,.27)*rim*.38;
      if(translucency>0.){
        float through=pow(max(dot(-N,LIGHT),0.),1.7);
        color+=albedo*vec3(.87,1.,.66)*through*translucency*mix(.35,1.,shadow);
      }
      vec3 H=normalize(LIGHT+V);
      float power=mix(104.,12.,roughness),spec=pow(max(dot(N,H),0.),power);
      color+=vec3(1.,.94,.85)*spec*sheen*mix(.22,1.,shadow);
      if(material>2.5&&material<3.5){
        float strand=pow(max(0.,1.-abs(dot(N,normalize(vec3(.42,.88,.20))))),12.);
        color+=vec3(.12,.12,.16)*strand*pow(1.-roughness,2.)*.16;
      }
      if(material>1.5&&material<2.5){
        color+=albedo*vec3(.11,.035,.022)*pow(1.-ndv,2.)*.42;
      }
      float heroDistance=length((vWorld-uHero)*vec3(1.,.72,1.));
      float waterLight=exp(-heroDistance*.075)*(.028+uPulse*.10);
      color+=albedo*vec3(.23,.74,.80)*waterLight;
      if(ground){
        float caustic=pow(.5+.5*sin(vWorld.x*.71+sin(vWorld.z*.43+uTime*.8)+uTime*1.1),17.);
        color+=vec3(.10,.32,.30)*caustic*exp(-length(vWorld.xz-uHero.xz)*.15)*(.18+uPulse*.48);
      }
      color+=pow(base,vec3(1.7))*emission*.68;
      if(material>9.5&&material<10.5){color+=albedo*.32+vec3(.25,.30,.35)*pow(1.-ndv,3.)*.20;}
      color=pow(film(color*1.03),vec3(1./2.2));
      float fog=1.-exp(-max(0.,-vWorld.z-140.)*.00145);
      fog+=exp(-max(vWorld.y,0.)*.032)*smoothstep(120.,370.,-vWorld.z)*.09;
      vec3 mist=mix(vec3(.67,.79,.68),vec3(.67,.83,.82),clamp(vWorld.y/220.,0.,1.));
      color=mix(color,mist,clamp(fog,0.,.76));
      gl_FragColor=vec4(color,1.);
    }`;
  const skyFS=`
    precision highp float;varying vec2 vUV;uniform float uTime;uniform float uDimension;uniform vec2 uResolution;
    float cloud(vec2 p,vec2 c,vec2 s){return exp(-dot((p-c)/s,(p-c)/s)*2.);}
    void main(){
      vec2 uv=vUV;
      vec3 col=mix(vec3(.91,.94,.78),vec3(.49,.76,.80),smoothstep(0.,1.,uv.y));
      float drift=sin(uTime*.012)*.03;
      float clouds=cloud(uv,vec2(.21+drift,.77),vec2(.22,.085))+cloud(uv,vec2(.72+drift,.89),vec2(.27,.07));
      col=mix(col,vec3(.99,.98,.87),clamp(clouds*.58,0.,.70));
      vec2 sun=(uv-vec2(.23,.80))*vec2(uResolution.x/uResolution.y,1.);
      float r=length(sun);
      col+=vec3(.10,.067,.025)*exp(-r*12.);
      col=mix(col,vec3(1.,.96,.79),(1.-smoothstep(.029,.033,r))*.9);
      gl_FragColor=vec4(col,1.);
    }`;

  const brightFS=`precision mediump float;varying vec2 vUV;uniform sampler2D uScene;uniform vec2 uResolution;
    void main(){vec2 p=1./uResolution;vec3 c=(texture2D(uScene,vUV+p*vec2(-1.,-1.)).rgb+texture2D(uScene,vUV+p*vec2(1.,-1.)).rgb+texture2D(uScene,vUV+p*vec2(-1.,1.)).rgb+texture2D(uScene,vUV+p*vec2(1.,1.)).rgb)*.25;float brightness=max(max(c.r,c.g),c.b);float contribution=smoothstep(.64,.96,brightness);gl_FragColor=vec4(c*contribution,1.);}`;
  const blurFS=`precision mediump float;varying vec2 vUV;uniform sampler2D uScene;uniform vec2 uDirection;
    void main(){vec3 c=texture2D(uScene,vUV).rgb*.227027;c+=texture2D(uScene,vUV+uDirection*1.384615).rgb*.316216;c+=texture2D(uScene,vUV-uDirection*1.384615).rgb*.316216;c+=texture2D(uScene,vUV+uDirection*3.230769).rgb*.070270;c+=texture2D(uScene,vUV-uDirection*3.230769).rgb*.070270;gl_FragColor=vec4(c,1.);}`;
  const raysFS=`precision mediump float;varying vec2 vUV;uniform sampler2D uScene;uniform float uTime;uniform float uReduced;
    void main(){vec2 uv=vUV,sun=vec2(.23,.80),stepUV=(sun-uv)*.058;vec3 rays=vec3(0.);float attenuation=1.;for(int i=0;i<12;i++){uv+=stepUV;vec3 c=texture2D(uScene,clamp(uv,0.,1.)).rgb;rays+=c*attenuation;attenuation*=.88;}rays*=.015*(1.-uReduced);rays*=smoothstep(.08,.70,vUV.y);gl_FragColor=vec4(rays,1.);}`;
  const postFS=`
    precision highp float;varying vec2 vUV;
    uniform sampler2D uScene;uniform sampler2D uBloom;uniform sampler2D uRays;
    uniform vec2 uResolution;uniform vec2 uHeroUV;uniform float uTime;uniform float uPulse;uniform float uDimension;uniform float uReduced;
    float luma(vec3 c){return dot(c,vec3(.299,.587,.114));}
    vec3 antialias(vec2 uv){
      vec2 px=1./uResolution;
      vec3 rgbM=texture2D(uScene,uv).rgb;
      vec3 rgbNW=texture2D(uScene,uv+vec2(-1.,-1.)*px).rgb,rgbNE=texture2D(uScene,uv+vec2(1.,-1.)*px).rgb;
      vec3 rgbSW=texture2D(uScene,uv+vec2(-1.,1.)*px).rgb,rgbSE=texture2D(uScene,uv+vec2(1.,1.)*px).rgb;
      float lM=luma(rgbM),lNW=luma(rgbNW),lNE=luma(rgbNE),lSW=luma(rgbSW),lSE=luma(rgbSE);
      float lo=min(lM,min(min(lNW,lNE),min(lSW,lSE))),hi=max(lM,max(max(lNW,lNE),max(lSW,lSE)));
      if(hi-lo<max(.025,hi*.10))return rgbM;
      vec2 dir=vec2(-((lNW+lNE)-(lSW+lSE)),(lNW+lSW)-(lNE+lSE));
      float reduce=max((lNW+lNE+lSW+lSE)*.03125,.00625);
      float reciprocal=1./(min(abs(dir.x),abs(dir.y))+reduce);
      dir=clamp(dir*reciprocal,vec2(-5.),vec2(5.))*px;
      vec3 a=.5*(texture2D(uScene,uv+dir*(-1./6.)).rgb+texture2D(uScene,uv+dir*(1./6.)).rgb);
      vec3 b=a*.5+.25*(texture2D(uScene,uv+dir*(-.5)).rgb+texture2D(uScene,uv+dir*.5).rgb);
      float lb=luma(b);return lb<lo||lb>hi?a:b;
    }
    void main(){
      vec2 uv=vUV,ratio=vec2(uResolution.x/uResolution.y,1.);
      vec2 centered=(uv-uHeroUV)*ratio;float dist=length(centered);
      float wave=sin(dist*33.-uTime*8.)*exp(-dist*2.2);
      vec2 offset=normalize(centered+vec2(.0001))*wave*uPulse*.006*(1.-uReduced);
      offset.x/=ratio.x;uv=clamp(uv+offset,.001,.999);
      vec3 col=antialias(uv);
      float chroma=uPulse*.0012*(1.-uReduced);
      if(chroma>.00001){col.r=mix(col.r,texture2D(uScene,uv+vec2(chroma,0.)).r,.55);col.b=mix(col.b,texture2D(uScene,uv-vec2(chroma,0.)).b,.55);}
      vec3 glow=texture2D(uBloom,uv).rgb;
      col+=glow*(.08+uPulse*.22)*(1.-uReduced*.60);
      col+=texture2D(uRays,uv).rgb;
      float ring=exp(-abs(dist-(.035+uPulse*.48))*95.)*uPulse*(1.-uReduced);
      col+=vec3(.13,.39,.39)*ring*.11;
      float luminance=luma(col);
      col=mix(vec3(luminance),col,1.025);
      col=mix(col,col*col*(3.-2.*col),.12);
      vec2 edge=(vUV-.5)*vec2(1.13,1.);
      float vignette=1.-smoothstep(.34,.79,length(edge))*.055;
      col*=vignette;
      col+=vec3(.011,.025,.031)*uPulse;
      gl_FragColor=vec4(clamp(col,0.,1.),1.);
    }`;
  window.TD_VISUALS=Object.freeze({version:'2.3',screenVS,sceneVS,sceneFS,shadowVS,shadowFS,skyFS,brightFS,blurFS,raysFS,postFS});
})();
