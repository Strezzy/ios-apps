#!/usr/bin/env python3
"""Apply the original Cozy Canopy art revision to the released 2.2 sources.

Deterministic, idempotent source migration. No dependencies or downloaded art.
The publishing workflow commits the generated sources before testing/building.
"""
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1] / 'EnterTheThirdDimension'
GAME = ROOT / 'Resources/Game'
MARKER = ROOT / 'docs/COZY-REVISION.txt'

def replace(text, old, new):
    if old not in text:
        raise RuntimeError('Art migration baseline mismatch: ' + old[:100])
    return text.replace(old, new)

def section(text, start, end, body):
    a, b = text.index(start), text.index(end, text.index(start))
    return text[:a] + body + '\n' + text[b:]

TREE = r'''  function tree(m,x,y,z,size,seed=0,distant=false){
    const height=(105+h(seed)*33)*size,bend=(h(seed+3)-.5)*13*size;
    const bark=distant?'#81928b':'#a88c65';
    tube(m,[[x,y,z],[x-2*size,y+height*.3,z],[x+bend*.4,y+height*.65,z-2*size],[x+bend,y+height,z]],
      [9.2*size,7.8*size,5.6*size,2.3*size],bark,MAT.wood,distant?10:18);
    if(!distant){
      for(let j=0;j<4;j++){
        const a=j*TAU/4+seed,dx=Math.cos(a)*23*size,dz=Math.sin(a)*16*size;
        tube(m,[[x,y+11*size,z],[x+dx*.5,y+2*size,z+dz*.5],[x+dx,y-.6,z+dz]],
          [4.1*size,2.2*size,.15],shade(bark,.94),MAT.wood,10);
      }
      // Broad carved marks, rather than high-frequency bark noise.
      for(let j=0;j<3;j++){
        const yy=y+(26+j*17)*size;
        tube(m,[[x-3*size,yy+1,z+7.4*size],[x-1*size,yy-1,z+8*size],[x+2.5*size,yy,z+7.7*size]],
          [.14*size,.24*size,.08],shade(bark,.83),MAT.wood,6);
      }
    }
    const colors=distant?['#739887','#82a393','#6c917f']:['#80b567','#93bf73','#acd384','#70a35b','#91bb68'];
    const lobes=[[-22,-1,2,27,25,22],[23,1,0,30,28,25],[-7,18,-13,33,31,28],[1,2,15,36,25,25]];
    for(let i=0;i<lobes.length;i++){
      const [xx,yy,zz,rx,ry,rz]=lobes[i],col=colors[(i+Math.abs(seed))%colors.length];
      sculpt(m,(a,b)=>{
        const sn=Math.sin(b),q=1+.025*Math.cos(a*5+seed)*sn*sn+.018*Math.cos(b*5);
        return[x+bend+xx*size+Math.cos(a)*sn*rx*size*q,y+height+yy*size+Math.cos(b)*ry*size,z+zz*size+Math.sin(a)*sn*rz*size*q];
      },(a,b)=>blend(col,shade(col,.85),Math.max(0,-Math.cos(b))*.55),MAT.leaf,distant?14:28,distant?9:18);
    }
    if(!distant&&seed%3===0)for(let j=0;j<3;j++){
      const xx=x+bend+(j-1)*16*size,yy=y+height-14*size+Math.sin(j*2)*7*size,zz=z+24*size;
      ellipsoid(m,xx,yy,zz,4.6*size,5.1*size,4.2*size,'#edbb70',MAT.cloth,14,10);
      tube(m,[[xx,yy+4.4*size,zz],[xx+1.2*size,yy+8*size,zz]],[.65*size,.3*size],bark,MAT.wood,6);
      leaf(m,[xx,yy+6*size,zz],[xx+6*size,yy+9*size,zz+.5],2.5*size,'#5c9655',j,MAT.leaf,6);
    }
  }
'''

