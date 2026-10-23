#!/usr/bin/env python3
"""Fail the build on accidental network APIs, Photos writes, or plaintext movie capture.
This is a source regression guard, not a substitute for an on-device filesystem/network audit.
"""
import pathlib,re,json,plistlib
root=pathlib.Path(__file__).resolve().parents[1]
rules={
 'network client':r'\b(?:URLSession|URLRequest|NWConnection|NWListener|WKWebView|UIWebView|CFNetwork|Firebase|Sentry|Crashlytics)\b',
 'Photos write':r'\b(?:PHAssetChangeRequest|PHAssetCreationRequest|UIImageWriteToSavedPhotosAlbum|UISaveVideoAtPathToSavedPhotosAlbum)\b',
 'plaintext movie output':r'\bAVCaptureMovieFileOutput\b|AVAssetWriter\s*\(\s*(?:url|outputURL)\s*:',
 'unprotected image persistence':r'\b(?:UIImagePNGRepresentation|UIImageJPEGRepresentation)\b',
 'private logging':r'\b(?:print|debugPrint|NSLog|os_log)\s*\(',
 'cloud entitlement':r'com\.apple\.developer\.(?:icloud|ubiquity)',
}
failures=[]
for file in (root/'Velvet').rglob('*.swift'):
    text=file.read_text()
    # Source-only guard. Comments are omitted to avoid documentation false positives.
    text=re.sub(r'/\*.*?\*/','',text,flags=re.S)
    text=re.sub(r'//[^\n]*','',text)
    for name,rule in rules.items():
        if re.search(rule,text):failures.append(f'{file.relative_to(root)}: {name}')
privacy=plistlib.loads((root/'Velvet/Resources/PrivacyInfo.xcprivacy').read_bytes())
assert not privacy['NSPrivacyTracking'] and not privacy['NSPrivacyCollectedDataTypes']
assert 'NSPhotoLibraryAddUsageDescription' not in (root/'project.yml').read_text()
if failures:raise SystemExit('\n'.join(failures))
print(json.dumps({'sourcePrivacyGuards':'PASS','swiftFiles':len(list((root/'Velvet').rglob('*.swift'))),'deviceFilesystemAndNetworkAudit':'NOT RUN'},indent=2))
