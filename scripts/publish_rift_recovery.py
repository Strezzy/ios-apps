#!/usr/bin/env python3
"""Publish only an independently validated Rift build; never replace released bytes."""
import hashlib,json,os,plistlib,re,struct,subprocess,tempfile,zipfile
from pathlib import Path

REPO='Strezzy/ios-apps'
ROOT=Path.cwd()
RUN=os.environ['RIFT_RUN_ID']
EXPECTED=os.environ['RIFT_SOURCE_SHA']
assert RUN.isdecimal() and re.fullmatch('[0-9a-f]{40}',EXPECTED), 'Invalid build identity'
WORK=Path(tempfile.mkdtemp(prefix='rift-publish-'))

def command(args,check=True):
    result=subprocess.run(list(map(str,args)),check=check,capture_output=True,text=True)
    if result.stdout: print(result.stdout,flush=True)
    if result.returncode and check: raise RuntimeError(result.stderr)
    return result

def api(path):
    return json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/{path}'],text=True))

def digest(path):
    with path.open('rb') as handle: return hashlib.file_digest(handle,'sha256').hexdigest()

def one(name):
    matches=list((WORK/'artifact').rglob(name))
    assert len(matches)==1, 'Expected exactly one '+name
    return matches[0]

run=api('actions/runs/'+RUN)
assert run['status']=='completed' and run['conclusion']=='success', 'Build is not successful'
assert run['head_sha']==EXPECTED and run['head_branch']=='rift-v1', 'Wrong source commit or branch'
assert run['path']=='.github/workflows/rift-build.yml', 'Wrong build workflow'
command(['gh','run','download',RUN,'--repo',REPO,'--name','Rift-iPhone','--dir',WORK/'artifact'])
ipa=one('Rift.ipa'); source=one('Rift-Source.zip'); report_path=one('BUILD-REPORT.json'); smoke_path=one('MODEL-SMOKE.json')
report=json.loads(report_path.read_text()); smoke=json.loads(smoke_path.read_text())
assert report['source']==EXPECTED and report['build_result']=='passed', 'Source/report mismatch'
assert report['simulator']=='passed' and report['iphone_compilation']=='passed', 'Native checks did not pass'
assert report['model_inference'].startswith('all catalog'), 'Model tests did not pass'
assert report['ipa_sha256']==digest(ipa) and report['ipa_bytes']==ipa.stat().st_size, 'IPA identity mismatch'
assert report.get('dependency_notice_files'), 'Bundled dependency notice audit is missing'

