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
assert report['app']=='Rift' and report['version']=='1.1' and report['simulator']=='passed' and report['iphone_compilation']=='passed'
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
assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleShortVersionString']=='1.1' and info['CFBundleVersion']==report['build']
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
tag='rift-1.1-build'+report['build']
notes=f'''Rift 1.1 ({report['build']}) · Stability update

- Slimmer composer with native keyboard-safe placement, tested in portrait and landscape.
- The AI runtime initializes only for generation, not at app launch. Local restoration runs off the UI thread.
- Bounded 512 KiB verification buffer, bounded metadata reader, throttled download progress, and model unload before transfers. Six-GiB hashing is covered by a memory-growth regression test. All model files were downloaded and verified using the production Swift code.
- Model-aware memory estimates with automatic context reduction down to 512 tokens. Lower batch sizes, memory-mapped weights, and no extra weight-repacking or speculative-model allocations.
- Short error banner with full details, preserved messages, and retry. Failed placeholders no longer become conversation input.
- Expanded Heretic group: 2.6B, 8B, 9B, plus 14B Compact (IQ3_XS) and 14B Precision (IQ4_XS). Two featured choices, with all sizes one tap away. All curated entries are uncensored community variants in quantized GGUF format, never stock-model fallbacks.
- Requested increased-memory-limit and extended-virtual-addressing entitlements included for signing tools. Within LiveContainer, the host's signed entitlements still control memory. The app cannot grant itself more memory or guarantee that 9B/14B fits every installation. 14B choices are explicitly experimental.

Verification: {summary['passedTests']} native simulator tests passed, zero failed/skipped. All 10 catalog quantizations passed actual two-turn macOS CPU inference and production Swift download/verification checks; Qwen3.5 4B also passed macOS Metal inference. ARM64 iPhone app and entitlement signature verified.

Physical-iPhone performance, heat, and LiveContainer behavior still require device testing. A Mac Metal result is not an iPhone benchmark; this update does not claim crashes are impossible. Uncensored does not mean guaranteed zero refusals or accuracy.

Update the existing Rift entry and keep its data container. Bundle ID remains com.billy.rift, iOS 26.0+. Existing downloaded models and chats are preserved. The installer supplies the final device signature.

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
metadata['localizedDescription']='Chat locally on your iPhone with quantized uncensored community models or a GGUF imported from Files. Includes a compact iPhone-organized model picker, Heretic 8B/9B and experimental 14B choices, Bloom text animations, saved chats, and local search. Version 1.1 adds keyboard and startup fixes, bounded large-file verification, adaptive memory/context handling, and clearer retry errors. No accounts, analytics, or cloud inference. Model downloads use the internet. Larger models depend on the signing/LiveContainer host memory allowance; physical-iPhone performance remains unverified.'
registry['com.billy.rift']=metadata;save(ROOT/'app-registry.json',registry)
verification=ROOT/'Rift/Verification'/('1.1-build'+report['build'])
for filename in ['BUILD-REPORT.json','MODEL-SMOKE.json','METAL-SMOKE.json']:
 save(verification/filename,json.loads((OUT/filename).read_text()))
cmd('git','config','user.name','github-actions[bot]');cmd('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
cmd('git','add','app-registry.json','Rift/Verification')
if subprocess.run(['git','diff','--cached','--quiet']).returncode:
 cmd('git','commit','-m','Record Rift 1.1 verified test evidence [skip ci]');cmd('git','push','origin','HEAD:main')
# Target a main snapshot whose workflow is already present, not an unmerged branch.
snapshot=cmd('git','rev-parse','HEAD')
existing=subprocess.run(['gh','release','view',tag,'--repo',REPO,'--json','isDraft,url'],capture_output=True,text=True)
if existing.returncode:
 assert 'release not found' in existing.stderr.lower(),existing.stderr
 cmd('gh','release','create',tag,*files,'--repo',REPO,'--target',snapshot,'--title',f"Rift 1.1 ({report['build']}) · Stability update",'--notes-file',OUT/'RELEASE-NOTES.md','--draft')
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
 cmd('git','commit','-m',f"Publish Rift 1.1 ({report['build']}) stability update [skip ci]");cmd('git','push','origin','HEAD:main')
print('PUBLISHED',release['html_url'],flush=True)
