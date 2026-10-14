#!/usr/bin/env python3
"""Verify actual iPhone packages, then publish without modifying legacy releases."""
from __future__ import annotations
import argparse, copy, hashlib, json, os, plistlib, re, subprocess, sys, tempfile, time, zipfile
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from native_suite_branding import APPS
ROOT=Path(__file__).resolve().parents[1]

def run(args,cwd=ROOT,capture=False,check=True):
    return subprocess.run(list(map(str,args)),cwd=cwd,text=True,check=check,capture_output=capture)

def save(path,data): path.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')

def verify(name):
    old,suffix,_=APPS[name]; folder=ROOT/old; build=folder/'Build'
    report=json.loads((build/'BUILD-REPORT.json').read_text())
    assert report['status']=='passed', 'Native build/test gate did not pass'
    original=build/(old+'.ipa'); target=build/(name+'.ipa')
    expected='com.billy.'+name.lower()
    with zipfile.ZipFile(original) as z:
        assert z.testzip() is None
        plist_paths=[n for n in z.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist',n)]
        assert len(plist_paths)==1
        base=plist_paths[0].rsplit('/',1)[0]; info=plistlib.loads(z.read(plist_paths[0]))
        for key,value in [('CFBundleIdentifier',expected),('CFBundleDisplayName',name),('CFBundleName',name)]:
            assert info.get(key)==value,(key,info.get(key),value)
        assert info['CFBundleShortVersionString']=='1.1'
        assert int(info['CFBundleVersion'])>=100
        assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
        assert z.read(base+'/'+info['CFBundleExecutable'])[:4]==b'\xcf\xfa\xed\xfe'
        primary=info.get('CFBundleIcons',{}).get('CFBundlePrimaryIcon',{})
        icon_names=primary.get('CFBundleIconFiles',[])
        assert icon_names,'No installed-app primary icon metadata'
        icons=[n for n in z.namelist() if n.startswith(base+'/') and n.count('/')==2 and n.endswith('.png') and any(Path(n).stem.startswith(x) for x in icon_names)]
        assert icons,'No compiled home-screen icon PNG'
        compiled=[]
        with tempfile.TemporaryDirectory() as temp:
            master=Image.open(ROOT/'branding/app-icons'/f'{name}.png').convert('RGB')
            for index,n in enumerate(icons):
                p=Path(temp)/f'icon{index}.png';p.write_bytes(z.read(n))
                decoded=Path(temp)/f'decoded{index}.png'
                run(['sips','-s','format','png',p,'--out',decoded],capture=True)
                image=Image.open(decoded).convert('RGB')
                expected_image=master.resize(image.size,Image.Resampling.LANCZOS)
                difference=sum(ImageStat.Stat(ImageChops.difference(image,expected_image)).mean)/3
                assert difference<8,(n,'Compiled icon does not match approved artwork',difference)
                compiled.append({'file':n,'dimensions':list(image.size),'mean_pixel_difference':round(difference,3)})
        extensions=[]
        for n in z.namelist():
            if n.endswith('.appex/Info.plist'):
                ext=plistlib.loads(z.read(n)); assert ext['CFBundleIdentifier'].startswith(expected+'.')
                assert name in ext['CFBundleDisplayName']
                extensions.append({'bundleIdentifier':ext['CFBundleIdentifier'],'displayName':ext['CFBundleDisplayName']})
        with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as out:
            for entry in z.infolist():
                item=copy.copy(entry)
                if item.filename==base or item.filename.startswith(base+'/'):
                    item.filename='Payload/'+name+'.app'+item.filename[len(base):]
                out.writestr(item,z.read(entry.filename))
    with zipfile.ZipFile(target) as z: assert z.testzip() is None
    if name=='Veil':
        log=(build/'Logs/native-tests.log').read_text()
        for test in ['testVeilInstalledIdentity','testVeilAccentIsGreenInBothAppearances']:
            assert re.search(r"Test Case '[^\n]*\b"+test+r"\b[^\n]*' passed",log),test
    report['original_build_ipa_sha256']=report.get('ipa_sha256')
    report.update(version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'],
        ipa_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),ipa_bytes=target.stat().st_size,
        native_branding={'status':'passed','name':name,'bundleIdentifier':expected,'archiveRoot':name+'.app',
                         'compiled_icons':compiled,'extensions':extensions,'physical_device':'Not tested'})
    save(build/(name+'-BUILD-REPORT.json'),report)
    (build/'SHA256SUMS-native.txt').write_text(report['ipa_sha256']+'  '+target.name+'\n')
    devices=json.loads(run(['xcrun','simctl','list','devices','booted','--json'],capture=True).stdout)['devices']
    for device in [d for ds in devices.values() for d in ds if d['name'].startswith('iPhone')]:
        udid=device['udid']
        if run(['xcrun','simctl','get_app_container',udid,expected],capture=True,check=False).returncode: continue
        for appearance in ['light','dark']:
            run(['xcrun','simctl','ui',udid,'appearance',appearance])
            run(['xcrun','simctl','launch',udid,expected],capture=True)
            time.sleep(2)
            run(['xcrun','simctl','io',udid,'screenshot',build/(name+'-'+appearance+'.png')])
        break
    print(json.dumps(report['native_branding'],indent=2))

