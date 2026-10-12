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
  // Semantic materials are consumed by the native scene shader. A triangle
  // always carries one material; positive values are reserved for light.
  const MAT=Object.freeze({leaf:-1,skin:-2,hair:-3,cloth:-4,stone:-5,wood:-6,soil:-7,eye:-8,path:-9});
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
  function sculpt(m,point,col,material,sides=24,rings=14){
    const grid=[],closedEnd=Math.hypot(...sub(point(0,Math.PI-.00001),point(1,Math.PI-.00001)))<.01;
    for(let row=0;row<=rings;row++){
      const b=clamp(row/rings*Math.PI,.00001,Math.PI-.00001);grid[row]=[];
      for(let side=0;side<=sides;side++){
        const a=side/sides*TAU,p=point(a,b),da=sub(point(a+.004,b),point(a-.004,b)),db=sub(point(a,Math.min(Math.PI-.000001,b+.004)),point(a,Math.max(.000001,b-.004)));
        grid[row].push({p,n:norm(cross(da,db)),c:typeof col==='function'?col(a,b,p):color(col)});
      }
    }
    for(let j=0;j<rings;j++)for(let i=0;i<sides;i++){
      const a=grid[j][i],b=grid[j][i+1],c=grid[j+1][i+1],d=grid[j+1][i];
      const vertices=j===0?[a,c,d]:j===rings-1&&closedEnd?[a,b,c]:[a,b,c,a,c,d];
      for(const v of vertices)m.vertex(v.p,v.c,v.n,material);
    }
  }
  function profile(m,levels,col,material,sides=24,scallop=0){
    const grid=levels.map(([y,rx,rz],j)=>Array.from({length:sides+1},(_,i)=>{
      const a=i/sides*TAU,prev=levels[Math.max(0,j-1)],next=levels[Math.min(levels.length-1,j+1)];
      const flare=1+scallop*Math.cos(a*7)*Math.max(0,1-j/3),yy=y+scallop*.7*Math.cos(a*7)*Math.max(0,1-j/2);
      return {p:[Math.cos(a)*rx*flare,yy,Math.sin(a)*rz*flare],n:norm([Math.cos(a)/Math.max(rx,.1),-(next[1]-prev[1])/Math.max(.1,(next[0]-prev[0])*rx),Math.sin(a)/Math.max(rz,.1)]),c:shade(col,.96+.06*Math.sin(a*7))};
    }));
    for(let j=0;j<grid.length-1;j++)for(let i=0;i<sides;i++)for(const p of [grid[j][i],grid[j][i+1],grid[j+1][i+1],grid[j][i],grid[j+1][i+1],grid[j+1][i]])m.vertex(p.p,p.c,p.n,material);
  }
  function rock(m,x,y,z,rx,ry,rz,col,seed=0){
    sculpt(m,(a,b)=>{const sn=Math.sin(b),q=1+.055*Math.sin(a*3+b*5+seed)+.035*Math.cos(a*5-b*3+seed);return[x+Math.cos(a)*sn*rx*q,y+Math.cos(b)*ry*q,z+Math.sin(a)*sn*rz*q];},(a,b)=>blend(shade(col,.84),shade(col,1.13),.5+.28*Math.cos(b)+.15*Math.sin(a*4+seed)),MAT.stone,14,9);
    // A velvet moss crown follows the upper rock, with a soft irregular hem.
    if(rx>7)sculpt(m,(a,b)=>{const u=b*.39,sn=Math.sin(u),q=1+.035*Math.sin(a*5+seed);return[x+Math.cos(a)*sn*rx*q,y+Math.cos(u)*ry+.13,z+Math.sin(a)*sn*rz*q];},'#668b65',MAT.leaf,14,5);
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
  function leaf(m,base,tip,width,col,seed=0,glow=MAT.leaf,steps=8){
    if(glow>=0&&glow<.4)glow=MAT.leaf;
    const axis=norm(sub(tip,base)),span=norm(cross(axis,[0,0,1]));
    const midpoint=base.map((v,i)=>mix(v,tip[i],.48));midpoint[1]+=width*.65;midpoint[2]-=width*.24;
    const grid=[];
    for(let row=0;row<=steps;row++){
      const t=row/steps,wt=Math.pow(Math.sin(Math.PI*t),.82)*width;
      const center=base.map((v,i)=>(1-t)*(1-t)*v+2*(1-t)*t*midpoint[i]+t*t*tip[i]);
      grid[row]=[-1,-.5,0,.5,1].map(u=>{
        const p=center.map((v,i)=>v+span[i]*u*wt);
        p[2]+=(1-u*u)*Math.sin(Math.PI*t)*width*.3+u*u*width*.12*Math.sin(t*4+seed);
        p[1]+=Math.abs(u)*Math.sin(t*9+seed)*width*.035;
        const n=norm([span[0]*u*.48,.36+Math.sin(t*Math.PI)*.3,.85]);
        return{p,n,c:blend(shade(col,.78+.13*t),shade(col,1.10),1-Math.abs(u))};
      });
    }
    for(let row=0;row<steps;row++)for(let colI=0;colI<4;colI++){
      const a=grid[row][colI],b=grid[row][colI+1],c=grid[row+1][colI+1],d=grid[row+1][colI];
      for(const v of [a,b,c,a,c,d])m.vertex(v.p,v.c,v.n,glow);
    }
    if(width>=3){const vein=[];for(let i=0;i<=4;i++){const t=i/4;const p=base.map((v,k)=>(1-t)*(1-t)*v+2*(1-t)*t*midpoint[k]+t*t*tip[k]);p[2]+=Math.sin(Math.PI*t)*width*.32+.22;vein.push(p);}
      tube(m,vein,[width*.018,width*.017,width*.013,width*.009,.025],shade(col,1.23),glow,5);
      if(width>7)for(let j=1;j<4;j++)for(const side of [-1,1]){
        const t=j/5,p=base.map((v,k)=>(1-t)*(1-t)*v+2*(1-t)*t*midpoint[k]+t*t*tip[k]);p[2]+=Math.sin(Math.PI*t)*width*.3+.15;
        const tt=t+.11,q=base.map((v,k)=>(1-tt)*(1-tt)*v+2*(1-tt)*tt*midpoint[k]+tt*tt*tip[k]+span[k]*side*Math.sin(Math.PI*tt)*width*.75);q[2]+=.12*width;
        tube(m,[p,q],[width*.009,.018],shade(col,1.11),glow,4);
      }
    }
  }
  function fern(m,x,y,z,size,seed=0,col='#398670'){
    for(let frond=0;frond<4;frond++){
      const side=frond<2?-1:1,angle=(frond-2)*.34,reach=(12+h(seed+frond)*15)*size;
      const tip=[x+Math.sin(angle)*reach*1.6,y+reach*(.65+h(frond)*.35),z+Math.cos(frond)*5*size];
      const middle=[mix(x,tip[0],.4),mix(y,tip[1],.65),mix(z,tip[2],.5)];
      tube(m,[[x,y,z],middle,tip],[.45*size,.35*size,.04],shade(col,.9),MAT.leaf,5);
      for(let j=1;j<5;j++){
        const t=j/6,b=[mix(x,tip[0],t),mix(y,tip[1],t),mix(z,tip[2],t)];
        for(const s of [-1,1]){const l=(1-t*.7)*7.2*size;leaf(m,b,[b[0]+s*l,b[1]+l*.35,b[2]+side*.45],l*.22,shade(col,.85+j*.04),seed+j+s,0,4);}
      }
    }
  }
  function broadPlant(m,x,y,z,size,seed=0){
    const palette=['#4b8865','#326e58','#6b9878','#44776b','#547671'];
    for(let j=0;j<6;j++){
      const a=(j/5-.5)*2.5,reach=(17+h(seed+j)*18)*size;
      const tip=[x+Math.sin(a)*reach,y+(12+Math.cos(a)*20)*size,z-6*size+Math.sin(j*1.9)*7*size];
      const start=[x,y+.7,z],base=[mix(x,tip[0],.18),y+5*size,mix(z,tip[2],.25)];
      tube(m,[start,base],[.6*size,.4*size],shade(palette[j%5],.8),MAT.leaf,5);
      leaf(m,base,tip,(4.2+h(seed+j+20)*3)*size,palette[(j+seed)%5],seed+j,.02,9);
    }
  }
  function blossom(m,x,y,z,size,col='#e8a2c7',seed=0){
    const cy=y+size*3;
    tube(m,[[x,y,z],[x+size*.25,y+size*1.8,z-.25],[x,cy,z]],[size*.11,size*.09,.03],'#568560',MAT.leaf,5);
    for(let i=0;i<5;i++){
      const a=i/5*TAU+seed,ux=Math.cos(a),uy=Math.sin(a);
      sculpt(m,(u,v)=>{const s=Math.sin(v),rad=.7+.08*Math.cos(u*3);return[x+ux*size*.59+Math.cos(u)*s*size*.46+ux*Math.cos(v)*size*.45,cy+uy*size*.59+Math.sin(u)*s*size*.35+uy*Math.cos(v)*size*.45,z+size*.15+s*size*.24+Math.cos(v)*size*.13];},(u,v)=>blend(col,'#fff0dd',.18+.28*Math.sin(v)),MAT.leaf,8,5);
    }
    ellipsoid(m,x,cy,z+size*.37,size*.24,size*.24,size*.14,'#efbc69',.28,8,5);
    if(size>2)for(let j=0;j<5;j++){const a=j/5*TAU;ellipsoid(m,x+Math.cos(a)*size*.14,cy+Math.sin(a)*size*.14,z+size*.51,size*.055,size*.055,size*.04,'#fff1bd',.5,5,3);}
    if(size>3)leaf(m,[x,y+size,z],[x+size*1.25,y+size*1.7,z+.1],size*.43,'#689471',seed,MAT.leaf,4);
  }
  function mushroom(m,x,y,z,size,col='#b897e0'){
    tube(m,[[x,y,z],[x-size*.12,y+size*.55,z],[x-size*.10,y+size*1.25,z],[x,y+size*1.58,z]],[size*.19,size*.15,size*.12,size*.15],'#bfc4a8',MAT.leaf,9);
    sculpt(m,(a,b)=>{const s=Math.sin(b),q=1+.035*Math.cos(a*7);return[x+Math.cos(a)*s*size*q,y+size*1.67+Math.cos(b)*size*.43,z+Math.sin(a)*s*size*.82*q];},(a,b)=>blend(col,'#e8d7ca',Math.pow(Math.sin(b),6)*.36),MAT.leaf,size>10?22:14,size>10?10:7);
    ellipsoid(m,x,y+size*1.62,z,size*.89,size*.065,size*.71,'#a9dec2',.36,14,4);
    if(size>5)for(let i=0;i<12;i++){
      const a=i/12*TAU;tube(m,[[x+Math.cos(a)*size*.17,y+size*1.565,z+Math.sin(a)*size*.14],[x+Math.cos(a)*size*.84,y+size*1.605,z+Math.sin(a)*size*.68]],[size*.016,size*.008],'#d1ecd0',.24,4);
    }
    for(let i=0;i<5;i++){const a=i*2.3,q=.28+h(i+size)*.36;ellipsoid(m,x+Math.cos(a)*size*q,y+size*(1.67+Math.sqrt(1-q*q)*.435),z+Math.sin(a)*size*q*.8,size*.07,size*.027,size*.08,'#eee1c5',MAT.leaf,6,4);}
  }
  function outline(x,z,w,d,r,samples=6){
    const out=[],centers=[[x+w-r,z+d-r,0],[x+r,z+d-r,Math.PI/2],[x+r,z+r,Math.PI],[x+w-r,z+r,Math.PI*1.5]];
    for(const [cx,cz,start]of centers)for(let i=0;i<samples;i++){const a=start+i/(samples-1)*Math.PI/2;out.push([cx+Math.cos(a)*r,cz+Math.sin(a)*r]);}
    return out;
  }
  function platform(m,p,bridgeBlend=1){
    const top=p.y+p.h,r=Math.min(p.d*.24,p.w*.18,20),edge=outline(p.x,p.z,p.w,p.d,r,9),cx=p.x+p.w/2,cz=p.z+p.d/2;
    const stone=p.kind==='stone',bridge=p.kind==='bridge',topColor=stone?'#99aa96':bridge?'#82a594':'#426b51';
    const rings=bridge?[{y:top,s:1,c:topColor},{y:top-2*bridgeBlend,s:1,c:'#5a7b64'},{y:p.y*bridgeBlend,s:.98,c:'#354f44'}]:[
      {y:top,s:1,c:topColor},{y:top-3,s:1,c:stone?'#7c8c7d':'#3d614b'},
      {y:top-Math.min(13,p.h*.35),s:.995,c:stone?'#5c7065':'#4b5740'},
      {y:p.y,s:.94,c:stone?'#40574e':'#303e32'}];
    for(let j=0;j<edge.length;j++){
      const k=(j+1)%edge.length;
      triangle(m,[cx,top,cz],[edge[j][0],top,edge[j][1]],[edge[k][0],top,edge[k][1]],topColor,[0,1,0],[0,1,0],[0,1,0],stone||bridge?MAT.stone:MAT.soil);
    }
    for(let row=0;row<rings.length-1;row++)for(let j=0;j<edge.length;j++){
      const k=(j+1)%edge.length,ring=(point,r)=>[mix(cx,point[0],r.s),r.y,mix(cz,point[1],r.s)];
      const a=ring(edge[j],rings[row]),b=ring(edge[k],rings[row]),c=ring(edge[k],rings[row+1]),d=ring(edge[j],rings[row+1]);
      const na=norm([a[0]-cx,(row===0?.6:.04)*Math.max(p.w,p.d),a[2]-cz]),nb=norm([b[0]-cx,(row===0?.6:.04)*Math.max(p.w,p.d),b[2]-cz]);
      triangle(m,a,b,c,rings[row].c,na,nb,nb,stone||bridge?MAT.stone:MAT.soil);triangle(m,a,c,d,rings[row].c,na,nb,na,stone||bridge?MAT.stone:MAT.soil);
    }
    if(bridge){
      for(let j=0;j<12;j++){
        const xx=p.x+11+j*24,zz=p.z+p.d*.5;rock(m,xx,top-.2,zz,12,1.7,13.0,'#96ae96',j+401);
        leaf(m,[xx-10,top+.03,zz-11],[xx+9,top+.06,zz-8],2.6,'#6c957d',j,MAT.leaf,5);
      }
      return;
    }
    if(!stone){
      // The soil continues naturally into the forest. Only solid land spans
      // receive this rear bank; the broken road remains a visible real gap.
      const rows=Math.ceil(p.w/24),depthRows=6;
      const bank=(i,j)=>{
        const x=p.x+i/rows*p.w,z=mix(p.z+.6,-169,j/depthRows),q=j/depthRows;
        const yy=mix(top+.012,forestHeight(x,-169)+.06,ease(q)),n=norm([0,1,.15*Math.sin(q*Math.PI)]);
        return{p:[x,yy,z],n,c:blend('#426b51','#335e49',ease(q))};
      };
      for(let i=0;i<rows;i++)for(let j=0;j<depthRows;j++)for(const v of [bank(i,j),bank(i+1,j),bank(i+1,j+1),bank(i,j),bank(i+1,j+1),bank(i,j+1)])m.vertex(v.p,v.c,v.n,MAT.soil);
      for(let i=0;i<p.w/53;i++){
        const x=p.x+13+i*53,zz=p.z+p.d-3;
        tube(m,[[x,top-2,zz],[x+5,top-13,zz+1],[x+1,top-25-h(i)*16,zz-2],[x+8,top-43-h(i+5)*15,zz-8]],[2.5,1.7,.9,.09],'#6a7251',MAT.wood,7);
        if(i%2===0)leaf(m,[x+3,top-17,zz],[x+12,top-29,zz+1],3.5,'#688155',i,MAT.leaf,5);
        rock(m,x+17,top-12,zz-2,8,5,3,'#586551',i+50);
      }
      // Warm compacted earth winds through the cool moss; feathered edges are
      // part of the mesh, not hard rectangular decals or stepped tiles.
      const pathRows=Math.ceil(p.w/11),slices=8;
      const trail=(i,j)=>{
        const xx=p.x+i/pathRows*p.w,t=j/slices,u=t*2-1,center=Math.sin(xx*.015)*6.4+Math.sin(xx*.047)*.75,radius=12.8+Math.sin(xx*.021)*1.8;
        return{p:[xx,top+.052+(1-u*u)*.012,center+u*radius],c:blend('#6f7352','#426b51',Math.pow(Math.abs(u),2.7)),n:[0,1,0]};
      };
      for(let i=0;i<pathRows;i++)for(let j=0;j<slices;j++)for(const v of [trail(i,j),trail(i+1,j),trail(i+1,j+1),trail(i,j),trail(i+1,j+1),trail(i,j+1)])m.vertex(v.p,v.c,v.n,MAT.path);
      for(let i=0;i<p.w/26;i++){
        const xx=p.x+14+i*26,zz=(h(i+p.x+88)-.5)*(p.d-20),seed=i+p.x,rx=8+h(seed)*15,rz=5+h(seed+8)*7;
        if(Math.abs(zz)<20)continue;
        const center=blend('#527747','#63865b',h(seed+17));
        for(let j=0;j<16;j++){
          const a=j/16*TAU,b=(j+1)/16*TAU,rA=.84+h(j+seed)*.18,rB=.84+h(j+1+seed)*.18;
          m.vertex([xx,top+.046,zz],color(center),[0,1,0],MAT.soil);
          m.vertex([xx+Math.cos(a)*rx*rA,top+.038,zz+Math.sin(a)*rz*rA],color('#426b51'),[0,1,0],MAT.soil);
          m.vertex([xx+Math.cos(b)*rx*rB,top+.038,zz+Math.sin(b)*rz*rB],color('#426b51'),[0,1,0],MAT.soil);
        }
      }
      for(let i=0;i<p.w/43;i++){
        const xx=p.x+19+i*43,zz=Math.sin(xx*.015)*6.4+(i%2?1:-1)*(15+h(i+3)*6);
        rock(m,xx,top+.35,zz,1.4+h(i)*1.5,.65+h(i)*.7,1.2,'#9eab85',i);
        if(i%3===0)leaf(m,[xx-2,top+.10,zz],[xx+3,top+.13,zz+2],1.4,'#bdab66',i,MAT.leaf,4);
      }
    }else{
      rock(m,cx,top-1.3,cz,Math.max(3,p.w*.35),1.65,p.d*.32,'#a6b099',p.x);
      if(p.id==='lookout')mushroom(m,p.x+8,top,p.z+8,4,'#b5aec0');
      for(let side=0;side<2;side++)tube(m,[[p.x+8+side*16,top-2,p.z+p.d],[p.x+10+side*16,top-6,p.z+p.d+.2],[p.x+9+side*16,top-11,p.z+p.d]],[.3,.22,.05],'#74826b',MAT.stone,5);
    }
  }
  function tree(m,x,y,z,size,seed=0,distant=false){
    const tall=(125+h(seed)*65)*size,bend=(h(seed+3)-.5)*22*size;
    const bark=distant?'#344f4c':seed%3===0?'#756453':'#5d6850';
    const pts=[[x,y,z],[x-3*size,y+tall*.24,z-2*size],[x+bend*.3,y+tall*.52,z],[x+bend,y+tall*.8,z-4*size],[x+bend*.7,y+tall,z-2*size]];
    tube(m,pts,[9*size,7.8*size,6*size,3.8*size,1.2*size],bark,MAT.wood,distant?10:16);
    if(!distant){
      for(let j=0;j<5;j++){const a=j*1.29+seed;const dx=Math.cos(a)*26*size,dz=Math.sin(a)*17*size;tube(m,[[x,y+15*size,z],[x+dx*.32,y+4*size,z+dz*.32],[x+dx*.67,y+.7,z+dz*.64],[x+dx,y-.8,z+dz]],[3.9*size,2.7*size,1.4*size,.14],shade(bark,.87),MAT.wood,9);}
      const vine=pts.map((p,i)=>[p[0]+Math.cos(i*1.6)*7*size,p[1],p[2]+Math.sin(i*1.6)*7*size]);tube(m,vine,[1.05*size,1.0*size,.9*size,.6*size,.09],'#7d8e60',MAT.leaf,6);
      // Long, offset cambium ridges and a small knot unify the tapered trunk.
      for(let j=0;j<7;j++){
        const angle=j/6*Math.PI,rr=[9.05,7.85,6.03,3.85,1.22];
        const ridge=pts.map((p,i)=>[p[0]+Math.cos(angle+i*.035)*rr[i]*size,p[1]+Math.sin(j+i)*size,p[2]+Math.sin(angle+i*.035)*rr[i]*size]);
        tube(m,ridge,[.30*size,.34*size,.25*size,.16*size,.04],shade(bark,j%2===0?1.15:.83),MAT.wood,5);
      }
      if(seed%3===0){
        const knot=[];for(let j=0;j<=14;j++){const a=j/14*TAU;knot.push([x-1.6*size+Math.cos(a)*2.1*size,y+39*size+Math.sin(a)*4.2*size,z+7.5*size]);}
        tube(m,knot,.40*size,shade(bark,.72),MAT.wood,6);
        tube(m,[[x-1.7*size,y+41.3*size,z+7.6*size],[x-1.0*size,y+38.7*size,z+7.6*size],[x-2.0*size,y+37*size,z+7.6*size]],[.34*size,.43*size,.09],shade(bark,.6),MAT.wood,6);
      }
    }
    for(let side=0;side<3;side++){
      const direction=side===0?-1:1,start=pts[2+side%2],end=[x+bend+direction*(32+side*9)*size,y+tall*(.8+side*.1),z-8*size+side*4];
      tube(m,[start,[mix(start[0],end[0],.4),end[1]-9*size,mix(start[2],end[2],.5)],end],[3*size,2*size,.5*size],bark,MAT.wood,9);
      const leafColors=distant?['#2c5551','#345f51','#325752']:['#3c6d53','#578761','#749872','#57765e'];
      for(let k=0;k<4;k++){
        const a=k/4*TAU+side*.7,tip=[end[0]+Math.cos(a)*(44+h(seed+k)*18)*size,end[1]+(14+Math.sin(a)*23)*size,end[2]+Math.sin(a)*(21+side*3)*size];
        leaf(m,end,tip,(9+h(k+seed)*6)*size,leafColors[(k+side)%leafColors.length],seed+k,0,distant?5:8);
      }
      if(!distant&&side===0&&seed%2===0){
        const len=(30+h(seed+19)*29)*size,vine=[];
        for(let k=0;k<6;k++)vine.push([end[0]+Math.sin(k*.85)*5*size,end[1]-k/5*len,end[2]+4*size]);
        tube(m,vine,[.55*size,.51*size,.45*size,.36*size,.24*size,.05],'#69825c',MAT.leaf,6);
        for(let k=1;k<5;k++){const p=vine[k],side=k%2?1:-1;leaf(m,p,[p[0]+side*10*size,p[1]-5*size,p[2]+2*size],3.1*size,'#7a996c',seed+k,MAT.leaf,5);}
      }
    }
    if(!distant&&seed%3===1)for(let j=0;j<3;j++)blossom(m,x+bend-11*size+j*11*size,y+tall-7*size,z+4*size,2.1*size,'#d0a2d2',j);
  }
  function birthTree(m){
    tube(m,[[14,0,-25],[11,29,-24],[17,61,-22],[26,83,-19],[39,105,-18],[35,136,-20]],[12,11,9,6,3,1.2],'#706f54',MAT.wood,18);
    for(const side of [-1,1])tube(m,[[14,13,-25],[14+side*12,2,-15],[14+side*25,0,-12]],[6,4,.6],'#65634c',MAT.wood,10);
    tube(m,[[26,83,-19],[44,95,-13],[60,101,-6],[74,99,0]],[4.7,3.8,2,.55],'#929675',MAT.wood,14);
    for(let j=0;j<6;j++){const a=j/5*Math.PI;const pts=[[14+Math.cos(a)*12,1,-25+Math.sin(a)*12],[11+Math.cos(a)*11,29,-24+Math.sin(a)*11],[17+Math.cos(a)*9,61,-22+Math.sin(a)*9],[26+Math.cos(a)*6,83,-19+Math.sin(a)*6],[39+Math.cos(a)*3,105,-18+Math.sin(a)*3]];tube(m,pts,[.42,.43,.37,.20,.04],j%2?'#858167':'#5c624a',MAT.wood,6);}
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
      const c=blend('#294c40','#416348',.3+.4*Math.sin(x*.008+z*.015));return{p:[x,y,z],n,c};
    };
    const rows=Array.from({length:zn+1},(_,j)=>Array.from({length:xn+1},(_,i)=>v(i,j)));
    for(let j=0;j<zn;j++)for(let i=0;i<xn;i++){
      const a=rows[j][i],b=rows[j][i+1],c=rows[j+1][i+1],d=rows[j+1][i];for(const p of [a,b,c,a,c,d])m.vertex(p.p,p.c,p.n,MAT.soil);
    }
    // Rounded low banks root every distant trunk in the forest floor.
    for(let i=0;i<31;i++){
      const x=-400+i*100,z=-176-h(i+70)*20,y=forestHeight(x,z);
      sculpt(m,(a,b)=>{const sn=Math.sin(b),q=1+.025*Math.cos(a*3+b*7+i);return[x+Math.cos(a)*sn*(65+h(i)*38)*q,y-9+Math.cos(b)*(17+h(i+2)*19),z+Math.sin(a)*sn*45];},'#3c6348',MAT.soil,16,9);
      if(i%3===0)rock(m,x+25,y-3,z+15,19,13,16,'#697e61',i+160);
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
      const c=blend(gate?'#8c9a9b':'#829987',gate?'#c3b2bb':'#c1c49d',row/rings);
      for(const [arr,normal]of [[front,[0,0,1]],[back,[0,0,-1]]]){
        const a=arr[row][j],b=arr[row][j+1],c0=arr[row+1][j+1],d=arr[row+1][j];triangle(m,a,b,c0,c,normal,normal,normal,MAT.cloth);triangle(m,a,c0,d,c,normal,normal,normal,MAT.cloth);
      }
      if(j===0||j===1){const side=j===0?0:2;triangle(m,front[row][side],back[row][side],back[row+1][side],shade(c,.85),[side===0?-1:1,0,0]);triangle(m,front[row][side],back[row+1][side],front[row+1][side],shade(c,.85),[side===0?-1:1,0,0]);}
    }
    const vein=[];for(let i=0;i<6;i++)vein.push([cx+Math.sin(i*.6)*.7,base+3+i*(o.h-6)/5,z+o.d*.5+.11]);tube(m,vein,[.45,.55,.63,.62,.43,.05],'#dfc487',.35,7);
    for(let i=2;i<9;i++){const yy=base+i*o.h/10,spread=Math.pow(Math.sin(i/10*Math.PI),.45)*o.w*.44;for(const side of [-1,1])tube(m,[[cx,yy,z+o.d*.5+.15],[cx+spread*side*.5,yy+4,z+o.d*.5+.15],[cx+spread*side,yy+9,z+o.d*.5+.12]],[.35,.28,.03],'#cce0c4',.18,5);}
    for(const side of [-1,1]){
      tube(m,[[cx,base,z],[cx+side*o.w*.48,base+o.h*.25,z],[cx+side*o.w*.49,base+o.h*.65,z],[cx,base+o.h,z]],[.65,.70,.58,.08],'#c8cba2',.22,9);
      const filigree=[];for(let j=0;j<=20;j++){const q=j/20*Math.PI*1.8,r=(1-j/25)*3.0;filigree.push([cx+side*(4+Math.cos(q)*r),base+o.h*.48+Math.sin(q)*r*2,z+o.d*.5+.16]);}tube(m,filigree,.11,'#e9d7a7',.26,5);
    }
    for(const [height,radius]of [[.28,1.6],[.63,2.0],[.80,1.3]]){
      const yy=base+o.h*height,lozenge=[[cx,yy+radius*1.8,z+1.18],[cx+radius,yy,z+1.18],[cx,yy-radius*1.8,z+1.18],[cx-radius,yy,z+1.18],[cx,yy+radius*1.8,z+1.18]];
      tube(m,lozenge,.15,'#f0dca5',.36,6);
    }
  }
  function barrier(m,o,lift=0){
    const data=cached('barrier:'+o.kind+':'+o.w+':'+o.h+':'+o.d,local=>barrierShape(local,{...o,x:0,y:0,z:0}));append(m,data,o.x,o.y+lift,o.z);
  }
  function lanternShape(m,x,y,z,lit=false){
    rock(m,x,y+1,z,7,2.3,6,'#8d9977',17);
    tube(m,[[x,y+1,z],[x-1.5,y+10,z],[x-1.0,y+21,z],[x+2.7,y+34,z],[x+1.3,y+43,z],[x-4,y+44.0,z],[x-5.1,y+40,z]],[2.25,1.95,1.7,1.28,.85,.65,.16],'#788363',MAT.wood,12);
    tube(m,[[x-1,y+4,z+1.7],[x+.5,y+13,z+1.5],[x-1.9,y+23,z+1.4],[x+.8,y+32,z+1.0]],[.36,.34,.29,.13],'#c2b17b',MAT.wood,6);
    for(const side of [-1,1])leaf(m,[x,y+17,z],[x+side*10,y+27,z-1],3.7,'#708e67',side,MAT.leaf,7);
    const cy=y+34,core=lit?'#f3cd82':'#607666';
    ellipsoid(m,x,cy,z+1,4.4,6.5,3.9,core,lit?.66:MAT.stone,18,12);
    // Fine curved ribs surround the amber seed and terminate in a leafy crown.
    for(let k=0;k<6;k++){
      const a=k/6*TAU,dx=Math.cos(a),dz=Math.sin(a),rib=[[x+dx*1.0,cy-7.0,z+1+dz],[x+dx*4.75,cy-3.8,z+1+dz*4.2],[x+dx*5.1,cy+2.0,z+1+dz*4.55],[x+dx*2.0,cy+6.5,z+1+dz*1.8]];
      tube(m,rib,[.31,.32,.27,.09],lit?'#c0b77d':'#849878',MAT.wood,7);
      leaf(m,rib[3],[x+dx*7.5,cy+8.1,z+1+dz*6.0],2.2,'#7e9c74',k,MAT.leaf,6);
    }
    for(const off of [-6.1,5.6]){const ring=[];for(let j=0;j<=18;j++){const a=j/18*TAU;ring.push([x+Math.cos(a)*2.15,cy+off,z+1+Math.sin(a)*1.9]);}tube(m,ring,.32,'#b7aa76',MAT.wood,7);}
    if(lit){ellipsoid(m,x-1.3,cy+1,z+3.8,1.7,3.0,1.2,'#fff0b7',.93,12,8);ellipsoid(m,x+.4,cy-2.8,z+4.0,.52,.71,.32,'#fff8d1',.90,8,5);}
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
  const looks={
    luma:{hair:'#754838',highlight:'#a77855',dress:'#82aa83',dark:'#456856',trim:'#efe0ba',skin:'#f0c7a6',cheek:'#e4a28d',iris:'#7c9e81',shoe:'#7b6150'},
    orin:{hair:'#a9b8b6',highlight:'#dce1ce',dress:'#847cab',dark:'#555d7c',trim:'#dfcda2',skin:'#d9b693',cheek:'#c88a79',iris:'#739bb0',shoe:'#5c5761'},
    pip:{hair:'#494047',highlight:'#786272',dress:'#c38689',dark:'#965d70',trim:'#efdab4',skin:'#e3ba98',cheek:'#d88c7d',iris:'#ac845e',shoe:'#665448'},
    keeper:{hair:'#8caa9a',highlight:'#b5c6ad',dress:'#508b86',dark:'#365f68',trim:'#dfc897',skin:'#cea88a',cheek:'#bf8176',iris:'#9c9965',shoe:'#526357'}
  };
  function lens(m,x,y,z,rx,ry,depth,col,material=MAT.eye,sides=20,rings=4){
    const grid=[];
    for(let j=0;j<=rings;j++){
      const r=j/rings;grid[j]=[];
      for(let i=0;i<=sides;i++){
        const a=i/sides*TAU,c=typeof col==='function'?col(r,a):color(col);
        grid[j].push({p:[x+Math.cos(a)*r*rx,y+Math.sin(a)*r*ry,z+depth*Math.sqrt(Math.max(0,1-r*r))],n:norm([Math.cos(a)*r*.4,Math.sin(a)*r*.4,1]),c});
      }
    }
    for(let j=0;j<rings;j++)for(let i=0;i<sides;i++)for(const v of (j===0?[grid[j][i],grid[j+1][i],grid[j+1][i+1]]:[grid[j][i],grid[j+1][i],grid[j+1][i+1],grid[j][i],grid[j+1][i+1],grid[j][i+1]]))m.vertex(v.p,v.c,v.n,material);
  }
  function eye(m,x,y,z,rx,ry,iris,blink=0){
    const open=1-blink,hh=Math.max(.065,ry*open),r=rx;
    lens(m,x,y,z,r*1.11,hh*1.10,.15,'#765c50',MAT.skin,18,3);
    lens(m,x,y,z+.09,r,hh,.30,(q,a)=>blend('#fff6de','#d2d7c7',q*.33+Math.max(0,Math.sin(a))*.10),MAT.eye,20,4);
    lens(m,x-.07,y-.15*open,z+.37,r*.64,hh*.85,.13,(q,a)=>{
      const pupil=q<.48?'#283737':iris,streak=.5+.5*Math.cos(a*19+q*8);
      return q>.88?blend(iris,'#344c44',.54):q<.48?color(pupil):blend(iris,'#dfc482',(.12+.23*streak)*(1-q));
    },MAT.eye,24,5);
    lens(m,x-.07,y-.16*open,z+.50,r*.26,hh*.58,.06,'#243238',MAT.eye,16,3);
    if(open>.15){lens(m,x-r*.27,y+hh*.36,z+.575,r*.24,hh*.22,.03,'#fffdf0',.25,10,3);lens(m,x+r*.27,y-hh*.39,z+.57,r*.095,hh*.095,.025,'#d4f5e5',.1,7,2);}
    const upper=[];for(let j=0;j<=8;j++){const a=j/8*Math.PI;upper.push([x+Math.cos(a)*r*1.015,y+Math.sin(a)*hh,z+.40]);}
    tube(m,upper,.115,'#4f423f',MAT.hair,6);
    tube(m,[[x-r*.93,y+hh*.18,z+.4],[x-r*1.20,y+hh*.37,z+.42]],[.15,.02],'#554241',MAT.hair,5);
    const lower=[];for(let j=0;j<=6;j++){const a=Math.PI+j/6*Math.PI;lower.push([x+Math.cos(a)*r*.99,y+Math.sin(a)*hh,z+.31]);}tube(m,lower,.055,'#c19278',MAT.skin,5);
  }
  function head(m,c){
    sculpt(m,(a,b)=>{
      const v=Math.cos(b),sn=Math.sin(b),cheek=1+.10*Math.exp(-Math.pow((v+.29)/.39,2)),chin=v<-.46?1-(Math.abs(v)-.46)*.29:1;
      return [Math.cos(a)*sn*8.30*cheek*chin,27.2+v*8.35,.28+Math.sin(a)*sn*5.75];
    },(a,b,p)=>{
      const cheeks=Math.exp(-Math.pow((Math.abs(p[0])-5.15)/1.8,2)-Math.pow((p[1]-25.2)/1.65,2))*Math.pow(Math.max(0,Math.sin(a)),5);
      return blend(c.skin,c.cheek,cheeks*.44);
    },MAT.skin,28,17);
    for(const s of [-1,1]){
      ellipsoid(m,s*8.02,26.3,.1,1.22,1.70,1.22,c.skin,MAT.skin,12,8);
      lens(m,s*8.14,26.3,1.03,.58,1.01,.13,blend(c.skin,c.cheek,.35),MAT.skin,10,3);
      lens(m,s*5.14,25.28,5.00,.65,.22,.018,blend(c.skin,c.cheek,.39),MAT.skin,12,3);
      tube(m,[[s*1.81,31.00,5.55],[s*3.17,31.45,5.65],[s*4.75,31.19,5.30]],[.12,.22,.07],shade(c.hair,.83),MAT.hair,7);
    }
    sculpt(m,(a,b)=>[Math.cos(a)*Math.sin(b)*.67,26.18+Math.cos(b)*.68,5.50+Math.sin(a)*Math.sin(b)*.78],(a,b)=>blend(c.skin,'#f4d5b1',.2+Math.max(0,Math.cos(b))*.15),MAT.skin,14,9);
    tube(m,[[-1.04,23.88,5.37],[-.55,23.55,5.54],[0,23.48,5.58],[.61,23.66,5.53],[1.0,23.94,5.34]],[.055,.105,.11,.09,.035],'#aa776b',MAT.skin,6);
    lens(m,0,23.16,5.39,.58,.11,.016,'#f6d3b4',MAT.skin,10,2);
  }
  function hairCap(m,c,style){
    // One connected cap includes the scalloped fringe and swept side locks.
    // The bangs are part of the scalp surface instead of stacked primitives.
    const sweep=style==='orin'?-1:1;
    const point=(a,t,offset=0)=>{
      const front=Math.pow(Math.max(0,Math.sin(a)),.72),back=style==='orin'?2.02:style==='pip'?1.81:1.92;
      const fringe=1.19+.064*Math.sin(a*8+.6)+sweep*.10*Math.cos(a),edge=mix(back,fringe,front),q=t*edge;
      const sn=Math.sin(q),strand=1+.009*Math.cos(a*13+q*.6),flare=style==='orin'?1+.048*Math.pow(t,5):1;
      return [Math.cos(a)*sn*(9.02+offset)*strand*flare,27.1+Math.cos(q)*(9.10+offset),.1+Math.sin(a)*sn*(6.15+offset)];
    };
    sculpt(m,(a,b)=>point(a,b/Math.PI),(a,b)=>blend(c.hair,c.highlight,.09+.035*Math.cos(a*13+b*.4)),MAT.hair,40,16);
    for(let j=0;j<9;j++){
      const a=.12+j/8*(Math.PI-.24),line=[];
      for(let k=0;k<8;k++){const t=.12+k/7*.84;line.push(point(a+(1-t)*sweep*.12,t,.055));}
      tube(m,line,[.015,.032,.046,.052,.062,.068,.055,.012],blend(c.hair,c.highlight,.36),MAT.hair,5);
    }
    if(style==='pip')for(const side of [-1,1]){
      sculpt(m,(a,b)=>{const sn=Math.sin(b),q=1+.030*Math.sin(a*6+b*2);return[side*7.55+Math.cos(a)*sn*3.30*q,34.2+Math.cos(b)*3.1,Math.sin(a)*sn*3.1-.2];},c.hair,MAT.hair,18,11);
      tube(m,[[side*5.9,34.5,2.6],[side*7.4,32.2,2.4],[side*9.1,33.1,1.8]],[.23,.32,.13],c.dress,MAT.cloth,7);
      ellipsoid(m,side*7.7,33.1,2.9,.50,.56,.30,c.trim,MAT.cloth,9,6);
    }
  }
  function braid(m,c,side=1){
    tube(m,[[side*7.4,30.6,.0],[side*8.4,25.0,1.0],[side*8.0,20.0,2.0],[side*7.2,15.7,2.4]],[2.2,2.0,1.5,.5],c.hair,MAT.hair,10);
    for(let j=0;j<6;j++)for(const s of [-1,1]){
      const yy=26.1-j*1.56,xx=side*(8.1-j*.10)+s*.72;
      tube(m,[[xx-s*.55,yy+1.0,2.12],[xx+s*.54,yy,2.55],[xx+s*.52,yy-1.02,2.09]],[.8,.9,.29],blend(c.hair,c.highlight,s>0?.20:.07),MAT.hair,7);
    }
    tube(m,[[side*6.5,16.6,2.0],[side*7.6,16.25,3.1],[side*8.4,16.8,2.1]],[.32,.38,.22],c.trim,MAT.cloth,7);
    leaf(m,[side*7.5,16.2,2.9],[side*6.7,13.3,2.6],.84,c.dress,0,MAT.cloth,5);
  }
  function costume(m,c,style){
    profile(m,[[6.4,6.40,3.60],[7.1,7.0,3.9],[9.1,6.6,3.70],[12.7,5.4,3.3],[16.1,4.30,2.9],[18.3,4.7,2.8],[19.6,3.3,2.3],[20.0,.15,.2]],c.dress,MAT.cloth,28,.07);
    ellipsoid(m,0,20.3,.1,2.23,1.95,2.02,c.skin,MAT.skin,12,8);
    for(const side of [-1,1]){
      tube(m,[[side*2.65,7.8,0],[side*2.82,4.4,.3],[side*2.8,1.9,.8]],[1.75,1.65,1.30],c.skin,MAT.skin,10);
      ellipsoid(m,side*2.8,1.25,1.35,2.15,1.35,2.65,c.shoe,MAT.cloth,14,8);
      tube(m,[[side*1.1,2.3,1.2],[side*2.8,2.62,2.1],[side*4.3,2.24,1.2]],[.14,.17,.1],c.trim,MAT.cloth,6);
      leaf(m,[side*.4,20.0,2.7],[side*3.3,17.1,3.0],1.20,c.trim,side,MAT.cloth,5);
    }
    for(let j=0;j<11;j++){
      const a=Math.PI*.12+j/10*Math.PI*.76,px=Math.cos(a)*6.85,pz=Math.sin(a)*3.86;
      tube(m,[[px,7.27,pz],[px*.92,8.4,pz*.96]],[.1,.045],blend(c.dress,c.trim,.33),MAT.cloth,5);
    }
    const hem=[];for(let j=0;j<=20;j++){const a=j/20*TAU;hem.push([Math.cos(a)*6.97,7.04+.14*Math.cos(a*7),Math.sin(a)*3.88]);}tube(m,hem,.18,c.trim,MAT.cloth,6);
    if(style==='luma'||style==='pip'){
      const rows=[[8.0,4.3,3.46],[10.5,4.02,3.34],[13.5,3.0,3.15],[16.6,2.32,2.8],[18.3,2.4,2.78]];
      for(let j=0;j<rows.length-1;j++)for(let k=0;k<8;k++){
        const patch=(r,u)=>[u*r[1],r[0]+.08*(1-u*u),r[2]+.55*(1-u*u)],a=patch(rows[j],k/4-1),b=patch(rows[j],(k+1)/4-1),cc=patch(rows[j+1],(k+1)/4-1),d=patch(rows[j+1],k/4-1),col=style==='pip'?blend(c.trim,c.dress,.34):'#dbd8b3';
        triangle(m,a,b,cc,col,[a[0]*.04,.06,1],[b[0]*.04,.06,1],[cc[0]*.04,.06,1],MAT.cloth);triangle(m,a,cc,d,col,[a[0]*.04,.06,1],[cc[0]*.04,.06,1],[d[0]*.04,.06,1],MAT.cloth);
      }
      tube(m,[[-1.4,12.3,3.65],[0,11.6,3.97],[1.4,12.3,3.65]],[.07,.085,.07],c.dark,MAT.cloth,5);
      for(const s of [-1,1])ellipsoid(m,s*1.8,16.2,3.35,.23,.28,.12,'#c4a769',MAT.cloth,7,4);
    }else{
      for(const side of [-1,1]){
        leaf(m,[side*.35,20.0,2.42],[side*6.4,11.2,3.0],2.8,c.dark,side,MAT.cloth,9);
        tube(m,[[side*.6,19.8,2.6],[side*4.15,18.5,3.3],[side*6.25,14.2,3.08],[side*6.4,11.2,3.0]],[.14,.19,.16,.08],c.trim,MAT.cloth,6);
      }
      lens(m,0,18.5,3.21,.65,.8,.27,style==='keeper'?'#d7b76b':'#b5c8c3',.12,12,4);
    }
    if(style==='orin'){
      tube(m,[[-3.7,18.8,3.07],[0,14.6,3.75],[4.9,10.5,3.41]],[.30,.36,.30],'#9f805e',MAT.cloth,7);
      ellipsoid(m,5.4,9.1,2.95,2.31,2.75,1.51,'#866e58',MAT.cloth,14,8);
      tube(m,[[3.5,10.6,3.7],[5.4,10.05,4.51],[7.0,10.6,3.7]],[.18,.2,.18],'#c2a278',MAT.cloth,6);
      lens(m,5.4,9.9,4.49,.32,.35,.1,c.trim,MAT.cloth,8,3);
    }
    if(style==='keeper'){
      tube(m,[[-2.5,19.2,3.0],[-2.2,15.0,3.61],[0,13.5,3.75],[2.1,15.0,3.61],[2.5,19.2,3.0]],.11,'#c9b27a',MAT.cloth,6);
      lens(m,0,13.65,3.93,.52,.76,.20,'#dfc47e',.16,10,4);
    }
  }
  function arm(m,c,side,reach=0){
    const q=side<0?reach:0,hand=[side*(8+q*6),13-q*7,.9+q];
    tube(m,[[side*4.1,18.4,0],[side*(6.5+q*.8),16.4-q*4,.8],hand],[1.80,1.48,1.10],c.skin,MAT.skin,10);
    ellipsoid(m,side*4.95,18.13,0,2.15,2.46,2.14,c.dress,MAT.cloth,14,8);
    tube(m,[[side*6.3,16.95,-.25],[side*6.3,16.47,1.32],[side*4.9,16.15,1.93]],[.14,.17,.14],c.trim,MAT.cloth,6);
    ellipsoid(m,...hand,1.28,1.55,1.14,c.skin,MAT.skin,12,8);
    ellipsoid(m,hand[0]-side*.85,hand[1]+.42,hand[2]+.37,.57,.79,.54,c.skin,MAT.skin,10,6);
    for(let j=0;j<2;j++)tube(m,[[hand[0]+side*.32,hand[1]-.54+j*.45,hand[2]+1.06],[hand[0]+side*.93,hand[1]-.66+j*.45,hand[2]+.82]],[.025,.012],shade(c.skin,.86),MAT.skin,4);
  }
  function hairAccessory(m,c,style){
    if(style==='luma'||style==='keeper'){
      const s=style==='keeper'?-1:1;
      leaf(m,[s*5.8,33.1,3.8],[s*8.7,37.45,2.9],1.54,style==='keeper'?'#b4c69c':'#85a975',0,MAT.leaf,7);
      for(let j=0;j<5;j++){const a=j/5*TAU;ellipsoid(m,s*6.6+Math.cos(a)*.9,33.35+Math.sin(a)*.85,5.21,.57,.68,.22,c.trim,MAT.cloth,9,6);}ellipsoid(m,s*6.6,33.35,5.45,.38,.38,.18,'#caab63',.06,10,6);
    }
    if(style==='pip'){
      for(const s of [-1,1]){leaf(m,[s*7.5,33.1,3.0],[s*10.6,34.5,2.3],1.12,c.dress,s,MAT.cloth,6);leaf(m,[s*7.5,33.1,3.0],[s*9.4,30.8,2.9],.92,c.trim,s,MAT.cloth,5);}
    }
  }
  function frogBody(m){
    sculpt(m,(a,b)=>{const s=Math.sin(b),v=Math.cos(b),q=1+.06*Math.cos(a*2)*s;return[Math.cos(a)*s*8.9*q,6.55+v*6.45,Math.sin(a)*s*5.25];},(a,b)=>blend('#77a885','#b2c792',.26+.26*Math.cos(b)),MAT.skin,24,14);
    lens(m,0,5.5,5.20,5.3,4.15,.36,'#d2d1a0',MAT.skin,20,5);
    for(const s of [-1,1]){
      ellipsoid(m,s*7.7,3.45,-1.2,4.55,3.7,3.8,'#709b77',MAT.skin,16,10);
      tube(m,[[s*5.4,6.6,2.8],[s*6.8,2.3,3.8],[s*6.3,1.05,5.7]],[1.22,1.05,.63],'#91b88b',MAT.skin,9);
      for(let j=0;j<3;j++){const xx=s*(5.50+j*.87);tube(m,[[s*6.2,1.1,5.5],[xx,.64,6.5],[xx+s*.14,.63,7.25]],[.31,.25,.15],'#acc899',MAT.skin,6);ellipsoid(m,xx+s*.14,.60,7.2,.47,.27,.54,'#c5d4a4',MAT.skin,8,5);}
      ellipsoid(m,s*4.55,12.18,1.10,4.0,4.12,3.37,'#8db68c',MAT.skin,18,11);
      lens(m,s*6.0,8.2,4.94,.91,.43,.05,'#d0a08c',MAT.skin,12,3);
      for(let j=0;j<3;j++)ellipsoid(m,s*(5.7+j*.95),8.3+j*.7,-3.1,.42,.35,.23,'#bad09c',MAT.skin,7,4);
    }
    tube(m,[[-3.4,7.4,5.82],[-1.65,6.68,5.97],[0,6.47,6.01],[1.7,6.68,5.97],[3.4,7.4,5.82]],[.09,.14,.14,.14,.08],'#52765a',MAT.skin,6);
    for(const s of [-1,1])ellipsoid(m,s*1.5,10.42,5.11,.25,.17,.10,'#547d5d',MAT.skin,7,4);
    leaf(m,[-1.5,13.0,-1],[3.8,18.1,-1],1.9,'#6c9975',0,MAT.leaf,7);
  }
  function foxBody(m){
    sculpt(m,(a,b)=>{const s=Math.sin(b),v=Math.cos(b),q=1+.10*Math.max(0,-v);return[.5+Math.cos(a)*s*6.7*q,9.1+v*8.3,Math.sin(a)*s*4.58];},(a,b)=>blend('#c78758','#dbab73',Math.max(0,Math.cos(b))*.37),MAT.hair,22,14);
    sculpt(m,(a,b)=>{const s=Math.sin(b),v=Math.cos(b),r=1+.025*Math.cos(a*7);return[.5+Math.cos(a)*s*3.52*r,11.0+v*5.69,3.10+Math.sin(a)*s*1.74];},'#ecd5af',MAT.hair,18,11);
    for(const side of [-1,1]){
      tube(m,[[side*3.1+.5,8.1,1.9],[side*3.2+.5,3.3,2.05],[side*3.35+.5,1.6,2.57]],[1.75,1.35,1.40],'#a97452',MAT.hair,10);
      ellipsoid(m,side*3.35+.5,1.20,3.0,2.0,1.12,2.48,'#67544a',MAT.hair,14,8);
      for(let j=0;j<2;j++)tube(m,[[side*3.35+.5+(j-.5)*.65,1.58,4.42],[side*3.35+.5+(j-.5)*.65,.93,5.03]],[.045,.02],'#b39473',MAT.hair,5);
    }
  }
  function foxHead(m){
    sculpt(m,(a,b)=>{const s=Math.sin(b),v=Math.cos(b),q=1+.13*Math.exp(-Math.pow((v+.18)/.42,2));return[Math.cos(a)*s*8.35*q,22.1+v*7.1,.15+Math.sin(a)*s*5.02];},(a,b)=>blend('#cd8e60','#e5b37d',.13+.22*Math.cos(b)),MAT.hair,26,15);
    for(const side of [-1,1]){
      sculpt(m,(a,b)=>{const sn=Math.sin(b);return[side*3.27+Math.cos(a)*sn*3.65,20.12+Math.cos(b)*2.80,3.94+Math.sin(a)*sn*1.28];},'#f0dbb5',MAT.hair,16,10);
      lens(m,side*5.75,21.32,4.19,.71,.30,.03,'#d99680',MAT.skin,10,3);
      tube(m,[[side*1.92,26.4,4.20],[side*3.08,26.90,4.37],[side*4.62,26.57,3.99]],[.08,.15,.045],'#8f624d',MAT.hair,6);
      for(let j=0;j<2;j++)tube(m,[[side*5.05,19.87-j*.58,4.23],[side*(8.3+j*.35),20.0-j*.98,3.8]],[.033,.005],'#a77e63',MAT.hair,5);
    }
    sculpt(m,(a,b)=>[Math.cos(a)*Math.sin(b)*1.09,20.37+Math.cos(b)*.78,5.25+Math.sin(a)*Math.sin(b)*.66],(a,b)=>blend('#3a4443','#6b6660',Math.max(0,Math.cos(b))*.5),MAT.eye,14,9);
    lens(m,-.28,20.70,5.88,.22,.10,.02,'#b6b7a2',MAT.eye,9,3);
    tube(m,[[0,19.85,5.59],[0,19.16,5.62],[-.82,18.69,5.30],[-1.44,19.12,5.04]],[.065,.10,.10,.04],'#8c6d59',MAT.hair,6);
    tube(m,[[0,19.16,5.62],[.82,18.69,5.30],[1.44,19.12,5.04]],[.10,.10,.04],'#8c6d59',MAT.hair,6);
  }
  function foxEar(m,side){
    tube(m,[[side*5.4,26.5,-.9],[side*6.8,29.1,-.2],[side*7.05,32.3,.2],[side*6.6,34.8,.32]],[3.04,2.32,1.32,.08],'#cb8e60',MAT.hair,14);
    leaf(m,[side*5.7,26.9,1.5],[side*6.65,33.8,1.17],1.70,'#d4a18a',side,MAT.skin,9);
    leaf(m,[side*5.7,27.1,1.65],[side*6.60,32.8,1.32],.86,'#e5b9a0',side,MAT.skin,7);
  }
  function foxTail(m){
    const p=[[-3.2,6.9,-2.5],[-7.9,6.2,-2.5],[-12.4,9.0,-1.8],[-15.8,13.8,-1.2],[-16.1,18.1,-.5],[-13.5,22.25,.1],[-11.4,23.6,.3]];
    tube(m,p,[2.6,4.05,4.65,4.52,3.60,1.9,.055],'#c58958',MAT.hair,16);
    tube(m,p.slice(4),[3.66,1.94,.05],'#ecd6b0',MAT.hair,16);
    tube(m,[[-14.9,17.8,2.3],[-12.95,21.45,1.9],[-11.4,23.6,.3]],[.18,.13,.015],'#fff0c9',MAT.hair,6);
  }
  const characterCache=new Map();
  function actorParts(form,appearance){
    const key=form+':'+appearance;if(characterCache.has(key))return characterCache.get(key);
    const bake=(name,build)=>cached('actor:'+key+':'+name,build),c=looks[appearance]||looks.luma,p={};
    if(form==='frog'){
      p.body=bake('body',frogBody);
      p.eyes=Array.from({length:9},(_,i)=>bake('eyes'+i,m=>{for(const s of [-1,1])eye(m,s*4.6,12.8,4.20,2.12,2.18,'#b4a76a',i/8);}));
      p.throat=bake('throat',m=>lens(m,0,5.55,5.54,3.3,2.22,.20,'#e1dbac',MAT.skin,16,4));
    }else if(form==='fox'){
      p.body=bake('body',foxBody);p.head=bake('head',foxHead);p.tail=bake('tail',foxTail);
      p.ears=[-1,1].map(s=>bake('ear'+s,m=>foxEar(m,s)));
      p.eyes=Array.from({length:9},(_,i)=>bake('eyes'+i,m=>{for(const s of [-1,1])eye(m,s*3.45,24.08,4.73,1.58,1.77,'#858b65',i/8);}));
    }else{
      p.body=bake('body',m=>costume(m,c,appearance));p.head=bake('head',m=>head(m,c));
      p.hair=bake('hair',m=>{hairCap(m,c,appearance);hairAccessory(m,c,appearance);});
      if(appearance==='luma'||appearance==='keeper')p.braid=bake('braid',m=>braid(m,c,appearance==='keeper'?-1:1));
      p.left=bake('left',m=>arm(m,c,-1,0));p.reach=bake('reach',m=>arm(m,c,-1,1));p.right=bake('right',m=>arm(m,c,1,0));
      p.eyes=Array.from({length:9},(_,i)=>bake('eyes'+i,m=>{for(const s of [-1,1])eye(m,s*3.25,28.30,5.36,1.67,2.18,c.iris,i/8);}));
    }
    characterCache.set(key,p);return p;
  }
  function actorPart(m,data,x,y,z,depth,angle=0,pivotX=0,pivotY=0,sy=1,yaw=0,other=null,morph=0,phase=0){
    const out=m.a,ca=Math.cos(angle),sa=Math.sin(angle),cy=Math.cos(yaw),ss=Math.sin(yaw);
    for(let i=0;i<data.length;i+=10){
      let px=morph&&other?mix(data[i],other[i],morph):data[i],py=morph&&other?mix(data[i+1],other[i+1],morph):data[i+1],pz=morph&&other?mix(data[i+2],other[i+2],morph):data[i+2];
      if(data[i+9]===MAT.cloth&&py>6&&py<16){const hem=Math.pow((16-py)/10,1.4);px+=Math.sin(phase*.93+py*.18)*hem*.19;pz+=Math.cos(phase*.77+px*.21)*hem*.11;}
      const xx=(px-pivotX)*cy+pz*ss,zz=-(px-pivotX)*ss+pz*cy,yy=(py-pivotY)*sy;
      const nx=morph&&other?mix(data[i+6],other[i+6],morph):data[i+6],ny=morph&&other?mix(data[i+7],other[i+7],morph):data[i+7],nz=morph&&other?mix(data[i+8],other[i+8],morph):data[i+8],nnx=nx*cy+nz*ss,nnz=-nx*ss+nz*cy;
      out.push(x+pivotX+xx*ca-yy*sa,y+pivotY+xx*sa+yy*ca,z+zz*depth,data[i+3],data[i+4],data[i+5],nnx*ca-ny*sa,nnx*sa+ny*ca,nnz,data[i+9]);
    }
  }
  function blinkAt(t,seed){const q=(t+seed*.37)%4.6;return q<.19?Math.sin(q/.19*Math.PI):q>2.2&&q<2.36&&h(seed)>.65?Math.sin((q-2.2)/.16*Math.PI):0;}
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
    const form=record.form||'girl',parts=actorParts(form,record.appearance||'luma'),phase=t*1.35+record.x*.21;
    const breath=Math.sin(phase),bob=walk?Math.abs(Math.sin(t*8.6))*walk*.55:0,depth=(record.depth||.6)/16;
    const headTilt=Math.sin(phase*.59)*.024-reach*.065,yaw=Math.sin(phase*.38)*.025,bi=Math.round(blinkAt(t,record.x)*8);
    const draw=(data,angle=0,px=0,py=0,sy=1,turn=0,other=null,morph=0,dy=0)=>actorPart(m,data,x,y+bob+dy,z,depth,angle,px,py,sy,turn,other,morph,phase);
    draw(parts.body,0,0,0,1+breath*.006);
    if(form==='frog'){
      draw(parts.throat,0,0,5.5,1+Math.max(0,Math.sin(t*2.2+record.x))*.11,0,null,0,breath*.025);
      draw(parts.eyes[bi],0);
    }else if(form==='fox'){
      draw(parts.tail,Math.sin(phase*.7)*.11,-3.2,7);
      draw(parts.head,headTilt,0,18,1,yaw,null,0,breath*.09);
      draw(parts.eyes[bi],headTilt,0,18,1,yaw,null,0,breath*.09);
      parts.ears.forEach((e,i)=>draw(e,headTilt+Math.sin(phase*1.7+i*4)*.048,(i?1:-1)*5.4,26.5,1,yaw,null,0,breath*.09));
    }else{
      draw(parts.left,Math.sin(phase)*.032*(1-reach),-4.1,18.4,1,0,parts.reach,reach);
      draw(parts.right,Math.sin(phase+1.1)*.031,4.1,18.4);
      draw(parts.head,headTilt,0,21.1,1,yaw,null,0,breath*.06);
      draw(parts.hair,headTilt+Math.sin(phase*.85)*.009,0,21.1,1,yaw,null,0,breath*.06);
      draw(parts.eyes[bi],headTilt,0,21.1,1,yaw,null,0,breath*.06);
      if(parts.braid)draw(parts.braid,headTilt+Math.sin(phase*.93)*.035,record.appearance==='keeper'?-7.4:7.4,29.9,1,yaw,null,0,breath*.06);
    }
  }
  function characterData(form,appearance,reach=0){
    return cached('portrait:'+form+':'+appearance+':'+reach,m=>{
      const p=actorParts(form,appearance);for(const key of ['body','head','hair','braid','tail'])if(p[key])append(m,p[key]);
      if(p.left)append(m,reach?p.reach:p.left);if(p.right)append(m,p.right);if(p.ears)for(const a of p.ears)append(m,a);append(m,p.eyes[0]);if(p.throat)append(m,p.throat);
    });
  }
  function buildWorld(m,world){
    forestFloor(m);
    for(let i=-2;i<19;i++){const x=i*130+h(i+77)*37,z=-455-h(i+3)*150;tree(m,x,forestHeight(x,z)-2,z,1.4+h(i)*.75,i+70,true);}
    for(let i=-2;i<20;i++){const x=i*119+h(i+11)*31,z=-172-h(i+5)*145;tree(m,x,forestHeight(x,z)-2,z,.77+h(i+23)*.75,i+25,false);}
    // Lower arched crowns frame the rainforest during the elevated 3-D view.
    for(const [x,seed]of [[285,182],[1090,191],[1735,203]]){
      const z=-148;tree(m,x,forestHeight(x,z)-2,z,.56,seed,false);
    }
    for(const [x,seed]of [[55,208],[520,213],[1320,218],[1940,222]]){
      const z=-151;tree(m,x,forestHeight(x,z)-2,z,.47+h(seed)*.08,seed,false);
    }
    for(const p of world.platforms)if(p.kind!=='bridge')platform(m,p);
    for(const o of world.obstacles)if(o.kind!=='gate')barrier(m,o);
    birthTree(m);
    for(let i=0;i<34;i++){
      const x=-100+i*67+h(i+66)*25;if(x>690&&x<1005)continue;
      const z=-60-h(i+13)*22,size=.56+h(i+18)*.40;
      fern(m,x,0,z,size,i+28,i%3===0?'#59897e':'#41806c');
      if(i%2===0)broadPlant(m,x+18,0,z-3,.6+h(i+44)*.45,i+15);
      if(i%3!==1)for(let j=0;j<3;j++)blossom(m,x-10+h(i+j)*20,0,z+8+h(i+j+40)*12,2.2+h(i+j)*2.9,i%2===0?'#dbabc8':'#aea6de',i+j);
      if(i%3===0){
        // Leave the power's gathering/reforming silhouette clear at the story
        // barriers throughout the camera orbit, including through refraction.
        const shift=world.obstacles.some(o=>Math.abs(x+24-o.x)<55)?-58:0;
        mushroom(m,x+24+shift,0,z+8,6+h(i)*5,'#aeadde');mushroom(m,x+33+shift,0,z+13,3.4+h(i)*2,'#d0b5cf');
      }
      if(i%4===0)rock(m,x-13,4,z+8,12,7,9,'#7b8a6a',i+20);
    }
    for(let i=0;i<30;i++){
      const x=-115+i*74+h(i+66)*24;if(x>690&&x<1005)continue;const z=68+h(i+18)*15;
      // A low foreground frames the stage, with clear windows around contact
      // encounters and the opening drop. It never hides the small frog form.
      const encounters=[world.spawn.x,world.prism.x,...world.npcs.map(n=>n.x),...(world.creatures||[]).map(n=>n.x)];
      if(encounters.some(xx=>Math.abs(xx-x)<37))continue;
      fern(m,x,0,z,.29+h(i)*.23,i+4,'#527b56');
      if(i%3===0)broadPlant(m,x-10,0,z+.5,.34+h(i)*.12,i+30);
      if(i%4===0)for(let j=0;j<3;j++)blossom(m,x+8+j*5,0,z-6+h(j+i)*5,2.1+h(j+i)*1.2,'#e4ccab',i+j);
      if(i%3!==1){rock(m,x-8,3,z+2,9,5,7,'#7c8d71',i+60);rock(m,x-16,1.8,z-2,4,3,5,'#8e9c7c',i+70);}
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
      tube(m,[[1839+side*37,0,-38],[1839+side*36,31,-39],[1839+side*29,64,-38],[1839+side*13,85,-36],[1839,88,-34]],[6,5.3,4.3,2.4,.6],'#9aab82',MAT.wood,16);
      for(let j=0;j<4;j++){const y=24+j*15,x=1839+side*(37-j*6);leaf(m,[x,y,-37],[x+side*16,y+15,-31],6.2,j%2===0?'#8ab99a':'#bdaccc',j,0,7);}
      blossom(m,1839+side*20,72,-31,4.1,'#e4b9cf',side);
    }
    // Prebake the small roster once during scene creation. First contact or a
    // newly visible resident never compiles geometry on an animation frame.
    for(const n of [...world.npcs,...(world.creatures||[])])actorParts(n.form||'girl',n.appearance||'luma');
    return m;
  }
  function dynamic(m,world,state){
    const p=state.player,t=state.time||0,d=state.dimensionBlend||0;
    const aspect=window.innerWidth&&window.innerHeight?window.innerWidth/window.innerHeight:2.18,viewHalf=(state.cameraHeight||232)*aspect*.5+64;
    const visible=(x,r=0)=>Math.abs(x-state.cameraX)<viewHalf+r;
    if(d>.03){
      const bridge=world.platforms.find(b=>b.kind==='bridge');
      if(bridge&&visible(bridge.x+bridge.w/2,bridge.w/2)){
        const data=cached('bridge',local=>{
          platform(local,bridge,1);
          for(let i=0;i<12;i++){const x=bridge.x+12+i*24;disk(local,x,.25,bridge.z+bridge.d*.5,7,6,'#b2d3b5',.2,12);}
          for(const z of [bridge.z+2,bridge.z+bridge.d-2])tube(local,[[bridge.x,-3,z],[bridge.x+bridge.w*.33,-8,z],[bridge.x+bridge.w*.67,-8,z],[bridge.x+bridge.w,-3,z]],[2,2.6,2.6,2],'#77a69a',.2,8);
        });append(m,data,0,0,0,d,1);
      }
    }
    if(d>.02){
      for(let i=-9;i<22;i++){const x=Math.floor(state.cameraX/22)*22+i*22;const supported=world.platforms.some(b=>b.kind==='earth'&&x>=b.x&&x<=b.x+b.w);if(supported)disk(m,x,.2,0,3.4,.5,blend('#527c69','#a5d5b0',d),.18,10);}
    }
    for(const n of [...world.npcs,...(world.creatures||[])])if(visible(n.x,20))creature(m,n,t,state.cinematic);
    if(visible(world.beacon.x,15))lantern(m,world.beacon.x,0,0,state.beaconLit);
    for(let i=0;i<world.checkpoints.length;i++){const cp=world.checkpoints[i];if(visible(cp.x+20,15))lantern(m,cp.x+20,0,-26,state.checkpointIndex>=i);}
    for(const o of world.obstacles)if(o.kind==='gate'&&visible(o.x,25))barrier(m,o,(state.gateOpen||0)*145);
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
