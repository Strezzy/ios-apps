/* Enter the Third Dimension. Original fixed-step gameplay, touch input and sound.
 * Simulation runs at 120 Hz, independent of display refresh. No network access.
 */
(() => {
  'use strict';
  const $=id=>document.getElementById(id),W=window.TD_WORLD;
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v)),approach=(v,t,a)=>v<t?Math.min(t,v+a):Math.max(t,v-a);
  const ease=t=>t*t*(3-2*t),STEP=1/120;
  const PHYS=Object.freeze({speed:132,acceleration:1250,airAcceleration:930,brake:1600,gravity:930,jump:342,release:125,maxFall:510,coyote:.12,buffer:.15,halfWidth:8,height:32,halfDepth:4});
  const FORMS=Object.freeze({girl:{name:'Girl',speed:132,jump:342,release:125,height:32,halfWidth:8,hint:'A shape made for exploring.'},frog:{name:'Frog',speed:118,jump:408,release:150,height:19,halfWidth:10,hint:'Higher, springier jumps.'},fox:{name:'Fox',speed:168,jump:330,release:125,height:23,halfWidth:11,hint:'A quicker way through the forest.'}});
  let creature='girl',unlockedForms=new Set(['girl']),formChanges=0;
  const formPhysics=()=>({...PHYS,...FORMS[creature]});
  const storageKey='third-dimension.chapter1.v2';
  let settings={sound:true,reduced:matchMedia('(prefers-reduced-motion: reduce)').matches},saved=null,introSeen=false;
  try{const s=JSON.parse(localStorage.getItem(storageKey)||'null');if(s&&s.version===2){introSeen=s.introSeen===true;settings.sound=s.sound!==false;settings.reduced=typeof s.reduced==='boolean'?s.reduced:settings.reduced;if(s.progress&&typeof s.progress==='object')saved=s.progress;}}catch(_){}
  let mode='title',renderer=null,fatal=null,time=0,elapsed=0,frames=0,lastTime=0,accumulator=0,renderDirty=true,lastRenderedMode='';
  let dimension=2,dimensionBlend=0,transition=null,pulse=0,cameraX=220,cameraZ=0;
  let hasPrism=false,hasSpark=false,beaconLit=false,gateOpen=0,checkpointIndex=-1,deaths=0,jumps=0,shifts=0;
  let jumpBuffer=0,coyote=PHYS.coyote,respawnTimer=0,toastTimer=0,dialogueTimer=0,ambientTimer=0,saveTimer=0;
  let collected=new Set(),particles=[],seenDialogues=new Set(),lastObjective='',lastShardCount=-1;
  const player={x:445,y:0,z:40,vx:0,vy:0,vz:0,grounded:true,facing:1,walk:0};
  let intro=null,pausedFrom='playing',cameraHeight=214,cameraY=45;
  const jelly={squash:1,squashVelocity:0,lean:0,leanVelocity:0,impact:0};
  const ramp=(t,a,b)=>ease(clamp((t-a)/(b-a),0,1));
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
    if(name==='jump'){tone(280,.18,.026,0,'sine',620);tone(840,.11,.009,.025,'sine',560);}
    if(name==='land')tone(180,.12,.022,0,'sine',64);
    if(name==='plop'){tone(520,.27,.045,0,'sine',70);tone(1100,.12,.018,.04,'sine',240);tone(170,.32,.018,.08);}
    if(name==='become')[330,495,660,990].forEach((f,i)=>tone(f,.75,.019,i*.14,'sine',f*1.13));
    if(name==='shard'){tone(880,.16,.022);tone(1320,.24,.018,.07);}
    if(name==='prism'||name==='spark')[330,440,554,660,880].forEach((f,i)=>tone(f,.42,.025,i*.065));
    if(name==='shift'){tone(dimension===2?165:660,1.25,.024,0,'sine',dimension===2?660:165);[330,495,660].forEach((f,i)=>tone(f,.7,.019,i*.16));}
    if(name==='checkpoint')[392,494,659].forEach((f,i)=>tone(f,.3,.024,i*.09));
    if(name==='fall')tone(300,.27,.028,0,'triangle',110);
    if(name==='complete')[330,440,554,660,880,1108].forEach((f,i)=>tone(f,.6,.029,i*.12));
  }
  function persist(){
    const progress={checkpointIndex,hasPrism,hasSpark,beaconLit,collected:[...collected],deaths,jumps,shifts,elapsed,creature:intro?intro.returnCreature:creature,unlockedForms:[...unlockedForms],formChanges,completed:mode==='complete'};
    if(mode!=='title')saved=progress;
    try{localStorage.setItem(storageKey,JSON.stringify({version:2,introSeen:intro?false:introSeen,sound:settings.sound,reduced:settings.reduced,progress:saved}));}catch(_){}
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
  $('formButton').addEventListener('click',()=>requestForm());
  const gameKeys=new Set(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','KeyA','KeyD','KeyW','KeyS','Space','KeyE','KeyQ','ShiftLeft','ShiftRight']);
  window.addEventListener('keydown',e=>{
    if(e.code==='Escape'||e.code==='KeyP'){prevent(e);if(!e.repeat){if(mode==='paused')resume();else pause();}return;}
    if(!gameKeys.has(e.code))return;prevent(e);if(mode!=='playing')return;unlockAudio();
    if(e.code==='KeyE'||e.code==='ShiftLeft'||e.code==='ShiftRight'){if(!e.repeat)requestShift();return;}
    if(e.code==='KeyQ'){if(!e.repeat)requestForm();return;}
    if(transition)return;const before=heldJump();keys.add(e.code);if(!before&&heldJump())jumpBuffer=PHYS.buffer;updateControlVisuals();
  });
  window.addEventListener('keyup',e=>{if(gameKeys.has(e.code)){prevent(e);keys.delete(e.code);updateControlVisuals();}});
  document.addEventListener('contextmenu',prevent);document.addEventListener('dragstart',prevent);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)nativePause();});window.addEventListener('blur',nativePause);
  function showToast(text,duration=3.5){if(dialogueTimer>0)return;$('toast').textContent=text;toastTimer=duration;$('toast').classList.add('show');}
  function dialogue(name,text,duration=5.5){toastTimer=0;$('toast').classList.remove('show');$('speaker').textContent=name;$('dialogueText').textContent=text;dialogueTimer=duration;$('dialogue').classList.remove('hidden');}
  function hideOverlays(){for(const id of ['title','pauseOverlay','completeOverlay'])$(id).classList.add('hidden');}
  function syncDimensionUI(){
    const visibleDimension=transition?(dimensionBlend>=.5?3:2):dimension;
    document.body.classList.toggle('in3d',visibleDimension===3);$('dimensionBadge').innerHTML=visibleDimension===3?'3D <i>THE UNFOLD</i>':'2D <i>THE FOLD</i>';
    $('powerText').textContent=transition?'REFORMING':!hasPrism?'FIND PRISM':dimension===3?'RETURN 2D':'ENTER 3D';$('power').disabled=!hasPrism||!!transition;
    $('power').setAttribute('aria-label',dimension===3?'Return to two dimensions':'Enter the third dimension');$('moveLabel').textContent=dimension===3?'MOVE + DEPTH':'MOVE';
    $('power').classList.toggle('pulse',hasPrism&&shifts===0);
    $('formText').textContent=FORMS[creature].name.toUpperCase();$('formCount').textContent=unlockedForms.size+'/3';$('formButton').disabled=unlockedForms.size<2||!!transition;$('formButton').setAttribute('aria-label','Current form: '+FORMS[creature].name+'. '+(unlockedForms.size<2?'Touch a forest creature to remember its shape.':'Change to the next remembered creature.'));$('formButton').classList.toggle('learned',unlockedForms.size>1);
  }
  function updateHUD(){
    let objective=!hasPrism?'Find the prism':player.x<420&&checkpointIndex<0?'Step around the enchanted leaf':!hasSpark&&!beaconLit?'Find the spark behind the road':!beaconLit?'Carry the spark to the lantern':'Follow the light through the gate';
    if(objective!==lastObjective){lastObjective=objective;$('objectiveText').textContent=objective;}
    if(lastShardCount!==collected.size){lastShardCount=collected.size;$('shards').textContent=`✦ ${collected.size} / ${W.shards.length}`;}
  }
  function resetPlayer(at){Object.assign(player,{x:at.x,y:at.y,z:at.z||0,vx:0,vy:0,vz:0,grounded:true,facing:1,walk:0});coyote=PHYS.coyote;jumpBuffer=0;resetJelly();}
  function resetJelly(){Object.assign(jelly,{squash:1,squashVelocity:0,lean:0,leanVelocity:0,impact:0});}
  function updateJelly(dt){
    // Damped springs respond to the actual fixed-step movement and impact.
    // Collider dimensions stay stable while the water surface flexes around it.
    const intensity=settings.reduced?.32:1;
    const target=1+(player.grounded?Math.sin(player.walk*18)*.014:clamp(player.vy/2100,-.055,.14))*intensity;
    jelly.squashVelocity+=((target-jelly.squash)*180-jelly.squashVelocity*12)*dt;
    jelly.squash=clamp(jelly.squash+jelly.squashVelocity*dt,.72,1.25);
    const leanTarget=player.vx/PHYS.speed*.14*intensity;
    jelly.leanVelocity+=((leanTarget-jelly.lean)*110-jelly.leanVelocity*10)*dt;
    jelly.lean=clamp(jelly.lean+jelly.leanVelocity*dt,-.23,.23);
    jelly.impact=Math.max(0,jelly.impact-dt*2.2);
  }
  function beginIntro(returnAt){
    mode='intro';intro={elapsed:0,duration:12.4,stage:'',returnAt:{...returnAt},returnCreature:creature};creature='girl';
    resetPlayer(W.spawn);cameraX=108;cameraZ=0;cameraHeight=152;cameraY=42;
    document.body.classList.add('cinematic');$('controls').classList.add('hidden');$('introOverlay').classList.remove('hidden');$('toast').classList.remove('show');toastTimer=0;
    updateIntro(0);
  }
  function endIntro(){
    if(!intro)return;
    const returnAt=intro.returnAt;creature=intro.returnCreature;intro=null;introSeen=true;mode='playing';resetPlayer(returnAt);
    cameraX=Math.max(140,player.x+58);cameraZ=0;cameraHeight=214;cameraY=45;
    clearInputs();document.body.classList.remove('cinematic');$('introOverlay').classList.add('hidden');$('controls').classList.remove('hidden');syncDimensionUI();updateHUD();
    showToast('Move with the left pad. Hold jump to spring higher.',4.5);persist();
  }
  function updateIntro(dt){
    intro.elapsed=Math.min(intro.duration,intro.elapsed+dt);const t=intro.elapsed;
    const stage=t<1.7?'leaf':t<2.3?'falling':t<3.25?'splash':t<5.3?'watching':t<6.6?'reaching':t<7.35?'melting':t<9.3?'becoming':t<10.8?'firstSteps':'waking';
    if(stage!==intro.stage){
      intro.stage=stage;
      const captions={leaf:'It began with a drop of rain.',falling:'',splash:'',watching:'A curious visitor came closer.',reaching:'One gentle touch. A shape to remember.',melting:'Almost.',becoming:'And tried again.',firstSteps:'The rain had never walked before.',waking:'Every life held another possibility.'};
      $('introCaption').textContent=captions[stage];$('introCaption').classList.toggle('has-caption',!!captions[stage]);
      if(stage==='splash'){sound('plop');burst(player.x,2,0,settings.reduced?7:25,'#b6f7ff',50);}
      if(stage==='becoming')sound('become');
      if(stage==='firstSteps'){tone(740,.3,.013);burst(player.x,5,0,settings.reduced?3:9,'#d2ffff',25);}
    }
    const pull=ramp(t,10.8,12.4);cameraX=108+32*pull;cameraHeight=152+62*pull;cameraY=42+3*pull;
    if(t>=intro.duration)endIntro();
  }
  function waterState(){
    const intensity=settings.reduced?.3:1;
    const water={creature,form:1,lift:0,squash:jelly.squash,lean:jelly.lean,wobble:((jelly.squash-1)*2.5+Math.sin(time*3.1)*.017)*intensity,ripple:jelly.impact,look:player.facing,intro:!!intro};
    if(intro){
      const t=intro.elapsed;water.lean=0;water.wobble=.045*intensity;
      if(t<1.7){water.form=0;water.lift=86;water.squash=1+Math.sin(t*5)*.06*intensity;}
      else if(t<2.3){const p=clamp((t-1.7)/.6,0,1);water.form=0;water.lift=86*(1-p*p);water.squash=1+p*.4*intensity;}
      else if(t<3.25){const p=(t-2.3)/.95;water.form=0;water.squash=1-.72*Math.cos(p*9)*Math.exp(-p*4);water.ripple=1-p;}
      else if(t<5.3){water.form=0;water.squash=.94+Math.sin(t*3)*.035;water.lean=.1*ramp(t,3.3,4.1);}
      else if(t<6.6){water.form=.76*ramp(t,5.3,6.6);water.squash=1;water.lift=1.2*Math.sin(ramp(t,5.3,6.6)*Math.PI);}
      else if(t<7.35){water.form=.76*(1-ramp(t,6.6,7.35));water.squash=1-.2*Math.sin(ramp(t,6.6,7.35)*Math.PI);}
      else if(t<9.3){water.form=ramp(t,7.35,9.3);water.squash=1+Math.sin(water.form*Math.PI)*.06*intensity;water.lift=Math.sin(water.form*Math.PI)*1.5;}
      else{water.form=1;water.squash=1+Math.sin((t-9.3)*10)*Math.exp(-(t-9.3)*2)*.08*intensity;water.lean=Math.sin((t-9.3)*3)*.025*intensity;}
      return water;
    }
    if(transition){
      const p=clamp(transition.elapsed/transition.duration,0,1);
      if(settings.reduced){water.form=1-ramp(p,0,.42)+ramp(p,.48,.92);water.lift=Math.sin(p*Math.PI)*4;water.squash=1;water.wobble=0;}
      else{
        water.form=p<.38?1-ramp(p,.1,.38):p<.6?Math.sin(clamp((p-.38)/.22,0,1)*Math.PI)*.3:ramp(p,.6,.86);
        water.lift=22*ramp(p,0,.2)*(1-ramp(p,.8,1));water.squash=1+Math.sin(p*Math.PI*6)*.09*Math.sin(p*Math.PI);water.wobble=Math.sin(p*Math.PI)*.11;
      }
      water.lean=0;water.ripple=Math.sin(p*Math.PI);return water;
    }
    if(mode==='title'){water.squash=1+Math.sin(time*2.8)*.025*intensity;water.lean=Math.sin(time*1.4)*.015*intensity;water.lift=2+Math.sin(time*1.9)*1.4*intensity;}
    return water;
  }
  function start(continuing=false){
    hasPrism=false;hasSpark=false;beaconLit=false;checkpointIndex=-1;collected=new Set();deaths=0;jumps=0;shifts=0;elapsed=0;seenDialogues=new Set();creature='girl';unlockedForms=new Set(['girl']);formChanges=0;
    if(continuing&&saved&&!saved.completed){checkpointIndex=clamp(Math.floor(Number(saved.checkpointIndex)||0),-1,W.checkpoints.length-1);hasPrism=!!saved.hasPrism;hasSpark=!!saved.hasSpark;beaconLit=!!saved.beaconLit;collected=new Set((Array.isArray(saved.collected)?saved.collected:[]).filter(i=>Number.isInteger(i)&&i>=0&&i<W.shards.length));deaths=Math.max(0,Number(saved.deaths)||0);jumps=Math.max(0,Number(saved.jumps)||0);shifts=Math.max(0,Number(saved.shifts)||0);elapsed=Math.max(0,Number(saved.elapsed)||0);}
    if(continuing&&saved&&!saved.completed){unlockedForms=new Set(['girl',...(Array.isArray(saved.unlockedForms)?saved.unlockedForms:[]).filter(f=>Object.hasOwn(FORMS,f))]);creature=unlockedForms.has(saved.creature)?saved.creature:'girl';formChanges=Math.max(0,Number(saved.formChanges)||0);}
    dimension=2;dimensionBlend=0;transition=null;pulse=0;gateOpen=beaconLit?1:0;particles=[];clearInputs();resetPlayer(checkpointIndex>=0?W.checkpoints[checkpointIndex]:W.spawn);
    cameraX=Math.max(140,player.x+58);cameraZ=0;cameraHeight=214;cameraY=45;mode='playing';intro=null;fatal=null;lastTime=0;accumulator=0;toastTimer=0;dialogueTimer=0;ambientTimer=2;saveTimer=0;lastObjective='';lastShardCount=-1;document.body.classList.remove('shifting','cinematic');hideOverlays();$('introOverlay').classList.add('hidden');$('dialogue').classList.add('hidden');$('hud').classList.remove('hidden');$('controls').classList.remove('hidden');syncDimensionUI();updateHUD();unlockAudio();
    if(!continuing||!introSeen)beginIntro(checkpointIndex>=0?W.checkpoints[checkpointIndex]:W.spawn);
    else showToast(hasPrism?'Your progress is saved at the lantern.':'Move with the left pad. Hold jump to spring higher.',4.5);
    persist();
  }
  function home(){mode='title';intro=null;creature='girl';clearInputs();hideOverlays();$('title').classList.remove('hidden');$('introOverlay').classList.add('hidden');$('hud').classList.add('hidden');$('controls').classList.add('hidden');$('dialogue').classList.add('hidden');$('toast').classList.remove('show');transition=null;document.body.classList.remove('shifting','in3d','cinematic');resetPlayer({x:330,y:0,z:40});cameraX=200;cameraZ=0;cameraHeight=155;cameraY=32;hasPrism=false;collected=new Set();beaconLit=false;gateOpen=0;$('play').innerHTML=(saved&&!saved.completed?'Continue the story':'Begin the story')+' <span aria-hidden="true">↗</span>';}
  function pause(){
    if(mode!=='playing'&&mode!=='respawning'&&mode!=='intro')return;
    pausedFrom=mode==='intro'?'intro':'playing';
    if(mode==='respawning'){resetPlayer(checkpointIndex>=0?W.checkpoints[checkpointIndex]:W.spawn);dimension=2;dimensionBlend=0;transition=null;syncDimensionUI();}
    mode='paused';clearInputs();player.vx=0;player.vz=0;accumulator=0;$('pauseOverlay').classList.remove('hidden');$('introOverlay').classList.add('hidden');$('controls').classList.add('hidden');$('dialogue').classList.add('hidden');persist();if(audioContext)audioContext.suspend().catch(()=>{});
  }
  function resume(){if(mode!=='paused'||(renderer&&renderer.contextLost)||fatal)return;clearInputs();mode=pausedFrom==='intro'&&intro?'intro':'playing';lastTime=0;accumulator=0;$('pauseOverlay').classList.add('hidden');$('controls').classList.toggle('hidden',mode==='intro');$('introOverlay').classList.toggle('hidden',mode!=='intro');if(dialogueTimer>0)$('dialogue').classList.remove('hidden');unlockAudio();}
  function nativePause(){pause();clearInputs();if(audioContext)audioContext.suspend().catch(()=>{});}
  function solids(){return W.platforms.concat(W.obstacles.filter(o=>o.kind!=='gate'||!beaconLit));}
  function overlapsXZ(p,b){return p.x+FORMS[creature].halfWidth>b.x+.01&&p.x-FORMS[creature].halfWidth<b.x+b.w-.01&&p.z+PHYS.halfDepth>b.z+.01&&p.z-PHYS.halfDepth<b.z+b.d-.01;}
  function overlapsY(p,b){return p.y+FORMS[creature].height>b.y+.02&&p.y<b.y+b.h-.02;}
  function foldSafety(){
    if(!hasPrism)return{safe:false,reason:'Find the prism first.'};if(transition)return{safe:false,reason:'The world is still unfolding.'};
    if(!player.grounded)return{safe:false,reason:'Land on solid ground before shifting.'};
    if(dimension===2)return{safe:true,reason:''};
    const at={...player,z:0};
    const blocked=solids().some(b=>overlapsY(at,b)&&at.x+FORMS[creature].halfWidth>b.x+.01&&at.x-FORMS[creature].halfWidth<b.x+b.w-.01&&Math.min(player.z,0)-PHYS.halfDepth<b.z+b.d-.01&&Math.max(player.z,0)+PHYS.halfDepth>b.z+.01);
    if(blocked)return{safe:false,reason:'Step clear of the paper wall before folding back.'};
    const floor=W.platforms.find(b=>overlapsXZ(at,b)&&Math.abs(player.y-(b.y+b.h))<.75);
    if(!floor)return{safe:false,reason:'Return to the main path before folding back.'};
    return{safe:true,reason:''};
  }
  function burst(x,y,z,count,color,speed=50){for(let i=0;i<count;i++){const a=i*2.399963+time;particles.push({x,y,z,vx:Math.cos(a)*speed*(.3+(i%5)/6),vy:25+(i%7)*speed/7,vz:Math.sin(a)*speed*.7,life:.65+(i%4)*.15,max:1.1,size:1.5+(i%3),color});}if(particles.length>160)particles.splice(0,particles.length-160);}
  function requestShift(){
    if(mode!=='playing'||transition)return;
    const safety=foldSafety();if(!safety.safe){showToast(safety.reason,2.8);tone(185,.14,.018);return;}
    unlockAudio();sound('shift');const next=dimension===2?3:2;transition={kind:'dimension',from:dimensionBlend,to:next===3?1:0,elapsed:0,duration:settings.reduced?1:2.6,startZ:player.z,target:next,phase:'rising'};shifts++;dimension=next;beginTransformation();
  }
  function requestForm(){
    if(mode!=='playing'||transition||unlockedForms.size<2)return;
    if(!player.grounded){showToast('Land before remembering another shape.',2.5);return;}
    const forms=Object.keys(FORMS).filter(f=>unlockedForms.has(f)),next=forms[(forms.indexOf(creature)+1)%forms.length],shape=FORMS[next];
    const blocked=solids().some(b=>player.x+shape.halfWidth>b.x+.01&&player.x-shape.halfWidth<b.x+b.w-.01&&player.y+shape.height>b.y+.02&&player.y<b.y+b.h-.02&&player.z+PHYS.halfDepth>b.z+.01&&player.z-PHYS.halfDepth<b.z+b.d-.01);
    if(blocked){showToast('Find a little more room to change shape.',2.5);return;}
    unlockAudio();sound('become');transition={kind:'form',nextCreature:next,from:dimensionBlend,to:dimensionBlend,elapsed:0,duration:settings.reduced?.8:1.35,startZ:player.z,target:dimension,phase:'rising'};formChanges++;beginTransformation();
  }
  function beginTransformation(){
    clearInputs();player.vx=0;player.vz=0;player.vy=0;resetJelly();document.body.classList.remove('shifting');void document.body.offsetWidth;document.body.classList.add('shifting');document.body.style.setProperty('--shift-progress','0');document.body.style.setProperty('--shift-veil','0');syncDimensionUI();
    $('shiftCaption').textContent='REMEMBERING THE RAIN';$('dialogue').classList.add('hidden');dialogueTimer=0;toastTimer=0;$('toast').classList.remove('show');
  }
  function updateTransition(dt){
    transition.elapsed+=dt;const p=clamp(transition.elapsed/transition.duration,0,1),oldBlend=dimensionBlend;
    const turn=ramp(p,settings.reduced?.25:.4,.93);
    dimensionBlend=transition.from+(transition.to-transition.from)*turn;if(transition.kind==='dimension'&&transition.target===2)player.z=transition.startZ*(1-turn);pulse=Math.sin(p*Math.PI)*(transition.kind==='form'?.24:.7);
    if(transition.kind==='form'&&p>=(settings.reduced?.44:.38)&&creature!==transition.nextCreature){creature=transition.nextCreature;syncDimensionUI();}
    const phase=p<.18?'rising':p<.38?'gathering':p<.6?'remembering':p<.86?'unfolding':'settling';
    if(phase!==transition.phase){
      transition.phase=phase;
      $('shiftCaption').textContent=phase==='gathering'?'BECOMING A DROP':phase==='remembering'?'A SHAPE TO REMEMBER':transition.kind==='form'?FORMS[transition.nextCreature].name.toUpperCase()+' FORM':transition.target===3?'ENTERING THE THIRD DIMENSION':'RETURNING TO THE PAGE';
      if(phase==='remembering')tone(620,.22,.015,0,'sine',180);
      if(phase==='unfolding')sound('become');
    }
    document.body.style.setProperty('--shift-progress',String(p));document.body.style.setProperty('--shift-veil',String(Math.sin(p*Math.PI)));
    if((oldBlend<.5)!==(dimensionBlend<.5))syncDimensionUI();
    if(p>=1){const target=transition.target,kind=transition.kind;dimensionBlend=transition.to;player.z=target===2?0:player.z;transition=null;pulse=0;jelly.squashVelocity=settings.reduced?-.3:-1.2;jelly.impact=.45;document.body.classList.remove('shifting');syncDimensionUI();showToast(kind==='form'?FORMS[creature].name+' form · '+FORMS[creature].hint:target===3?'The pad has unfolded. Up / down now move through depth.':'Two dimensions. Still made of rain.',3.5);persist();}
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
    const dir=readInput(),physics=formPhysics();coyote=player.grounded?PHYS.coyote:Math.max(0,coyote-dt);jumpBuffer=Math.max(0,jumpBuffer-dt);
    if(jumpBuffer>0&&coyote>0){player.vy=physics.jump;player.grounded=false;coyote=0;jumpBuffer=0;jumps++;jelly.squashVelocity=settings.reduced?.45:2.3;sound('jump');burst(player.x,player.y+2,player.z,5,'#b9efff',27);}
    if(!heldJump()&&player.vy>physics.release)player.vy=physics.release;
    const accel=player.grounded?PHYS.acceleration:PHYS.airAcceleration;
    player.vx=approach(player.vx,dir.x*physics.speed,(dir.x?accel:PHYS.brake)*dt);player.vz=dimension===3?approach(player.vz,dir.z*physics.speed,(dir.z?accel:PHYS.brake)*dt):0;
    if(Math.abs(player.vx)>3)player.facing=player.vx>0?1:-1;player.walk+=Math.hypot(player.vx,player.vz)*dt/90;
    const boxes=solids();
    player.x+=player.vx*dt;
    for(const b of boxes){if(overlapsXZ(player,b)&&overlapsY(player,b)){if(player.vx>0)player.x=b.x-physics.halfWidth;else if(player.vx<0)player.x=b.x+b.w+physics.halfWidth;player.vx=0;}}
    player.z+=player.vz*dt;
    for(const b of boxes){if(overlapsXZ(player,b)&&overlapsY(player,b)){if(player.vz>0)player.z=b.z-PHYS.halfDepth;else if(player.vz<0)player.z=b.z+b.d+PHYS.halfDepth;player.vz=0;}}
    const oldY=player.y,wasGrounded=player.grounded;player.vy=Math.max(-PHYS.maxFall,player.vy-PHYS.gravity*dt);const impactSpeed=Math.max(0,-player.vy);player.y+=player.vy*dt;player.grounded=false;
    for(const b of boxes){
      if(!overlapsXZ(player,b))continue;
      const top=b.y+b.h;
      if(player.vy<=0&&oldY>=top-.1&&player.y<=top){player.y=top;player.vy=0;player.grounded=true;}
      else if(player.vy>0&&oldY+physics.height<=b.y+.1&&player.y+physics.height>=b.y){player.y=b.y-physics.height;player.vy=0;}
    }
    if(player.grounded&&!wasGrounded){jelly.squashVelocity=-Math.min(3.2,.7+impactSpeed*.008)*(settings.reduced?.25:1);jelly.impact=Math.min(1,impactSpeed/260);sound('land');burst(player.x,player.y+1,player.z,settings.reduced?3:7,'#b9efff',20);}
    player.x=clamp(player.x,-105,W.width-22);
    if(player.y< -150){die();return;}
    const near=(c,x=18,y=22,z=14)=>Math.abs(player.x-c.x)<x&&Math.abs(player.y+15-c.y)<y&&Math.abs(player.z-c.z)<z;
    if(!hasPrism&&near(W.prism,24,28,15)){hasPrism=true;sound('prism');burst(W.prism.x,W.prism.y,0,38,'#c5adff',80);syncDimensionUI();dialogue('The prism','The light remembers what water can be. Tap the droplet to gather yourself, then unfold into the third dimension.',6.5);showToast('POWER FOUND · Enter the third dimension',4.4);persist();}
    for(const living of [...W.npcs,...(W.creatures||[])]){
      const form=living.form||'girl';if(!Object.hasOwn(FORMS,form)||unlockedForms.has(form))continue;
      if(Math.abs(player.x-living.x)<physics.halfWidth+(living.radius||10)&&Math.abs(player.z-living.z)<9&&player.y<living.y+(living.height||24)&&player.y+physics.height>living.y){
        unlockedForms.add(form);sound('become');syncDimensionUI();burst(player.x,player.y+12,player.z,settings.reduced?6:16,'#b6f6ff',35);showToast(FORMS[form].name.toUpperCase()+' REMEMBERED · Tap Form. '+FORMS[form].hint,5);persist();
      }
    }
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
    if(mode==='intro')updateIntro(dt);
    if(mode==='playing')simulate(dt);
    if(!intro&&!transition)updateJelly(dt);
    if(mode==='respawning'){respawnTimer-=dt;if(respawnTimer<=0){resetPlayer(checkpointIndex>=0?W.checkpoints[checkpointIndex]:W.spawn);dimension=2;dimensionBlend=0;transition=null;pulse=0;mode='playing';document.body.classList.remove('shifting');syncDimensionUI();cameraX=Math.max(140,player.x+58);cameraZ=0;}}
    gateOpen=approach(gateOpen,beaconLit?1:0,dt*.62);
    if(mode!=='title'&&!intro){const targetX=clamp(player.x+58,140,W.width-140);cameraX+=(targetX-cameraX)*(1-Math.exp(-dt*4.6));cameraZ+=(player.z-cameraZ)*(1-Math.exp(-dt*3.3));cameraHeight=202+18*dimensionBlend-(transition?16*Math.sin(Math.PI*clamp(transition.elapsed/transition.duration,0,1)):0);cameraY=45+dimensionBlend*4;}
    for(const p of particles){p.life-=dt;p.x+=p.vx*dt;p.y+=p.vy*dt;p.z+=p.vz*dt;p.vy-=110*dt;}particles=particles.filter(p=>p.life>0);
    toastTimer=Math.max(0,toastTimer-dt);if(!toastTimer)$('toast').classList.remove('show');dialogueTimer=Math.max(0,dialogueTimer-dt);if(!dialogueTimer)$('dialogue').classList.add('hidden');
    if(mode==='playing'&&!transition){ambientTimer-=dt;if(ambientTimer<=0){ambientTimer=5.5;const notes=dimension===3?[220,330,440,554]:[196,294,392,494];notes.forEach((f,i)=>tone(f,2,.006,i*.28));}}
  }
  function cinematicState(){return intro?{active:true,stage:intro.stage,elapsed:intro.elapsed,duration:intro.duration,progress:intro.elapsed/intro.duration}:{active:false,stage:'complete',elapsed:12.4,duration:12.4,progress:1};}
  function renderState(){return{mode,player,time,cameraX,cameraZ,cameraHeight,cameraY,dimension,dimensionBlend,transitioning:!!transition,transitionProgress:transition?transition.elapsed/transition.duration:0,water:waterState(),cinematic:cinematicState(),pulse,reduced:settings.reduced,hasPrism,hasSpark,beaconLit,gateOpen,checkpointIndex,collected:[...collected],particles};}
  function showError(error){$('retry').classList.remove('hidden');fatal=String(error&&error.message||error);errors.push(fatal);mode='error';clearInputs();$('errorTitle').textContent='The world needs a fresh start.';$('errorText').textContent='The graphics renderer could not complete startup. Reload the game to try again.';$('rendererError').classList.remove('hidden');}
  function onLost(){nativePause();$('errorTitle').textContent='Rebuilding the world…';$('errorText').textContent='Your progress is safe. The graphics renderer is recovering.';$('retry').classList.add('hidden');$('rendererError').classList.remove('hidden');}
  function onRestored(){$('rendererError').classList.add('hidden');$('retry').classList.remove('hidden');lastTime=0;accumulator=0;renderDirty=true;if(mode==='paused')showToast('The world is ready. Continue when you are.',3.5);}
  function getState(){
    return{version:'2.3 (5)',ready:!!renderer&&renderer.frames>0&&!renderer.contextLost&&!fatal,mode,pausedFrom,dimension,dimensionBlend,transitioning:!!transition,transitionProgress:transition?transition.elapsed/transition.duration:0,transitionDuration:transition?transition.duration:0,transitionPhase:transition?transition.phase:'none',transitionKind:transition?transition.kind:'none',water:waterState(),jelly:{...jelly},cinematic:cinematicState(),introSeen,creature,unlockedForms:[...unlockedForms],formChanges,player:{...player,width:FORMS[creature].halfWidth*2,height:FORMS[creature].height,depth:.6+dimensionBlend*8.4},camera:{x:cameraX,z:cameraZ,height:cameraHeight,y:cameraY,yaw:dimensionBlend*.72,elevation:dimensionBlend*.49},elapsed,deaths,jumps,shifts,hasPrism,hasSpark,beaconLit,gateOpen,checkpointIndex,checkpoint:checkpointIndex>=0?{...W.checkpoints[checkpointIndex]}:{...W.spawn},collected:[...collected],totalShards:W.shards.length,foldSafety:foldSafety(),input:{...readInput(),jumpHeld:heldJump(),touches:padTouches.size+jumpTouches.size},physics:formPhysics(),world:{platforms:W.platforms.map(x=>({...x})),obstacles:W.obstacles.map(x=>({...x})),creatures:(W.creatures||[]).map(n=>({...n})),npcs:W.npcs.map(n=>({id:n.id,x:n.x,y:n.y,z:n.z,depth:n.depth})),prism:{...W.prism},spark:{...W.spark},beacon:{...W.beacon},finish:{...W.finish}},renderer:renderer?renderer.getState():null,errors:[...errors],settings:{...settings},objective:lastObjective,playerScreen:renderer?renderer.project(player.x,player.y+FORMS[creature].height/2,player.z):null};
  }
  window.ThirdDimension=Object.freeze({get ready(){return!!renderer&&renderer.frames>0&&!renderer.contextLost&&!fatal;},get errors(){return [...errors];},getState,nativePause});window.Moonhop=Object.freeze({nativePause,getState});
  window.addEventListener('error',e=>{const msg=e.message||'Unknown script error';if(!errors.includes(msg))errors.push(msg);});window.addEventListener('unhandledrejection',e=>errors.push(String(e.reason)));
  $('play').addEventListener('click',()=>start(!!saved&&!saved.completed));$('pause').addEventListener('click',pause);$('resume').addEventListener('click',resume);$('restart').addEventListener('click',()=>start(false));$('replay').addEventListener('click',()=>start(false));$('home').addEventListener('click',home);$('retry').addEventListener('click',()=>location.reload());
  $('skipIntro').addEventListener('click',()=>{if(mode==='intro')endIntro();});
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