def publish(name):
    old,suffix,_=APPS[name];build=ROOT/old/'Build'
    report=json.loads((build/(name+'-BUILD-REPORT.json')).read_text())
    assert report['status']=='passed' and report['native_branding']['status']=='passed'
    ipa=build/(name+'.ipa');assert hashlib.sha256(ipa.read_bytes()).hexdigest()==report['ipa_sha256']
    new_id='com.billy.'+name.lower();old_id='com.billy.'+suffix
    tag=f"{name.lower()}-{report['version']}-build{report['build']}"
    notes=(f"{name} {report['version']} ({report['build']})\n\n"
        f"Native rebuild with the approved {name} icon, installed display name and bundle ID `{new_id}`. "
        +('Veil now uses an emerald/mint interface, simpler import controls, adaptive large-text layout and reduced-transparency surfaces. ' if name=='Veil' else 'The existing interface colors and processing behavior are retained. ')
        +'The actual packaged identity and compiled home-screen icon were checked. Native test evidence and light/dark simulator captures are attached. '
        +'Physical iPhone behavior has not been tested. '+('RIFE hardware-only tests remain explicitly skipped, not passed. ' if name=='Lucid' else '')
        +'\n\n## Important installation change\n\n'
        +f'The bundle ID changes from `{old_id}` to `{new_id}` at the owner\'s request. This is a separate app identity, not a data-preserving in-place update. '
        +'Keep the previous installation and export any files or recordings you need before removing it. Data and preferences do not automatically move into the new sandbox. '
        +'Older published IPAs remain available and were not replaced. Use this arm64 iPhone IPA with your normal sideloading/signing setup.\n')
    notes_file=build/(name+'-RELEASE-NOTES.md');notes_file.write_text(notes)
    files=[ipa,build/(name+'-BUILD-REPORT.json'),build/'SHA256SUMS-native.txt']
    files += [p for p in (build/(name+'-light.png'),build/(name+'-dark.png')) if p.exists()]
    if run(['gh','release','view',tag,'--repo','Strezzy/ios-apps'],capture=True,check=False).returncode==0:
        with tempfile.TemporaryDirectory() as tmp:
            run(['gh','release','download',tag,'--repo','Strezzy/ios-apps','--pattern',ipa.name,'--dir',tmp])
            assert hashlib.sha256((Path(tmp)/ipa.name).read_bytes()).hexdigest()==report['ipa_sha256']
    else:
        args=['gh','release','create',tag,*files,'--repo','Strezzy/ios-apps','--target',os.environ['GITHUB_SHA'],
              '--title',f"{name} {report['version']} ({report['build']})",'--notes-file',notes_file]
        if name=='Lucid': args+=['--prerelease','--latest=false']
        run(args)
    for attempt in range(5):
        run(['git','fetch','origin','main'])
        with tempfile.TemporaryDirectory() as temp:
            work=Path(temp)/'catalog';run(['git','worktree','add','--detach',work,'origin/main'])
            try:
                import importlib.util
                spec=importlib.util.spec_from_file_location('catalog_release',work/'scripts/update_catalog.py')
                module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
                registry=json.loads((work/'app-registry.json').read_text());catalog=json.loads((work/'apps.json').read_text())
                before={a['bundleIdentifier']:copy.deepcopy(a) for a in catalog['apps'] if a['bundleIdentifier'] not in (old_id,new_id)}
                meta=copy.deepcopy(registry.get(new_id,registry.get(old_id)))
                assert meta is not None
                meta.update(name=name,icon=name+'.png')
                ordered={}
                for key,value in registry.items():
                    if key==old_id: ordered[new_id]=meta
                    elif key!=new_id: ordered[key]=value
                    else: ordered[new_id]=meta
                registry=ordered
                local=work/old/'catalog-entry.json'
                if local.exists(): save(local,meta)
                module.update(catalog,registry,[ipa],tag,datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),notes)
                after={a['bundleIdentifier']:a for a in catalog['apps'] if a['bundleIdentifier'] not in (old_id,new_id)}
                assert before==after,'Unrelated app metadata or release changed'
                save(work/'app-registry.json',registry);save(work/'apps.json',catalog);module.render_readme(catalog)
                evidence=work/'branding/native-releases';evidence.mkdir(exist_ok=True)
                save(evidence/(name+'.json'),report)
                paths=['app-registry.json','apps.json','README.md',f'branding/native-releases/{name}.json']
                if local.exists(): paths.append(f'{old}/catalog-entry.json')
                run(['git','add',*paths],cwd=work)
                if run(['git','diff','--cached','--quiet'],cwd=work,check=False).returncode==0: return
                run(['git','config','user.name','github-actions[bot]'],cwd=work)
                run(['git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com'],cwd=work)
                run(['git','commit','-m',f'Publish verified native {name} {report["version"]} ({report["build"]}) [skip ci]'],cwd=work)
                if run(['git','push','origin','HEAD:main'],cwd=work,check=False).returncode==0: return
            finally:
                run(['git','worktree','remove','--force',work])
    raise RuntimeError('Concurrent catalog edits prevented publishing; the verified release remains available')

def main():
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['verify','publish']);p.add_argument('app',choices=APPS);a=p.parse_args()
    (verify if a.mode=='verify' else publish)(a.app)
if __name__=='__main__':main()
