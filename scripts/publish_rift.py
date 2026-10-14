#!/usr/bin/env python3
"""Publish a verified Rift artifact without rebuilding or relabeling simulator output."""
import base64,hashlib,json,os,plistlib,re,struct,subprocess,sys,tempfile,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPO='Strezzy/ios-apps'
def command(*args):
    return subprocess.check_output([str(x) for x in args],text=True).strip()
def verify_executable(data):
    assert len(data)>=32 and data[:4]==b'\xcf\xfa\xed\xfe','Expected a thin 64-bit Mach-O executable'
    magic,cpu,subtype,kind,count,command_bytes,flags,reserved=struct.unpack_from('<8I',data)
    assert cpu==0x0100000c and kind==2,'Expected an arm64 application executable'
    assert command_bytes<=len(data)-32 and count<4096,'Invalid load-command table'
    offset=32; platform=None
    for _ in range(count):
        assert offset+8<=32+command_bytes,'Truncated load command'
        code,length=struct.unpack_from('<II',data,offset)
        assert length>=8 and offset+length<=32+command_bytes,'Invalid load-command size'
        if code==0x32:
            assert length>=24,'Invalid build-version command'
            platform=struct.unpack_from('<I',data,offset+8)[0]
        offset+=length
    assert offset==32+command_bytes and platform==2,'Executable is not built for iPhoneOS'
def verify(directory):
    directory=Path(directory)
    report=json.loads((directory/'BUILD-REPORT.json').read_text())
    assert report['app']=='Rift' and report['build_result']=='passed','Native build did not pass'
    assert report['simulator']=='passed','Native tests did not pass'
    checks=json.loads((directory/'MODEL-SMOKE.json').read_text())
    assert checks and all(row['exit_code']==0 for row in checks),'A model did not pass actual inference'
    ipa=directory/'Rift.ipa'
    with ipa.open('rb') as f: digest=hashlib.file_digest(f,'sha256').hexdigest()
    assert digest==report['ipa_sha256'] and ipa.stat().st_size==report['ipa_bytes'],'IPA identity mismatch'
    with zipfile.ZipFile(ipa) as archive:
        assert archive.testzip() is None,'IPA archive corruption'
        info=plistlib.loads(archive.read('Payload/Rift.app/Info.plist'))
        assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleDisplayName']=='Rift'
        assert 'iPhoneOS' in info['CFBundleSupportedPlatforms'],'Simulator output cannot be released'
        verify_executable(archive.read('Payload/Rift.app/'+info['CFBundleExecutable']))
        assert 'Payload/Rift.app/Assets.car' in archive.namelist()
        assert 'Payload/Rift.app/PrivacyInfo.xcprivacy' in archive.namelist()
        assert not any('/PlugIns/' in name or 'XCTest' in name for name in archive.namelist()),'Test-only components in release'
        assert info['CFBundleVersion']==report['build'] and info['CFBundleShortVersionString']=='1.0'
        models=json.loads(archive.read('Payload/Rift.app/catalog.json'))
        assert set(m['id'] for m in models)==set(c['id'] for c in checks),'Unchecked model in IPA'
        for model in models:
            assert model['uncensored'] and re.fullmatch('[0-9a-f]{40}',model['revision'])
            assert next(c for c in checks if c['id']==model['id'])['file_sha256']==model['sha256']
    source=(directory/'SOURCE-REVISION.txt').read_text().strip()
    assert re.fullmatch('[0-9a-f]{40}',source)
    return report,ipa,models,source
