#!/usr/bin/env python3
"""Exercise the bundled game in WebKit. Only the animation clock is controlled.
No mutable game state, teleportation, renderer replacement, or CSP bypass.
"""
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from functools import partial
import threading, hashlib, json, datetime, traceback
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]/'EnterTheThirdDimension'
GAME=ROOT/'Resources/Game'
OUT=ROOT/'Build/Browser-QA'
OUT.mkdir(parents=True,exist_ok=True)
checks=[]
report={'version':'2.3 (5)','engine':'Playwright WebKit','clock':'deterministic 50 ms presentation intervals; unchanged 120 Hz simulation','sourceHashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in GAME.iterdir() if p.is_file()},'checks':checks,'physicalDevicePerformance':'Not measured'}

def check(name,condition,details=None):
    checks.append({'name':name,'passed':bool(condition),'details':details})
    if not condition:raise AssertionError(name+': '+str(details))

class Quiet(SimpleHTTPRequestHandler):
    def log_message(self,*args):pass

server=ThreadingHTTPServer(('127.0.0.1',0),partial(Quiet,directory=str(GAME)))
threading.Thread(target=server.serve_forever,daemon=True).start()
url=f'http://127.0.0.1:{server.server_port}'
errors=[];external=[]

try:
 with sync_playwright() as pw:
    browser=pw.webkit.launch(headless=True)
    context=browser.new_context(viewport={'width':1000,'height':460},device_scale_factor=1.5,has_touch=True)
    context.add_init_script('''window.__q=[];window.__t=0;window.requestAnimationFrame=cb=>(window.__q.push(cb),window.__q.length);window.__step=n=>{for(let i=0;i<n;i++){window.__t+=50;const q=window.__q;window.__q=[];for(const cb of q)cb(window.__t);}};''')
    page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('request',lambda r:external.append(r.url) if not r.url.startswith(url) else None)
    page.goto(url,wait_until='load')
    def frame(n=1):
        for i in range(0,n,10):page.evaluate('(n)=>__step(n)',min(10,n-i))
    def state():return page.evaluate('ThirdDimension.getState()')
    def click(id):page.evaluate('(id)=>document.getElementById(id).click()',id)
    def key(k,down=True):page.evaluate('([k,d])=>window.dispatchEvent(new KeyboardEvent(d?"keydown":"keyup",{code:k,key:k,bubbles:true,cancelable:true}))',[k,down])
    def walk(k,predicate,limit=180):
        key(k)
        for _ in range(limit):
            frame()
            if predicate(state()):break
        else:raise AssertionError('Movement timed out '+k+' '+json.dumps(state()['player']))
        key(k,False);frame(3)
    def shift():
        click('power');check('Shift begins',state()['transitioning'])
        for _ in range(80):
            frame()
            if not state()['transitioning']:break
        check('Shift ends safely',not state()['transitioning'] and state()['mode']=='playing')
    def form():
        click('formButton')
        for _ in range(70):
            frame()
            if not state()['transitioning']:break
    def capture(name):
        frame(2);page.screenshot(path=str(OUT/(name+'.png')),animations='disabled')
    frame(3);s=state()
    check('Current game starts',s['ready'] and s['version']=='2.3 (5)',s['errors'])
    check('Current lighting and water shaders render',s['renderer']['visualVersion']=='2.3' and s['renderer']['water']['draws']>0)
    check('Shadow and finishing passes render',all(s['renderer'][k]['ready'] for k in ('shadows','bloom','fxaa')))
    capture('Cozy-Title')
    click('play');frame(34)
    check('Rain origin begins',state()['mode']=='intro')
    frame(85);capture('Cozy-First-Touch');frame(145)
    check('Full opening reaches gameplay',state()['mode']=='playing')
    s=state();check('Girl form is remembered',s['creature']=='girl' and 'girl' in s['unlockedForms'])
    # Independent touch pointers must support movement and jump together.
    page.evaluate('''()=>{const r=document.getElementById('movePad').getBoundingClientRect();document.getElementById('movePad').dispatchEvent(new PointerEvent('pointerdown',{pointerId:101,pointerType:'touch',clientX:r.right-15,clientY:r.top+r.height/2,bubbles:true,cancelable:true}));document.getElementById('jump').dispatchEvent(new PointerEvent('pointerdown',{pointerId:102,pointerType:'touch',bubbles:true,cancelable:true}));}''')
    x=s['player']['x'];frame(5);s=state()
    check('Simultaneous touch movement and jumping',s['player']['x']>x and s['player']['y']>0 and s['input']['touches']==2)
    page.evaluate('''()=>{for(const [id,p] of [['movePad',101],['jump',102]])document.getElementById(id).dispatchEvent(new PointerEvent('pointercancel',{pointerId:p,bubbles:true}));}''')
    frame(20);check('Touch cancellation clears held input',state()['input']['touches']==0)
    walk('ArrowRight',lambda s:s['player']['x']>330)
    check('Prism collectible works',state()['hasPrism'])
    key('ArrowRight');frame(15);key('ArrowRight',False);frame(3)
    check('2D wall blocks movement',state()['player']['x']<355)
    shift();check('World unfolds into depth',state()['dimension']==3 and state()['dimensionBlend']==1)
    capture('Cozy-Canopy')
    walk('ArrowDown',lambda s:s['player']['z']>36)
    walk('ArrowRight',lambda s:s['player']['x']>412)
    shift();check('World folds onto safe path',state()['dimension']==2 and abs(state()['player']['z'])<.01)
    walk('ArrowRight',lambda s:s['player']['x']>478)
    check('Touching frog unlocks its form','frog' in state()['unlockedForms'])
    form();check('Frog form renders',state()['creature']=='frog' and state()['renderer']['water']['creature']=='frog')
    key('Space');frame(6);check('Frog jump responds',state()['player']['y']>40);key('Space',False);frame(20)
    capture('Cozy-Frog');form()
    walk('ArrowRight',lambda s:s['player']['x']>658)
    shift();walk('ArrowUp',lambda s:s['player']['z']< -60)
    walk('ArrowRight',lambda s:s['player']['x']>1005)
    check('Hidden bridge and spark quest work',state()['hasSpark'] and state()['deaths']==0)
    shift();walk('ArrowRight',lambda s:s['player']['x']>1076)
    check('Touching fox unlocks its form','fox' in state()['unlockedForms'])
    form();form();check('Fox form renders',state()['creature']=='fox' and state()['renderer']['water']['creature']=='fox')
    capture('Cozy-Fox')
    click('pause');frame(2);check('Pause holds simulation',state()['mode']=='paused')
    before=state()['player'];frame(8);check('Paused character remains still',state()['player']==before)
    click('effects');frame(2);check('Reduced effects resize safely',state()['renderer']['quality']=='reduced')
    click('effects');frame(2);check('Full effects restore safely',state()['renderer']['quality']=='full')
    capture('Cozy-Pause')
    stored=page.evaluate("JSON.parse(localStorage.getItem('third-dimension.chapter1.v2'))")
    check('Progress is saved locally',stored['progress']['checkpointIndex']>=1 and 'fox' in stored['progress']['unlockedForms'])
    page.reload(wait_until='load');frame(3);click('play');frame(3)
    check('Reload preserves forms and quest',state()['hasSpark'] and 'fox' in state()['unlockedForms'])
    walk('ArrowRight',lambda s:s['player']['x']>1138)
    key('Space');key('ArrowRight');frame(11);key('Space',False)
    for _ in range(55):
        frame();s=state()
        if s['player']['x']>1330:break
        if s['player']['grounded'] and s['player']['vx']==0:key('Space',False);key('Space')
    key('Space',False);key('ArrowRight',False);frame(5)
    check('Platform steps remain traversable',state()['player']['x']>1308,state()['player'])
    walk('ArrowRight',lambda s:s['player']['x']>1520)
    check('Spark restores the village lantern',state()['beaconLit'])
    walk('ArrowRight',lambda s:s['mode']=='complete',limit=150)
    check('Chapter is completable',state()['mode']=='complete')
    report['completedChapter']=state();capture('Cozy-Complete')
    # Fresh story for context recovery and view rotation checks.
    click('replay');frame(3)
    if state()['mode']=='intro':click('skipIntro');frame(3)
    page.evaluate("window.__loss=document.getElementById('world').getContext('webgl').getExtension('WEBGL_lose_context');if(__loss)__loss.loseContext()")
    page.wait_for_timeout(500);frame(2)
    check('Graphics loss pauses safely',state()['renderer']['contextLost'] and state()['mode']=='paused')
    page.evaluate('window.__loss.restoreContext()');page.wait_for_timeout(1200);frame(3)
    check('Graphics resources rebuild',not state()['renderer']['contextLost'] and state()['renderer']['restorations']>=1)
    click('resume');frame(3)
    check('Recovered world renders again',state()['ready'] and state()['renderer']['water']['draws']>0)
    page.set_viewport_size({'width':460,'height':1000});frame(2)
    check('Portrait view pauses the landscape game',state()['mode']=='paused')
    page.set_viewport_size({'width':1000,'height':460});frame(3)
    click('resume');frame(3)
    check('Landscape resumes',state()['mode']=='playing')
    check('No JavaScript exceptions',not errors,errors)
    check('No runtime external requests',not external,external)
    check('No recorded graphics errors',not state()['errors'] and not state()['renderer']['errors'] and not state()['renderer']['water']['errors'])
    report['status']='passed';report['finalState']=state();browser.close()
except Exception as e:
 report['status']='failed';report['failure']=str(e);report['traceback']=traceback.format_exc();raise
finally:
 server.shutdown();report['createdAt']=datetime.datetime.now(datetime.timezone.utc).isoformat();report['totalChecks']=len(checks);report['passed']=sum(c['passed'] for c in checks)
 (OUT/'BROWSER-QA.json').write_text(json.dumps(report,indent=2)+'\n')
 (ROOT/'docs/WEBKIT-QA.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'status':report.get('status'),'checks':len(checks),'passed':report['passed'],'failure':report.get('failure')}),flush=True)
