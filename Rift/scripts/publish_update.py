#!/usr/bin/env python3
"""Validate the scoped voice update, publish the exact IPA, update only Rift's listing."""
import copy,hashlib,json,os,plistlib,re,subprocess,sys,tempfile,zipfile
from pathlib import Path
ROOT=Path.cwd(); OUT=Path(sys.argv[1]).resolve(); REPO='Strezzy/ios-apps'
def cmd(*args):return subprocess.check_output([str(a) for a in args],text=True).strip()
def sha(path):
 with Path(path).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def save(path,data):Path(path).parent.mkdir(parents=True,exist_ok=True);Path(path).write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
def api(path):return json.loads(cmd('gh','api','repos/'+REPO+'/'+path))
feature_update=os.getenv('RIFT_FEATURE_UPDATE')=='1'
report=json.loads((OUT/'BUILD-REPORT.json').read_text()); ipa=OUT/'Rift.ipa'
assert report['app']=='Rift' and report['version']=='1.8.1' and report['simulator']=='passed' and report['iphone_compilation']=='passed'
from voice_test_scope import VOICE_TESTS, EXPECTED_TESTS, selection_for_source
summary=report['test_summary']
selection, prior = selection_for_source(report['source'], ROOT/'Rift')
assert summary['failedTests']==0 and summary['skippedTests']==0
assert report['test_selection']==selection, 'Only the three reviewed UI checks may gate this patch'
assert prior is None and summary['passedTests'] == EXPECTED_TESTS
validated_count = summary['passedTests']
report['validated_feature_test_count'] = validated_count
source=report['source'];assert re.fullmatch('[0-9a-f]{40}',source) and source==os.environ['RIFT_SOURCE']
# Other apps may publish concurrently. Only newer Rift source invalidates this IPA.
assert subprocess.run(['git','diff','--quiet',source,'HEAD','--','Rift/Rift','Rift/RiftTests','Rift/RiftUITests','Rift/project.yml']).returncode==0, 'Newer Rift source exists; wait for its verified build'
assert sha(ipa)==report['ipa_sha256'] and ipa.stat().st_size==report['ipa_bytes']
assert feature_update, 'This patch only supports the scoped release path'
# Reuse 1.8 inference evidence only when the shipping inference/download code is unchanged.
baseline='65ea4249858e49aae5e0be9d3fb0a9b561e623ad'
allowed={'Rift/Rift/ChatView.swift','Rift/Rift/DebugChatFixture.swift','Rift/Rift/SettingsView.swift','Rift/Rift/AppModel.swift'}
changed=set(cmd('git','diff','--name-only',baseline,source,'--','Rift/Rift').splitlines())
assert changed <= allowed, changed
old=cmd('git','show',baseline+':Rift/Rift/AppModel.swift')
new=(ROOT/'Rift/Rift/AppModel.swift').read_text().strip()
def shipping(text): return re.sub(r'(?m)^ *#if DEBUG\n.*?^ *#endif\n', '', text, flags=re.S)
assert shipping(old)==shipping(new), 'Shipping inference logic changed; prior evidence cannot be reused'
prior=json.loads((ROOT/'Rift/Verification/1.8-build132/VISION-SMOKE.json').read_text())
assert prior['passed'] and prior['source']==baseline
report['inference_evidence_source']=baseline
sys.path.insert(0,str(ROOT/'scripts'))
from publish_rift import verify_executable
from update_catalog import inspect_ipa,update,render_readme
info,permissions=inspect_ipa(ipa)
assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleShortVersionString']=='1.8.1' and info['CFBundleVersion']==report['build']
assert set(permissions['entitlements'])=={'com.apple.developer.kernel.increased-memory-limit','com.apple.developer.kernel.extended-virtual-addressing'}
with zipfile.ZipFile(ipa) as z:
 assert z.testzip() is None
 verify_executable(z.read('Payload/Rift.app/Rift'))
 catalog=json.loads(z.read('Payload/Rift.app/catalog.json'))
 assert catalog==json.loads((ROOT/'Rift/Rift/Resources/catalog.json').read_text())
 if not feature_update:
  assert {m['id'] for m in catalog}=={c['id'] for c in checks}
  for model in catalog:
   assert model['uncensored']
   assert next(c for c in checks if c['id']==model['id'])['file_sha256']==model['sha256']
