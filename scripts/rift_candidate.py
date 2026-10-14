#!/usr/bin/env python3
"""Separate iPhone validation from memory-intensive model tests without weakening either gate."""
import hashlib,json,os,plistlib,re,shutil,subprocess,sys,time,zipfile
from pathlib import Path
REPO=Path(__file__).resolve().parents[1]; ROOT=REPO/'Rift'; BUILD=ROOT/'Build'; LOGS=BUILD/'Logs'
for p in [BUILD,LOGS]: p.mkdir(parents=True,exist_ok=True)
SOURCE=os.environ.get('GITHUB_SHA',subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip())
VERSION=str(100+int(os.environ.get('GITHUB_RUN_NUMBER','1')))
def run(args,name):
    print('+',' '.join(map(str,args)),flush=True)
    with (LOGS/(name+'.log')).open('w') as f:
        p=subprocess.Popen(list(map(str,args)),cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
        for line in p.stdout: print(line,end='',flush=True); f.write(line)
        if p.wait(): raise RuntimeError(name+' failed')
def output(*args): return subprocess.check_output(list(map(str,args)),text=True,cwd=ROOT)
def write(name,value): (BUILD/name).write_text(json.dumps(value,indent=2)+'\n')
def digest(path):
    with path.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def identity():
    return {'source':SOURCE,'native_wrapper_sha256':digest(ROOT/'Rift/Native/RiftEngine.mm'),'catalog_sha256':digest(ROOT/'Rift/Resources/catalog.json')}
def prepare():
    run([sys.executable,ROOT/'scripts/prepare.py'],'prepare')
    # Source has already been corrected and committed; do not mutate Swift during builds.
    assert 'source_corrections' not in (ROOT/'scripts/prepare.py').read_text()
    text=(ROOT/'Rift/Models.swift').read_text(); assert text.count('let length=MemoryLayout.size(ofValue:system.machine)')==1
    assert 'NSURLErrorCannotResume' not in (ROOT/'Rift/AppModel.swift').read_text()
def native():
    prepare()
    run([sys.executable,ROOT/'scripts/native.py','iphonesimulator','iphoneos'],'native-runtimes')
    spec=(ROOT/'project.yml').read_text()
    spec=re.sub(r"CURRENT_PROJECT_VERSION: '[^']+'","CURRENT_PROJECT_VERSION: '"+VERSION+"'",spec)
    spec=re.sub(r"CFBundleVersion: '[^']+'","CFBundleVersion: '"+VERSION+"'",spec)
    (ROOT/'project.yml').write_text(spec)
    run(['xcodegen','generate'],'xcodegen')
    devices=json.loads(output('xcrun','simctl','list','devices','available','--json'))['devices']
    choices=[d for runtime,items in devices.items() if 'iOS' in runtime for d in items if 'iPhone' in d['name'] and d.get('isAvailable')]
    choices.sort(key=lambda d:('Pro' in d['name'],'18' in d['name'],'17' in d['name']),reverse=True)
    assert choices,'No iPhone simulator available'; device=choices[0]; uid=device['udid']
    if device['state']!='Booted': run(['xcrun','simctl','boot',uid],'boot')
    common=['xcodebuild','-project',ROOT/'Rift.xcodeproj','-scheme','Rift','-configuration','Debug','-destination','id='+uid,'-derivedDataPath',BUILD/'DerivedData','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','DEVELOPMENT_TEAM=']
    run(common+['build-for-testing'],'simulator-build')
    run(['xcrun','simctl','bootstatus',uid,'-b'],'simulator-ready')
    result=BUILD/'Tests.xcresult';shutil.rmtree(result,ignore_errors=True)
    run(common+['test-without-building','-parallel-testing-enabled','NO','-resultBundlePath',result],'native-tests')
    summary=json.loads(output('xcrun','xcresulttool','get','test-results','summary','--path',result))
    assert summary['failedTests']==0 and summary['passedTests']>=20
    shots=BUILD/'Screenshots';shots.mkdir(exist_ok=True)
    run(['xcrun','xcresulttool','export','attachments','--path',result,'--output-path',shots/'Tests'],'export-attachments')
    for appearance in ['light','dark']:
        run(['xcrun','simctl','ui',uid,'appearance',appearance],'appearance-'+appearance)
        subprocess.run(['xcrun','simctl','terminate',uid,'com.billy.rift'],capture_output=True)
        run(['xcrun','simctl','launch',uid,'com.billy.rift'],'launch-'+appearance);time.sleep(2)
        run(['xcrun','simctl','io',uid,'screenshot',shots/('Rift-'+appearance+'.png')],'screenshot-'+appearance)
    run(['xcrun','simctl','shutdown',uid],'simulator-shutdown')
    run(['xcodebuild','-project',ROOT/'Rift.xcodeproj','-scheme','Rift','-configuration','Release','-destination','generic/platform=iOS','-derivedDataPath',BUILD/'DeviceDerivedData','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','DEVELOPMENT_TEAM=','build'],'iphone-build')
    app=BUILD/'DeviceDerivedData/Build/Products/Release-iphoneos/Rift.app'
    info=plistlib.loads((app/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleVersion']==VERSION
    payload=BUILD/'Payload';shutil.rmtree(payload,ignore_errors=True);payload.mkdir();shutil.copytree(app,payload/'Rift.app')
    run(['ditto','-c','-k','--keepParent',payload,BUILD/'Rift.ipa'],'package-candidate')
    write('NATIVE-REPORT.json',dict(identity(),app='Rift',version='1.0',build=VERSION,simulator='passed',iphone_compilation='passed',test_summary=summary,ipa_sha256=digest(BUILD/'Rift.ipa'),ipa_bytes=(BUILD/'Rift.ipa').stat().st_size))
    (BUILD/'SOURCE-REVISION.txt').write_text(SOURCE+'\n')
    with zipfile.ZipFile(BUILD/'Rift-Source.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in ROOT.rglob('*'):
            if p.is_file() and not any(x in ['Build','ThirdParty','Rift.xcodeproj','__pycache__'] for x in p.relative_to(ROOT).parts): z.write(p,'Rift/'+str(p.relative_to(ROOT)))
        z.write(__file__,'scripts/rift_candidate.py')
def models():
    prepare()
    memory=int(output('sysctl','-n','hw.memsize'))
    assert memory>=12*1024**3,'Model validation needs a host with at least 12 GiB of RAM'
    run([sys.executable,ROOT/'scripts/native.py','macosx'],'model-runtime')
    run([sys.executable,ROOT/'scripts/smoke.py'],'model-inference')
    checks=json.loads((BUILD/'MODEL-SMOKE.json').read_text())
    catalog=json.loads((ROOT/'Rift/Resources/catalog.json').read_text())
    assert {m['id'] for m in catalog}=={m['id'] for m in checks}
    assert all(m['exit_code']==0 for m in checks)
    write('MODEL-IDENTITY.json',dict(identity(),host_memory_bytes=memory,host_architecture=output('uname','-m').strip(),actual_CPU_inference='passed'))
def combine(directory):
    p=Path(directory);n=json.loads((p/'NATIVE-REPORT.json').read_text());m=json.loads((p/'MODEL-IDENTITY.json').read_text())
    for key in ['source','native_wrapper_sha256','catalog_sha256']: assert n[key]==m[key], 'Source mismatch: '+key
    assert n['source']==SOURCE and n['simulator']=='passed' and n['iphone_compilation']=='passed'
    assert m['actual_CPU_inference']=='passed'
    n.update(build_result='passed',model_inference='all catalog models passed actual macOS CPU inference on a separate 14 GB Intel host',iPhone_inference='not_tested',LiveContainer='not_tested',thermal_performance='not_tested',model_host=m)
    (p/'BUILD-REPORT.json').write_text(json.dumps(n,indent=2)+'\n')
if __name__=='__main__':
    try:
        phase=sys.argv[1]
        if phase=='native':native()
        elif phase=='models':models()
        elif phase=='combine':combine(sys.argv[2])
        else: raise ValueError('Unknown phase')
    except Exception as error:
        write('FAILURE.json',{'source':SOURCE,'error':str(error),'phase':sys.argv[1]});raise
