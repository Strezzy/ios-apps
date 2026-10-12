/* Original smooth rainforest geometry. No imported models, sprites, or textures.
 * Coordinates and supporting surfaces exactly follow TD_WORLD; the scenery is
 * decorative. Living inhabitants retain a thin Z silhouette in either mode.
 */
(() => {
  'use strict';
  const TAU=Math.PI*2, clamp=(v,a,b)=>Math.max(a,Math.min(b,v)), mix=(a,b,t)=>a+(b-a)*t;
  const h=n=>{const v=Math.sin(n*127.1+311.7)*43758.5453;return v-Math.floor(v);};
  const color=c=>typeof c==='string'?[parseInt(c.slice(1,3),16)/255,parseInt(c.slice(3,5),16)/255,parseInt(c.slice(5,7),16)/255]:c;
  const shade=(c,s)=>color(c).map(v=>clamp(v*s,0,1));
  const blend=(a,b,t)=>color(a).map((v,i)=>mix(v,color(b)[i],t));
  const norm=v=>{const l=Math.hypot(...v)||1;return v.map(x=>x/l);};
  const add=(a,b)=>a.map((v,i)=>v+b[i]), sub=(a,b)=>a.map((v,i)=>v-b[i]);
  const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
  const ease=t=>{t=clamp(t,0,1);return t*t*(3-2*t);};
  const triangle=(m,a,b,c,col,na,nb=na,nc=na,g=0)=>{col=color(col);m.vertex(a,col,na,g);m.vertex(b,col,nb,g);m.vertex(c,col,nc,g);};
  const geometryCache=new Map();
  function cached(key,build){
    if(geometryCache.has(key))return geometryCache.get(key);
    const mesh={a:[],vertex(p,c,n,g){this.a.push(...p,...c,...n,g);}};build(mesh);
    const data=new Float32Array(mesh.a);geometryCache.set(key,data);return data;
  }
  function append(m,data,x=0,y=0,z=0,sy=1,sz=1){
    const out=m.a;for(let i=0;i<data.length;i+=10)out.push(x+data[i],y+data[i+1]*sy,z+data[i+2]*sz,data[i+3],data[i+4],data[i+5],data[i+6],data[i+7],data[i+8],data[i+9]);
  }

  function ellipsoid(m,x,y,z,rx,ry,rz,col,glow=0,sides=14,rings=8){
    const pos=(a,b)=>{const sn=Math.sin(b),n=[Math.cos(a)*sn,Math.cos(b),Math.sin(a)*sn];return{p:[x+n[0]*rx,y+n[1]*ry,z+n[2]*rz],n:norm([n[0]/Math.max(.001,rx),n[1]/Math.max(.001,ry),n[2]/Math.max(.001,rz)])};};
    for(let row=0;row<rings;row++)for(let side=0;side<sides;side++){
      const a=side/sides*TAU,A=(side+1)/sides*TAU,b=row/rings*Math.PI,B=(row+1)/rings*Math.PI;
      const p=pos(a,b),q=pos(A,b),r=pos(A,B),s=pos(a,B);
      if(row>0)triangle(m,p.p,q.p,r.p,col,p.n,q.n,r.n,glow);
      if(row<rings-1)triangle(m,p.p,r.p,s.p,col,p.n,r.n,s.n,glow);
    }
  }
  function tube(m,points,radii,col,glow=0,sides=10){
    const rings=points.map((p,i)=>{
      const tangent=norm(sub(points[Math.min(i+1,points.length-1)],points[Math.max(0,i-1)]));
      const axis=Math.abs(tangent[1])>.93?[1,0,0]:[0,1,0],u=norm(cross(tangent,axis)),v=norm(cross(tangent,u));
      const radius=Array.isArray(radii)?radii[i]:radii;
      return Array.from({length:sides},(_,j)=>{const a=j/sides*TAU,n=u.map((q,k)=>q*Math.cos(a)+v[k]*Math.sin(a));return{p:p.map((q,k)=>q+n[k]*radius),n};});
    });
    for(let i=0;i<rings.length-1;i++)for(let j=0;j<sides;j++){
      const a=rings[i][j],b=rings[i][(j+1)%sides],c=rings[i+1][(j+1)%sides],d=rings[i+1][j];
      const c0=shade(col,.88+.14*i/Math.max(1,rings.length-1));
      triangle(m,a.p,b.p,c.p,c0,a.n,b.n,c.n,glow);triangle(m,a.p,c.p,d.p,c0,a.n,c.n,d.n,glow);
    }
    for(const end of [0,points.length-1]){
      const n=norm(sub(points[end],points[end===0?1:end-1]));
      for(let j=0;j<sides;j++)triangle(m,points[end],rings[end][j].p,rings[end][(j+1)%sides].p,col,n,n,n,glow);
    }
  }
  function leaf(m,base,tip,width,col,seed=0,glow=0,steps=8){
    const axis=norm(sub(tip,base)),span=norm(cross(axis,[0,0,1]));
    const midpoint=base.map((v,i)=>mix(v,tip[i],.48));midpoint[1]+=width*.65;midpoint[2]-=width*.24;
    const grid=[];
    for(let row=0;row<=steps;row++){
      const t=row/steps,wt=Math.pow(Math.sin(Math.PI*t),.82)*width;
      const center=base.map((v,i)=>(1-t)*(1-t)*v+2*(1-t)*t*midpoint[i]+t*t*tip[i]);
      grid[row]=[-1,0,1].map(u=>{
        const p=center.map((v,i)=>v+span[i]*u*wt);
        p[2]+=(1-u*u)*Math.sin(Math.PI*t)*width*.24+u*u*width*.10*Math.sin(t*4+seed);
        const n=norm([span[0]*u*.34,.35+Math.sin(t*Math.PI)*.25,.85]);
        return{p,n,c:blend(shade(col,.80+.20*t),shade(col,1.18),1-Math.abs(u))};
      });
    }
    for(let row=0;row<steps;row++)for(let colI=0;colI<2;colI++){
      const a=grid[row][colI],b=grid[row][colI+1],c=grid[row+1][colI+1],d=grid[row+1][colI];
      for(const v of [a,b,c,a,c,d])m.vertex(v.p,v.c,v.n,glow);
    }
    if(width>=3){const vein=[];for(let i=0;i<=4;i++){const t=i/4;const p=base.map((v,k)=>(1-t)*(1-t)*v+2*(1-t)*t*midpoint[k]+t*t*tip[k]);p[2]+=Math.sin(Math.PI*t)*width*.25+.1;vein.push(p);}
      tube(m,vein,[width*.023,width*.022,width*.017,width*.012,.04],shade(col,1.32),glow,5);}
  }
  function fern(m,x,y,z,size,seed=0,col='#398670'){
    for(let frond=0;frond<4;frond++){
      const side=frond<2?-1:1,angle=(frond-2)*.34,reach=(12+h(seed+frond)*15)*size;
      const tip=[x+Math.sin(angle)*reach*1.6,y+reach*(.65+h(frond)*.35),z+Math.cos(frond)*5*size];
      const middle=[mix(x,tip[0],.4),mix(y,tip[1],.65),mix(z,tip[2],.5)];
      tube(m,[[x,y,z],middle,tip],[.45*size,.35*size,.04],shade(col,.9),0,5);
      for(let j=1;j<5;j++){
        const t=j/6,b=[mix(x,tip[0],t),mix(y,tip[1],t),mix(z,tip[2],t)];
        for(const s of [-1,1]){const l=(1-t*.7)*7.2*size;leaf(m,b,[b[0]+s*l,b[1]+l*.35,b[2]+side*.45],l*.22,shade(col,.85+j*.04),seed+j+s,0,4);}
      }
    }
  }
  function broadPlant(m,x,y,z,size,seed=0){
    const palette=['#538e73','#42856f','#729d86','#578d8c','#627b89'];
    for(let j=0;j<6;j++){
      const a=(j/5-.5)*2.5,reach=(17+h(seed+j)*18)*size;
      const tip=[x+Math.sin(a)*reach,y+(12+Math.cos(a)*20)*size,z-6*size+Math.sin(j*1.9)*7*size];
      const start=[x,y+.7,z],base=[mix(x,tip[0],.18),y+5*size,mix(z,tip[2],.25)];
      tube(m,[start,base],[.6*size,.4*size],shade(palette[j%5],.8),0,5);
      leaf(m,base,tip,(4.2+h(seed+j+20)*3)*size,palette[(j+seed)%5],seed+j,.02,9);
    }
  }
  function blossom(m,x,y,z,size,col='#e8a2c7',seed=0){
    tube(m,[[x,y,z],[x+size*.2,y+size*2,z-.2],[x,y+size*3,z]],[size*.14,size*.11,.03],'#498b70',0,5);
    for(let i=0;i<5;i++){const a=i/5*TAU+seed;const xx=x+Math.cos(a)*size*.67,yy=y+size*3+Math.sin(a)*size*.67;ellipsoid(m,xx,yy,z,size*.66,size*.56,size*.19,col,.18,8,5);}
    ellipsoid(m,x,y+size*3,z+size*.17,size*.32,size*.32,size*.22,'#fff1b3',.8,8,5);
  }
  function mushroom(m,x,y,z,size,col='#b897e0'){
    tube(m,[[x,y,z],[x-size*.12,y+size*.75,z],[x,y+size*1.65,z]],[size*.18,size*.15,size*.12],'#b7d0bd',.1,7);
    ellipsoid(m,x,y+size*1.7,z,size,size*.43,size*.81,col,.32,size>10?24:12,size>10?10:6);
    ellipsoid(m,x,y+size*1.63,z,size*.88,size*.085,size*.72,'#b4f1d6',.65,10,4);
    for(let i=0;i<3;i++){const a=i*2.3;ellipsoid(m,x+Math.cos(a)*size*.55,y+size*1.93,z+Math.sin(a)*size*.5,size*.12,size*.07,size*.12,'#f7e7ee',.4,6,4);}
  }
  function outline(x,z,w,d,r,samples=6){
    const out=[],centers=[[x+w-r,z+d-r,0],[x+r,z+d-r,Math.PI/2],[x+r,z+r,Math.PI],[x+w-r,z+r,Math.PI*1.5]];
    for(const [cx,cz,start]of centers)for(let i=0;i<samples;i++){const a=start+i/(samples-1)*Math.PI/2;out.push([cx+Math.cos(a)*r,cz+Math.sin(a)*r]);}
    return out;
  }
  function platform(m,p,bridgeBlend=1){
    const top=p.y+p.h,r=Math.min(p.d*.24,p.w*.18,20),edge=outline(p.x,p.z,p.w,p.d,r),cx=p.x+p.w/2,cz=p.z+p.d/2;
    const stone=p.kind==='stone',bridge=p.kind==='bridge';
    const rings=bridge?[{y:top,s:1,c:'#80aaa0'},{y:top-2*bridgeBlend,s:1,c:'#547d72'},{y:p.y*bridgeBlend,s:.98,c:'#304f4c'}]:[
      {y:top,s:1,c:stone?'#a3bbae':'#4d826d'},
      {y:top-3,s:1,c:stone?'#819d92':'#39745e'},
      {y:top-Math.min(12,p.h*.35),s:.995,c:stone?'#526f6c':'#2e6658'},
      {y:p.y,s:.94,c:stone?'#365855':'#203e3b'}];
    for(let j=0;j<edge.length;j++){const k=(j+1)%edge.length;triangle(m,[cx,top,cz],[edge[j][0],top,edge[j][1]],[edge[k][0],top,edge[k][1]],rings[0].c,[0,1,0]);}
    for(let row=0;row<rings.length-1;row++)for(let j=0;j<edge.length;j++){
      const k=(j+1)%edge.length,ring=(point,r)=>[mix(cx,point[0],r.s),r.y,mix(cz,point[1],r.s)];
      const a=ring(edge[j],rings[row]),b=ring(edge[k],rings[row]),c=ring(edge[k],rings[row+1]),d=ring(edge[j],rings[row+1]);
      const na=norm([a[0]-cx,(row===0?.6:.04)*Math.max(p.w,p.d),a[2]-cz]),nb=norm([b[0]-cx,(row===0?.6:.04)*Math.max(p.w,p.d),b[2]-cz]);
      triangle(m,a,b,c,rings[row].c,na,nb,nb);triangle(m,a,c,d,rings[row].c,na,nb,na);
    }
    if(bridge)return;
    if(!stone){
      for(let i=0;i<p.w/58;i++){
        const x=p.x+17+i*58,zz=p.z+p.d-3;
        tube(m,[[x,top-3,zz],[x+5,top-15,zz+1],[x+2,top-30-h(i)*20,zz-2],[x+8,top-43-h(i+5)*18,zz-8]],[2.8,2,1,.1],'#3f7564',0,6);
        if(i%2===0)leaf(m,[x+3,top-19,zz],[x+12,top-29,zz+1],3.2,'#578d6b',i,0,4);
        ellipsoid(m,x+17,top-17,zz-1,9,7,3,'#35544d',0,8,5);
      }
      const rows=Math.ceil(p.w/16);
      for(let i=0;i<rows;i++){
        const x0=p.x+i*p.w/rows,x1=p.x+(i+1)*p.w/rows,z0=Math.sin(x0*.015)*7,z1=Math.sin(x1*.015)*7;
        const r0=12+Math.sin(x0*.041)*3,r1=12+Math.sin(x1*.041)*3,c=blend('#7b9680','#638871',h(i+p.x)*.7);
        triangle(m,[x0,top+.04,z0-r0],[x0,top+.04,z0+r0],[x1,top+.04,z1+r1],c,[0,1,0]);
        triangle(m,[x0,top+.04,z0-r0],[x1,top+.04,z1+r1],[x1,top+.04,z1-r1],c,[0,1,0]);
      }
      for(let i=0;i<p.w/30;i++){
        const xx=p.x+14+i*30,zz=(h(i+p.x+88)-.5)*(p.d-18),seed=i+p.x;
        const rx=10+h(seed)*16,rz=5+h(seed+8)*8;
        const c=blend('#447a64','#64967a',h(seed+17));
        for(let j=0;j<16;j++){const a=j/16*TAU,b=(j+1)/16*TAU,rA=.77+h(j+seed)*.3,rB=.77+h(j+1+seed)*.3;triangle(m,[xx,top+.035,zz],[xx+Math.cos(a)*rx*rA,top+.035,zz+Math.sin(a)*rz*rA],[xx+Math.cos(b)*rx*rB,top+.035,zz+Math.sin(b)*rz*rB],c,[0,1,0]);}
      }
    }else{
      ellipsoid(m,cx,top+.03,cz,Math.max(3,p.w*.35),.45,p.d*.31,'#a9c1a5',0,12,4);
      if(p.id==='lookout')mushroom(m,p.x+8,top,p.z+8,4,'#a3cfe6');
    }
  }
  function tree(m,x,y,z,size,seed=0,distant=false){
    const tall=(125+h(seed)*65)*size,bend=(h(seed+3)-.5)*22*size;
    const bark=distant?'#244b50':seed%3===0?'#766561':'#4d6660';
    const pts=[[x,y,z],[x-3*size,y+tall*.24,z-2*size],[x+bend*.3,y+tall*.52,z],[x+bend,y+tall*.8,z-4*size],[x+bend*.7,y+tall,z-2*size]];
    tube(m,pts,[9*size,7.8*size,6*size,3.8*size,1.2*size],bark,0,distant?8:12);
    if(!distant){
      for(let j=0;j<4;j++){const a=j*1.5+seed;const dx=Math.cos(a)*23*size,dz=Math.sin(a)*14*size;tube(m,[[x,y+12*size,z],[x+dx*.48,y+2*size,z+dz*.5],[x+dx,y-.3,z+dz]],[4*size,2.5*size,.3],shade(bark,.82),0,7);}
      const vine=pts.map((p,i)=>[p[0]+Math.cos(i*1.6)*7*size,p[1],p[2]+Math.sin(i*1.6)*7*size]);tube(m,vine,[1.4*size,1.3*size,1.1*size,.8*size,.15],'#76a487',0,5);
    }
    for(let side=0;side<3;side++){
      const direction=side===0?-1:1,start=pts[2+side%2],end=[x+bend+direction*(32+side*9)*size,y+tall*(.8+side*.1),z-8*size+side*4];
      tube(m,[start,[mix(start[0],end[0],.4),end[1]-9*size,mix(start[2],end[2],.5)],end],[3*size,2*size,.5*size],bark,0,7);
      const leafColors=distant?['#245b59','#2c6661','#2b5d60']:['#306e62','#458771','#65a087','#567b77'];
      for(let k=0;k<4;k++){
        const a=k/4*TAU+side*.7,tip=[end[0]+Math.cos(a)*(44+h(seed+k)*18)*size,end[1]+(14+Math.sin(a)*23)*size,end[2]+Math.sin(a)*(21+side*3)*size];
        leaf(m,end,tip,(9+h(k+seed)*6)*size,leafColors[(k+side)%leafColors.length],seed+k,0,distant?5:8);
      }
    }
    if(!distant&&seed%3===1)for(let j=0;j<3;j++)blossom(m,x+bend-11*size+j*11*size,y+tall-7*size,z+4*size,2.1*size,'#d0a2d2',j);
  }
  function birthTree(m){
    tube(m,[[14,0,-25],[11,29,-24],[17,61,-22],[26,83,-19],[39,105,-18],[35,136,-20]],[12,11,9,6,3,1.2],'#667168',0,14);
    for(const side of [-1,1])tube(m,[[14,13,-25],[14+side*12,2,-15],[14+side*25,0,-12]],[6,4,.6],'#586557',0,8);
    tube(m,[[26,83,-19],[44,95,-13],[60,101,-6],[74,99,0]],[4.7,3.8,2,.55],'#84917a',0,10);
    leaf(m,[61,101,-4],[82,99,1],8,'#95bc83',1,0,12);
    for(let j=0;j<7;j++){const a=j/7*TAU;leaf(m,[34,128,-22],[34+Math.cos(a)*53,140+Math.sin(a)*27,-25+Math.sin(a)*16],14,['#447f6a','#6ca886','#43836f'][j%3],j,0,10);}
    fern(m,7,0,-10,.9,2);mushroom(m,27,0,-16,5.1,'#c6a0d1');mushroom(m,34,0,-19,3.7,'#d7b3c9');
  }
  function forestHeight(x,z){
    const behind=clamp((-z-125)/130,0,1),hill=7+10*Math.sin(x*.005-z*.008)**2+13*Math.sin(x*.011+z*.003)**2;
    return mix(-21,hill,behind);
  }
  function forestFloor(m){
    const xn=52,zn=16,x0=-720,x1=2850,z0=-130,z1=-1180;
    const v=(i,j)=>{
      const x=mix(x0,x1,i/xn),z=mix(z0,z1,j/zn),y=forestHeight(x,z);
      const n=norm([forestHeight(x-1,z)-forestHeight(x+1,z),2,forestHeight(x,z-1)-forestHeight(x,z+1)]);
      const c=blend('#25534d','#376d5b',.2+.6*h(i*.7+j));return{p:[x,y,z],n,c};
    };
    const rows=Array.from({length:zn+1},(_,j)=>Array.from({length:xn+1},(_,i)=>v(i,j)));
    for(let j=0;j<zn;j++)for(let i=0;i<xn;i++){
      const a=rows[j][i],b=rows[j][i+1],c=rows[j+1][i+1],d=rows[j+1][i];for(const p of [a,b,c,a,c,d])m.vertex(p.p,p.c,p.n,0);
    }
    // Rounded low banks root every distant trunk in the forest floor.
    for(let i=0;i<31;i++){
      const x=-400+i*100,z=-176-h(i+70)*20,y=forestHeight(x,z);
      ellipsoid(m,x,y-9,z,65+h(i)*38,17+h(i+2)*19,45,'#32685a',0,14,8);
      if(i%3===0)ellipsoid(m,x+25,y-3,z+15,19,13,16,'#597e70',0,14,9);
    }
  }
  function barrierShape(m,o,lift=0){
    const cx=o.x+o.w/2,base=o.y+lift,z=o.z+o.d/2,gate=o.kind==='gate';
    // One enchanted leaf, with the exact same thin collision slab as before.
    const rings=20,front=[],back=[];
    for(let i=0;i<=rings;i++){
      const t=i/rings,spread=Math.pow(Math.sin(Math.PI*t),.45)*o.w*.5,y=base+t*o.h;
      front.push([[cx-spread,y,z+o.d*.5],[cx,y,z+o.d*.5],[cx+spread,y,z+o.d*.5]]);
      back.push([[cx-spread,y,z-o.d*.5],[cx,y,z-o.d*.5],[cx+spread,y,z-o.d*.5]]);
    }
    for(let row=0;row<rings;row++)for(let j=0;j<2;j++){
      const c=blend(gate?'#92a6b6':'#829fb3',gate?'#d2c0d3':'#b2cabe',row/rings);
      for(const [arr,normal]of [[front,[0,0,1]],[back,[0,0,-1]]]){
        const a=arr[row][j],b=arr[row][j+1],c0=arr[row+1][j+1],d=arr[row+1][j];triangle(m,a,b,c0,c,normal,normal,normal,.12);triangle(m,a,c0,d,c,normal,normal,normal,.12);
      }
      if(j===0||j===1){const side=j===0?0:2;triangle(m,front[row][side],back[row][side],back[row+1][side],shade(c,.85),[side===0?-1:1,0,0]);triangle(m,front[row][side],back[row+1][side],front[row+1][side],shade(c,.85),[side===0?-1:1,0,0]);}
    }
    const vein=[];for(let i=0;i<6;i++)vein.push([cx,base+3+i*(o.h-6)/5,z+o.d*.5+.11]);tube(m,vein,[.5,.6,.7,.7,.5,.08],'#f3e1b2',.65,6);
    for(let i=2;i<9;i++){const yy=base+i*o.h/10,spread=Math.pow(Math.sin(i/10*Math.PI),.45)*o.w*.44;for(const side of [-1,1])tube(m,[[cx,yy,z+o.d*.5+.15],[cx+spread*side*.5,yy+4,z+o.d*.5+.15],[cx+spread*side,yy+9,z+o.d*.5+.12]],[.35,.28,.03],'#cce0c4',.18,5);}
    for(const side of [-1,1])tube(m,[[cx,base,z],[cx+side*o.w*.48,base+o.h*.25,z],[cx+side*o.w*.49,base+o.h*.65,z],[cx,base+o.h,z]],[.8,.75,.65,.1],'#b8d7b2',.3,7);
  }
  function barrier(m,o,lift=0){
    const data=cached('barrier:'+o.kind+':'+o.w+':'+o.h+':'+o.d,local=>barrierShape(local,{...o,x:0,y:0,z:0}));append(m,data,o.x,o.y+lift,o.z);
  }
  function lanternShape(m,x,y,z,lit=false){
    tube(m,[[x,y,z],[x-2,y+15,z],[x+2,y+29,z],[x,y+39,z]],[3.1,2.3,1.7,.5],'#617f69',0,8);
    for(let k=0;k<4;k++){const a=k/4*TAU;leaf(m,[x,y+25,z],[x+Math.cos(a)*10,y+41,z+Math.sin(a)*7],3.8,lit?'#9ed4ad':'#65938a',k,lit?.35:.1,6);}
    ellipsoid(m,x,y+36,z,6,9,5,lit?'#ffe4a1':'#557d80',lit?1:.04,12,8);
    if(lit){ellipsoid(m,x-1,y+38,z+4,2.6,4,1.6,'#fff6cd',1,8,6);}
  }
  function lantern(m,x,y,z,lit=false){append(m,cached('lantern:'+!!lit,local=>lanternShape(local,0,0,0,lit)),x,y,z);}
  function disk(m,x,y,z,rx,rz,col,glow=0,sides=24){
    for(let i=0;i<sides;i++){const a=i/sides*TAU,b=(i+1)/sides*TAU;triangle(m,[x,y,z],[x+Math.cos(a)*rx,y,z+Math.sin(a)*rz],[x+Math.cos(b)*rx,y,z+Math.sin(b)*rz],col,[0,1,0],[0,1,0],[0,1,0],glow);}
  }
  function shadow(m,x,y,z,rx,rz){
    const onTrail=Math.abs(z-Math.sin(x*.015)*7)<15,base=onTrail?'#718f78':'#4d826d';
    const radii=[0,.43,.77,1],tones=[.64,.76,.91,1],normal=[0,1,0];
    for(let ring=0;ring<3;ring++)for(let i=0;i<24;i++){
      const a=i/24*TAU,b=(i+1)/24*TAU,point=(angle,r)=>[x+Math.cos(angle)*rx*r,y,z+Math.sin(angle)*rz*r];
      const p=point(a,radii[ring]),q=point(b,radii[ring]),r=point(b,radii[ring+1]),s=point(a,radii[ring+1]);
      const c0=shade(base,tones[ring]),c1=shade(base,tones[ring+1]);
      for(const [v,c]of [[p,c0],[q,c0],[r,c1],[p,c0],[r,c1],[s,c1]])m.vertex(v,c,normal,0);
    }
  }
  function girl(m,style,reach=0){
    const looks={luma:{hair:'#7a4655',dress:'#88bca0',trim:'#e9d3b1',skin:'#f3cda8'},orin:{hair:'#cbcbc6',dress:'#9482b5',trim:'#e5cda2',skin:'#d6b897'},pip:{hair:'#62506c',dress:'#ce9dae',trim:'#f6d6af',skin:'#edc6a4'},keeper:{hair:'#95afa8',dress:'#4e8f91',trim:'#c5d4b0',skin:'#d5b293'}};
    const c=looks[style]||looks.luma;
    ellipsoid(m,0,25,-2,9.2,11.4,4.5,c.hair,0,18,10);
    for(const side of [-1,1]){
      ellipsoid(m,side*3.1,4,0,2.2,4,2.1,c.skin,0,10,7);ellipsoid(m,side*3.1,1.1,1,2.6,1.35,3,'#71675e',0,10,6);
    }
    ellipsoid(m,0,13,0,6.5,7.2,3.9,c.dress,0,16,10);ellipsoid(m,0,9.7,0,7.5,3.4,4.2,c.dress,0,16,7);
    tube(m,[[-5.9,9.1,2.8],[0,8.6,4.25],[5.9,9.1,2.8]],[.4,.4,.4],c.trim,.04,7);
    ellipsoid(m,0,21.1,.2,2.5,2.3,2.4,c.skin,0,10,6);
    for(const side of [-1,1]){
      const reachSide=side<0?reach:0,hand=[side*(8+reachSide*6),13-reachSide*7,.9+reachSide];
      tube(m,[[side*4.9,19.3,0],[side*(7.4+reachSide*2),16.4-reachSide*4,.8],hand],[2.4,1.7,1.35],c.skin,0,9);
      ellipsoid(m,side*5.2,18.2,0,2.8,3,2.7,c.dress,0,10,6);ellipsoid(m,...hand,1.55,1.9,1.3,c.skin,0,10,6);
    }
    ellipsoid(m,0,27.5,1,8.35,8.2,4.7,c.skin,0,20,13);
    for(const side of [-1,1]){
      ellipsoid(m,side*3.1,28,5.1,1.55,2.2,.35,'#fbf5dd',0,10,8);
      ellipsoid(m,side*3.1,27.6,5.45,.97,1.57,.2,'#353f49',0,10,8);
      ellipsoid(m,side*3.35-.18,28.35,5.63,.35,.44,.08,'#ffffff',.25,7,5);
      ellipsoid(m,side*5.25,24.75,5,.98,.48,.12,'#e8a1a0',.05,9,5);
      ellipsoid(m,side*7.4,22,-.7,2.5,8.7,3.1,c.hair,0,12,9);
    }
    tube(m,[[-1.2,23.8,5.43],[0,23.45,5.65],[1.2,23.8,5.43]],[.13,.15,.13],'#9b6b65',0,6);
    for(let i=-2;i<=2;i++)ellipsoid(m,i*2.8,33-Math.abs(i)*.6,3.5,2.6,2.8,2.5,c.hair,0,12,8);
    leaf(m,[5,34,2],[10,39,1],2.1,c.dress,0,.08,6);blossom(m,5.8,31.2,5.9,1.45,c.trim,1);
  }
  function frog(m){
    const green='#8fc19a';
    ellipsoid(m,0,6.5,0,9,6.6,5.5,green,0,16,10);
    ellipsoid(m,0,5,4.1,6.1,4.2,1.4,'#d9d8a6',0,14,8);
    for(const side of [-1,1]){
      ellipsoid(m,side*8,3,-1,4.7,3.9,4.2,'#70a78a',0,12,8);
      tube(m,[[side*5.5,6,3],[side*7,2,4],[side*6.5,1,6]],[1.5,1.2,.8],green,0,8);
      for(let toe=0;toe<3;toe++)ellipsoid(m,side*(6.1+toe*.8),.65,6.7+toe*.25,.55,.35,1.1,'#aecda0',0,7,5);
      ellipsoid(m,side*4.8,12.9,1.1,4,4,3.7,green,0,14,9);
      ellipsoid(m,side*4.8,13.3,4.35,2.6,2.7,.65,'#f2efce',0,12,8);
      ellipsoid(m,side*4.7,13.35,4.96,1.3,1.75,.3,'#34494b',0,10,8);
      ellipsoid(m,side*4.95-.3,14.05,5.21,.43,.57,.12,'#ffffff',.35,7,5);
      ellipsoid(m,side*6,8.25,5,.95,.55,.18,'#d6a2a1',0,8,5);
    }
    tube(m,[[-3.3,7.5,5.4],[0,6.4,5.8],[3.3,7.5,5.4]],[.17,.2,.17],'#496d60',0,7);
    ellipsoid(m,-1,11,-4.4,1.4,.9,.6,'#c1d4ad',0,8,5);
  }
  function fox(m){
    const fur='#d79975';
    tube(m,[[-4,7,-2],[-10,7,-3],[-15,11,-2],[-16,17,-1],[-13,22,0]],[3.1,4.4,5.2,3.8,.8],fur,0,13);
    tube(m,[[-16,17,-1],[-14,20,-.5],[-13,22,0]],[3.8,2.3,.6],'#f0dac0',0,12);
    ellipsoid(m,1,9,0,6.8,8.4,4.9,fur,0,16,11);
    ellipsoid(m,1,10,4,3.4,5.7,1.6,'#f0dbc0',0,12,8);
    for(const side of [-1,1]){
      ellipsoid(m,side*3.2+1,3.4,1,2.1,3.5,2.4,fur,0,10,7);ellipsoid(m,side*3.2+1,1,2,2.6,1.3,3.2,'#776151',0,10,6);
      tube(m,[[side*4.8,25.6,-.6],[side*6.3,30,0],[side*6.2,33,.3]],[3.8,2.2,.15],fur,0,12);
      tube(m,[[side*4.8,26,1.6],[side*6.2,30,1.5],[side*6.2,32,1]],[1.85,1,.05],'#edc7b7',0,9);
    }
    ellipsoid(m,0,22,0,8.4,7.6,5.1,fur,0,18,12);
    for(const side of [-1,1]){
      ellipsoid(m,side*3.2,19.5,4.2,3.8,2.8,1.7,'#f7e4c6',0,12,8);
      ellipsoid(m,side*3.5,23,4.7,1.1,1.45,.33,'#374447',0,10,8);
      ellipsoid(m,side*3.7-.25,23.6,4.95,.35,.44,.12,'#ffffff',.2,7,5);
      ellipsoid(m,side*5.2,21,4.7,.75,.3,.15,'#e5a3a0',0,8,5);
    }
    ellipsoid(m,0,19.8,5.55,1.15,.85,.65,'#475052',0,10,7);
    tube(m,[[-1.3,18.8,5.62],[0,18.1,5.76],[1.3,18.8,5.62]],[.12,.16,.12],'#7f675d',0,6);
  }
  const characterCache=new Map();
  function characterData(form,appearance,reach=0){
    const key=form+':'+appearance+':'+reach;if(characterCache.has(key))return characterCache.get(key);
    const m={a:[],vertex(p,c,n,g){this.a.push(...p,...c,...n,g);}};
    if(form==='frog')frog(m);else if(form==='fox')fox(m);else girl(m,appearance,reach);
    const data=new Float32Array(m.a);characterCache.set(key,data);return data;
  }
  function creature(m,record,t,cinematic){
    let x=record.x,y=record.y,z=record.z,reach=0,walk=0;
    if(record.id==='luma'&&cinematic&&cinematic.active){
      const time=cinematic.elapsed||0;
      if(time<3.25)x=154;
      else if(time<5.3){const q=ease((time-3.25)/2.05);x=mix(154,84,q);walk=Math.sin(q*Math.PI);}
      else if(time<6.2)x=84;
      else if(time<8.8){const q=ease((time-6.2)/2.6);x=mix(84,112,q);walk=Math.sin(q*Math.PI);}
      else x=mix(112,125,ease((time-10.8)/1.6));
      reach=ease((time-4.6)/.7)*(1-ease((time-6.2)/1.4));
    }
    const a=characterData(record.form||'girl',record.appearance||'luma',0),b=reach>0?characterData('girl',record.appearance||'luma',1):a;
    const frogForm=record.form==='frog',bob=Math.sin(t*(frogForm?1.7:1.2)+record.x)*.27+(walk?Math.abs(Math.sin(t*9))*walk*.9:0);
    const zScale=(record.depth||.6)/16;
    const out=m.a;
    for(let i=0;i<a.length;i+=10){
      const px=mix(a[i],b[i],reach),py=mix(a[i+1],b[i+1],reach),pz=mix(a[i+2],b[i+2],reach);
      out.push(x+px,y+py*(1+bob*.007)+bob*.18,z+pz*zScale,a[i+3],a[i+4],a[i+5],a[i+6],a[i+7],a[i+8],a[i+9]);
    }
  }
  function buildWorld(m,world){
    forestFloor(m);
    for(let i=-2;i<19;i++){const x=i*130+h(i+77)*37,z=-455-h(i+3)*150;tree(m,x,forestHeight(x,z)-2,z,1.4+h(i)*.75,i+70,true);}
    for(let i=-2;i<20;i++){const x=i*119+h(i+11)*31,z=-172-h(i+5)*145;tree(m,x,forestHeight(x,z)-2,z,.77+h(i+23)*.75,i+25,false);}
    // Lower arched crowns frame the rainforest during the elevated 3-D view.
    for(const [x,seed]of [[285,182],[1090,191],[1735,203]]){
      const z=-148;tree(m,x,forestHeight(x,z)-2,z,.56,seed,false);
    }
    for(const p of world.platforms)if(p.kind!=='bridge')platform(m,p);
    for(const o of world.obstacles)if(o.kind!=='gate')barrier(m,o);
    for(const n of [...world.npcs,...(world.creatures||[])])if(n.id!=='luma')creature(m,n,0,null);
    birthTree(m);
    for(let i=0;i<34;i++){
      const x=-100+i*67+h(i+66)*25;if(x>690&&x<1005)continue;
      const z=-60-h(i+13)*22,size=.56+h(i+18)*.40;
      fern(m,x,0,z,size,i+28,i%3===0?'#59897e':'#41806c');
      if(i%2===0)broadPlant(m,x+18,0,z-3,.6+h(i+44)*.45,i+15);
      if(i%3!==1)for(let j=0;j<3;j++)blossom(m,x-10+h(i+j)*20,0,z+8+h(i+j+40)*12,2.2+h(i+j)*2.9,i%2===0?'#dbabc8':'#aea6de',i+j);
      if(i%3===0){mushroom(m,x+24,0,z+8,6+h(i)*5,'#aeadde');mushroom(m,x+33,0,z+13,3.4+h(i)*2,'#d0b5cf');}
      if(i%4===0)ellipsoid(m,x-13,4,z+8,12,7,9,'#618976',0,14,8);
    }
    for(let i=0;i<30;i++){
      const x=-115+i*74+h(i+66)*24;if(x>690&&x<1005)continue;const z=68+h(i+18)*15;
      fern(m,x,0,z,.37+h(i)*.3,i+4,'#44836c');
      if(i%3===0)broadPlant(m,x-10,0,z+.5,.43+h(i)*.16,i+30);
      if(i%4===0)for(let j=0;j<3;j++)blossom(m,x+8+j*5,0,z-6+h(j+i)*5,2.1+h(j+i)*1.2,'#e4ccab',i+j);
      if(i%3!==1){ellipsoid(m,x-8,3,z+2,9,5,7,'#668777',0,12,8);ellipsoid(m,x-16,1.8,z-2,4,3,5,'#799987',0,10,6);}
    }
    // Luminous mushrooms and broad undergrowth join the layered forest banks.
    for(let i=0;i<13;i++){
      const x=-35+i*170+h(i+60)*47,z=-183-h(i+49)*23,y=forestHeight(x,z);
      mushroom(m,x,y,z,15+h(i+15)*9,i%2===0?'#9696ba':'#8bbdb1');
      mushroom(m,x+26,y,z+11,7+h(i)*5,'#b8a9d0');
      broadPlant(m,x-28,y,-176-h(i+49)*23,1.05+h(i)*.4,i+50);
    }
    // A living arch, with branches and petals, frames the chapter's destination.
    for(const side of [-1,1]){
      tube(m,[[1839+side*37,0,-38],[1839+side*36,31,-39],[1839+side*29,64,-38],[1839+side*13,85,-36],[1839,88,-34]],[6,5.3,4.3,2.4,.6],'#8ca18d',0,12);
      for(let j=0;j<4;j++){const y=24+j*15,x=1839+side*(37-j*6);leaf(m,[x,y,-37],[x+side*16,y+15,-31],6.2,j%2===0?'#8ab99a':'#bdaccc',j,0,7);}
      blossom(m,1839+side*20,72,-31,4.1,'#e4b9cf',side);
    }
    return m;
  }
  function dynamic(m,world,state){
    const p=state.player,t=state.time||0,d=state.dimensionBlend||0;
    if(d>.03){
      const bridge=world.platforms.find(b=>b.kind==='bridge');
      if(bridge){
        const data=cached('bridge',local=>{
          platform(local,bridge,1);
          for(let i=0;i<12;i++){const x=bridge.x+12+i*24;disk(local,x,.25,bridge.z+bridge.d*.5,7,6,'#b2d3b5',.2,12);}
          for(const z of [bridge.z+2,bridge.z+bridge.d-2])tube(local,[[bridge.x,-3,z],[bridge.x+bridge.w*.33,-8,z],[bridge.x+bridge.w*.67,-8,z],[bridge.x+bridge.w,-3,z]],[2,2.6,2.6,2],'#77a69a',.2,8);
        });append(m,data,0,0,0,d,1);
      }
    }
    if(p&&p.grounded)shadow(m,p.x,p.y+.17,p.z,9,5);
    if(d>.02){
      for(let i=-9;i<22;i++){const x=Math.floor(state.cameraX/22)*22+i*22;const supported=world.platforms.some(b=>b.kind==='earth'&&x>=b.x&&x<=b.x+b.w);if(supported)disk(m,x,.2,0,3.4,.5,blend('#527c69','#a5d5b0',d),.18,10);}
    }
    for(const n of world.npcs)if(n.id==='luma'&&Math.abs(n.x-state.cameraX)<610)creature(m,n,t,state.cinematic);
    lantern(m,world.beacon.x,0,0,state.beaconLit);
    for(let i=0;i<world.checkpoints.length;i++){const cp=world.checkpoints[i];if(Math.abs(cp.x-state.cameraX)<650)lantern(m,cp.x+20,0,-26,state.checkpointIndex>=i);}
    for(const o of world.obstacles)if(o.kind==='gate')barrier(m,o,(state.gateOpen||0)*145);
    for(let i=0;i<(state.reduced?15:30);i++){
      const x=state.cameraX-320+h(i+3)*670+Math.sin(t*.16+i)*11,y=9+h(i+80)*145+Math.sin(t*.7+i)*5,z=-110+h(i+6)*200;
      const s=(.4+h(i)*.85)*(state.reduced?.8:1);ellipsoid(m,x,y,z,s,s*.9,s,i%4===0?'#edc6d6':'#c4eed0',.75,6,4);
    }
    if(state.beaconLit)for(let i=0;i<9;i++){const a=i/9*TAU+t*.15;ellipsoid(m,1839+Math.cos(a)*18,41+Math.sin(a)*26,-32,1.4,1.8,1.1,'#d7f5be',.9,6,4);}
    return m;
  }
  window.TD_RAINFOREST=Object.freeze({buildWorld,dynamic,barrier,lantern,
    orb:(m,x,y,z,r,col,glow=0)=>ellipsoid(m,x,y,z,r,r,r,col,glow,10,7),
    shadow,
    // Read-only creation helpers are also used by visual diagnostics.
    ellipsoid,leaf,tree,characterData,
    style:'smooth mystical rainforest',creatureDepth:.6});
})();
