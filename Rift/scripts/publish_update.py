#!/usr/bin/env python3
"""Validate the complete matrix, publish the exact IPA, update only Rift's listing."""
import copy,hashlib,json,os,plistlib,re,subprocess,sys,tempfile,zipfile
from pathlib import Path
ROOT=Path.cwd(); OUT=Path(sys.argv[1]).resolve(); REPO='Strezzy/ios-apps'
def cmd(*args):return subprocess.check_output([str(a) for a in args],text=True).strip()
def sha(path):
 with Path(path).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def save(path,data):Path(path).parent.mkdir(parents=True,exist_ok=True);Path(path).write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
def api(path):return json.loads(cmd('gh','api','repos/'+REPO+'/'+path))
report=json.loads((OUT/'BUILD-REPORT.json').read_text()); ipa=OUT/'Rift.ipa'
assert report['app']=='Rift' and report['version']=='1.2' and report['simulator']=='passed' and report['iphone_compilation']=='passed'
summary=report['test_summary'];assert summary['failedTests']==0 and summary['skippedTests']==0 and summary['passedTests']>=40
source=report['source'];assert re.fullmatch('[0-9a-f]{40}',source) and source==os.environ['RIFT_SOURCE']
assert sha(ipa)==report['ipa_sha256'] and ipa.stat().st_size==report['ipa_bytes']
checks=[]
for path in sorted(OUT.glob('models-*/MODEL-SMOKE.json')):checks+=json.loads(path.read_text())
assert len(checks)==len({c['id'] for c in checks})==10
assert all(c['exit_code']==0 and c['source']==source and c['transfer']['growth_bytes']<160*1048576 for c in checks)
metal=json.loads((OUT/'METAL-SMOKE.json').read_text())
assert len(metal)==1 and metal[0]['id']=='qwen35-4b' and metal[0]['exit_code']==0 and metal[0]['backend']=='macOS Metal' and metal[0]['source']==source
sys.path.insert(0,str(ROOT/'scripts'))
from publish_rift import verify_executable
from update_catalog import inspect_ipa,update,render_readme
info,permissions=inspect_ipa(ipa)
assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleShortVersionString']=='1.2' and info['CFBundleVersion']==report['build']
assert set(permissions['entitlements'])=={'com.apple.developer.kernel.increased-memory-limit','com.apple.developer.kernel.extended-virtual-addressing'}
with zipfile.ZipFile(ipa) as z:
 assert z.testzip() is None
 verify_executable(z.read('Payload/Rift.app/Rift'))
 catalog=json.loads(z.read('Payload/Rift.app/catalog.json'))
 assert {m['id'] for m in catalog}=={c['id'] for c in checks}
 for model in catalog:
  assert model['uncensored']
  assert next(c for c in checks if c['id']==model['id'])['file_sha256']==model['sha256']
