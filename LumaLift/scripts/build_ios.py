#!/usr/bin/env python3
"""Build iPhone binaries and gate beta publication on supported simulator tests.

Physical GPU tests remain in XCTest for device execution. Their explicit skips
are recorded separately; neither is counted as an inference or export pass.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time
import zipfile
from prepare_assets import main as prepare_assets
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'Build'
LOGS = BUILD / 'Logs'
TESTS = ['testSettingsAreIndependent', 'testOutputAndMotionLimits', 'testFrameClockAndArbitraryTimesteps',
         'testTilesCoverEveryPixelExactlyOnce', 'testBundledCoreMLRestorationExecutes',
         'testOriginalTimingAndCancellation', 'testPortraitOrientationIsPreserved', 'testShortAudioDoesNotTruncateVideo',
         'testZeroStrengthPreservesTileLayout', 'testFullEnhancementAtOriginalFPS',
         'testMotionUnavailableFailsWithoutPartialExport']
TESTS += ['testFilesPickerAcceptsGenericProviderTypes', 'testFilesImportPreservesOriginalMovieAndReadsGenericFiles', 'testFilesImportAcceptsMP4AndKeepsSettings', 'testFilesImportRejectsNonVideoWithoutReplacingClip', 'testFilesImportRejectsDirectoriesAndMissingFiles', 'testLucidFilesFixKeepsExistingBundleIdentity']
DEVICE_TESTS = ['testBundledRIFERunsOnAppleRuntime', 'testFullEnhancementAnd60FPSExport']
def run(args, log=None, capture=False):
    args = [str(arg) for arg in args]
    print('+', ' '.join(args), flush=True)
    if log:
        with (LOGS / (log + '.log')).open('w') as handle:
            process = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                handle.write(line)
                if not line.startswith(('    /', '    builtin-', '    cd ', '    export ', 'SwiftExplicitDependencyGeneratePcm')) and len(line) < 3000:
                    print(line, end='', flush=True)
            if process.wait(): raise RuntimeError(log + ' failed; see its build log.')
        return None
    return subprocess.run(args, cwd=ROOT, text=True, check=True, capture_output=capture).stdout

def main():
    if sys.platform != 'darwin': raise SystemExit('Use GitHub Actions or macOS with Xcode 26 or newer.')
    LOGS.mkdir(parents=True, exist_ok=True)
    report = {'status': 'in progress', 'source_revision': os.environ.get('GITHUB_SHA'),
              'release_channel': 'beta', 'physical_iphone_validation': 'Not performed',
              'motion_inference_validation': 'Not performed: hosted simulator GPU cannot initialize MPSGraph. Device tests are retained, not passed.',
              'required_simulator_tests': TESTS, 'required_device_tests_pending': DEVICE_TESTS}
    try:
        report['xcode'] = run(['xcodebuild', '-version'], capture=True).strip()
        report['sdk'] = run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], capture=True).strip()
        assert int(report['sdk'].split('.')[0]) >= 26
        forbidden = re.compile(r'URLSession|URLRequest|import\s+(Network|WebKit|CFNetwork)|https?://')
        shipping = list((ROOT / 'App').glob('*.swift')) + list((ROOT / 'Core').glob('*.swift'))
        assert not any(forbidden.search(p.read_text()) for p in shipping), 'Network API audit failed.'
        report['network_api_scan'] = 'Passed for app-owned Swift sources; not a network traffic capture.'
        report['source_hashes'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in shipping}
        report['models'] = json.loads((ROOT / 'Resources/MODEL-PROVENANCE.json').read_text())
        assert report['models']['conversion_verified']
        prepare_assets()
        run(['xcodegen', 'generate', '--spec', 'project.yml'], log='project')
        build = os.environ.get('LUMALIFT_BUILD_NUMBER', '1')
        common = ['xcodebuild', '-project', 'LumaLift.xcodeproj', '-scheme', 'LumaLift',
                  '-derivedDataPath', BUILD / 'DerivedData', 'CODE_SIGNING_ALLOWED=NO',
                  'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'DEVELOPMENT_TEAM=',
                  'CURRENT_PROJECT_VERSION=' + build]
        run(common + ['-configuration', 'Release', '-destination', 'generic/platform=iOS', 'build'], log='iphone-build')
        report['iphone_compilation'] = 'passed'
        devices = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], capture=True))['devices']
        candidates = []
        for runtime, entries in devices.items():
            version = re.search(r'iOS-(\d+)(?:-(\d+))?', runtime)
            if version and int(version[1]) >= 26:
                for device in entries:
                    if device.get('isAvailable') and device['name'].startswith('iPhone'):
                        candidates.append(((int(version[1]), int(version[2] or 0), 'Pro' in device['name'], device['name']), device))
        if not candidates: raise RuntimeError('No iOS 26+ iPhone simulator is installed.')
        device = max(candidates, key=lambda pair: pair[0])[1]
        udid = device['udid']
        report['simulator'] = device['name']
        sim = common + ['-configuration', 'Debug', '-destination', 'id=' + udid]
        run(sim + ['build-for-testing'], log='simulator-build')
        if device['state'] != 'Booted': run(['xcrun', 'simctl', 'boot', udid])
        run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], log='simulator-boot')
        result = BUILD / 'TestResults.xcresult'
        if result.exists(): shutil.rmtree(result)
        run(sim + ['-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES',
                   '-default-test-execution-time-allowance', '600', '-maximum-test-execution-time-allowance', '600',
                   '-resultBundlePath', result, 'test-without-building'], log='native-tests')
        transcript = (LOGS / 'native-tests.log').read_text()
        def has_result(name, state):
            return bool(re.search(r"Test Case '[^\n]*\b" + re.escape(name) + r"\b[^\n]*' " + state, transcript))
        passed = [name for name in TESTS if has_result(name, 'passed')]
        skipped = [name for name in DEVICE_TESTS if has_result(name, 'skipped')]
        if passed != TESTS: raise RuntimeError('Required simulator tests missing: ' + str(set(TESTS) - set(passed)))
        if skipped != DEVICE_TESTS: raise RuntimeError('Hardware-dependent tests must be explicitly recorded as skipped on this simulator.')
        report['native_tests'] = {'status': 'passed', 'count': len(passed), 'tests': passed,
                                  'skipped_count': len(skipped), 'skipped': skipped,
                                  'coverage': 'Simulator-supported tests only. Real RIFE inference and combined 60 FPS export remain unverified.'}
        sim_app = BUILD / 'DerivedData/Build/Products/Debug-iphonesimulator/LumaLift.app'
        run(['xcrun', 'simctl', 'install', udid, sim_app])
        run(['xcrun', 'simctl', 'launch', udid, 'com.billy.lucid'], log='simulator-launch')
        time.sleep(3)
        run(['xcrun', 'simctl', 'io', udid, 'screenshot', BUILD / 'Simulator-Launch.png'])
        report['simulator_launch'] = 'Passed; screenshot attached.'
        app = BUILD / 'DerivedData/Build/Products/Release-iphoneos/LumaLift.app'
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'com.billy.lucid'
        assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
        assert (app / 'LumaLift').read_bytes()[:4] == b'\xcf\xfa\xed\xfe'
        assert list(app.rglob('LumaGeneral.mlmodelc')), 'Missing bundled Core ML model.'
        assert list(app.rglob('rife-v4.26.rmw')), 'Missing bundled RIFE weights.'
        assert list(app.rglob('default.metallib')), 'Missing compiled Metal shaders.'
        assert (app / 'PrivacyInfo.xcprivacy').exists()
        assert (app / 'ThirdParty.txt').exists()
        ipa = BUILD / 'LumaLift.ipa'
        with zipfile.ZipFile(ipa, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(app.rglob('*')):
                if path.is_file(): archive.write(path, 'Payload/LumaLift.app/' + path.relative_to(app).as_posix())
        with zipfile.ZipFile(ipa) as archive: assert archive.testzip() is None
        source = BUILD / 'LumaLift-Source.zip'
        with zipfile.ZipFile(source, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(ROOT.rglob('*')):
                relative = path.relative_to(ROOT)
                if not path.is_file() or any(part in ('Build', '.git', '__pycache__', '.build') for part in relative.parts): continue
                archive.write(path, 'LumaLift/' + relative.as_posix())
        checksum = hashlib.sha256(ipa.read_bytes()).hexdigest()
        (BUILD / 'SHA256SUMS.txt').write_text(checksum + '  LumaLift.ipa\n' + hashlib.sha256(source.read_bytes()).hexdigest() + '  LumaLift-Source.zip\n')
        shutil.copyfile(ROOT / 'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png', BUILD / 'LumaLift-Icon.png')
        report.update(status='passed', version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                      ipa_sha256=checksum, ipa_bytes=ipa.stat().st_size,
                      signing='Unsigned arm64 iPhone app. Sign with your sideloading/developer tool.')
    except Exception as error:
        report.update(status='failed', error=str(error)); raise
    finally:
        (BUILD / 'BUILD-REPORT.json').write_text(json.dumps(report, indent=2) + '\n')
if __name__ == '__main__': main()
