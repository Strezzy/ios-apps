#!/usr/bin/env node
/** Real offline WebGL checks. These do not emulate iOS or claim device performance. */
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const { chromium } = require(path.join(process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES || '', 'playwright'));
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = process.env.MUSIC_CD_PREVIEW_DIR || path.join(root, '..', 'cd-render-previews'); fs.mkdirSync(out,{recursive:true});
const browser = await chromium.launch({ executablePath: process.env.MUSIC_CHROME_PATH,
  headless:true, args:['--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'],
});
const report = { environment:'Chromium WebGL2 via SwiftShader on Linux; no iOS runtime', checks:[], warnings:[], screenshots:[], nativeDeviceTested:false };
const context = await browser.newContext({viewport:{width:400,height:400},deviceScaleFactor:1,offline:true});
const requests=[],errors=[];
let page;
function check(name, details={}) { report.checks.push({name,passed:true,...details}); console.log('PASS '+name); }
async function wait(test, timeout=60000) { await page.waitForFunction(test,null,{timeout}); }
async function command(state) { await page.evaluate(s => window.MusicCD.receive(s),state); }
async function snap(name) { const filename=name+'.png';await page.screenshot({path:path.join(out,filename),omitBackground:true});report.screenshots.push(filename); }
const diagnostics=()=>page.evaluate(()=>window.MusicCD.diagnostics());
const fixture=(color,label)=>page.evaluate(({color,label})=>{const c=document.createElement('canvas');c.width=c.height=256;const g=c.getContext('2d');g.fillStyle=color;g.fillRect(0,0,256,256);g.fillStyle='#ffffff';g.font='bold 30px sans-serif';g.textAlign='center';g.fillText(label,128,64);g.fillRect(35,172,186,6);return c.toDataURL('image/png');},{color,label});
try {
  page = await context.newPage();
  page.on('request',r=>requests.push(r.url()));
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  await page.addInitScript(()=>{window._cdMessages=[];window.webkit={messageHandlers:{musicCD:{postMessage:m=>window._cdMessages.push(m)}}};});
  await page.goto('file://'+path.join(root,'Resources/CDCase/index.html'));
  await wait(()=>window._cdMessages.some(m=>m.type==='ready'));
  check('Local classic script installs native bridge with network disabled');
  await command({quality:'hero',active:true,playing:true,art:null,background:[.12,.12,.14]});
  await wait(()=>window.MusicCD.diagnostics().ready || window.MusicCD.diagnostics().failed);
  assert.equal((await diagnostics()).failed,false,JSON.stringify(await page.evaluate(()=>window._cdMessages)));
  await snap('hero-closed');
  const before = (await diagnostics()).spin;
  await wait(()=>window.MusicCD.diagnostics().spin>.12);
  assert.ok((await diagnostics()).spin>before);
  check('Custom case shaders render; active playback advances disc rotation',await diagnostics());
  await command({playing:false});
  await wait(()=>!window.MusicCD.diagnostics().scheduled);
  const stopped=(await diagnostics()).spin;
  await page.waitForTimeout(220);
  assert.equal((await diagnostics()).spin,stopped);
  check('Pause settles disc and stops idle animation frames');
  await command({tiltX:.4,tiltY:-.45,animateTilt:false});
  await wait(()=>!window.MusicCD.diagnostics().scheduled);
  await snap('hero-tilted');
  check('Native normalized tilt changes case pose without browser gestures');
  await command({tiltX:0,tiltY:0,animateTilt:false,open:true,animateOpen:true});
  await wait(()=>window.MusicCD.diagnostics().phase==='opening');
  await command({open:false}); await command({open:true});
  await wait(()=>window.MusicCD.diagnostics().phase==='open');
  await page.waitForTimeout(160);
  assert.equal((await diagnostics()).phase,'open');
  check('Rapid Open–Close–Open honors newest intent without an unwanted extra close');
  await snap('hero-open');
  check('Original lid-opening choreography reaches open pose');
  await page.setViewportSize({width:760,height:360});
  await snap('inspector-landscape');
  assert.equal((await diagnostics()).width,760);
  check('Landscape resize retains same live case and open state');
  await page.setViewportSize({width:400,height:400});
  await command({open:false,animateOpen:true});
  await wait(()=>window.MusicCD.diagnostics().phase==='rest');
  const red=await fixture('#e44762','SIDE A'),blue=await fixture('#247dc5','SIDE B');
  await command({art:red});
  await page.waitForTimeout(100);
  await wait(()=>window.MusicCD.diagnostics().artMix===1 && !window.MusicCD.diagnostics().scheduled);
  await snap('artwork-red');
  await command({art:blue});
  await page.waitForTimeout(100);
  await wait(()=>window.MusicCD.diagnostics().artMix===1 && !window.MusicCD.diagnostics().scheduled);
  await snap('artwork-blue');
  const stableCount=(await diagnostics()).textureCount;
  for(let i=0;i<12;i++) { await command({art:i%2===0?red:blue}); await page.waitForTimeout(35); }
  await page.waitForTimeout(100);
  await wait(()=>window.MusicCD.diagnostics().artMix===1 && !window.MusicCD.diagnostics().scheduled);
  assert.equal((await diagnostics()).textureCount,stableCount);
  check('Rapid artwork replacement settles to newest texture without texture growth',{textureCount:stableCount});
  await command({active:false,playing:true});
  const inactive=(await diagnostics()).spin;
  await page.waitForTimeout(220);
  assert.equal((await diagnostics()).scheduled,false);assert.equal((await diagnostics()).spin,inactive);
  check('Inactive view stops animation even while audio state says playing');
  await command({active:true,reducedMotion:true,playing:true,open:true});
  await wait(()=>window.MusicCD.diagnostics().phase==='open' && !window.MusicCD.diagnostics().scheduled);
  check('Reduce Motion suppresses automatic spin and snaps explicit lid changes');
  await command({reducedMotion:false,playing:false,open:false,animateOpen:true});
  await wait(()=>window.MusicCD.diagnostics().phase==='closing');
  await command({reducedMotion:true});
  await wait(()=>window.MusicCD.diagnostics().phase==='rest' && !window.MusicCD.diagnostics().scheduled);
  check('Enabling Reduce Motion during lid animation immediately settles its requested endpoint');
  await command({open:false,art:'https://example.invalid/must-not-load.jpg'});
  await page.waitForTimeout(160);
  await wait(()=>!window.MusicCD.diagnostics().scheduled);
  assert.equal(requests.filter(u=>/^https?:/.test(u)).length,0);
  check('Remote artwork rejected; every requested dependency stays local');
  await command({quality:'grid',active:true,playing:true,reducedMotion:false,art:blue,background:[.12,.12,.14]});
  await page.setViewportSize({width:180,height:180});
  await wait(()=>window.MusicCD.diagnostics().ready);
  await snap('grid-case');
  const grid=await diagnostics();assert.equal(grid.roomSize,128);assert.equal(grid.pixelRatio,1);assert.equal(grid.fpsLimit,18);
  check('Grid uses bounded resolution and render budget',grid);
  await page.evaluate(()=>{const canvas=document.querySelector('canvas');canvas.getContext('webgl2').getExtension('WEBGL_lose_context').loseContext();});
  await wait(()=>window.MusicCD.diagnostics().failed);
  check('WebGL context loss reports native fallback instead of silent broken view');
  await page.setViewportSize({width:200,height:200});
  await page.waitForTimeout(180);
  assert.equal((await diagnostics()).scheduled,false);
  check('Resize after context loss cannot restart the failed renderer');
  assert.equal(errors.length,0,errors.join('\n'));
  check('No uncaught JavaScript or shader errors');
  report.requests=requests;report.renderBundleSHA256=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'Resources/CDCase/music-cd.js'))).digest('hex');
  report.browserVersion=browser.version();report.passed=true;report.screenshot_storage='Development-only scratch previews, excluded from downloads';
} catch(error) {
  report.passed=false;report.failure=String(error?.stack||error);report.consoleErrors=errors;
  if(page) {report.diagnostics=await diagnostics().catch(()=>null);report.messages=await page.evaluate(()=>window._cdMessages).catch(()=>null);await page.screenshot({path:path.join(out,'failure.png'),omitBackground:true}).catch(()=>{});}
  console.error(report.failure);process.exitCode=1;
} finally {
  fs.writeFileSync(path.join(root,'Support/CD-RENDER-REPORT.json'),JSON.stringify(report,null,2)+'\n');
  await browser.close();
}