report.update(build_result='passed',model_inference='All 10 pinned quantizations passed production Swift downloads, verification and two-turn macOS CPU inference',metal_inference='Qwen3.5 4B passed two-turn macOS Metal inference; not a physical-iPhone test',signing='Ad-hoc signature carries requested memory entitlements; installer and host must grant them')
save(OUT/'BUILD-REPORT.json',report);save(OUT/'MODEL-SMOKE.json',checks)
if '--verify-only' in sys.argv:print('VERIFIED',report['build']);sys.exit(0)
tag='rift-1.2-build'+report['build']
notes=f'''Rift 1.2 ({report['build']}) · Chat and animation fixes

- Bloom and Soft fade now use the native custom renderer while replies stream. Selectable text is kept out of that drawing path on affected iOS versions; native selection returns after the reply settles. The first live fragment animates too.
- Every animation style has a live inline preview. Selecting a style restarts the sample immediately, with a Replay button and a larger preview. Reduce Motion, Low Power Mode and VoiceOver behavior is explained rather than looking like a broken switch.
- Opening the keyboard follows the latest reply after the viewport shrinks. Incoming wrapping text, rotation and composer resizing keep its last line above the keyboard. Manual scrolling still lets you read earlier messages; Latest reply returns to the bottom.
- Removed Offline mode and migrated its old preference. Inference remains local by design. Model downloads are explicit actions; the cellular model-download preference remains.
- Memory readings now distinguish remaining headroom, the process footprint and the estimated total process budget. An Unload model from memory action releases the cached model without deleting downloads. Help explains the LiveContainer host/signing requirement. No memory limits are bypassed or promises of extra RAM made.

Verification: {summary['passedTests']} native simulator tests passed with zero failures/skips. Includes rendered-pixel animation checks (not only accessibility text), keyboard/latest-reply layout tests, privacy preference migration, and memory-display regressions. All 10 existing catalog quantizations were rechecked through production Swift downloads and two-turn macOS CPU inference; Qwen3.5 4B also passed macOS Metal inference. ARM64 iPhone executable and requested memory entitlements verified.

Physical-iPhone behavior and LiveContainer still need confirmation. The displayed remaining headroom is not total physical RAM or necessarily the full process limit. An Increased Memory Limit capability must be granted to the actual signed host for a LiveContainer guest. Extended Virtual Addressing does not create more physical RAM.

Update the existing Rift entry and keep its data container. The bundle ID remains com.billy.rift, iOS 26.0+. Existing downloaded models and chats are preserved. The catalog and inference engine are unchanged; uncensored is not a zero-refusal or accuracy guarantee.

Build source: {source}
IPA SHA-256: {report['ipa_sha256']}
'''
(OUT/'RELEASE-NOTES.md').write_text(notes)
files=[ipa,OUT/'Rift-Source.zip',OUT/'BUILD-REPORT.json',OUT/'MODEL-SMOKE.json',OUT/'METAL-SMOKE.json']
(OUT/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in files))
files.append(OUT/'SHA256SUMS.txt')
registry=json.loads((ROOT/'app-registry.json').read_text())
metadata=copy.deepcopy(registry['com.billy.rift'])
metadata['subtitle']='Private offline AI chat'
metadata['localizedDescription']='Chat locally on your iPhone with quantized uncensored community models or a GGUF imported from Files. Includes a compact iPhone-organized model picker, Heretic 8B/9B and experimental 14B choices, Bloom text animations, saved chats, and local search. Version 1.2 fixes live text animation and keyboard-follow scrolling, adds replaying style previews, removes the offline switch, and explains remaining memory versus the host process budget. No accounts, analytics, or cloud inference. Model downloads use the internet. Larger models depend on the signing/LiveContainer host memory allowance; physical-iPhone performance remains unverified.'
registry['com.billy.rift']=metadata;save(ROOT/'app-registry.json',registry)
verification=ROOT/'Rift/Verification'/('1.2-build'+report['build'])
for filename in ['BUILD-REPORT.json','MODEL-SMOKE.json','METAL-SMOKE.json']:
 save(verification/filename,json.loads((OUT/filename).read_text()))
cmd('git','config','user.name','github-actions[bot]');cmd('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
cmd('git','add','app-registry.json','Rift/Verification')
if subprocess.run(['git','diff','--cached','--quiet']).returncode:
 cmd('git','commit','-m','Record Rift 1.2 verified test evidence [skip ci]');cmd('git','push','origin','HEAD:main')
# Target a main snapshot whose workflow is already present, not an unmerged branch.
snapshot=cmd('git','rev-parse','HEAD')
existing=subprocess.run(['gh','release','view',tag,'--repo',REPO,'--json','isDraft,url'],capture_output=True,text=True)
if existing.returncode:
 assert 'release not found' in existing.stderr.lower(),existing.stderr
 cmd('gh','release','create',tag,*files,'--repo',REPO,'--target',snapshot,'--title',f"Rift 1.2 ({report['build']}) · Chat and animation fixes",'--notes-file',OUT/'RELEASE-NOTES.md','--draft')
with tempfile.TemporaryDirectory() as temp:
 cmd('gh','release','download',tag,'--repo',REPO,'--pattern','Rift.ipa','--dir',temp)
 assert sha(Path(temp)/'Rift.ipa')==report['ipa_sha256']
state=json.loads(cmd('gh','release','view',tag,'--repo',REPO,'--json','isDraft,url'))
if state['isDraft']:cmd('gh','release','edit',tag,'--repo',REPO,'--draft=false')
release=api('releases/tags/'+tag);assert not release['draft']
allapps=json.loads((ROOT/'apps.json').read_text())
others=copy.deepcopy([a for a in allapps['apps'] if a['bundleIdentifier']!='com.billy.rift'])
previous=next(a for a in allapps['apps'] if a['bundleIdentifier']=='com.billy.rift')
isolated={'apps':[copy.deepcopy(previous)]}
update(isolated,{'com.billy.rift':metadata},[ipa],tag,release['published_at'],notes)
allapps['apps']=others+isolated['apps'];save(ROOT/'apps.json',allapps);render_readme(allapps)
cmd('git','add','apps.json','README.md')
if subprocess.run(['git','diff','--cached','--quiet']).returncode:
 cmd('git','commit','-m',f"Publish Rift 1.2 ({report['build']}) chat and animation fixes [skip ci]");cmd('git','push','origin','HEAD:main')
print('PUBLISHED',release['html_url'],flush=True)
