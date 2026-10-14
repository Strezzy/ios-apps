#!/usr/bin/env python3
"""Native build and test pipeline. Successful compilation is not reported as physical-device validation."""
import hashlib,json,os,platform,plistlib,shutil,subprocess,sys,time,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'Build'; LOGS=BUILD/'Logs'; SHOTS=BUILD/'Screenshots'
for path in [BUILD,LOGS,SHOTS]: path.mkdir(parents=True,exist_ok=True)
report={'app':'Rift','version':'1.0','build':str(os.getenv('RIFT_BUILD_NUMBER','1')),'source':os.getenv('GITHUB_SHA','local'),'iPhone_inference':'not_tested','LiveContainer':'not_tested','thermal_performance':'not_tested','simulator':'not_run','model_inference':'not_run'}
def save(): (BUILD/'BUILD-REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
def run(command,name,cwd=ROOT):
    print('+',' '.join(map(str,command)),flush=True)
    with (LOGS/(name+'.log')).open('w') as log:
        process=subprocess.Popen(list(map(str,command)),cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
        for line in process.stdout: print(line,end='',flush=True); log.write(line)
        code=process.wait()
    if code: raise RuntimeError(name+' failed with exit code '+str(code))
def capture(command): return subprocess.check_output(list(map(str,command)),text=True)
try:
    # Stored state is optional during initialization so corrupt files can be preserved and surfaced safely.
    path=ROOT/'Rift/AppModel.swift'; text=path.read_text().replace('    let storage: LocalStorage?','    private(set) var storage: LocalStorage?'); path.write_text(text)
    run([sys.executable,ROOT/'scripts/prepare.py'],'prepare')
    run([sys.executable,ROOT/'scripts/native.py','iphonesimulator'],'native-simulator')
    # Use a fresh generated project for each build number without changing app identity.
    project=ROOT/'project.yml'; spec=project.read_text()
    import re
    spec=re.sub(r"CURRENT_PROJECT_VERSION: '[^']+'","CURRENT_PROJECT_VERSION: '"+report['build']+"'",spec)
    spec=re.sub(r"CFBundleVersion: '[^']+'","CFBundleVersion: '"+report['build']+"'",spec)
    project.write_text(spec)
    run(['xcodegen','generate'],'xcodegen')
    devices=json.loads(capture(['xcrun','simctl','list','devices','available','--json']))['devices']
    choices=[d for runtime,items in devices.items() if 'iOS' in runtime for d in items if 'iPhone' in d['name'] and d.get('isAvailable')]
    assert choices,'No iPhone simulator is installed'
    choices.sort(key=lambda d:('Pro' in d['name'],'18' in d['name'],'17' in d['name']),reverse=True)
    device=choices[0]; uid=device['udid']; report['simulator_device']=device['name']; save()
    if device['state']!='Booted': run(['xcrun','simctl','boot',uid],'simulator-boot')
    run(['xcrun','simctl','bootstatus',uid,'-b'],'simulator-ready')
    common=['xcodebuild','-project',ROOT/'Rift.xcodeproj','-scheme','Rift','-configuration','Debug','-destination','id='+uid,'-derivedDataPath',BUILD/'DerivedData','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','DEVELOPMENT_TEAM=']
    run(common+['build-for-testing'],'simulator-build')
    result=BUILD/'Tests.xcresult'; shutil.rmtree(result,ignore_errors=True)
    run(common+['test-without-building','-parallel-testing-enabled','NO','-resultBundlePath',result],'native-tests')
    report['simulator']='passed'
    try: report['test_summary']=json.loads(capture(['xcrun','xcresulttool','get','test-results','summary','--path',result]))
    except Exception as e: report['summary_note']=str(e)
    try: run(['xcrun','xcresulttool','export','attachments','--path',result,'--output-path',SHOTS/'Tests'],'test-attachments')
    except Exception as e: report['attachments_note']=str(e)
    for appearance in ['light','dark']:
        run(['xcrun','simctl','ui',uid,'appearance',appearance],'appearance-'+appearance)
        subprocess.run(['xcrun','simctl','terminate',uid,'com.billy.rift'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        run(['xcrun','simctl','launch',uid,'com.billy.rift'],'launch-'+appearance)
        time.sleep(2)
        run(['xcrun','simctl','io',uid,'screenshot',SHOTS/('Rift-'+appearance+'.png')],'screenshot-'+appearance)
    save()
    run([sys.executable,ROOT/'scripts/native.py','iphoneos','macosx'],'native-device-and-mac')
    run([sys.executable,ROOT/'scripts/smoke.py'],'model-inference')
    report['model_inference']='all catalog models passed macOS CPU smoke; not iPhone performance'; save()
    run(['xcodebuild','-project',ROOT/'Rift.xcodeproj','-scheme','Rift','-configuration','Release','-destination','generic/platform=iOS','-derivedDataPath',BUILD/'DeviceDerivedData','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','DEVELOPMENT_TEAM=','build'],'iphone-build')
    app=BUILD/'DeviceDerivedData/Build/Products/Release-iphoneos/Rift.app'
    info=plistlib.loads((app/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleDisplayName']=='Rift'
    assert str(info['CFBundleVersion'])==report['build']
    assert (app/'Assets.car').exists() and (app/'catalog.json').exists()
    architecture=capture(['xcrun','lipo','-info',app/'Rift']); assert 'arm64' in architecture
    report['executable_architecture']=architecture.strip()
    payload=BUILD/'Payload'; shutil.rmtree(payload,ignore_errors=True); payload.mkdir()
    shutil.copytree(app,payload/'Rift.app')
    ipa=BUILD/'Rift.ipa'; ipa.unlink(missing_ok=True)
    run(['ditto','-c','-k','--keepParent',payload,ipa],'package')
    with ipa.open('rb') as f: report['ipa_sha256']=hashlib.file_digest(f,'sha256').hexdigest()
    report['ipa_bytes']=ipa.stat().st_size; report['build_result']='passed'; save()
    with zipfile.ZipFile(BUILD/'Rift-Source.zip','w',zipfile.ZIP_DEFLATED) as z:
        for path in ROOT.rglob('*'):
            if path.is_file() and not any(part in ['Build','ThirdParty','Rift.xcodeproj','__pycache__'] for part in path.relative_to(ROOT).parts): z.write(path,'Rift/'+str(path.relative_to(ROOT)))
except Exception as error:
    report['build_result']='failed'; report['failure']=str(error); save(); raise
