#!/usr/bin/env python3
"""Gate release publication on this exact native binary and focused test results."""
import argparse,hashlib,json,os,plistlib,re,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'Build'
def verify_binary():
    r=json.loads((BUILD/'BUILD-REPORT.json').read_text())
    assert r['configuration']=='Release' and r['architecture']=='arm64'
    assert r['bundleIdentifier']=='com.billy.loop' and r['sdk'].startswith('iphoneos')
    assert re.fullmatch('[0-9a-f]{40}',r['sourceCommit'])
    if os.environ.get('GITHUB_SHA'):assert r['sourceCommit']==os.environ['GITHUB_SHA']
    ipa=BUILD/'Loop.ipa'
    assert ipa.stat().st_size==r['ipaBytes'] and hashlib.sha256(ipa.read_bytes()).hexdigest()==r['sha256']
    assert '** BUILD SUCCEEDED **' in (BUILD/'device-build.log').read_text()
    with zipfile.ZipFile(ipa) as z:
        names=z.namelist()
        info=plistlib.loads(z.read('Payload/Loop.app/Info.plist'))
        assert (info['CFBundleShortVersionString'],info['CFBundleVersion'])==(r['version'],r['build'])
        for model in ['LoopAging','LoopMatte','DepthAnythingV2SmallF16','SAM2TinyImageEncoderFLOAT16','SAM2TinyMaskDecoderFLOAT16','SAM2TinyPromptEncoderFLOAT16']:
            assert any('/'+model+'.mlmodelc/' in x for x in names),model
        for name in ['face_landmarker.task','selfie_multiclass_256x256.tflite','default.metallib','SCENE-MODELS.json']:
            assert any(x.endswith('/'+name) for x in names),name
    return r
def verify_release():
    r=verify_binary()
    t=json.loads((BUILD/'FOCUSED-CREATIVE-TESTS.json').read_text())
    assert t['sourceCommit']==r['sourceCommit']
    assert t['passedTests']>=50 and t['failedTests']==0 and t.get('skippedTests',0)==0,t
    report={'profile':'focused-creative','version':r['version'],'build':r['build'],'sourceCommit':r['sourceCommit'],'ipaSHA256':r['sha256'],'nativeReleaseBuild':'passed','automatedTests':{'passed':t['passedTests'],'failed':t['failedTests'],'skipped':t.get('skippedTests',0)},'scope':t['scope'],'fullEditorUISuite':'not-run','physicalDeviceValidation':'not-run'}
    (BUILD/'VALIDATION-REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--binary',action='store_true');p.add_argument('--mode',action='store_true');a=p.parse_args()
    if a.mode:print('focused-creative')
    elif a.binary:print(json.dumps(verify_binary(),indent=2))
    else:verify_release()