if __name__=='__main__':
    directory=Path(sys.argv[1]).resolve()
    report,ipa,models,source=verify(directory)
    if '--verify-only' in sys.argv:
        print(json.dumps({'verified':True,'build':report['build'],'source':source,'sha256':report['ipa_sha256']}));sys.exit(0)
    tag='rift-1.0-build'+report['build']
    notes=f'''Rift 1.0 ({report['build']}) · First beta

Native crimson SwiftUI and Liquid Glass local chat for iPhone. Includes the approved Rift icon, smooth letter-by-letter reply reveal, an animation preview and toggle, saved conversations, local search, copy/regenerate/export, Files GGUF imports, and a curated uncensored-only model catalog grouped by iPhone and family. iPhone 18 Pro and Pro Max profiles are included. Tiny benefit badges explain the tradeoffs.

No account, analytics or hosted inference. Model downloads connect to their host only when requested. Custom imports are marked unverified; no zero-refusal or model-accuracy guarantee is made.

## Validation

The native simulator build and test suite passed. All {len(models)} bundled catalog entries completed actual macOS CPU inference using the app's native wrapper. SHA-256 model checks and the arm64 iPhone package were verified. The reply scheduler has native tests for burst smoothing, Unicode, bounded visual latency, revisions, and immediate reduced-motion display.

**Physical iPhone inference speed, Metal compatibility, peak memory, heat, and LiveContainer behavior remain unverified.** CPU and simulator checks are not physical-device benchmarks. Phone recommendations are estimates; live memory checks remain enabled.

## Install

Download Rift.ipa and use your existing signing or LiveContainer setup. This is an unsigned arm64 iPhone app for iOS 26 or later, bundle ID com.billy.rift. Download a model in the app or import a compatible single-file GGUF.

Build source: {source}
IPA bytes: {report['ipa_bytes']}
SHA-256: {report['ipa_sha256']}
'''
    note=directory/'RELEASE-NOTES.md';note.write_text(notes)
    (directory/'SHA256SUMS.txt').write_text(report['ipa_sha256']+'  Rift.ipa\n')
    registry=json.loads((ROOT/'app-registry.json').read_text())
    registry['com.billy.rift']={
        'name':'Rift','subtitle':'Private offline AI chat · Beta',
        'localizedDescription':'Chat with AI on your iPhone without an account, analytics, or cloud inference. Download a curated uncensored community model, or import a compatible GGUF from Files. Includes a small iPhone-organized model library, model benefit badges, soft animated replies, saved chats, local search, and transcript export. Downloads require internet; chat works offline afterward. Uncensored does not guarantee zero refusals or accurate answers. First beta: physical iPhone performance and LiveContainer compatibility remain unverified.',
        'icon':'Rift.png','category':'utilities','tintColor':'#D62947'}
    (ROOT/'app-registry.json').write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n')
    asset=json.loads(command('gh','api',f'repos/{REPO}/contents/Rift/Rift/Assets.xcassets/AppIcon.appiconset/Rift.png?ref={source}'))
    data=base64.b64decode(asset['content']);assert data.startswith(b'\x89PNG\r\n\x1a\n')
    (ROOT/'assets/Rift.png').write_bytes(data)
    files=[ipa,directory/'Rift-Source.zip',directory/'BUILD-REPORT.json',directory/'MODEL-SMOKE.json',directory/'SHA256SUMS.txt']
    existing=subprocess.run(['gh','release','view',tag,'--repo',REPO],capture_output=True)
    if existing.returncode==0: raise RuntimeError('This build already has a release. Never replace published bytes.')
    command('gh','release','create',tag,*files,'--repo',REPO,'--target',source,'--title',f"Rift 1.0 ({report['build']}) · First beta",'--notes-file',note,'--draft')
    with tempfile.TemporaryDirectory() as tmp:
        command('gh','release','download',tag,'--repo',REPO,'--pattern','Rift.ipa','--dir',tmp)
        with (Path(tmp)/'Rift.ipa').open('rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()==report['ipa_sha256']
    command('gh','release','edit',tag,'--repo',REPO,'--draft=false')
    release=json.loads(command('gh','api',f'repos/{REPO}/releases/tags/{tag}'))
    sys.path.insert(0,str(ROOT/'scripts'))
    from update_catalog import update,render_readme
    catalog=json.loads((ROOT/'apps.json').read_text())
    update(catalog,registry,[ipa],tag,release['published_at'],notes)
    (ROOT/'apps.json').write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n')
    render_readme(catalog)
    command('git','add','app-registry.json','apps.json','README.md','assets/Rift.png')
    command('git','commit','-m',f"Publish verified Rift 1.0 ({report['build']}) first beta [skip ci]")
    command('git','pull','--rebase','origin','main')
    command('git','push','origin','HEAD:main')
    print(release['html_url'])