EYES = r'''  function eye(m,x,y,z,rx,ry,iris,blink=0){
    const open=Math.max(.035,1-blink),r=rx*1.12,hh=ry*1.08*open;
    // Readable enamel eyes with a deep pupil, broad reflected sky and two glints.
    // No sub-pixel iris spokes, lash hairs, or coplanar translucent overlays.
    lens(m,x,y,z,r*1.06,hh*1.05,.20,'#6b5046',MAT.cloth,24,4);
    lens(m,x,y,z+.20,r,hh,.64,(q,a)=>blend('#263b3b',iris,
      Math.max(0,-Math.sin(a))*(1-q*.6)*.42),MAT.eye,28,7);
    if(open>.18){
      lens(m,x-r*.28,y+hh*.32,z+.94,r*.27,hh*.23,.09,'#fff8e8',.08,14,4);
      lens(m,x+r*.27,y-hh*.30,z+.93,r*.105,hh*.10,.055,'#b3dfd4',.02,10,3);
    }
    if(open<.25){
      tube(m,[[x-r*.8,y+.08,z+.45],[x,y-.08,z+.58],[x+r*.8,y+.08,z+.45]],
        [.09,.14,.09],'#314740',MAT.cloth,7);
    }
  }
'''

PROPS = r'''  // Original cozy set dressing. All props stay behind the walkable lane;
  // the hidden bridge and both depth routes keep their existing collisions.
  function cottage(m,x,z,palette=0){
    const wall=['#f1d7ab','#eac3b1','#d0e2ba'][palette%3],roof=['#87a894','#ad8c9e','#beac7b'][palette%3];
    const shell=cached('cozy-cottage:'+palette,local=>{
      profile(local,[[0,29,22],[3,30,23],[32,30,23],[45,23,19],[48,0,0]],wall,MAT.cloth,32);
      profile(local,[[36,36,28],[40,37,29],[47,32,26],[57,22,20],[67,7,9],[69,0,0]],roof,MAT.cloth,40);
      // A round timber door, cream rim, amber handle and glass portholes.
      ellipsoid(local,0,14,22.9,9.5,15.5,1.7,'#f9e7ba',MAT.cloth,24,16);
      ellipsoid(local,0,13.8,24.2,7.5,13.6,.9,'#aa825b',MAT.wood,24,16);
      ellipsoid(local,4,13,25.2,.95,.95,.75,'#f3cd78',MAT.eye,12,8);
      for(const s of [-1,1]){
        ellipsoid(local,s*19,24,20.2,6.4,7.4,1.5,'#f6e5bd',MAT.cloth,20,14);
        ellipsoid(local,s*19,24,21.5,4.65,5.65,.65,'#83b8b0',MAT.eye,20,14);
        tube(local,[[s*19-4,24,22.2],[s*19+4,24,22.2]],.48,'#efe0b2',MAT.cloth,8);
        tube(local,[[s*19,19,22.2],[s*19,29,22.2]],.48,'#efe0b2',MAT.cloth,8);
      }
      ellipsoid(local,0,1.1,27,12,2.4,7,'#c6bd9b',MAT.stone,20,10);
      // A ridge button and scalloped eave give the little house a clear silhouette.
      ellipsoid(local,0,69,0,4,2.5,5,shade(roof,1.12),MAT.cloth,16,8);
      for(let j=0;j<14;j++){
        const a=j/14*TAU;
        ellipsoid(local,Math.cos(a)*35,38,Math.sin(a)*27,3.4,2.7,3.2,shade(roof,1.06),MAT.cloth,10,7);
      }
      for(const s of [-1,1]){
        ellipsoid(local,s*32,4,26,5,5,5,'#d1a780',MAT.cloth,16,10);
        for(let j=0;j<3;j++)blossom(local,s*32+(j-1)*2.6,8,26,1.8,j%2?'#f2c389':'#df9caa',j);
      }
    });append(m,shell,x,0,z);
  }
  function garden(m,x,z){
    for(let i=0;i<4;i++){
      const xx=x+i*12;
      ellipsoid(m,xx,10,z,1.8,10,1.8,'#dfcaa3',MAT.wood,12,8);
      ellipsoid(m,xx,20,z,2.1,2.1,2.1,'#f0dab0',MAT.cloth,12,8);
    }
    for(const yy of [7,15])tube(m,[[x,yy,z],[x+36,yy,z]],1.1,'#d2bc92',MAT.wood,9);
    for(let j=0;j<5;j++)blossom(m,x+j*8,0,z+8,2.4,j%2?'#f3ce88':'#e7a9bb',j);
  }
  function pond(m,x,z,rx,rz){
    // Smooth opaque waterbed shader, separate from the refractive playable water.
    for(let j=0;j<40;j++){
      const a=j/40*TAU,b=(j+1)/40*TAU;
      triangle(m,[x,.12,z],[x+Math.cos(a)*rx,.12,z+Math.sin(a)*rz],[x+Math.cos(b)*rx,.12,z+Math.sin(b)*rz],
        '#92c9c5',[0,1,0],[0,1,0],[0,1,0],-11);
    }
    for(let i=0;i<8;i++){
      const a=i/8*TAU;rock(m,x+Math.cos(a)*rx,.5,z+Math.sin(a)*rz,3.5,1.7,2.5,'#c6ccb0',i);
    }
    disk(m,x+rx*.27,.24,z-2,3.8,2.8,'#8cac6d',MAT.leaf,20);
    blossom(m,x+rx*.27,.25,z-2,1.4,'#eec5bc',0);
  }
  function cozyWorld(m){
    for(const [x,z,p]of [[184,-88,0],[555,-88,1],[1110,-88,2],[1745,-88,0]])cottage(m,x,z,p);
    for(const [x,z]of [[213,-49],[568,-48],[1755,-49]])garden(m,x,z);
    pond(m,442,-55,28,16);pond(m,1370,-51,25,17);
  }
  function cozyLife(m,state){
    const t=state.time||0;
    // Cached petals become distant butterflies, not new collectible forms.
    const wing=cached('cozy-butterfly',local=>{
      ellipsoid(local,-1.55,0,0,1.8,2.5,.35,'#f5c897',MAT.cloth,12,8);
      ellipsoid(local,1.55,0,0,1.8,2.5,.35,'#f5c897',MAT.cloth,12,8);
      ellipsoid(local,0,0,.2,.3,1.6,.35,'#8f785e',MAT.cloth,8,6);
    });
    for(let i=0;i<(state.reduced?2:5);i++){
      const xx=Math.floor(state.cameraX/300)*300-220+i*138+Math.sin(t*.36+i)*16;
      append(m,wing,xx,35+Math.sin(t*.55+i)*12,-115-i*8,1,.55+.35*Math.sin(t*10+i));
    }
  }
'''

