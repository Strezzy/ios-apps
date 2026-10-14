#!/usr/bin/env python3
"""Receive the deliberately public Echo build, validate it, and update its source entry."""
import copy, hashlib, json, os, plistlib, re, subprocess, tempfile, urllib.parse, urllib.request, zipfile
from datetime import datetime, timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ALLOWED={'Echo.ipa','Echo-BUILD-REPORT.json','Echo-light.png','Echo-dark.png','SHA256SUMS.txt'}
def run(args,cwd=ROOT,capture=False,check=True):
    return subprocess.run(list(map(str,args)),cwd=cwd,check=check,capture_output=capture,text=True)
def save(path,data): path.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
def main():
    transfer=json.loads((ROOT/'branding/transfers/echo.json').read_text())
    url=urllib.parse.urlparse(transfer['url'])
    assert url.scheme=='https' and url.hostname.endswith('.oaiusercontent.com')
    assert re.fullmatch('[a-f0-9]{64}',transfer['archive_sha256'])
    with tempfile.TemporaryDirectory() as temporary:
        directory=Path(temporary);bundle=directory/'Echo-Public.zip'
        with urllib.request.urlopen(transfer['url'],timeout=120) as source, bundle.open('wb') as output:
            count=0
            while chunk:=source.read(1024*1024):
                count+=len(chunk);assert count<=200*1024*1024
                output.write(chunk)
        assert hashlib.sha256(bundle.read_bytes()).hexdigest()==transfer['archive_sha256']
        with zipfile.ZipFile(bundle) as archive:
            assert archive.testzip() is None
            assert set(archive.namelist())==ALLOWED,'Unexpected private content or missing intended public files'
            assert sum(i.file_size for i in archive.infolist())<300*1024*1024
            for filename in ALLOWED: (directory/filename).write_bytes(archive.read(filename))
        report=json.loads((directory/'Echo-BUILD-REPORT.json').read_text())
        assert report['status']=='passed' and report['native_branding']['status']=='passed'
        assert report['bundleIdentifier']=='com.billy.echo' and report['name']=='Echo'
        ipa=directory/'Echo.ipa';digest=hashlib.sha256(ipa.read_bytes()).hexdigest()
        assert digest==report['ipa_sha256']==transfer['ipa_sha256']
        assert ipa.stat().st_size==report['ipa_bytes']
        for line in (directory/'SHA256SUMS.txt').read_text().splitlines():
            checksum,filename=line.split('  ',1)
            assert filename in ALLOWED and filename!='SHA256SUMS.txt'
            assert hashlib.sha256((directory/filename).read_bytes()).hexdigest()==checksum
        with zipfile.ZipFile(ipa) as archive:
            assert archive.testzip() is None
            names=[n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist',n)]
            assert names==['Payload/Echo.app/Info.plist']
            info=plistlib.loads(archive.read(names[0]))
            for key,value in [('CFBundleIdentifier','com.billy.echo'),('CFBundleDisplayName','Echo'),('CFBundleName','Echo')]: assert info[key]==value
            assert info['CFBundleShortVersionString']==report['version']=='1.1'
            assert info['CFBundleVersion']==report['build'] and int(report['build'])>=100
            assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
            assert archive.read('Payload/Echo.app/'+info['CFBundleExecutable'])[:4]==b'\xcf\xfa\xed\xfe'
        tag=f'echo-{report["version"]}-build{report["build"]}'
        notes=(f'Echo {report["version"]} ({report["build"]})\n\n'
            'Native iPhone rebuild with the approved purple waveform icon, installed name Echo and bundle identifier com.billy.echo. '
            'Purple and lavender now coordinate the buttons, voice avatars, waveforms, background and controls. '
            'The actual compiled home-screen icon was pixel-checked against the approved master. Native tests, including identity and light/dark accent checks, passed. '
            'Light and dark simulator captures are attached. Full voice generation with downloaded models still requires testing on a physical iPhone.\n\n'
            '## Important installation change\n\n'
            'The bundle identifier changes from com.billy.voiceglass to com.billy.echo at the owner\'s request. This is a separate app identity. '
            'Keep the previous installation and export important clips or voice samples before removing it. Files, settings and model downloads do not automatically transfer. '
            'Previous release downloads remain available and were not overwritten. This is an unsigned arm64 iPhone IPA for your existing sideloading/signing setup.\n')
        notesfile=directory/'RELEASE-NOTES.md';notesfile.write_text(notes)
        if run(['gh','release','view',tag],capture=True,check=False).returncode:
            run(['gh','release','create',tag,*[directory/f for f in sorted(ALLOWED)],'--target',os.environ['GITHUB_SHA'],'--title',f'Echo {report["version"]} ({report["build"]})','--notes-file',notesfile])
        else:
            checkdir=directory/'published';checkdir.mkdir()
            run(['gh','release','download',tag,'--pattern','Echo.ipa','--dir',checkdir])
            assert hashlib.sha256((checkdir/'Echo.ipa').read_bytes()).hexdigest()==digest
        for attempt in range(5):
            run(['git','fetch','origin','main']);work=directory/f'catalog{attempt}'
            run(['git','worktree','add','--detach',work,'origin/main'])
            try:
                import importlib.util
                spec=importlib.util.spec_from_file_location('echo_catalog',work/'scripts/update_catalog.py')
                catalog_module=importlib.util.module_from_spec(spec);spec.loader.exec_module(catalog_module)
                registry=json.loads((work/'app-registry.json').read_text());catalog=json.loads((work/'apps.json').read_text())
                old,new='com.billy.voiceglass','com.billy.echo'
                before={a['bundleIdentifier']:copy.deepcopy(a) for a in catalog['apps'] if a['bundleIdentifier'] not in (old,new)}
                metadata=copy.deepcopy(registry.get(new,registry.get(old)));assert metadata
                metadata.update(name='Echo',icon='Echo.png',tintColor='#A28AEF')
                registry={new if k==old else k:(metadata if k in (old,new) else v) for k,v in registry.items()}
                assert new in registry and old not in registry
                catalog_module.update(catalog,registry,[ipa],tag,datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),notes)
                after={a['bundleIdentifier']:a for a in catalog['apps'] if a['bundleIdentifier'] not in (old,new)}
                assert before==after,'Unrelated app changed'
                save(work/'app-registry.json',registry);save(work/'apps.json',catalog);catalog_module.render_readme(catalog)
                evidence=work/'branding/native-releases';evidence.mkdir(exist_ok=True);save(evidence/'Echo.json',report)
                run(['git','add','app-registry.json','apps.json','README.md','branding/native-releases/Echo.json'],cwd=work)
                if not run(['git','diff','--cached','--quiet'],cwd=work,check=False).returncode:return
                run(['git','config','user.name','github-actions[bot]'],cwd=work)
                run(['git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com'],cwd=work)
                run(['git','commit','-m',f'Publish verified native Echo {report["version"]} ({report["build"]}) [skip ci]'],cwd=work)
                if not run(['git','push','origin','HEAD:main'],cwd=work,check=False).returncode:return
            finally:run(['git','worktree','remove','--force',work])
        raise RuntimeError('Release published, but concurrent catalog edits prevented source update')
if __name__=='__main__':main()
