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
assert report['app']=='Rift' and report['version']=='1.6' and report['simulator']=='passed' and report['iphone_compilation']=='passed'
from voice_test_scope import VOICE_TESTS, EXPECTED_TESTS, selection_for_source
summary=report['test_summary']
selection, prior = selection_for_source(report['source'], ROOT/'Rift')
assert summary['failedTests']==0 and summary['skippedTests']==0
assert report['test_selection']==selection, 'Only the reviewed voice tests may gate this release'
assert prior is None and summary['passedTests'] == EXPECTED_TESTS
validated_count = summary['passedTests']
report['validated_feature_test_count'] = validated_count
source=report['source'];assert re.fullmatch('[0-9a-f]{40}',source) and source==os.environ['RIFT_SOURCE']
# Other apps may publish concurrently. Only newer Rift source invalidates this IPA.
assert subprocess.run(['git','diff','--quiet',source,'HEAD','--','Rift/Rift','Rift/RiftTests','Rift/RiftUITests','Rift/project.yml']).returncode==0, 'Newer Rift source exists; wait for its verified build'
assert sha(ipa)==report['ipa_sha256'] and ipa.stat().st_size==report['ipa_bytes']
if feature_update:
 # This release changes presentation and voice only; reuse the existing model validation.
 unchanged=['Rift/Rift/Native','Rift/Rift/Resources/catalog.json','Rift/Rift/DownloadJob.swift','Rift/Rift/GGUF.swift','Rift/Rift/Models.swift','Rift/Rift/MemoryBudget.swift','Rift/Rift/AppModel.swift','Rift/Rift/Storage.swift']
 assert subprocess.run(['git','diff','--quiet','2f9cf01a96fef8db3b03f25d515c0e05ed741d8b',source,'--',*unchanged]).returncode==0, 'Model or storage code changed; feature-only release is not applicable'
else:
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
assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleShortVersionString']=='1.6' and info['CFBundleVersion']==report['build']
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
if feature_update:
 report.update(model_inference='Not rerun; model catalog, downloader, inference and storage code unchanged from 1.5', validation_scope='20 scoped tests: incremental speech, audio cues, chat layout, scrolling, Cipher default, living background and orb lifecycle; arm64 iPhone compilation', metal_inference='Not rerun; inference engine unchanged')
save(OUT/'BUILD-REPORT.json',report)
if not feature_update:save(OUT/'MODEL-SMOKE.json',checks)
if '--verify-only' in sys.argv:print('VERIFIED',report['build']);sys.exit(0)
tag='rift-1.6-build'+report['build']
notes=f'''Rift 1.6 ({report['build']}) · Living chat and faster voice

- Starts speaking stable phrases while the selected local model continues generating. Reasoning, code and link destinations stay out of spoken output. Listening resumes only after text generation and queued speech both finish; closing or stopping cancels the owned voice turn.
- Hides the voice preparation indicator. Opening and closing now have distinct darker glass tones with longer fading tails and continuous soft haptic fades. Sound respects Silent Mode and the existing Settings preferences.
- Centers the Rift mark in empty chats, removes welcome copy and prompt shortcuts, and changes the footer to “Unrestricted On-device AI”.
- Adds subtle drifting/fading crimson and garnet background light. Reduce Motion and Low Power Mode keep it still.
- Makes Cipher the initial text animation while preserving explicitly saved choices. Replaces reading/writing status text with a three-dot reply bubble and fits short outgoing bubbles to their text.
- Keeps short streaming conversations anchored at the top; follows the latest reply only once content exceeds the viewport. Models, inference, downloads, chat storage and voice selection are unchanged.

Verification: {validated_count} focused simulator checks passed, plus arm64 iPhone compilation. Only these changes and directly connected behavior were tested. No model inference checks were rerun. Microphone capture, audible playback and tactile feel require a physical iPhone; simulator checks cannot verify them.

Update the existing Rift entry and keep its data container. Bundle ID remains com.billy.rift, iOS 26.0+. Existing chats and downloaded models are retained. The installer supplies the final signature.

Build source: {source}
IPA SHA-256: {report['ipa_sha256']}
'''
(OUT/'RELEASE-NOTES.md').write_text(notes)
evidence_files=['BUILD-REPORT.json'] if feature_update else ['BUILD-REPORT.json','MODEL-SMOKE.json','METAL-SMOKE.json']
files=[ipa,OUT/'Rift-Source.zip',*[OUT/name for name in evidence_files]]
(OUT/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in files))
files.append(OUT/'SHA256SUMS.txt')
registry=json.loads((ROOT/'app-registry.json').read_text())
metadata=copy.deepcopy(registry['com.billy.rift'])
metadata['subtitle']='Private offline AI chat'
metadata['localizedDescription']='Private offline iPhone chat with downloaded uncensored community models or an imported GGUF. Version 1.6 adds a subtly living crimson background, a centered Rift mark in empty chats, compact outgoing bubbles, a three-dot reply indicator and Cipher as the default text animation. Voice replies begin as text generates. The glass orb has longer opening/closing tones and soft haptic fades; voice preferences remain in Settings. Speech setup may require an explicit download; voice quality depends on installed iOS voices. No accounts, analytics, uploaded recordings or cloud inference. Larger models depend on host memory.'
registry['com.billy.rift']=metadata;save(ROOT/'app-registry.json',registry)
verification=ROOT/'Rift/Verification'/('1.6-build'+report['build'])
for filename in evidence_files:
 save(verification/filename,json.loads((OUT/filename).read_text()))
cmd('git','config','user.name','github-actions[bot]');cmd('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
cmd('git','add','app-registry.json','Rift/Verification')
if subprocess.run(['git','diff','--cached','--quiet']).returncode:
 cmd('git','commit','-m','Record Rift 1.6 verified test evidence [skip ci]');cmd('git','push','origin','HEAD:main')
# Target a main snapshot whose workflow is already present, not an unmerged branch.
snapshot=cmd('git','rev-parse','HEAD')
existing=subprocess.run(['gh','release','view',tag,'--repo',REPO,'--json','isDraft,url'],capture_output=True,text=True)
if existing.returncode:
 assert 'release not found' in existing.stderr.lower(),existing.stderr
 cmd('gh','release','create',tag,*files,'--repo',REPO,'--target',snapshot,'--title',f"Rift 1.6 ({report['build']}) · Living chat and faster voice",'--notes-file',OUT/'RELEASE-NOTES.md','--draft')
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
 cmd('git','commit','-m',f"Publish Rift 1.6 ({report['build']}) Living chat and faster voice [skip ci]");cmd('git','push','origin','HEAD:main')
print('PUBLISHED',release['html_url'],flush=True)