SKY = r'''  const skyFS=`
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
'''

CSS = r'''
/* Cozy Canopy: original tactile botanical interface. Hit areas are unchanged. */
:root{--ink:#30483c;--paper:#fff3d8;--mint:#b9d7af;--gold:#eabe77}
body,button{font-family:ui-rounded,"SF Pro Rounded",system-ui,sans-serif}
body{background:#adcfc4;color:var(--ink)}
.vignette{opacity:.16}
#hud{color:#fff7df;text-shadow:0 1px 4px #36553b70}
.chapter-mark small{color:#f5edd6;letter-spacing:.17em;font-size:9px}
.chapter-mark strong{font-weight:750;font-size:15px}
.mini-prism{color:#ffe3a3}
#objective{background:#fff4dfec;color:#435747;border:1px solid #fffbeea8;box-shadow:0 3px 0 #66856833,0 8px 22px #183d2914;border-radius:22px;font-size:12px;padding:9px 15px;text-shadow:none}
#shards{color:#8c672e;border-color:#bcac853d}
#dimensionBadge{color:#fff4d9;font-size:22px}#dimensionBadge i{color:#edf0db;font-size:8px}
.icon-button{background:#fff4dfe8;color:#527159;border:1px solid #fffbed;border-radius:19px;box-shadow:0 3px 0 #66856855}
.icon-button:active{transform:translateY(2px)}
.title-screen{background:linear-gradient(90deg,#f7f1d9f5 0%,#f7f1d9e0 28%,#f7f1d96b 47%,transparent 67%)}
.title-content{color:#365543}
.title-content .eyebrow{color:#67855b;font-weight:750;letter-spacing:.23em}
.title-content h1{font-family:ui-rounded,"SF Pro Rounded",system-ui,sans-serif;font-weight:850;letter-spacing:-.05em;line-height:.98;color:#365543;text-shadow:0 2px 0 #fff8e8}
.title-content h1 em{color:#b8844e;font-style:normal}
.title-dot{color:#bc8a53}.title-content p{color:#6a7860}.title-bottom,.version{color:#728168}.title-scene-label{color:#fff2d3;text-shadow:0 2px 8px #344d3d}
.primary{background:#426d57;color:#fff3d9;border:1px solid #517d63;border-radius:20px;box-shadow:0 4px 0 #2d5444,0 10px 24px #243c2820;font-weight:700;letter-spacing:.01em}
.primary:active{transform:translateY(3px);box-shadow:0 1px 0 #2d5444}
.control-label{color:#fff6df;text-shadow:0 1px 4px #334c2d99;font-size:9px;letter-spacing:.17em}
#movePad{background:#f7eedccc;border:2px solid #fff9e4b8;color:#527359;box-shadow:0 4px 0 #456d4c55,inset 0 1px 8px #fff8ebaa;backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px)}
.pad-half{color:#527359}.pad-half.active{background:#d0dfbca8;color:#344f40}
.stick-ring{border-color:#a7ba9455}.stick-ring span{color:#55755a}
#stick{background:linear-gradient(150deg,#cfe2be,#9fbe98);border:2px solid #ecf3daba;box-shadow:0 3px 0 #76957170,0 4px 12px #3e6a4830}
#jump{background:linear-gradient(150deg,#ffdfa2,#ecc085);color:#5c6144;border:2px solid #fff3c9;box-shadow:0 5px 0 #c5986477,0 10px 24px #3d562831}
#jump svg{stroke:#6e6744}#jump:active,#jump.held{transform:translateY(3px) scale(.97);box-shadow:0 2px 0 #b98f5a88}
#power{background:linear-gradient(145deg,#d6e8d1e8,#a4cdbbdf);border:2px solid #ebf5d9c9;color:#3d715d;box-shadow:0 4px 0 #648b6e55}
#power svg{stroke:#416f5d}#power span{color:#3d6550}
#formButton{background:#fff0d6de;border:2px solid #fff7e5b8;color:#826952;box-shadow:0 4px 0 #a79a6d55}
#formButton svg{stroke:#836b52}#formText{color:#77624d}#formCount{color:#6b7656;background:#faf5de;border-color:#c2c9a6}
#power:disabled,#formButton:disabled{opacity:.48;filter:saturate(.4)}
#toast{background:#fff5dfef;color:#4c6249;border:1px solid #fffbee;border-radius:24px;box-shadow:0 5px 18px #28462a25;font-size:13px;max-width:68vw}
#dialogue{background:#fff4dfed;color:#50654b;border:1px solid #fff9e5;border-radius:22px;box-shadow:0 6px 24px #264c2830}
#speaker{color:#53704e}#dialogueText{color:#54604a}.dialogue-dot{background:#88ae77;box-shadow:0 0 0 5px #91b57c24}
.modal{background:#29483e66;backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px)}
.modal-card{background:#fff2d9f5;border:2px solid #fff9e8;border-radius:32px;color:#3c5646;box-shadow:0 12px 60px #17372d40}
.modal-card .eyebrow{color:#8b9c68}.modal-card h2{color:#385744;font-family:ui-rounded,"SF Pro Rounded",system-ui,sans-serif;font-weight:800;letter-spacing:-.03em}
.modal-card p,.key-help{color:#76816a}.secondary{color:#58704f;background:#dde5c7;border-color:#c8d4b5;border-radius:16px}.text-button{color:#8c7659}
#introOverlay{color:#fff6dd}.intro-heading{color:#fff2cf}.intro-caption-wrap{background:linear-gradient(transparent,#294c3945)}
#introCaption{color:#fff7e6;text-shadow:0 2px 8px #193f2c}
#skipIntro{color:#4c694e;background:#fff0dada;border:1px solid #fff6e4;border-radius:18px}
#shiftVeil{background:radial-gradient(ellipse at center,#e5ffdb12,transparent 62%)}#shiftCaption{color:#fff1cc;text-shadow:0 2px 8px #3d604e}
#rotate{background:#426b54;color:#fff2da}#rotate h2{color:#fff2da}
@media(max-height:430px){.chapter-mark strong{font-size:13px}.chapter-mark small{font-size:8px}#objective{font-size:11px;padding:8px 12px}#toast{font-size:12px}.title-content h1{font-size:46px}.title-content p{font-size:13px}}
@media(prefers-reduced-motion:reduce){button,#movePad,#stick,.modal-card{transition:none!important;animation:none!important}}
'''

