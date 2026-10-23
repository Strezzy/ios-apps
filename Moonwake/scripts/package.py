from pathlib import Path
import hashlib,json,plistlib,subprocess,zipfile
root=Path(__file__).resolve().parents[1]
build=root/'Build'; app=build/'Device/Build/Products/Release-iphoneos/Moonwake.app'
assert app.is_dir(), 'A real device build is required'
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.billy.moonwake'
assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
assert len(list((app/'Audio').glob('*.wav')))==17, 'Missing bundled audio'
ipa=build/'Moonwake.ipa'
with zipfile.ZipFile(ipa,'w',zipfile.ZIP_DEFLATED) as z:
    for f in sorted(app.rglob('*')):
        if f.is_file(): z.write(f,Path('Payload/Moonwake.app')/f.relative_to(app))
digest=hashlib.sha256(ipa.read_bytes()).hexdigest()
report={'product':'Moonwake','version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'bundleIdentifier':info['CFBundleIdentifier'],'deploymentTarget':info['MinimumOSVersion'],'sdk':info.get('DTSDKName'),'xcode':info.get('DTXcode'),'configuration':'Release','distributionSigned':False,'architecture':'arm64','nativeGame':'Swift + SpriteKit + SwiftUI','sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'ipaBytes':ipa.stat().st_size,'sha256':digest,'physicalDeviceValidation':'Pending: physical iPhone frame rate, thermals, haptics and sideloading behavior are not established by simulator tests.'}
(build/'BUILD-REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
(build/'SHA256SUMS.txt').write_text(digest+'  Moonwake.ipa\n')
print(json.dumps(report,indent=2))
