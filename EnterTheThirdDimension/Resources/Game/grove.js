/* Original Sunshower Grove art, v2.3. All geometry is authored here.
 * Static decoration stays outside the playable depth corridor; the platform
 * and collision data remain authoritative. No external art or game assets.
 */
(() => {
  'use strict';
  const TAU=Math.PI*2, mix=(a,b,t)=>a+(b-a)*t;
  const rgb=c=>Array.isArray(c)?c:[1,3,5].map(i=>parseInt(c.slice(i,i+2),16)/255);
  const tint=(c,t)=>rgb(c).map(v=>Math.min(1,v*t));
  const norm=v=>{const l=Math.hypot(...v)||1;return v.map(x=>x/l);};
  const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
  const sub=(a,b)=>a.map((v,i)=>v-b[i]);
  const seed=n=>{const v=Math.sin(n*73.13+11.7)*43758.5453;return v-Math.floor(v);};
  const triangle=(m,a,b,c,col,n)=>{n=n||norm(cross(sub(b,a),sub(c,a)));for(const p of [a,b,c])m.vertex(p,rgb(col),n,-4);};
  function surface(m,point,col,mat=-1,sides=20,rings=12){
    const grid=[];
    for(let j=0;j<=rings;j++){
      const v=Math.max(.00001,Math.min(Math.PI-.00001,j/rings*Math.PI));grid[j]=[];
      for(let i=0;i<=sides;i++){
        const u=i/sides*TAU,p=point(u,v),a=sub(point(u+.003,v),point(u-.003,v));
        const b=sub(point(u,Math.min(Math.PI-.000001,v+.003)),point(u,Math.max(.000001,v-.003)));
        grid[j].push({p,n:norm(cross(a,b)),c:typeof col==='function'?rgb(col(u,v)):rgb(col)});
      }
    }
    for(let j=0;j<rings;j++)for(let i=0;i<sides;i++){
      const a=grid[j][i],b=grid[j][i+1],c=grid[j+1][i+1],d=grid[j+1][i];
      for(const q of j===0?[a,c,d]:j===rings-1?[a,b,c]:[a,b,c,a,c,d])m.vertex(q.p,q.c,q.n,mat);
    }
  }
  function blob(m,x,y,z,rx,ry,rz,col,mat=-1,phase=0){
    surface(m,(u,v)=>{const s=Math.sin(v),r=1+.025*Math.sin(u*3+phase)*s+.012*Math.cos(v*4+u*2);return[x+Math.cos(u)*s*rx*r,y+Math.cos(v)*ry,z+Math.sin(u)*s*rz*r];},(u,v)=>tint(col,.96+.045*Math.cos(v)),mat,24,14);
  }
  function rod(m,a,b,r,col,mat=-6,sides=10){
    const n=norm(sub(b,a)),u=norm(cross(n,Math.abs(n[1])>.9?[1,0,0]:[0,1,0])),v=cross(n,u),c=rgb(col);
    for(let i=0;i<sides;i++){
      const p=i/sides*TAU,q=(i+1)/sides*TAU,n0=u.map((x,j)=>x*Math.cos(p)+v[j]*Math.sin(p)),n1=u.map((x,j)=>x*Math.cos(q)+v[j]*Math.sin(q));
      const A=a.map((x,j)=>x+n0[j]*r),B=a.map((x,j)=>x+n1[j]*r),C=b.map((x,j)=>x+n1[j]*r),D=b.map((x,j)=>x+n0[j]*r);
      for(const [pos,nor] of [[A,n0],[B,n1],[C,n1],[A,n0],[C,n1],[D,n0]])m.vertex(pos,c,nor,mat);
    }
  }
  function curve(m,pts,r,col,mat=-6){for(let i=1;i<pts.length;i++)rod(m,pts[i-1],pts[i],r,col,mat,8);}
  function box(m,x,y,z,w,h,d,col,mat=-6){m.box(x,y,z,w,h,d,col,mat);}
  function ring(m,x,y,z,rx,ry,col,r=.4){const p=[];for(let i=0;i<=28;i++){const a=i/28*TAU;p.push([x+Math.cos(a)*rx,y+Math.sin(a)*ry,z]);}curve(m,p,r,col);}
  function canopyTree(m,x,y,z,s,key,distant,tools){
    const height=(91+seed(key)*25)*s,bend=(seed(key+2)-.5)*11*s;
    const bark=distant?'#8b9c75':'#a28561',leaf=distant?'#6fbd91':['#69ad62','#80bd68','#62af7f','#96bc65'][Math.abs(key)%4];
    const trunk=[[x,y,z],[x-2*s,y+height*.26,z],[x+bend*.3,y+height*.55,z],[x+bend,y+height*.87,z],[x+bend*.8,y+height,z]];
    tools.tube(m,trunk,[6.6*s,6.3*s,5.4*s,3.6*s,.9*s],bark,-6,distant?10:16);
    for(let side=-1;side<=1;side+=2){
      tools.tube(m,[[x,y+12*s,z],[x+side*9*s,y+2*s,z+4*s],[x+side*18*s,y-.9,z+8*s]],[3.8*s,2.4*s,.2],tint(bark,.93),-6,10);
      tools.tube(m,[[x+bend*.3,y+height*.52,z],[x+side*13*s,y+height*.75,z-1*s],[x+side*24*s,y+height*.84,z-3*s]],[3.1*s,2.1*s,.45],bark,-6,10);
    }
    const crowns=[[-23,.88,0,29,26,27],[23,.88,-4,29,25,28],[0,1.05,-6,35,32,30],[-7,.83,14,30,20,25],[2,.98,-25,30,25,25]];
    for(let i=0;i<crowns.length;i++){
      const [dx,h,dz,rx,ry,rz]=crowns[i];
      // Broad scallops create one designed crown, not a spray of tiny leaves.
      surface(m,(u,v)=>{const sn=Math.sin(v),r=1+.05*Math.cos(u*5+key*.7)*sn+.025*Math.sin(v*6);return[x+bend+dx*s+Math.cos(u)*sn*rx*s*r,y+height*h+Math.cos(v)*ry*s,z+dz*s+Math.sin(u)*sn*rz*s*r];},(u,v)=>tint(leaf,.91+.10*Math.cos(v)+i*.017),-1,distant?18:28,distant?10:16);
    }
    if(!distant){
      ring(m,x-1.1*s,y+height*.38,z+6*s,1.65*s,3.2*s,tint(bark,.78),.30*s);
      for(let j=0;j<3;j++){
        const xx=x+bend+(j-1)*19*s,yy=y+height*.89+(j%2)*10*s,zz=z+30*s;
        tools.leaf(m,[xx,yy,zz],[xx+11*s,yy+5*s,zz+1],3.3*s,tint(leaf,1.12),key+j,-1,7);
      }
      if(key%3===0)for(let j=0;j<3;j++){
        const xx=x+bend+(j-1)*17*s,yy=y+height*.76+(j%2)*7*s,zz=z+22*s;
        blob(m,xx,yy,zz,4.2*s,4.6*s,4*s,['#f1b671','#e8bc82','#edb7a0'][j],-12,j);
        rod(m,[xx,yy+3.8*s,zz],[xx+.4*s,yy+6.7*s,zz],.36*s,'#897151');
        tools.leaf(m,[xx,yy+5*s,zz],[xx+5*s,yy+6.5*s,zz],1.5*s,'#67985a',j,-1,5);
      }
    }
  }
  function roof(m,x,y,z,s,col){
    // Gabled roof with overlapping, rounded cedar tiles and a curled ridge.
    const front=z+28*s,back=z-28*s,half=44*s;
    for(const side of [-1,1]){
      const p0=[x,y+26*s,front],p1=[x+side*half,y,front],p2=[x+side*half,y,back],p3=[x,y+26*s,back];
      const N=norm([side*.50,.86,0]);for(const p of [p0,p1,p2,p0,p2,p3])m.vertex(p,rgb(col),N,-4);
      for(let row=0;row<5;row++)for(let j=0;j<7;j++){
        const t=(row+.52)/5,xx=x+side*half*t,yy=y+26*s*(1-t)+.7*s,zz=front-(j+.5)*8*s+(row%2)*1.2*s;
        surface(m,(u,v)=>{const sn=Math.sin(v),a=Math.cos(u)*sn*5.35*s,b=Math.cos(v)*1.15*s;return[xx+a,yy-a*side*.58+b,zz+Math.sin(u)*sn*4.4*s];},tint(col,.98+seed(row*7+j)*.08),-4,10,6);
      }
      rod(m,[x,y+26*s,front+.9*s],[x+side*half,y,front+.9*s],1.5*s,'#f2ddb4');
      rod(m,[x+side*half,y,front],[x+side*half,y,back],1.4*s,'#c29465');
    }
    rod(m,[x,y+27.2*s,front+3*s],[x,y+27.2*s,back-3*s],2.0*s,'#ecd3a4');
  }
  function cottage(m,x,y,z,s,col,tools){
    // The houses are scenic, outside the player's reachable Z corridor.
    blob(m,x,y-2*s,z,43*s,5*s,33*s,'#b7ae8b',-5);
    box(m,x-36*s,y,z-23*s,72*s,44*s,46*s,'#f2dfb2',-4);
    triangle(m,[x-36*s,y+44*s,z+23*s],[x+36*s,y+44*s,z+23*s],[x,y+67*s,z+23*s],'#f2dfb2',[0,0,1]);
    for(let j=-3;j<=3;j++)rod(m,[x+j*10*s,y+2*s,z+23.12*s],[x+j*10*s,y+42*s,z+23.12*s],.17*s,'#d4c598');
    for(const side of [-1,1])rod(m,[x+side*35*s,y,z+23.7*s],[x+side*35*s,y+43*s,z+23.7*s],1.75*s,'#b48960');
    roof(m,x,y+43*s,z,s,col);
    blob(m,x,y+15*s,z+24*s,10.3*s,15*s,1.2*s,'#96b5a0',-4);
    ring(m,x,y+15*s,z+25.3*s,10.5*s,15.1*s,'#b38960',1.1*s);
    for(let j=-2;j<=2;j++)rod(m,[x+j*3*s,y+4*s,z+25.18*s],[x+j*3*s,y+25*s,z+25.18*s],.16*s,'#688b7c');
    blob(m,x+5.9*s,y+13.4*s,z+26*s,.8*s,.8*s,.9*s,'#e9bb6f',-8);
    for(const side of [-1,1]){
      const xx=x+side*23*s;
      blob(m,xx,y+27*s,z+24*s,7*s,8*s,1*s,'#769fa0',-8);
      ring(m,xx,y+27*s,z+25*s,7.3*s,8.3*s,'#b1845c',1.0*s);
      rod(m,[xx-6*s,y+27*s,z+25.3*s],[xx+6*s,y+27*s,z+25.3*s],.47*s,'#f7e2b2');
      rod(m,[xx,y+20*s,z+25.3*s],[xx,y+34*s,z+25.3*s],.47*s,'#f7e2b2');
      box(m,xx-8*s,y+15*s,z+23.8*s,16*s,4.1*s,4*s,'#ae805a');
      for(let j=0;j<3;j++)tools.blossom(m,xx+(j-1)*5*s,y+18*s,z+27*s,1.45*s,['#f5b4a9','#f4dfa6','#b4aed3'][j],j);
    }
    for(let j=0;j<3;j++)blob(m,x+(j-1)*7*s,y+.3*s,z+36*s,4.8*s,1.0*s,5.2*s,'#d2c4a2',-5,j);
    // A chimney with a capped brick stack and hand-placed joints.
    box(m,x+23*s,y+55*s,z-11*s,8*s,21*s,9*s,'#c99979');
    for(let j=0;j<4;j++)box(m,x+22.8*s,y+(57+j*4.7)*s,z-11.2*s,8.4*s,.6*s,9.4*s,'#e4c0a0');
    box(m,x+21.5*s,y+76*s,z-12.5*s,11*s,2.4*s,12*s,'#dfc39c');
  }
  function picket(m,x,y,z,width,s=1){
    for(let i=0;i<=width/8;i++){
      const xx=x+i*8;
      box(m,xx-1.1*s,y,z-1.1*s,2.2*s,12*s,2.2*s,'#e8d6ae');
      blob(m,xx,y+12*s,z,1.1*s,1.3*s,1.1*s,'#e8d6ae',-6);
    }
    for(const h of [3.5,8.5])rod(m,[x-2,y+h*s,z-.7],[x+width+2,y+h*s,z-.7],.85*s,'#c7ab7c');
  }
  function bush(m,x,y,z,s,tools,key=0){
    for(const [dx,dy,dz,r]of [[-8,6,0,9],[5,7,0,11],[0,10,-4,10]])blob(m,x+dx*s,y+dy*s,z+dz*s,r*s,r*.75*s,r*.75*s,['#8cb866','#70af70','#9bc17a'][Math.abs(dx)%3],-1,key+dx);
    if(key%2===0)for(let j=0;j<3;j++)tools.blossom(m,x-5*s+j*5*s,y+11*s,z+6*s,1.2*s,'#f1d4ae',j);
  }
  function bench(m,x,y,z,s=1){
    for(const side of [-1,1]){
      rod(m,[x+side*12*s,y,z],[x+side*12*s,y+17*s,z],1.2*s,'#7e986c');
      rod(m,[x+side*12*s,y,z+8*s],[x+side*12*s,y+8*s,z+8*s],1.2*s,'#7e986c');
    }
    for(const yy of [13,17])box(m,x-16*s,y+yy*s,z-1.2*s,32*s,3*s,2.4*s,'#dab17c');
    for(const zz of [1.3,4.8,8.1])box(m,x-17*s,y+8*s,z+zz*s,34*s,1.8*s,3*s,'#e6c691');
  }
  function garden(m,world,tools){
    for(const [x,s,col] of [[185,.87,'#83a989'],[566,.77,'#c48980'],[1450,.84,'#86aaa7'],[1905,.97,'#b7a079']]){
      const z=-132,y=-4;
      cottage(m,x,y,z,s,col,tools);
      picket(m,x-58*s,y,z+27*s,20*s,.70);picket(m,x+37*s,y,z+27*s,20*s,.70);
      bush(m,x-47*s,y,z+10*s,.88,tools,3);bush(m,x+50*s,y,z+15*s,1.0,tools,2);
    }
    bench(m,295,-2,-112,.80);bench(m,1344,-2,-117,.88);
    // Sculpted river stones ground the banks without a rectangular tile edge.
    for(const p of world.platforms.filter(p=>p.kind==='earth'))for(let i=0;i<p.w/18;i++){
      const x=p.x+8+i*18,y=p.y+p.h-7-seed(i)*3,z=p.z+p.d-1;
      blob(m,x,y,z,10+seed(i+30)*3,6.5+seed(i+40)*2.2,4.3,'#aaa789',-5,i);
    }
    // Rounded hedges and garden color stay below the scene's silhouettes.
    for(let i=0;i<22;i++){
      const x=-135+i*103;if(x>680&&x<1005)continue;
      if(world.obstacles.some(o=>Math.abs(o.x-x)<60))continue;
      bush(m,x,0,-94,.77,tools,i);
    }
    // Footpaths receive individually rounded pavers near village entries.
    for(const center of [178,565,1435,1870])for(let j=0;j<4;j++)blob(m,center+(j%2)*2,.09,-22-j*15,5.1,1.0,6.7,'#c8be95',-5,j);
    // Bunting frames the opening garden, rather than obscuring the controls.
    const a=[100,55,-108],b=[265,51,-108];
    for(const p of [a,b])rod(m,[p[0],-3,p[2]],p,1.05,'#bd9667');
    const line=[];for(let j=0;j<=24;j++){const u=j/24;line.push([mix(a[0],b[0],u),mix(a[1],b[1],u)-8*Math.sin(u*Math.PI),-108]);}curve(m,line,.18,'#dabf91');
    for(let j=1;j<12;j++){
      const u=j/12,x=mix(a[0],b[0],u),y=mix(a[1],b[1],u)-8*Math.sin(u*Math.PI),col=['#dfa491','#e5c57a','#8ebbae','#a3b894'][j%4];
      triangle(m,[x-3.8,y,-107.8],[x+3.8,y,-107.8],[x,y-7.5,-107.5],col,[0,0,1]);
    }
  }
  function animate(m,world,state,tools){
    const t=state.time||0,x=state.cameraX,p=state.player;
    if(!state.reduced)for(let i=0;i<5;i++){
      const cx=x-190+i*103+Math.sin(t*.43+i)*18,cy=22+seed(i+42)*57+Math.sin(t*1.4+i)*5,z=-55-seed(i+21)*45;
      const flap=Math.sin(t*8.4+i*2.1)*.80;
      for(const side of [-1,1]){
        const center=[cx,cy,z],tip=[cx+side*(2.3+Math.cos(flap)*1.8),cy+.6+Math.sin(flap)*3.2,z+Math.sin(flap)*2.4];
        tools.leaf(m,center,tip,1.55,['#f7db9d','#edb7b4','#bca8d9'][i%3],i,-12,5);
      }
      rod(m,[cx,cy-1.2,z],[cx,cy+1.2,z],.20,'#876e55');
    }
    // A bounded ring of dew beads follows the existing morph choreography.
    if(state.transitioning&&!state.reduced){
      const strength=Math.sin(Math.PI*Math.min(1,state.transitionProgress));
      for(let i=0;i<9;i++){
        const a=i/9*TAU-t*1.8,r=13+strength*7,u=i/8;
        tools.ellipsoid(m,p.x+Math.cos(a)*r,p.y+(state.water?.lift||0)+8+u*22,p.z+Math.sin(a)*r*.7,.45,.75,.45,i%2?'#d3f5e4':'#f6dcb7',.24,8,6);
      }
    }
  }
  window.TD_GROVE=Object.freeze({canopyTree,garden,animate,blob,version:'2.3',identity:'Sunshower Grove',features:['scalloped orchard canopies','rounded cedar-shingle cottages','garden benches and picket fences','pastel bunting','butterfly wing animation','rounded bank stones']});
})();