with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, 'Corrupt IPA archive'
    names=archive.namelist()
    assert all(not n.startswith('/') and '..' not in Path(n).parts for n in names)
    assert not any(n.lower().endswith('.gguf') for n in names), 'Model weights must not be bundled'
    plists=[n for n in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist',n)]
    assert len(plists)==1
    info=plistlib.loads(archive.read(plists[0])); base=plists[0].rsplit('/',1)[0]
    assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleDisplayName']=='Rift'
    assert 'iPhoneOS' in info['CFBundleSupportedPlatforms'], 'Simulator app cannot be released'
    assert str(info['CFBundleVersion'])==str(report['build'])
    executable=archive.read(base+'/'+info['CFBundleExecutable'])
    assert executable[:4]==b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I',executable,4)[0]==0x0100000c, 'Not an arm64 iPhone executable'
    assert base+'/Assets.car' in names
    assert hashlib.sha256(archive.read(base+'/ThirdPartyNotices.txt')).hexdigest()==report['dependency_notices_sha256']
    models=json.loads(archive.read(base+'/catalog.json'))
    assert 3<=len(models)<=6
    assert len({m['id'] for m in models})==len(models)
    for model in models:
        assert model['uncensored'] is True and 'uncensored' in model['repo'].lower()
        assert re.fullmatch('[0-9a-f]{40}',model['revision']) and re.fullmatch('[0-9a-f]{64}',model['sha256'])
    assert {m['id'] for m in smoke}=={m['id'] for m in models}
    for result in smoke:
        assert result['exit_code']==0
        response=json.loads(result['stdout'])
        assert response['loaded'] is True and len(response['output'].strip())>2
        selected=next(m for m in models if m['id']==result['id'])
        assert result['file_sha256']==selected['sha256']
with zipfile.ZipFile(source) as archive:
    assert archive.testzip() is None
    for name in ['Rift/Rift/AppModel.swift','Rift/Rift/StreamingText.swift','Rift/Rift/Native/RiftEngine.mm','Rift/RiftTests/CancellationTests.swift']:
        assert name in archive.namelist(), 'Missing tested source '+name
    assert json.loads(archive.read('Rift/Rift/Resources/catalog.json'))==models
    icon=archive.read('Rift/Rift/Assets.xcassets/AppIcon.appiconset/Rift.png')
    assert icon.startswith(b'\x89PNG\r\n\x1a\n')

version=info['CFBundleShortVersionString']; build=str(info['CFBundleVersion'])
assert re.fullmatch(r'\d+(?:\.\d+)*',version) and build.isdecimal()
tag=f'rift-{version}-build{build}'
notes=f'''# Rift {version} ({build}) · First beta

Private, on-device AI chat with native crimson/garnet Liquid Glass and the approved suite icon.

## Included

- Bloom replies: new letters softly fade, lift, and settle into place. A bounded reveal buffer smooths uneven model output without slowing inference. Soft Fade and Instant alternatives, Reduce Motion/VoiceOver support, and a replayable Settings preview are included.
- A small uncensored-only catalog grouped by iPhone and model family, including iPhone 18 Pro / Pro Max browsing profiles and compact benefit badges. Actual available memory is checked before loading.
- Compatible single-file GGUF imports from Files, explicit verified downloads, pause/resume, offline mode, saved conversations, search, copying, regeneration, Markdown/code display, and transcript export.
- No accounts, analytics, hosted inference, or chat uploads. Download hosts can see network connection information; messages are not part of downloads.

## Verification and limits

The native simulator core/UI/animation tests and arm64 iPhone compilation passed. All {len(models)} catalog models produced actual replies through the production native runtime on macOS CPU. Dependency notices are bundled. The build report records the exact tests, backend, and file identities.

**Physical iPhone Metal inference, long-chat thermal behavior, and LiveContainer compatibility remain untested.** Device-fit estimates and benefit badges are not comparative performance benchmarks. Large models may need a higher app-memory allowance in the signing setup or LiveContainer host; browsing another iPhone never bypasses memory checks.

Every curated download is an explicitly uncensored community modification, not a stock aligned model. No model can be guaranteed never to refuse. Custom imports retain their own behavior and are marked unverified. Model licenses remain in force.

## Install

Download Rift.ipa and use your signing/sideloading installer or the Strezzy app source in LiveContainer. This is an unsigned arm64 iPhone application for iOS 26 or later. Model weights are downloaded separately. Bundle ID: com.billy.rift.

Tested source input: `{EXPECTED}`. The attached source archive includes the generated build resources actually compiled. The release uses the verified Rift branch; unrelated applications are unchanged.

Build: https://github.com/{REPO}/actions/runs/{RUN}

IPA SHA-256: `{digest(ipa)}`
'''
notes_path=WORK/'RELEASE-NOTES.md'; notes_path.write_text(notes)
checksums=WORK/'SHA256SUMS.txt'
assets=[ipa,source,report_path,smoke_path]
checksums.write_text(''.join(digest(path)+'  '+path.name+'\n' for path in assets))
assets.append(checksums)

# Reject an accidental downgrade before creating any public release.
command(['git','fetch','origin','main'])
command(['git','reset','--hard','origin/main'])
old=json.loads((ROOT/'apps.json').read_text())
existing=next((a for a in old['apps'] if a['bundleIdentifier']=='com.billy.rift'),None)
if existing:
    for v in existing.get('versions',[]):
        assert (v['version'],int(v['buildVersion'])) < (version,int(build)), 'Rift already has this or a newer version'
found=command(['gh','release','view',tag,'--repo',REPO,'--json','tagName'],check=False)
assert found.returncode!=0, 'This release tag already exists; released bytes are never replaced'
command(['gh','release','create',tag,'--repo',REPO,'--target',EXPECTED,'--title',f'Rift {version} ({build}) · First beta','--notes-file',notes_path,'--draft'])
command(['gh','release','upload',tag,'--repo',REPO]+assets)
# Read back the uploaded IPA before publishing the draft.
command(['gh','release','download',tag,'--repo',REPO,'--pattern','Rift.ipa','--dir',WORK/'readback'])
assert digest(WORK/'readback/Rift.ipa')==digest(ipa), 'Uploaded IPA readback mismatch'
command(['gh','release','edit',tag,'--repo',REPO,'--draft=false','--latest=false'])
release=api('releases/tags/'+tag)
assert not release['draft'] and not release['prerelease']

metadata={'name':'Rift','subtitle':'Private, offline AI chat · Beta','localizedDescription':'Chat privately with uncensored community AI models on your iPhone. Download a model once or import a compatible GGUF from Files, then chat offline. Native crimson Liquid Glass, smooth Bloom reply animation, saved conversations, search, export, and a small iPhone-organized model picker with benefit badges. No accounts, analytics, or cloud inference. Uncensored does not guarantee zero refusals; custom imports retain their own behavior. Physical iPhone performance, heat and LiveContainer compatibility still require device testing.','icon':'Rift.png','category':'utilities','tintColor':'#D62947'}
command(['git','config','user.name','github-actions[bot]'])
command(['git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com'])
for attempt in range(3):
    command(['git','fetch','origin','main'])
    command(['git','reset','--hard','origin/main'])
    registry_path=ROOT/'app-registry.json'; catalog_path=ROOT/'apps.json'
    registry=json.loads(registry_path.read_text()); catalog=json.loads(catalog_path.read_text())
    unrelated={a['bundleIdentifier']:a for a in catalog['apps'] if a['bundleIdentifier']!='com.billy.rift'}
    registry['com.billy.rift']=metadata
    registry_path.write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n')
    (ROOT/'assets/Rift.png').write_bytes(icon)
    command(['python3','scripts/update_catalog.py','--tag',tag,'--local',ipa,'--date',release['published_at'],'--notes',notes])
    updated=json.loads(catalog_path.read_text())
    assert unrelated=={a['bundleIdentifier']:a for a in updated['apps'] if a['bundleIdentifier']!='com.billy.rift'}, 'Unrelated app listings changed'
    command(['git','add','app-registry.json','apps.json','README.md','assets/Rift.png'])
    unchanged=command(['git','diff','--cached','--quiet'],check=False).returncode==0
    if unchanged: break
    command(['git','commit','-m',f'Publish verified Rift {version} ({build}) and preserve existing app listings [skip ci]'])
    push=command(['git','push','origin','HEAD:main'],check=False)
    if push.returncode==0: break
    if attempt==2: raise RuntimeError('Release is published, but the catalog push conflicted three times. Refresh and reconcile main before retrying the catalog update.')
print(json.dumps({'release':release['html_url'],'tag':tag,'ipa_sha256':digest(ipa),'build':build,'catalog':'updated','physical_device_testing':False},indent=2))
