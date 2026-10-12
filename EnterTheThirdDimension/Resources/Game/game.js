/* Enter the Third Dimension. Original fixed-step gameplay, touch input and sound.
 * Simulation runs at 120 Hz, independent of display refresh. No network access.
 */
(() => {
  'use strict';
  const $=id=>document.getElementById(id),W=window.TD_WORLD;
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v)),approach=(v,t,a)=>v<t?Math.min(t,v+a):Math.max(t,v-a);
  const ease=t=>t*t*(3-2*t),STEP=1/120;
  const PHYS=Object.freeze({speed:132,acceleration:1250,airAcceleration:930,brake:1600,gravity:930,jump:342,release:125,maxFall:510,coyote:.12,buffer:.15,halfWidth:8,height:28,halfDepth:4});
  const storageKey='third-dimension.chapter1.v2';
  let settings={sound:true,reduced:matchMedia('(prefers-reduced-motion: reduce)').matches},saved=null;
  try{const s=JSON.parse(localStorage.getItem(storageKey)||'null');if(s&&s.version===2){settings.sound=s.sound!==false;settings.reduced=typeof s.reduced==='boolean'?s.reduced:settings.reduced;if(s.progress&&typeof s.progress==='object')saved=s.progress;}}catch(_){}
  let mode='title',renderer=null,fatal=null,time=0,elapsed=0,frames=0,lastTime=0,accumulator=0,renderDirty=true,lastRenderedMode='';
  let dimension=2,dimensionBlend=0,transition=null,pulse=0,cameraX=220,cameraZ=0;
  let hasPrism=false,hasSpark=false,beaconLit=false,gateOpen=0,checkpointIndex=-1,deaths=0,jumps=0,shifts=0;
  let jumpBuffer=0,coyote=PHYS.coyote,respawnTimer=0,toastTimer=0,dialogueTimer=0,ambientTimer=0,saveTimer=0;
  let collected=new Set(),particles=[],seenDialogues=new Set(),lastObjective='',lastShardCount=-1;
  const player={x:445,y:0,z:40,vx:0,vy:0,vz:0,grounded:true,facing:1,walk:0};
  const keys=new Set(),padTouches=new Map(),jumpTouches=new Set(),errors=[];
  let audioContext=null;
  const input={x:0,z:0};
  function unlockAudio(){
    if(!settings.sound)return;try{const A=window.AudioContext||window.webkitAudioContext;if(!audioContext&&A)audioContext=new A();if(audioContext&&audioContext.state!=='running')audioContext.resume().catch(()=>{});}catch(_){}
  }
  function tone(f,d=.18,v=.035,delay=0,type='sine',end){
    if(!settings.sound||!audioContext||audioContext.state!=='running')return;
    try{const o=audioContext.createOscillator(),g=audioContext.createGain(),at=audioContext.currentTime+delay;o.type=type;o.frequency.setValueAtTime(f,at);if(end)o.frequency.exponentialRampToValueAtTime(end,at+d);g.gain.setValueAtTime(.0001,at);g.gain.exponentialRampToValueAtTime(v,at+.012);g.gain.exponentialRampToValueAtTime(.0001,at+d);o.connect(g);g.connect(audioContext.destination);o.start(at);o.stop(at+d+.02);o.onended=()=>{o.disconnect();g.disconnect();};}catch(_){}
  }
  function sound(name){
    if(name==='jump')tone(220,.16,.035,0,'triangle',480);
    if(name==='land')tone(92,.06,.019,0,'triangle',62);
    if(name==='shard'){tone(880,.16,.022);tone(1320,.24,.018,.07);}
    if(name==='prism'||name==='spark')[330,440,554,660,880].forEach((f,i)=>tone(f,.42,.025,i*.065));
    if(name==='shift'){tone(dimension===2?165:660,.75,.03,0,'sine',dimension===2?660:165);[330,495,660].forEach((f,i)=>tone(f,.6,.023,i*.075));}
    if(name==='checkpoint')[392,494,659].forEach((f,i)=>tone(f,.3,.024,i*.09));
    if(name==='fall')tone(300,.27,.028,0,'triangle',110);
    if(name==='complete')[330,440,554,660,880,1108].forEach((f,i)=>tone(f,.6,.029,i*.12));
  }
  function persist(){
    const progress={checkpointIndex,hasPrism,hasSpark,beaconLit,collected:[...collected],deaths,jumps,shifts,elapsed,completed:mode==='complete'};
    if(mode!=='title')saved=progress;
    try{localStorage.setItem(storageKey,JSON.stringify({version:2,sound:settings.sound,reduced:settings.reduced,progress:saved}));}catch(_){}
  }
  function refreshSettings(){
    $('sound').textContent=settings.sound?'Sound on':'Sound off';$('sound').setAttribute('aria-pressed',String(settings.sound));$('effects').textContent=settings.reduced?'Reduced effects':'Full effects';$('effects').setAttribute('aria-pressed',String(settings.reduced));document.body.classList.toggle('reduced-effects',settings.reduced);
  }
  function heldJump(){return keys.has('Space')||jumpTouches.size>0;}
  function readInput(){
    let x=Number(keys.has('ArrowRight')||keys.has('KeyD'))-Number(keys.has('ArrowLeft')||keys.has('KeyA'));
    let z=dimension===3?Number(keys.has('ArrowDown')||keys.has('KeyS'))-Number(keys.has('ArrowUp')||keys.has('KeyW')):0;
    for(const v of padTouches.values()){x+=v.x;z+=dimension===3?v.z:0;}
    const length=Math.hypot(x,z);if(length>1){x/=length;z/=length;}input.x=x;input.z=z;return input;
  }
  function updateControlVisuals(){
    readInput();document.querySelector('.pad-left').classList.toggle('active',input.x<-.1);document.querySelector('.pad-right').classList.toggle('active',input.x>.1);$('jump').classList.toggle('pressed',heldJump());$('stick').style.transform=`translate(${input.x*29}px,${input.z*29}px)`;
  }
  function clearInputs(){keys.clear();padTouches.clear();jumpTouches.clear();jumpBuffer=0;input.x=0;input.z=0;updateControlVisuals();}
  const prevent=e=>{if(e.cancelable)e.preventDefault();};
  function padValue(e){
    const r=$('movePad').getBoundingClientRect(),cx=r.left+r.width/2,cy=r.top+r.height/2;
    if(e.clientX<r.left-85||e.clientX>r.right+85||e.clientY<r.top-85||e.clientY>r.bottom+85)return{x:0,z:0};
    if(dimension===2)return{x:e.clientX<cx?-1:1,z:0};
    let x=(e.clientX-cx)/(r.width*.36),z=(e.clientY-cy)/(r.height*.36),l=Math.hypot(x,z);if(l<.17)return{x:0,z:0};if(l>1){x/=l;z/=l;}return{x,z};
  }
  $('movePad').addEventListener('pointerdown',e=>{prevent(e);if(mode!=='playing'||transition)return;unlockAudio();padTouches.set(e.pointerId,padValue(e));try{$('movePad').setPointerCapture(e.pointerId);}catch(_){}updateControlVisuals();});
  $('movePad').addEventListener('pointermove',e=>{if(!padTouches.has(e.pointerId))return;prevent(e);padTouches.set(e.pointerId,padValue(e));updateControlVisuals();});
  for(const name of ['pointerup','pointercancel','lostpointercapture'])$('movePad').addEventListener(name,e=>{padTouches.delete(e.pointerId);updateControlVisuals();});
  $('jump').addEventListener('pointerdown',e=>{prevent(e);if(mode!=='playing'||transition)return;unlockAudio();const held=heldJump();jumpTouches.add(e.pointerId);if(!held)jumpBuffer=PHYS.buffer;try{$('jump').setPointerCapture(e.pointerId);}catch(_){}updateControlVisuals();});
  for(const name of ['pointerup','pointercancel','lostpointercapture'])$('jump').addEventListener(name,e=>{jumpTouches.delete(e.pointerId);updateControlVisuals();});
  $('power').addEventListener('click',()=>requestShift());
  const gameKeys=new Set(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','KeyA','KeyD','KeyW','KeyS','Space','KeyE','ShiftLeft','ShiftRight']);
  window.addEventListener('keydown',e=>{
    if(e.code==='Escape'||e.code==='KeyP'){prevent(e);if(!e.repeat){if(mode==='paused')resume();else pause();}return;}
    if(!gameKeys.has(e.code))return;prevent(e);if(mode!=='playing')return;unlockAudio();
    if(e.code==='KeyE'||e.code==='ShiftLeft'||e.code==='ShiftRight'){if(!e.repeat)requestShift();return;}
    if(transition)return;const before=heldJump();keys.add(e.code);if(!before&&heldJump())jumpBuffer=PHYS.buffer;updateControlVisuals();
  });
  window.addEventListener('keyup',e=>{if(gameKeys.has(e.code)){prevent(e);keys.delete(e.code);updateControlVisuals();}});
  document.addEventListener('contextmenu',prevent);document.addEventListener('dragstart',prevent);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)nativePause();});window.addEventListener('blur',nativePause);
  function showToast(text,duration=3.5){$('toast').textContent=text;toastTimer=duration;$('toast').classList.add('show');}
  function dialogue(name,text,duration=5.5){$('speaker').textContent=name;$('dialogueText').textContent=text;dialogueTimer=duration;$('dialogue').classList.remove('hidden');}
  function hideOverlays(){for(const id of ['title','pauseOverlay','completeOverlay'])$(id).classList.add('hidden');}
  function syncDimensionUI(){
    document.body.classList.toggle('in3d',dimension===3);$('dimensionBadge').innerHTML=dimension===3?'3D <i>THE UNFOLD</i>':'2D <i>THE FOLD</i>';
    $('powerText').textContent=!hasPrism?'FIND PRISM':dimension===3?'RETURN 2D':'ENTER 3D';$('power').disabled=!hasPrism||!!transition;
    $('power').setAttribute('aria-label',dimension===3?'Return to two dimensions':'Enter the third dimension');$('moveLabel').textContent=dimension===3?'MOVE + DEPTH':'MOVE';
    $('power').classList.toggle('pulse',hasPrism&&shifts===0);
  }
  function updateHUD(){
    let objective=!hasPrism?'Find the prism':player.x<420&&checkpointIndex<0?'Step around the paper wall':!hasSpark&&!beaconLit?'Find the spark behind the road':!beaconLit?'Carry the spark to the lantern':'Follow the light through the gate';
    if(objective!==lastObjective){lastObjective=objective;$('objectiveText').textContent=objective;}
    if(lastShardCount!==collected.size){lastShardCount=collected.size;$('shards').textContent=`✦ ${collected.size} / ${W.shards.length}`;}
  }
  function resetPlayer(at){Object.assign(player,{x:at.x,y:at.y,z:at.z||0,vx:0,vy:0,vz:0,grounded:true,facing:1,walk:0});coyote=PHYS.coyote;jumpBuffer=0;}
  function start(continuing=false){
    hasPrism=false;hasSpark=false;beaconLit=false;checkpointIndex=-1;collected=new Set();deaths=0;jumps=0;shifts=0;elapsed=0;seenDialogues=new Set();
    if(continuing&&saved&&!saved.completed){checkpointIndex=clamp(Math.floor(Number(saved.checkpointIndex)||0),-1,W.checkpoints.length-1);hasPrism=!!saved.hasPrism;hasSpark=!!saved.hasSpark;beaconLit=!!saved.beaconLit;collected=new Set((Array.isArray(saved.collected)?saved.collected:[]).filter(i=>Number.isInteger(i)&&i>=0&&i<W.shards.length));deaths=Math.max(0,Number(saved.deaths)||0);jumps=Math.max(0,Number(saved.jumps)||0);shifts=Math.max(0,Number(saved.shifts)||0);elapsed=Math.max(0,Number(saved.elapsed)||0);}
    dimension=2;dimensionBlend=0;transition=null;pulse=0;gateOpen=beaconLit?1:0;particles=[];clearInputs();resetPlayer(checkpointIndex>=0?W.checkpoints[checkpointIndex]:W.spawn);
    cameraX=Math.max(175,player.x+80);cameraZ=0;mode='playing';fatal=null;lastTime=0;accumulator=0;toastTimer=0;dialogueTimer=0;ambientTimer=2;saveTimer=0;lastObjective='';lastShardCount=-1;document.body.classList.remove('shifting');hideOverlays();$('dialogue').classList.add('hidden');$('hud').classList.remove('hidden');$('controls').classList.remove('hidden');syncDimensionUI();updateHUD();unlockAudio();
    showToast(hasPrism?'Your progress is saved at the lantern.':'Move with the left pad. Hold jump to go higher.',4.5);persist();
  }
  function home(){mode='title';clearInputs();hideOverlays();$('title').classList.remove('hidden');$('hud').classList.add('hidden');$('controls').classList.add('hidden');$('dialogue').classList.add('hidden');$('toast').classList.remove('show');transition=null;document.body.classList.remove('shifting','in3d');resetPlayer({x:445,y:0,z:40});cameraX=220;cameraZ=0;hasPrism=false;collected=new Set();beaconLit=false;gateOpen=0;$('play').innerHTML=(saved&&!saved.completed?'Continue the story':'Begin the story')+' <span aria-hidden="true">↗</span>';}
  function pause(){
    if(mode!=='playing'&&mode!=='respawning')return;
    if(mode==='respawning'){resetPlayer(checkpointIndex>=0?W.checkpoints[checkpointIndex]:W.spawn);dimension=2;dimensionBlend=0;transition=null;syncDimensionUI();}
    mode='paused';clearInputs();player.vx=0;player.vz=0;accumulator=0;$('pauseOverlay').classList.remove('hidden');$('controls').classList.add('hidden');$('dialogue').classList.add('hidden');persist();if(audioContext)audioContext.suspend().catch(()=>{});
  }
  function resume(){if(mode!=='paused'||(renderer&&renderer.contextLost)||fatal)return;clearInputs();mode='playing';lastTime=0;accumulator=0;$('pauseOverlay').classList.add('hidden');$('controls').classList.remove('hidden');if(dialogueTimer>0)$('dialogue').classList.remove('hidden');unlockAudio();}
  function nativePause(){pause();clearInputs();if(audioContext)audioContext.suspend().catch(()=>{});}
  function solids(){return W.platforms.concat(W.obstacles.filter(o=>o.kind!=='gate'||!beaconLit));}
  function overlapsXZ(p,b){return p.x+PHYS.halfWidth>b.x+.01&&p.x-PHYS.halfWidth<b.x+b.w-.01&&p.z+PHYS.halfDepth>b.z+.01&&p.z-PHYS.halfDepth<b.z+b.d-.01;}
  function overlapsY(p,b){return p.y+PHYS.height>b.y+.02&&p.y<b.y+b.h-.02;}
  function foldSafety(){
    if(!hasPrism)return{safe:false,reason:'Find the prism first.'};if(transition)return{safe:false,reason:'The world is still unfolding.'};
    if(!player.grounded)return{safe:false,reason:'Land on solid ground before shifting.'};
    if(dimension===2)return{safe:true,reason:''};
    const at={...player,z:0};
    const blocked=solids().some(b=>overlapsY(at,b)&&at.x+PHYS.halfWidth>b.x+.01&&at.x-PHYS.halfWidth<b.x+b.w-.01&&Math.min(player.z,0)-PHYS.halfDepth<b.z+b.d-.01&&Math.max(player.z,0)+PHYS.halfDepth>b.z+.01);
    if(blocked)return{safe:false,reason:'Step clear of the paper wall before folding back.'};
    const floor=W.platforms.find(b=>overlapsXZ(at,b)&&Math.abs(player.y-(b.y+b.h))<.75);
    if(!floor)return{safe:false,reason:'Return to the main path before folding back.'};
    return{safe:true,reason:''};
  }
  function burst(x,y,z,count,color,speed=50){for(let i=0;i<count;i++){const a=i*2.399963+time;particles.push({x,y,z,vx:Math.cos(a)*speed*(.3+(i%5)/6),vy:25+(i%7)*speed/7,vz:Math.sin(a)*speed*.7,life:.65+(i%4)*.15,max:1.1,size:1.5+(i%3),color});}if(particles.length>160)particles.splice(0,particles.length-160);}
  function requestShift(){
    if(mode!=='playing'||transition)return;
    const safety=foldSafety();if(!safety.safe){showToast(safety.reason,2.8);tone(185,.14,.018);return;}
    unlockAudio();sound('shift');const next=dimension===2?3:2;transition={from:dimensionBlend,to:next===3?1:0,elapsed:0,duration:settings.reduced?.5:.85,startZ:player.z,target:next};shifts++;clearInputs();player.vx=0;player.vz=0;player.vy=0;
    dimension=next;document.body.classList.remove('shifting');void document.body.offsetWidth;document.body.classList.add('shifting');syncDimensionUI();burst(player.x,player.y+14,player.z,settings.reduced?8:32,'#a6fce0',68);
    $('dialogue').classList.add('hidden');dialogueTimer=0;showToast(next===3?'The pad has unfolded. Up / down now move through depth.':'Back in the fold. A different way forward.',4.1);
  }
  function updateTransition(dt){
    transition.elapsed+=dt;const p=clamp(transition.elapsed/transition.duration,0,1);dimensionBlend=transition.from+(transition.to-transition.from)*ease(p);if(transition.target===2)player.z=transition.startZ*(1-ease(p));pulse=Math.sin(p*Math.PI);
    if(p>=1){dimensionBlend=transition.to;player.z=transition.target===2?0:player.z;transition=null;pulse=0;document.body.classList.remove('shifting');syncDimensionUI();persist();}
  }
  function die(){if(mode!=='playing')return;deaths++;mode='respawning';respawnTimer=.65;clearInputs();sound('fall');burst(player.x,Math.max(-20,player.y+15),player.z,22,'#ebc5a2',70);showToast('A little tumble. Your lantern is right here.',2.6);}
  function finish(){
    mode='complete';clearInputs();player.vx=0;player.vz=0;dialogueTimer=0;$('dialogue').classList.add('hidden');$('toast').classList.remove('show');$('controls').classList.add('hidden');$('completeOverlay').classList.remove('hidden');sound('complete');
    $('results').textContent=`✦ ${collected.size} of ${W.shards.length} shards found · ${shifts} dimensional shifts`;
    burst(player.x,player.y+35,player.z,60,'#b9ffdc',105);persist();
  }
  function simulate(dt){
    if(mode!=='playing')return;elapsed+=dt;saveTimer+=dt;if(saveTimer>15){saveTimer=0;persist();}
    if(transition){updateTransition(dt);return;}
    const dir=readInput();coyote=player.grounded?PHYS.coyote:Math.max(0,coyote-dt);jumpBuffer=Math.max(0,jumpBuffer-dt);
    if(jumpBuffer>0&&coyote>0){player.vy=PHYS.jump;player.grounded=false;coyote=0;jumpBuffer=0;jumps++;sound('jump');burst(player.x,player.y+2,player.z,5,'#b6c9b3',27);}
    if(!heldJump()&&player.vy>PHYS.release)player.vy=PHYS.release;
    const accel=player.grounded?PHYS.acceleration:PHYS.airAcceleration;
    player.vx=approach(player.vx,dir.x*PHYS.speed,(dir.x?accel:PHYS.brake)*dt);player.vz=dimension===3?approach(player.vz,dir.z*PHYS.speed,(dir.z?accel:PHYS.brake)*dt):0;
    if(Math.abs(player.vx)>3)player.facing=player.vx>0?1:-1;player.walk+=Math.hypot(player.vx,player.vz)*dt/90;
    const boxes=solids();
    player.x+=player.vx*dt;
    for(const b of boxes){if(overlapsXZ(player,b)&&overlapsY(player,b)){if(player.vx>0)player.x=b.x-PHYS.halfWidth;else if(player.vx<0)player.x=b.x+b.w+PHYS.halfWidth;player.vx=0;}}
    player.z+=player.vz*dt;
    for(const b of boxes){if(overlapsXZ(player,b)&&overlapsY(player,b)){if(player.vz>0)player.z=b.z-PHYS.halfDepth;else if(player.vz<0)player.z=b.z+b.d+PHYS.halfDepth;player.vz=0;}}
    const oldY=player.y,wasGrounded=player.grounded;player.vy=Math.max(-PHYS.maxFall,player.vy-PHYS.gravity*dt);player.y+=player.vy*dt;player.grounded=false;
    for(const b of boxes){
      if(!overlapsXZ(player,b))continue;
      const top=b.y+b.h;
      if(player.vy<=0&&oldY>=top-.1&&player.y<=top){player.y=top;player.vy=0;player.grounded=true;}
      else if(player.vy>0&&oldY+PHYS.height<=b.y+.1&&player.y+PHYS.height>=b.y){player.y=b.y-PHYS.height;player.vy=0;}
    }
    if(player.grounded&&!wasGrounded){sound('land');burst(player.x,player.y+1,player.z,4,'#a9c3b2',20);}
    player.x=clamp(player.x,-105,W.width-22);
    if(player.y< -150){die();return;}
    const near=(c,x=18,y=22,z=14)=>Math.abs(player.x-c.x)<x&&Math.abs(player.y+15-c.y)<y&&Math.abs(player.z-c.z)<z;
    if(!hasPrism&&near(W.prism,24,28,15)){hasPrism=true;sound('prism');burst(W.prism.x,W.prism.y,0,38,'#c5adff',80);syncDimensionUI();dialogue('The prism','A new direction, hiding in plain sight. Tap the glowing cube to enter the third dimension.',6.5);showToast('POWER FOUND · Enter the third dimension',4.4);persist();}
    W.shards.forEach((c,i)=>{if(!collected.has(i)&&near(c,15,20,12)){collected.add(i);sound('shard');burst(c.x,c.y,c.z,7,'#ffe2a7',35);}});
    if(!hasSpark&&!beaconLit&&near(W.spark,20,27,15)){hasSpark=true;sound('spark');burst(W.spark.x,W.spark.y,W.spark.z,32,'#ffd395',75);dialogue('The lost spark','Warm as a tiny sunrise. Bring it to the lantern by the village gate.',5.8);persist();}
    if(hasSpark&&!beaconLit&&Math.abs(player.x-W.beacon.x)<32&&Math.abs(player.z)<20&&player.y<10){beaconLit=true;hasSpark=false;sound('complete');burst(W.beacon.x,42,0,52,'#ffe0a7',85);dialogue('The Keeper','You brought the light home. And you found a way the rest of us could never see.',7);showToast('THE GATE REMEMBERS',4);persist();}
    W.checkpoints.forEach((cp,i)=>{if(i>checkpointIndex&&player.x>=cp.x-10&&Math.abs(player.z)<32&&player.grounded&&Math.abs(player.y-cp.y)<2){checkpointIndex=i;sound('checkpoint');showToast('Lantern lit · Progress saved',2.6);persist();}});
    for(const n of W.npcs){if(!seenDialogues.has(n.id)&&Math.abs(player.x-n.x)<48&&Math.abs(player.z-n.z)<35){seenDialogues.add(n.id);if(dialogueTimer<=0)dialogue(n.name,n.lines.join(' '),6.3);}}
    if(hasPrism&&player.x>330&&player.x<357&&dimension===2&&!seenDialogues.has('wall')){seenDialogues.add('wall');showToast('Too tall to jump. What if you could walk around it?',4.5);}
    if(player.x>656&&player.x<721&&!seenDialogues.has('bridge')){seenDialogues.add('bridge');dialogue('A different perspective','The broken road has another path. Enter 3D, then move up into the scene to find the bridge.',7);}
    if(beaconLit&&player.x>W.finish.x&&Math.abs(player.z)<55&&player.grounded)finish();
    updateHUD();
  }
  function update(dt){
    if(mode==='paused'||mode==='error')return;
    time+=dt;
    if(mode==='title'){dimensionBlend=.73+Math.sin(time*.18)*.065;player.walk=0;}
    if(mode==='playing')simulate(dt);
    if(mode==='respawning'){respawnTimer-=dt;if(respawnTimer<=0){resetPlayer(checkpointIndex>=0?W.checkpoints[checkpointIndex]:W.spawn);dimension=2;dimensionBlend=0;transition=null;pulse=0;mode='playing';document.body.classList.remove('shifting');syncDimensionUI();cameraX=Math.max(175,player.x+80);cameraZ=0;}}
    gateOpen=approach(gateOpen,beaconLit?1:0,dt*.62);
    if(mode!=='title'){const targetX=clamp(player.x+80,175,W.width-155);cameraX+=(targetX-cameraX)*(1-Math.exp(-dt*4.6));cameraZ+=(player.z-cameraZ)*(1-Math.exp(-dt*3.3));}
    for(const p of particles){p.life-=dt;p.x+=p.vx*dt;p.y+=p.vy*dt;p.z+=p.vz*dt;p.vy-=110*dt;}particles=particles.filter(p=>p.life>0);
    toastTimer=Math.max(0,toastTimer-dt);if(!toastTimer)$('toast').classList.remove('show');dialogueTimer=Math.max(0,dialogueTimer-dt);if(!dialogueTimer)$('dialogue').classList.add('hidden');
    if(mode==='playing'&&!transition){ambientTimer-=dt;if(ambientTimer<=0){ambientTimer=5.5;const notes=dimension===3?[220,330,440,554]:[196,294,392,494];notes.forEach((f,i)=>tone(f,2,.006,i*.28));}}
  }
  function renderState(){return{mode,player,time,cameraX,cameraZ,dimension,dimensionBlend,transitioning:!!transition,transitionProgress:transition?transition.elapsed/transition.duration:0,pulse,reduced:settings.reduced,hasPrism,hasSpark,beaconLit,gateOpen,checkpointIndex,collected:[...collected],particles};}
  function showError(error){$('retry').classList.remove('hidden');fatal=String(error&&error.message||error);errors.push(fatal);mode='error';clearInputs();$('errorTitle').textContent='The world needs a fresh start.';$('errorText').textContent='The graphics renderer could not complete startup. Reload the game to try again.';$('rendererError').classList.remove('hidden');}
  function onLost(){nativePause();$('errorTitle').textContent='Rebuilding the world…';$('errorText').textContent='Your progress is safe. The graphics renderer is recovering.';$('retry').classList.add('hidden');$('rendererError').classList.remove('hidden');}
  function onRestored(){$('rendererError').classList.add('hidden');$('retry').classList.remove('hidden');lastTime=0;accumulator=0;renderDirty=true;if(mode==='paused')showToast('The world is ready. Continue when you are.',3.5);}
  function getState(){
    return{version:'2.0 (2)',ready:!!renderer&&renderer.frames>0&&!renderer.contextLost&&!fatal,mode,dimension,dimensionBlend,transitioning:!!transition,transitionProgress:transition?transition.elapsed/transition.duration:0,player:{...player,width:16,height:PHYS.height,depth:.6+dimensionBlend*8.4},camera:{x:cameraX,z:cameraZ,yaw:dimensionBlend*.72,elevation:dimensionBlend*.49},elapsed,deaths,jumps,shifts,hasPrism,hasSpark,beaconLit,gateOpen,checkpointIndex,checkpoint:checkpointIndex>=0?{...W.checkpoints[checkpointIndex]}:{...W.spawn},collected:[...collected],totalShards:W.shards.length,foldSafety:foldSafety(),input:{...readInput(),jumpHeld:heldJump(),touches:padTouches.size+jumpTouches.size},physics:{...PHYS},world:{platforms:W.platforms.map(x=>({...x})),obstacles:W.obstacles.map(x=>({...x})),npcs:W.npcs.map(n=>({id:n.id,x:n.x,y:n.y,z:n.z,depth:n.depth})),prism:{...W.prism},spark:{...W.spark},beacon:{...W.beacon},finish:{...W.finish}},renderer:renderer?renderer.getState():null,errors:[...errors],settings:{...settings},objective:lastObjective,playerScreen:renderer?renderer.project(player.x,player.y+15,player.z):null};
  }
  window.ThirdDimension=Object.freeze({get ready(){return!!renderer&&renderer.frames>0&&!renderer.contextLost&&!fatal;},get errors(){return [...errors];},getState,nativePause});window.Moonhop=Object.freeze({nativePause,getState});
  window.addEventListener('error',e=>{const msg=e.message||'Unknown script error';if(!errors.includes(msg))errors.push(msg);});window.addEventListener('unhandledrejection',e=>errors.push(String(e.reason)));
  $('play').addEventListener('click',()=>start(!!saved&&!saved.completed));$('pause').addEventListener('click',pause);$('resume').addEventListener('click',resume);$('restart').addEventListener('click',()=>start(false));$('replay').addEventListener('click',()=>start(false));$('home').addEventListener('click',home);$('retry').addEventListener('click',()=>location.reload());
  $('sound').addEventListener('click',()=>{settings.sound=!settings.sound;if(settings.sound)unlockAudio();else if(audioContext)audioContext.suspend().catch(()=>{});refreshSettings();persist();});$('effects').addEventListener('click',()=>{settings.reduced=!settings.reduced;renderDirty=true;refreshSettings();persist();});
  function resize(){try{if(renderer&&!renderer.contextLost)renderer.resize();renderDirty=true;if(innerHeight>innerWidth)nativePause();}catch(e){showError(e);}}
  window.addEventListener('resize',resize);
  function frame(timestamp){
    if(!lastTime)lastTime=timestamp;const dt=Math.min(.05,Math.max(0,(timestamp-lastTime)/1000));lastTime=timestamp;
    if(!document.hidden&&!fatal&&renderer&&!renderer.contextLost){
      accumulator+=dt;let steps=0;while(accumulator>=STEP&&steps<7){update(STEP);accumulator-=STEP;steps++;}
      if(mode!=='paused'||lastRenderedMode!=='paused'||renderDirty){try{renderer.draw(renderState());frames++;lastRenderedMode=mode;renderDirty=false;}catch(e){showError(e);}}
    }else accumulator=0;
    requestAnimationFrame(frame);
  }
  refreshSettings();home();
  try{renderer=new window.TD_Renderer($('world'),W,window.TD_ART,{lost:onLost,restored:onRestored,error:showError});resize();requestAnimationFrame(frame);}catch(e){showError(e);}
})();
