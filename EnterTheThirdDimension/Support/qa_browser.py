#!/usr/bin/env python3
"""Exercise the production game with deterministic input and selected real frames.
The test-only scheduler accelerates simulation and omits intermediate draws. It
is injected by Playwright, not shipped in Game/. This is not an FPS benchmark.
"""
import argparse, functools, hashlib, http.server, json, math, re, threading, time
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / 'Resources/Game'
BOOT = """(() => {let tasks=new Map(),id=0,clock=1000;window.requestAnimationFrame=f=>{tasks.set(++id,f);return id};window.cancelAnimationFrame=i=>tasks.delete(i);window.__qa={draw:true,last:null,renderer:null,advance(n,draw=true){for(let i=0;i<n;i++){this.draw=draw&&i===n-1;clock+=1000/60;const q=[...tasks.values()];tasks.clear();q.forEach(f=>f(clock));}this.draw=true;}};})();"""
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--engine',default='chromium',choices=['chromium','webkit']);ap.add_argument('--inline',action='store_true');ap.add_argument('--output',type=Path,default=ROOT/'Build/BrowserQA');args=ap.parse_args()
 out=args.output;out.mkdir(parents=True,exist_ok=True);checks=[];errors=[];snapshots={}
 report={'app':'Enter the Third Dimension','version':'2.3 (5)','status':'running','engine':args.engine,'transport':'inlined local resources, CSP omitted by harness' if args.inline else 'unaltered bundled resources served on loopback','simulation':'deterministic 60 Hz scheduler; intermediate draws omitted; selected frames use the actual renderer','physical_device':False,'performance_measurement':False,'checks':checks,'errors':errors,'resources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(GAME.iterdir()) if p.is_file()}}
 def check(name,condition,detail=None):
  checks.append({'name':name,'passed':bool(condition),'detail':detail});print(('PASS ' if condition else 'FAIL ')+name,flush=True)
  if not condition:raise AssertionError(name+': '+str(detail))
 handler=functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(GAME));server=None
 if not args.inline:
  server=http.server.ThreadingHTTPServer(('127.0.0.1',0),handler);threading.Thread(target=server.serve_forever,daemon=True).start()
 with sync_playwright() as pw:
  kw={}
  if args.engine=='chromium':kw={'executable_path':'/usr/bin/chromium','args':['--no-sandbox','--use-angle=swiftshader-webgl','--enable-unsafe-swiftshader']}
  browser=getattr(pw,args.engine).launch(headless=True,**kw)
  context=browser.new_context(viewport={'width':1000,'height':480},device_scale_factor=2)
  context.add_init_script(BOOT)
  page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
  def load():
   if args.inline:
    html=(GAME/'index.html').read_text();html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>','',html)
    html=re.sub(r'<link rel="stylesheet" href="([^"]+)">',lambda m:'<style>'+(GAME/m[1]).read_text()+'</style>',html)
    html=re.sub(r'<script src="([^"]+)"></script>',lambda m:'<script>'+(GAME/m[1]).read_text()+'</script>',html)
    page.evaluate(BOOT);page.set_content(html,wait_until='load')
   else:page.goto('http://127.0.0.1:%d/index.html'%server.server_port,wait_until='load')
   page.evaluate("""()=>{const draw=TD_Renderer.prototype.draw;TD_Renderer.prototype.draw=function(s){__qa.renderer=this;__qa.last=s;return (__qa.draw||s.mode==='paused')?draw.call(this,s):false;};__qa.advance(2,true);}""")
  def state():return page.evaluate('ThirdDimension.getState()')
  def step(seconds=0.1,draw=False):page.evaluate('([n,d])=>__qa.advance(n,d)',[max(1,round(seconds*60)),draw])
  def click(id):page.locator('#'+id).dispatch_event('click')
  def key(code,down=True):page.evaluate('([code,down])=>window.dispatchEvent(new KeyboardEvent(down?"keydown":"keyup",{code,bubbles:true,cancelable:true}))',[code,down])
  def capture(name):
   step(.05,True);s=state();snapshots[name]=s
   check(name+' clean render',s['ready'] and not s['errors'] and not s['renderer']['errors'] and not s['renderer']['water']['errors'])
   check(name+' complete passes',all(s['renderer'][k]['ready'] for k in ['shadows','bloom','fxaa']))
   check(name+' finite hero',all(math.isfinite(s['player'][k]) for k in ['x','y','z']))
   page.screenshot(path=str(out/(name+'.png')))
  def move_to(axis,target,limit=30):
   codes=('KeyA','KeyD') if axis=='x' else ('KeyW','KeyS');s=state();direction=1 if target>s['player'][axis] else -1;code=codes[direction>0];key(code)
   for _ in range(limit*60):
    step(1/60);s=state()
    if direction*(s['player'][axis]-target)>=0 or (axis=='x' and target>=1830 and s['mode']=='complete'):break
   else:raise AssertionError('Could not move '+axis+' to '+str(target)+': '+str(s['player']))
   key(code,False);step(.12);return s
  def shift():key('KeyE');key('KeyE',False);step(2.8)
  try:
   load();s=state();check('Current game and visual versions',s['version']=='2.3 (5)' and s['renderer']['visualVersion']=='2.3')
   check('New grove module active',page.evaluate('TD_GROVE.identity')=='Sunshower Grove')
   capture('Grove-Title');click('play');step(.8);check('Opening begins as suspended drop',state()['water']['form']==0)
   step(1.2);check('Drop falls from tree',state()['cinematic']['stage']=='falling');step(.65);check('Drop splashes',state()['cinematic']['stage']=='splash')
   step(3.25);capture('First-Touch');check('Contact morph begins',state()['water']['form']>0)
   step(1.0);check('First morph melts back',state()['cinematic']['stage']=='melting');step(6)
   check('Opening reaches playable state',state()['mode']=='playing' and state()['introSeen']);capture('Grove-2D')
   key('KeyE');key('KeyE',False);check('Power locked before prism',not state()['transitioning'])
   # Actual production pointer handlers, including simultaneous contacts.
   page.evaluate("""()=>{let r=document.getElementById('movePad').getBoundingClientRect();document.getElementById('movePad').dispatchEvent(new PointerEvent('pointerdown',{pointerId:11,clientX:r.right-20,clientY:r.top+r.height/2,bubbles:true}));document.getElementById('jump').dispatchEvent(new PointerEvent('pointerdown',{pointerId:12,bubbles:true}));}""")
   step(.12);s=state();check('Simultaneous move and jump contacts',s['input']['touches']==2 and s['player']['vx']>0 and s['player']['y']>0)
   page.evaluate("""()=>{for(const [id,pointerId]of [['movePad',11],['jump',12]])document.getElementById(id).dispatchEvent(new PointerEvent('pointercancel',{pointerId,bubbles:true}));}""");step(.8);check('Cancelled touches clear',state()['input']['touches']==0)
   move_to('x',255);check('Prism collected',state()['hasPrism']);move_to('x',350);key('KeyD');step(.45);key('KeyD',False);check('Flat wall blocks the road',state()['player']['x']<=354.1)
   key('KeyE');key('KeyE',False);step(.55);check('Dimension morph lifts the girl',state()['water']['lift']>15);step(.75);capture('Grove-Morph');step(1.5)
   check('3D world and control state',state()['dimension']==3 and page.evaluate('document.body.classList.contains("in3d")'))
   move_to('z',-30);move_to('x',374);check('Unsafe fold into wall rejected',not state()['foldSafety']['safe']);key('KeyE');key('KeyE',False);check('Rejected fold leaves 3D active',state()['dimension']==3 and not state()['transitioning'])
   move_to('x',425);move_to('z',0);shift();check('Safe fold returns to plane',state()['dimension']==2 and abs(state()['player']['z'])<.01)
   move_to('x',489);check('Frog remembered by contact','frog' in state()['unlockedForms']);key('KeyQ');key('KeyQ',False);step(1.5);check('Frog form has higher jump',state()['creature']=='frog' and state()['physics']['jump']>342);capture('Water-Frog')
   key('Space');step(.25);height=state()['player']['y'];key('Space',False);step(1);check('Frog jumping and landing',height>50 and state()['player']['grounded'])
   key('KeyQ');key('KeyQ',False);step(1.5);move_to('x',620);check('First checkpoint saved',state()['checkpointIndex']>=0)
   shift();move_to('z',-62);move_to('x',843);check('Hidden bridge supports player',state()['player']['grounded'] and abs(state()['player']['y'])<1);check('Lost spark collected',state()['hasSpark']);check('Folding over the gap is blocked',not state()['foldSafety']['safe']);capture('Hidden-Bridge')
   move_to('x',1030);move_to('z',0);shift();move_to('x',1084);check('Fox remembered by contact','fox' in state()['unlockedForms'])
   key('KeyQ');key('KeyQ',False);step(1.5);key('KeyQ');key('KeyQ',False);step(1.5);check('Fox form runs faster',state()['creature']=='fox' and state()['physics']['speed']>132);capture('Water-Fox')
   key('KeyQ');key('KeyQ',False);step(1.5);move_to('x',1125)
   # Jump the three fixed story steps without mutating the simulation state.
   key('KeyD');key('Space');step(.66);key('Space',False);key('KeyD',False);step(.5)
   if state()['player']['x']<1265:
    key('KeyD');key('Space');step(.7);key('Space',False);key('KeyD',False);step(.5)
   check('Traverse raised platforms',state()['player']['x']>1265)
   move_to('x',1450);shift();capture('Grove-3D');shift();move_to('x',1515);check('Village beacon restored',state()['beaconLit']);step(2)
   click('pause');s=state();key('KeyD');step(1);check('Pause freezes player',state()['mode']=='paused' and state()['player']['x']==s['player']['x'])
   click('effects');step(.05,True);check('Reduced quality resources rebuild',state()['renderer']['quality']=='reduced');capture('Reduced-Effects');click('effects');step(.05,True);check('Full quality restores',state()['renderer']['quality']=='full');click('resume');step(.1)
   move_to('x',1840);check('Chapter completes',state()['mode']=='complete');capture('Chapter-Complete')
   if not args.inline:
    saved=page.evaluate("JSON.parse(localStorage.getItem('third-dimension.chapter1.v2'))")
    check('Persistent save records completed story',saved['progress']['completed'] and saved['introSeen'])
    # Reload a genuine older save shape, not an internal game-state mutation.
    saved['progress']['completed']=False;saved['progress']['checkpointIndex']=1;saved['progress'].pop('unlockedForms',None);saved['progress'].pop('creature',None)
    page.evaluate("s=>localStorage.setItem('third-dimension.chapter1.v2',JSON.stringify(s))",saved);load();click('play');step(.1);check('Legacy save migrates safely',state()['creature']=='girl' and state()['checkpointIndex']==1)
   else:report['persistence']='Not asserted with opaque inline origin; real-origin WebKit run required.'
   # Restoration is triggered through the real WebGL extension.
   lost=page.evaluate("()=>{const e=__qa.renderer.gl.getExtension('WEBGL_lose_context');window.__loss=e;if(e){e.loseContext();return true}return false}")
   if lost:
    page.wait_for_timeout(150);check('Graphics context loss observed',state()['renderer']['contextLost']);page.evaluate('window.__loss.restoreContext()');page.wait_for_timeout(600);step(.1,True);check('Graphics context restored',not state()['renderer']['contextLost'] and state()['renderer']['restorations']>0)
   else:report['context_loss']='Extension unavailable, not asserted.'
   check('No JavaScript or renderer errors',not errors and not state()['errors'] and not state()['renderer']['errors'])
   report['status']='passed';report['passed']=len(checks)
  except Exception as e:
   report['status']='failed';report['failure']=str(e);print('FAILED',e,flush=True)
   try:snapshots['failure']=state();page.screenshot(path=str(out/'Failure.png'))
   except Exception:pass
  finally:
   report['snapshots']=snapshots;(out/'QA.json').write_text(json.dumps(report,indent=2)+'\n');browser.close()
   if server:server.shutdown()
 if report['status']!='passed':raise SystemExit(1)
if __name__=='__main__':main()