NOTES = '''# Enter the Third Dimension 2.3 (5): Cozy Canopy

An original storybook-rainforest art pass. The game remains a landscape
platform adventure about a living raindrop, not a life-simulation clone.

- Rounded, multi-lobed tree crowns, warmer trunks and soft grass banks.
- Original pastel cottages, porthole windows, garden fences and flower pots.
- Animated garden pools and distant fluttering butterflies.
- Larger-headed chibi residents with clean enamel eyes and readable faces.
- A softer, brighter jelly heroine with fuller proportions, sky reflections,
  translucent refraction and movement-driven elastic animation.
- Warm daylight, pale atmospheric haze, cleaner materials and softened
  character lighting. Retains real dynamic shadows, bloom and edge smoothing.
- Tactile cream, sage and apricot controls, pause menus and story presentation.
- The original opening, remembered girl/frog/fox forms, dimensional puzzles,
  touch controls, checkpoints and save data are preserved.

All added art and shader changes are original and run offline. No Nintendo
models, music, textures, UI assets or third-party shaders are included.

Native simulator launch and resource/IPA verification are required before
publication. Browser checks and captures are included as build evidence.
Physical iPhone frame pacing, thermal behavior and long-session performance
are not established by simulator or desktop browser results.

Version 2.3, build 5. Bundle ID com.billy.moonhop, iOS 16.0+.
The IPA is ad-hoc signed for the existing sideloading workflow, not App Store
distribution signed.
'''

