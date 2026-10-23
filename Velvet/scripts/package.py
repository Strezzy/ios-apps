#!/usr/bin/env python3
import hashlib,json,plistlib,shutil,subprocess,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
build=root/'Build';app=build/'Device/Build/Products/Release-iphoneos/Velvet.app'
assert app.is_dir(), 'No compiled app; packaging refused'
from fetch_model import FILENAME, SIZE, SHA256, verified
assert verified(app/'Models'/FILENAME), 'Pinned offline AI model missing or corrupt in compiled app; packaging refused'
ipa=build/'Velvet-unsigned.ipa'
with zipfile.ZipFile(ipa,'w',zipfile.ZIP_DEFLATED) as z:
    for f in sorted(app.rglob('*')):
        if f.is_file():z.write(f,Path('Payload/Velvet.app')/f.relative_to(app))
info=plistlib.loads((app/'Info.plist').read_bytes())
report={'product':'Velvet','version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'deploymentTarget':info['MinimumOSVersion'],'sdk':info.get('DTSDKName'),'xcode':info.get('DTXcode'),'xcodeBuild':info.get('DTXcodeBuild'),'configuration':'Release','signed':False,'model':{'name':FILENAME,'bytes':SIZE,'sha256':SHA256},'deviceValidation':'Needs Device Validation','ipaBytes':ipa.stat().st_size,'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()}
(build/'BUILD-REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
(build/'SHA256SUMS.txt').write_text(report['sha256']+'  '+ipa.name+'\n')
print(json.dumps(report,indent=2))
