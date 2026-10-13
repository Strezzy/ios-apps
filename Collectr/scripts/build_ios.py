#!/usr/bin/env python3
"""Build with Apple's SDK, run native invariants and DA3, launch, package and verify."""
import json, os, plistlib, shutil, stat, subprocess, sys, time, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'Build'

def run(args,log=None,capture=False):
    print('+ '+' '.join(map(str,args)),flush=True)
    if log:
        with (BUILD/'Logs'/log).open('w') as stream:
            p=subprocess.Popen(list(map(str,args)),cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            for line in p.stdout:
                stream.write(line)
                if 'error:' in line or 'warning:' in line or 'Test Case' in line or '** ' in line: print(line,end='',flush=True)
            if p.wait(): raise RuntimeError(f'{log} failed. See Build/Logs/{log}')
    else:
        p=subprocess.run(list(map(str,args)),cwd=ROOT,check=True,capture_output=capture,text=True)
        return p.stdout if capture else None

def main():
    BUILD.mkdir(exist_ok=True);(BUILD/'Logs').mkdir(exist_ok=True)
    run([sys.executable,ROOT/'scripts/generate_icon.py'])
    run([sys.executable,ROOT/'scripts/prepare_models.py'])
    run(['xcodegen','generate','--spec',ROOT/'project.yml'])
    build_number=os.environ.get('COLLECTR_BUILD_NUMBER','1')
    common=['xcodebuild','-project',ROOT/'Collectr.xcodeproj','-scheme','Collectr','-derivedDataPath',BUILD/'DerivedData','CODE_SIGNING_ALLOWED=NO',f'CURRENT_PROJECT_VERSION={build_number}']
    run(common+['-configuration','Release','-sdk','iphoneos','-destination','generic/platform=iOS','build'],log='device-build.log')
    devices=json.loads(run(['xcrun','simctl','list','devices','available','--json'],capture=True))
    choices=[d for runtime,items in devices['devices'].items() if 'iOS-26' in runtime or 'iOS-27' in runtime for d in items if d.get('isAvailable') and d['name'].startswith('iPhone')]
    if not choices: raise RuntimeError('iOS 26+ simulator missing')
    device=next((d for d in choices if 'Pro' in d['name']),choices[0]);udid=device['udid']
    run(common+['-configuration','Debug','-destination',f'platform=iOS Simulator,id={udid}','-resultBundlePath',BUILD/'Tests.xcresult','test'],log='tests.log')
    log=(BUILD/'Logs/tests.log').read_text()
    if '** TEST SUCCEEDED **' not in log or 'testBundledDA3ProducesFiniteDepth' not in log: raise RuntimeError('Native tests or bundled DA3 inference not verified')
    simapp=BUILD/'DerivedData/Build/Products/Debug-iphonesimulator/Collectr.app'
    subprocess.run(['xcrun','simctl','boot',udid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    run(['xcrun','simctl','bootstatus',udid,'-b'])
    run(['xcrun','simctl','install',udid,simapp])
    launch=run(['xcrun','simctl','launch',udid,'com.billy.collectr'],capture=True)
    time.sleep(3)
    run(['xcrun','simctl','io',udid,'screenshot',BUILD/'Simulator-Launch.png'])
    app=BUILD/'DerivedData/Build/Products/Release-iphoneos/Collectr.app'
    info=plistlib.loads((app/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier']=='com.billy.collectr'
    assert info['CFBundleVersion']==build_number
    assert (app/'Models/Detailed.mlmodelc').is_dir()
    assert (app/'default.metallib').is_file()
    assert (app/'PrivacyInfo.xcprivacy').is_file()
    assert not (app/'Resources').exists()
    staging=BUILD/'Payload';shutil.rmtree(staging,ignore_errors=True);staging.mkdir()
    shutil.copytree(app,staging/'Collectr.app',symlinks=True)
    binary=staging/'Collectr.app/Collectr'
    binary.chmod(binary.stat().st_mode|stat.S_IXUSR|stat.S_IXGRP|stat.S_IXOTH)
    assert binary.read_bytes()[:4]==b'\xcf\xfa\xed\xfe','Expected 64-bit Mach-O'
    ipa=BUILD/'Collectr.ipa'
    with zipfile.ZipFile(ipa,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for p in sorted(staging.rglob('*')):
            if p.is_file(): archive.write(p,p.relative_to(BUILD))
    with zipfile.ZipFile(ipa) as archive:
        assert archive.testzip() is None
        assert 'Payload/Collectr.app/Info.plist' in archive.namelist()
    report={'version':'0.1.0','build':build_number,'revision':os.environ.get('GITHUB_SHA'),'xcode':run(['xcodebuild','-version'],capture=True),'nativeTests':'passed','model':'Pinned Depth Anything 3 Base FP16 504, real simulator inference passed','simulator':device['name'],'launch':launch.strip(),'ipaBytes':ipa.stat().st_size,'physicalDevice':'Not tested: motion, Photos deletion, two-phone trade and LiveContainer permissions need on-device validation.','scarcity':'Fixed local editions and recoverable nearby transfers; no authoritative global ledger.'}
    (BUILD/'BUILD-REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__': main()
