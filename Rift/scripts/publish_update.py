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
assert report['app']=='Rift' and report['version']=='1.8' and report['simulator']=='passed' and report['iphone_compilation']=='passed'
from voice_test_scope import VOICE_TESTS, EXPECTED_TESTS, selection_for_source
summary=report['test_summary']
selection, prior = selection_for_source(report['source'], ROOT/'Rift')
assert summary['failedTests']==0 and summary['skippedTests']==0
assert report['test_selection']==selection, 'Only the reviewed attachment tests may gate this release'
assert prior is None and summary['passedTests'] == EXPECTED_TESTS
validated_count = summary['passedTests']
report['validated_feature_test_count'] = validated_count
source=report['source'];assert re.fullmatch('[0-9a-f]{40}',source) and source==os.environ['RIFT_SOURCE']
# Other apps may publish concurrently. Only newer Rift source invalidates this IPA.
assert subprocess.run(['git','diff','--quiet',source,'HEAD','--','Rift/Rift','Rift/RiftTests','Rift/RiftUITests','Rift/project.yml']).returncode==0, 'Newer Rift source exists; wait for its verified build'
assert sha(ipa)==report['ipa_sha256'] and ipa.stat().st_size==report['ipa_bytes']
if feature_update:
 # The selected 4B vision path changes; unrelated catalog entries are not rerun.
 unchanged=['Rift/Rift/Resources/catalog.json','Rift/Rift/DownloadJob.swift','Rift/Rift/GGUF.swift','Rift/Rift/MemoryBudget.swift','Rift/Rift/Storage.swift','Rift/Rift/Rift.entitlements']
 assert subprocess.run(['git','diff','--quiet','1421445242ea5ef292b6497769edfa0d1e07597b',source,'--',*unchanged]).returncode==0
 vision=json.loads((OUT/'VISION-SMOKE.json').read_text())
 assert vision['source']==source and vision['model_id']=='qwen35-4b' and vision['passed'] and vision['exit_code']==0
 assert vision['backend']=='macOS Metal' and vision['vision_backend']=='CPU' and len(vision['answers'])==3 and all(a['passed'] for a in vision['answers'])
 assert vision['model_sha256']=='79e28ecacf84e75b6056cf4059636d435aa9eb67795780f7b7dbc7d32a962741'
 assert vision['projector_sha256']=='a1e32e86ea99aa7a56f3dcfe7e63c1d0be9439d31fd07087099f15bc0fda0f22'

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
assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleShortVersionString']=='1.8' and info['CFBundleVersion']==report['build']
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
 report.update(model_inference='Only Qwen3.5 4B: two distinct images and text-document fallback passed with production native engine with CPU image encoding and macOS Metal generation', validation_scope='10 scoped simulator checks: file/PDF extraction, image normalization, bounds, chat compatibility, drawer/model picker, composer/preview, keyboard/rotation and voice open/close; arm64 iPhone compilation', metal_inference='Selected Qwen3.5 4B vision and text checks passed; no unrelated models rerun')
save(OUT/'BUILD-REPORT.json',report)
if not feature_update:save(OUT/'MODEL-SMOKE.json',checks)
if '--verify-only' in sys.argv:print('VERIFIED',report['build']);sys.exit(0)
tag='rift-1.8-build'+report['build']
notes=f'''Rift 1.8 ({report['build']}) · Local image and file attachments

- Adds a small plus button on the left of the composer to choose an image or file from Files. Preview or remove the attachment before sending; one attachment per message.
- Enables local image understanding for the installed Qwen3.5 4B Uncensored Aggressive Q4_K_M model using its publisher’s matching vision encoder. A separate, optional 676 MB download is required and SHA-256 verified. The existing uncensored weights are unchanged; no content filter or cloud moderation is added.
- Reads UTF-8/UTF-16 text, Markdown, CSV, JSON and text-based PDFs locally. Scanned PDFs can be attached as page images; unsupported, oversized or over-context files fail explicitly. This release does not add video, audio-file or Office-document understanding.
- Stores attached images privately on this iPhone, bounds image resolution and image-token usage, and checks additional memory before loading vision. Images are never uploaded. Choosing an iCloud file may require Files to download it first.
- Preserves the new left drawer, model menu, morphing composer, visible crimson background and existing memory entitlements alongside attachments. Saved chats without attachments remain compatible.

Verification: {validated_count} focused simulator checks passed, arm64 iPhone compilation and signed-package entitlement checks passed, and the production native engine correctly identified two different images plus a text-document code using only Qwen3.5 4B with CPU image encoding and macOS Metal generation. No other models were retested. Physical iPhone/LiveContainer vision performance remains device-dependent and was not measured by this runner.

Update the existing Rift entry and keep its data container. Bundle ID remains com.billy.rift, iOS 26.0+. Existing chats and downloaded models are retained. The installer supplies the final signature.

Build source: {source}
IPA SHA-256: {report['ipa_sha256']}
'''
(OUT/'RELEASE-NOTES.md').write_text(notes)
evidence_files=['BUILD-REPORT.json','VISION-SMOKE.json'] if feature_update else ['BUILD-REPORT.json','MODEL-SMOKE.json','METAL-SMOKE.json']
files=[ipa,OUT/'Rift-Source.zip',*[OUT/name for name in evidence_files]]
(OUT/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in files))
files.append(OUT/'SHA256SUMS.txt')
registry=json.loads((ROOT/'app-registry.json').read_text())
metadata=copy.deepcopy(registry['com.billy.rift'])
metadata['subtitle']='Private offline AI chat'
metadata['localizedDescription']='Private offline iPhone chat with downloaded uncensored community models or an imported GGUF. Version 1.8 adds local image and file attachments from the composer’s plus button. Qwen3.5 4B image understanding uses the matching publisher vision encoder, an optional verified 676 MB download. Text and text-based PDFs are read locally. The same uncensored weights are retained, with no added content filter or cloud moderation. Includes the left conversation drawer, quick model menu, morphing composer and living crimson background. No accounts, analytics, uploaded recordings or cloud inference. Larger models and images depend on device and host memory.'
registry['com.billy.rift']=metadata;save(ROOT/'app-registry.json',registry)
verification=ROOT/'Rift/Verification'/('1.8-build'+report['build'])
for filename in evidence_files:
 save(verification/filename,json.loads((OUT/filename).read_text()))
cmd('git','config','user.name','github-actions[bot]');cmd('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
cmd('git','add','app-registry.json','Rift/Verification')
if subprocess.run(['git','diff','--cached','--quiet']).returncode:
 cmd('git','commit','-m','Record Rift 1.8 verified test evidence [skip ci]');cmd('git','push','origin','HEAD:main')
# Target a main snapshot whose workflow is already present, not an unmerged branch.
snapshot=cmd('git','rev-parse','HEAD')
existing=subprocess.run(['gh','release','view',tag,'--repo',REPO,'--json','isDraft,url'],capture_output=True,text=True)
if existing.returncode:
 assert 'release not found' in existing.stderr.lower(),existing.stderr
 cmd('gh','release','create',tag,*files,'--repo',REPO,'--target',snapshot,'--title',f"Rift 1.8 ({report['build']}) · Local image and file attachments",'--notes-file',OUT/'RELEASE-NOTES.md','--draft')
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
 cmd('git','commit','-m',f"Publish Rift 1.8 ({report['build']}) Local image and file attachments [skip ci]");cmd('git','push','origin','HEAD:main')
print('PUBLISHED',release['html_url'],flush=True)
