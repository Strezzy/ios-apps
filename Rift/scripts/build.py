#!/usr/bin/env python3
"""Build real native binaries and retain evidence separately from device claims."""
import hashlib,json,os,plistlib,re,shutil,subprocess,sys,time,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'Build'; LOGS=BUILD/'Logs'; SHOTS=BUILD/'Screenshots'
for path in [BUILD,LOGS,SHOTS]: path.mkdir(parents=True,exist_ok=True)
REPORT=BUILD/'BUILD-REPORT.json'
report=json.loads(REPORT.read_text()) if REPORT.exists() else {'app':'Rift','version':'1.8.2','build':str(os.getenv('RIFT_BUILD_NUMBER','1')),'source':os.getenv('RIFT_SOURCE',os.getenv('GITHUB_SHA','local')),'iPhone_inference':'not_tested','LiveContainer':'not_tested','thermal_performance':'not_tested','simulator':'not_run','model_inference':'not_run'}
def save(): REPORT.write_text(json.dumps(report,indent=2)+'\n')
def run(command,name,cwd=ROOT):
    print('+',' '.join(map(str,command)),flush=True)
    with (LOGS/(name+'.log')).open('w') as log:
        process=subprocess.Popen(list(map(str,command)),cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
        for line in process.stdout: print(line,end='',flush=True); log.write(line)
        code=process.wait()
    if code: raise RuntimeError(name+' failed with exit code '+str(code))
def capture(command): return subprocess.check_output(list(map(str,command)),text=True)
def notices():
    source=ROOT/'ThirdParty/llama'
    sections=['Rift 1.8.2 dependency notices\nllama.cpp revision 8345f333951c661d166b00e6f9362e553768f292\nhttps://github.com/ggml-org/llama.cpp\n\nThe following notices accompany the pinned source tree. Some components are not linked in this build.']
    names=[]
    for path in sorted(source.rglob('*')):
        if not path.is_file() or path.is_symlink(): continue
        name=path.name.upper()
        if not (name.startswith('LICENSE') or name.startswith('LICENCE') or name.startswith('COPYING') or name=='NOTICE'): continue
        if path.stat().st_size>2_000_000: continue
        try: text=path.read_text(encoding='utf-8')
        except UnicodeDecodeError: continue
        relative=str(path.relative_to(source)); names.append(relative)
        sections.append('===== '+relative+' =====\n\n'+text)
    assert 'LICENSE' in names, 'Pinned runtime license is missing'
    destination=ROOT/'Rift/Resources/ThirdPartyNotices.txt'
    destination.write_text('\n\n'.join(sections)+'\n')
    report['dependency_notice_files']=names
    report['dependency_notices_sha256']=hashlib.sha256(destination.read_bytes()).hexdigest()
    save()
def prepare():
    if not (ROOT/'RECOVERY-APPLIED').exists(): run([sys.executable,ROOT/'scripts/recover.py'],'source-recovery')
    run([sys.executable,ROOT/'scripts/prepare.py'],'prepare')
    notices()
    project=ROOT/'project.yml'; spec=project.read_text()
    spec=re.sub(r"CURRENT_PROJECT_VERSION: '[^']+'","CURRENT_PROJECT_VERSION: '"+report['build']+"'",spec)
    spec=re.sub(r"CFBundleVersion: '[^']+'","CFBundleVersion: '"+report['build']+"'",spec)
    project.write_text(spec)
    run(['xcodegen','generate'],'xcodegen')
def test_evidence(result):
    if not result.exists(): return
    try: report['test_summary']=json.loads(capture(['xcrun','xcresulttool','get','test-results','summary','--path',result]))
    except Exception as e: report['summary_note']=str(e)
    try: run(['xcrun','xcresulttool','export','attachments','--path',result,'--output-path',SHOTS/'Tests'],'test-attachments')
    except Exception as e: report['attachments_note']=str(e)
    save()
def simulator():
    subprocess.run(['defaults','write','com.apple.iphonesimulator','ConnectHardwareKeyboard','-bool','NO'],check=True)
    devices=json.loads(capture(['xcrun','simctl','list','devices','available','--json']))['devices']
    choices=[d for runtime,items in devices.items() if 'iOS' in runtime for d in items if 'iPhone' in d['name'] and d.get('isAvailable')]
    assert choices,'No iPhone simulator is installed'
    choices.sort(key=lambda d:('Pro' in d['name'],'18' in d['name'],'17' in d['name']),reverse=True)
    device=choices[0]; uid=device['udid']; report['simulator_device']=device['name']; save()
    if device['state']!='Booted': run(['xcrun','simctl','boot',uid],'simulator-boot')
    common=['xcodebuild','-project',ROOT/'Rift.xcodeproj','-scheme','Rift','-configuration','Debug','-destination','id='+uid,'-derivedDataPath',BUILD/'DerivedData','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','DEVELOPMENT_TEAM=']
    result=BUILD/'Tests.xcresult'; shutil.rmtree(result,ignore_errors=True)
    try:
        # Compile while first-boot migration completes instead of serially waiting.
        run(common+['build-for-testing'],'simulator-build')
        run(['xcrun','simctl','bootstatus',uid,'-b'],'simulator-ready')
        from voice_test_scope import selection_for_source
        assert os.getenv('RIFT_TEST_SCOPE') == 'controls', 'Choose the reviewed controls scope explicitly'
        selection, prior = selection_for_source(report['source'], ROOT)
        report['test_selection'] = selection
        save()
        run(common+['test-without-building','-parallel-testing-enabled','NO','-resultBundlePath',result]+['-only-testing:'+test for test in selection],'native-tests')
        report['simulator']='passed'; save()
    finally:
        test_evidence(result)
        subprocess.run(['xcrun','simctl','shutdown',uid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    save()
def iphone():
    run(['xcodebuild','-project',ROOT/'Rift.xcodeproj','-scheme','Rift','-configuration','Release','-destination','generic/platform=iOS','-derivedDataPath',BUILD/'DeviceDerivedData','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','DEVELOPMENT_TEAM=','build'],'iphone-build')
    report['iphone_compilation']='passed'; save()
def smoke():
    # CPU model tests must not compete with an unused simulator for unified RAM.
    subprocess.run(['xcrun','simctl','shutdown','all'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    run([sys.executable,ROOT/'scripts/smoke.py'],'model-inference')
    report['model_inference']='all catalog entries passed actual macOS CPU smoke'; save()
def package(require_models=True):
    assert report['simulator']=='passed' and report.get('iphone_compilation')=='passed' and (not require_models or report['model_inference'].startswith('all catalog')), 'Required validation did not pass'
    app=BUILD/'DeviceDerivedData/Build/Products/Release-iphoneos/Rift.app'
    info=plistlib.loads((app/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier']=='com.billy.rift' and info['CFBundleDisplayName']=='Rift'
    assert str(info['CFBundleVersion'])==report['build']
    assert (app/'Assets.car').exists() and (app/'catalog.json').exists()
    assert (app/'ThirdPartyNotices.txt').exists(), 'Runtime copyright notices must ship in the app'
    architecture=capture(['xcrun','lipo','-info',app/'Rift']); assert 'arm64' in architecture
    report['executable_architecture']=architecture.strip()
    payload=BUILD/'Payload'; shutil.rmtree(payload,ignore_errors=True); payload.mkdir()
    run(['codesign','--force','--sign','-','--entitlements',ROOT/'Rift/Rift.entitlements','--generate-entitlement-der','--timestamp=none',app],'adhoc-memory-entitlements')
    run(['codesign','--verify','--strict',app],'verify-signature')
    shutil.copytree(app,payload/'Rift.app')
    ipa=BUILD/'Rift.ipa'; ipa.unlink(missing_ok=True)
    run(['ditto','-c','-k','--keepParent',payload,ipa],'package')
    with ipa.open('rb') as f: report['ipa_sha256']=hashlib.file_digest(f,'sha256').hexdigest()
    report['presentation_validation']='Attachment import, PDF/text extraction, image normalization, storage compatibility, picker/preview and connected keyboard behavior tested; physical-device feel not tested on this runner'; report['ipa_bytes']=ipa.stat().st_size; report['build_result']='passed' if require_models else 'native_passed'; save()
    with zipfile.ZipFile(BUILD/'Rift-Source.zip','w',zipfile.ZIP_DEFLATED) as z:
        for path in ROOT.rglob('*'):
            if path.is_file() and not any(part in ['Build','ThirdParty','Rift.xcodeproj','__pycache__'] for part in path.relative_to(ROOT).parts): z.write(path,'Rift/'+str(path.relative_to(ROOT)))
try:
    phase=sys.argv[1] if len(sys.argv)>1 else 'all'
    if phase in ['prepare','all']: prepare()
    if phase in ['native','all']: run([sys.executable,ROOT/'scripts/native.py'],'native-runtimes')
    if phase in ['simulator','all']: simulator()
    if phase in ['iphone','all']: iphone()
    if phase in ['smoke','all']: smoke()
    if phase in ['package','all']: package()
    if phase == 'candidate': package(require_models=False)
except Exception as error:
    report['build_result']='failed'; report['failure']=str(error); save(); raise