report.update(build_result='passed',signing='Ad-hoc signature carries requested memory entitlements; installer and host must grant them')
report.update(model_inference='Not rerun: unchanged shipping inference retains verified 1.8 build 132 evidence', validation_scope='3 focused UI checks: immediate second send and voice close/reopen, drawer gestures/settings, keyboard/rotation; arm64 iPhone compilation', metal_inference='Retained from 1.8 build 132; no model downloads or inference tests run')
save(OUT/'BUILD-REPORT.json',report)
if not feature_update:save(OUT/'MODEL-SMOKE.json',checks)
if '--verify-only' in sys.argv:print('VERIFIED',report['build']);sys.exit(0)
tag='rift-1.8.1-build'+report['build']
notes=f'''Rift 1.8.1 ({report['build']}) · Responsive controls and full-height drawer

- Makes the composer read its current send/stop/voice/close state on every tap and gives each role a fresh touch target. Decorative glass no longer owns interactive animation on that target.
- Removes drawer scaling and extends the sliding chat surface to the screen edges, preserving its full height and rounded corners.
- Preserves models, attachments, voice processing, saved chats, the existing uncensored weights, and memory entitlements.

Verification: {validated_count} focused simulator UI checks passed, plus arm64 iPhone compilation and signed-package checks. No model downloads or inference tests were rerun; unchanged inference retains the verified 1.8 build 132 evidence. Physical-device timing remains unmeasured.

Update the existing Rift entry and keep its data container. Bundle ID remains com.billy.rift, iOS 26.0+.
Build source: {source}
IPA SHA-256: {report['ipa_sha256']}
'''
(OUT/'RELEASE-NOTES.md').write_text(notes)
evidence_files=['BUILD-REPORT.json']
files=[ipa,OUT/'Rift-Source.zip',*[OUT/name for name in evidence_files]]
(OUT/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in files))
files.append(OUT/'SHA256SUMS.txt')
registry=json.loads((ROOT/'app-registry.json').read_text())
metadata=copy.deepcopy(registry['com.billy.rift'])
metadata['subtitle']='Private offline AI chat'
metadata['localizedDescription']=metadata['localizedDescription'] + ' Version 1.8.1 fixes composer responsiveness and keeps the conversation drawer transition full height.'
registry['com.billy.rift']=metadata;save(ROOT/'app-registry.json',registry)
verification=ROOT/'Rift/Verification'/('1.8.1-build'+report['build'])
for filename in evidence_files:
 save(verification/filename,json.loads((OUT/filename).read_text()))
cmd('git','config','user.name','github-actions[bot]');cmd('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
cmd('git','add','app-registry.json','Rift/Verification')
if subprocess.run(['git','diff','--cached','--quiet']).returncode:
 cmd('git','commit','-m','Record Rift 1.8.1 verified test evidence [skip ci]');cmd('git','push','origin','HEAD:main')
# Target a main snapshot whose workflow is already present, not an unmerged branch.
snapshot=cmd('git','rev-parse','HEAD')
existing=subprocess.run(['gh','release','view',tag,'--repo',REPO,'--json','isDraft,url'],capture_output=True,text=True)
if existing.returncode:
 assert 'release not found' in existing.stderr.lower(),existing.stderr
 cmd('gh','release','create',tag,*files,'--repo',REPO,'--target',snapshot,'--title',f"Rift 1.8.1 ({report['build']}) · Responsive controls and full-height drawer",'--notes-file',OUT/'RELEASE-NOTES.md','--draft')
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
 cmd('git','commit','-m',f"Publish Rift 1.8.1 ({report['build']}) Responsive controls and full-height drawer [skip ci]");cmd('git','push','origin','HEAD:main')
print('PUBLISHED',release['html_url'],flush=True)