def main():
    if MARKER.exists():
        if MARKER.read_text().strip() != 'Cozy Canopy 2.3 (5)':
            raise RuntimeError('Unexpected cozy revision')
        return
    # Validate the complete migration baseline before writing files.
    outputs={}
    p=GAME/'rainforest.js';s=p.read_text()
    s=section(s,'  function tree(', '  function birthTree(',TREE)
    s=section(s,'  function eye(', '  function head(',EYES)
    s=replace(s,'  function buildWorld(m,world){',PROPS+'\n  function buildWorld(m,world){')
    s=replace(s,'    forestFloor(m);','    forestFloor(m);cozyWorld(m);')
    s=replace(s,"    const p=state.player,t=state.time||0,d=state.dimensionBlend||0;", "    const p=state.player,t=state.time||0,d=state.dimensionBlend||0;cozyLife(m,state);")
    # A smooth, continuous chibi deformation. Normals are transformed by the
    # inverse transpose of the same Jacobian, not scaled as positions.
    old='out.push(x+pivotX+xx*ca-yy*sa,y+pivotY+xx*sa+yy*ca,z+zz*depth,data[i+3],data[i+4],data[i+5],nnx*ca-ny*sa,nnx*sa+ny*ca,nnz,data[i+9]);'
    new='''const tx=pivotX+xx*ca-yy*sa,ty=pivotY+xx*sa+yy*ca;
      const q=clamp((ty-17)/8,0,1),blend=q*q*(3-2*q),sx=.98+.20*blend,ds=(q>0&&q<1)?.20*6*q*(1-q)/8:0;
      const ty2=ty*.82+Math.max(0,ty-18)*.26,ys=ty>18?1.08:.82;
      const nx2=(nnx*ca-ny*sa)/sx,ny2=((nnx*sa+ny*ca)-nx2*tx*ds)/ys;
      out.push(x+tx*sx,y+ty2,z+zz*depth,data[i+3],data[i+4],data[i+5],nx2,ny2,nnz,data[i+9]);'''
    s=replace(s,old,new)
    for a,b in {'#426b51':'#79a962','#335e49':'#78a370','#294c40':'#7d9e80','#416348':'#94b087','#3c6348':'#84ac74','#6f7352':'#d4bd89','#4b8865':'#88b783','#326e58':'#689e72','#6b9878':'#a6c98e','#44776b':'#7eac80','#547671':'#89b194','#3c6d53':'#87ad71','#578761':'#a0c486','#749872':'#b4d58e'}.items():s=s.replace(a,b)
    s=replace(s,"style:'smooth mystical rainforest'", "style:'smooth mystical rainforest',artRevision:'Cozy Canopy 2.3'")
    outputs[p]=s
    p=GAME/'visuals.js';s=p.read_text()
    s=section(s,'  const skyFS=', '  const brightFS=',SKY)
    s=replace(s,'base*=.74+broad*.43+grain*.09+fleck*.035;','base*=.96+broad*.065;')
    s=replace(s,'base=mix(base,vec3(.19,.215,.16),dirt*.27);roughness=.84;',"base=mix(base,vec3(.63,.65,.39),dirt*.035);roughness=.84;\n          if(N.y<.55)base=mix(vec3(.49,.37,.24),vec3(.68,.53,.34),smoothstep(-85.,0.,vWorld.y))*(.98+.02*sin(vWorld.y*.28));")
    s=replace(s,'N=normalize(N+vec3(slope.x*.13,0.,slope.y*.13));','N=normalize(N+vec3(slope.x*.015,0.,slope.y*.015));')
    s=replace(s,'base*=.78+grooves*.28+noise(vWorld.xy*.7)*.045;','base*=.95+grooves*.055;')
    s=replace(s,'base*=.83+stone*.30;','base*=.95+stone*.08;')
    s=replace(s,'base*=1.+weave*.012;','base*=1.+weave*.002;')
    s=replace(s,'base*=.94+vein*.075;','base*=.985+vein*.022;')
    s=replace(s,'float shadow=softShadow(N,material);','''float shadow=softShadow(N,material);
      if((material>1.5&&material<4.5)||(material>7.5&&material<8.5))shadow=mix(.94,1.,shadow);
      if(material>10.5&&material<11.5){
        float rip=sin(vWorld.x*.24+uTime*.8+sin(vWorld.z*.22-uTime*.42));
        base=mix(vec3(.35,.66,.64),vec3(.69,.84,.74),.5+.5*rip);
        float glint=pow(max(0.,sin(vWorld.x*.47+uTime)*cos(vWorld.z*.5-uTime*.4)),28.);
        base+=vec3(.35,.36,.25)*glint;roughness=.28;sheen=.3;
      }''')
    s=replace(s,'mix(.28,1.,shadow)','mix(.62,1.,shadow)')
    s=replace(s,'mix(vec3(.22,.26,.24),vec3(.49,.69,.80),upward)*.58','mix(vec3(.45,.44,.30),vec3(.65,.78,.80),upward)*.70')
    s=replace(s,'vec3(1.0,.91,.78)*(wrap*.96)','vec3(1.0,.92,.76)*(wrap*.84)')
    s=replace(s,'color=pow(film(color*1.44),vec3(1./2.2));','color=pow(film(color*1.20),vec3(1./2.2));')
    s=replace(s,'max(0.,-vWorld.z-105.)*.00175','max(0.,-vWorld.z-140.)*.00145')
    s=replace(s,'mix(vec3(.095,.21,.25),vec3(.18,.29,.33),clamp(vWorld.y/220.,0.,1.))','mix(vec3(.67,.79,.68),vec3(.67,.83,.82),clamp(vWorld.y/220.,0.,1.))')
    s=replace(s,'mix(vec3(luminance),col,1.055)','mix(vec3(luminance),col,1.025)')
    s=replace(s,'length(edge))*.115','length(edge))*.055')
    s=s.replace("version:'2.2'","version:'2.3'")
    outputs[p]=s
    p=GAME/'water.js';s=p.read_text()
    s=replace(s,'vec3(.057,.020,.012)','vec3(.035,.012,.009)')
    s=replace(s,'vec3(.018,.055,.070)','vec3(.045,.105,.115)')
    s=replace(s,'vec3(.072,.365,.485),vec3(.16,.47,.56)','vec3(.18,.53,.59),vec3(.34,.65,.68)')
    s=replace(s,'transmitted,waterColor,.34+faceBody*.19','transmitted,waterColor,.41+faceBody*.17')
    s=replace(s,'vec3(.062,.18,.17),vec3(.20,.34,.48)','vec3(.22,.40,.30),vec3(.62,.80,.83)')
    s=replace(s,'environment,.15+F*.64','environment,.12+F*.68')
    s=replace(s,'color*vec3(.86,.96,1.025)+vec3(.008,.006,.027)','color*vec3(.88,1.,1.035)+vec3(.018,.024,.032)')
    s=replace(s,'float rays=sin(angle*31.+ir*15.)*.5+.5;','float rays=.5;')
    s=replace(s,'vec3 eye=mix(sclera,irisColor,ring);','vec3 eye=mix(ink,irisColor*.65,ring*.6);')
    s=replace(s,'float pupil=1.-smoothstep(.26,.33','float pupil=1.-smoothstep(.44,.57')
    s=replace(s,'vec2(.21,.25)','vec2(.26,.29)')
    s=replace(s,'            const wave=Math.sin(Y*.48', '''            if(creature===0){
              const head=smooth((Y-17)/8)*form;X*=1+.18*head;Z*=1+.12*head;
              Y=mix(Y,Y*.87+Math.max(0,Y-18)*.25,form);
            }
            const wave=Math.sin(Y*.48''')
    s=s.replace("visualGeneration:'2.2'","visualGeneration:'2.3'")
    outputs[p]=s
    p=GAME/'game.js';s=p.read_text().replace("version:'2.2 (4)'","version:'2.3 (5)'")
    s=replace(s,'cameraHeight=214+18*dimensionBlend','cameraHeight=202+18*dimensionBlend')
    s=s.replace('Step around the paper wall','Step around the enchanted leaf')
    outputs[p]=s
    p=GAME/'render.js';s=p.read_text().replace("visualVersion:'2.2'","visualVersion:'2.3'")
    outputs[p]=s
    p=GAME/'index.html';s=p.read_text().replace('THE LIVING FOREST · 2.2','COZY CANOPY · 2.3')
    s=replace(s,'<link rel="stylesheet" href="style.css">','<link rel="stylesheet" href="style.css">\n  <link rel="stylesheet" href="cozy.css">')
    s=s.replace('content="#10182e"','content="#426b54"')
    outputs[p]=s
    outputs[GAME/'cozy.css']=CSS
    for name in ['build_ios.py','build_project.py','verify_ipa.py','build_release.py']:
        p=ROOT/'Support'/name;s=p.read_text()
        for a,b in [('2.2 (4)','2.3 (5)'),('2.2-build4','2.3-build5'),('"2.2"','"2.3"'),("'2.2'","'2.3'"),('"build": "4"','"build": "5"'),('"CFBundleVersion": "4"','"CFBundleVersion": "5"'),("'CURRENT_PROJECT_VERSION':'4'","'CURRENT_PROJECT_VERSION':'5'"),('result.get("build") == "4"','result.get("build") == "5"')]:s=s.replace(a,b)
        outputs[p]=s
    p=ROOT.parent/'.github/workflows/third-dimension.yml';s=p.read_text().replace('2.2-build4','2.3-build5').replace('Dimension 2.2 release','Dimension 2.3 release')
    start=s.index('--notes "');end=s.index('"\n',start)
    s=s[:start]+'--notes "Cozy Canopy: rounder chibi residents, warm daylight, soft tree crowns, pastel cottages, garden pools, butterflies, brighter liquid forms and tactile botanical controls. Original adventure, touch controls, saves and offline play preserved.'+s[end:]
    outputs[p]=s
    outputs[ROOT/'RELEASE-NOTES.md']=NOTES
    p=ROOT/'README.md';s=p.read_text().replace('**2.2**, build **4**','**2.3**, build **5**')
    s=s.replace('## A first look','## Cozy Canopy, version 2.3\n\nRound-canopy trees, original pastel cottages, garden pools, clean chibi faces,\nwarm daylight and a tactile cream-and-sage interface. The water heroine keeps\nher reflective, refractive surface, with fuller proportions and a softer tint.\nThe dimensional adventure and existing saved progress are preserved.\n\n## A first look')
    s=s.replace('These are actual frames','The following are archived 2.2 frames. Updated 2.3 captures are provided in the build evidence. These are actual frames')
    outputs[p]=s
    # Never describe an earlier QA report as validation of the current resources.
    p=ROOT/'docs/WEBKIT-QA.json'
    if p.exists():outputs[ROOT/'docs/WEBKIT-QA-2.2.json']=p.read_text()
    outputs[p]='{"version":"2.3 (5)","status":"pending current-build browser verification","historicalReport":"WEBKIT-QA-2.2.json"}\n'
    for p,s in outputs.items():p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
    p=ROOT/'Resources/Info.plist';info=plistlib.loads(p.read_bytes());info['CFBundleShortVersionString']='2.3';info['CFBundleVersion']='5';p.write_bytes(plistlib.dumps(info,sort_keys=False))
    MARKER.write_text('Cozy Canopy 2.3 (5)\n')
    print('Applied Cozy Canopy 2.3 (5) to',len(outputs)+2,'source files')

if __name__=='__main__':main()
