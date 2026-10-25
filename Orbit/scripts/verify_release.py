#!/usr/bin/env python3
"""Check actual build evidence and record the precise validation scope."""
import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'Build'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def verify():
    build = json.loads((BUILD / 'BUILD-REPORT.json').read_text())
    assert build['configuration'] == 'Release'
    assert build['architecture'] == 'arm64'
    assert build['bundleIdentifier'] == 'com.billy.orbit'
    assert build['sdk'].startswith('iphoneos')
    assert re.fullmatch(r'[0-9a-f]{40}', build['sourceCommit'])
    assert re.fullmatch(r'\d+(?:\.\d+)*', build['version'])
    assert build['build'].isdigit()
    if os.environ.get('GITHUB_SHA'):
        assert build['sourceCommit'] == os.environ['GITHUB_SHA']
    assert (BUILD / 'Orbit.ipa').stat().st_size == build['ipaBytes']
    assert sha256(BUILD / 'Orbit.ipa') == build['sha256']
    assert '** BUILD SUCCEEDED **' in (BUILD / 'device-build.log').read_text()
    tests = json.loads((BUILD / 'TEST-RESULTS.json').read_text())
    assert tests.get('failedTests') == 0, tests
    # Four geometry tests, the ordinary-video decoder test, and the UI smoke
    # must pass even if this simulator cannot decode stereo MV-HEVC.
    assert tests.get('passedTests', 0) >= 6, tests
    assert '** TEST SUCCEEDED **' in (BUILD / 'test.log').read_text()
    for name in ['Orbit-Home-Portrait.png', 'Orbit-Home-Landscape.png']:
        assert (BUILD / name).stat().st_size > 10000, name
    if (BUILD / 'CHECK-REUSE.json').is_file():
        reuse = json.loads((BUILD / 'CHECK-REUSE.json').read_text())
        assert reuse['currentSourceCommit'] == build['sourceCommit']
        assert reuse['unitTestSourceCommit'] == '8abeda5be908b06b3a49c715d06d6d142f6d34fe'
        for name, digest in reuse['files'].items():
            assert sha256(BUILD / name) == digest
        subprocess.run(['git', 'diff', '--quiet', reuse['unitTestSourceCommit'], build['sourceCommit'], '--',
                        'Orbit/App', 'Orbit/Core', 'Orbit/Rendering', 'Orbit/Tests/Unit',
                        'Orbit/project.yml', 'Orbit/Resources/Assets.xcassets'], cwd=ROOT.parent, check=True)
        units = json.loads((BUILD / 'UNIT-TEST-RESULTS.json').read_text())
        ui = json.loads((BUILD / 'UI-TEST-RESULTS.json').read_text())
        assert (units['passedTests'], units['failedTests'], units['skippedTests']) == (6, 0, 1)
        assert (ui['passedTests'], ui['failedTests'], ui.get('skippedTests', 0)) == (1, 0, 0)
        assert (tests['passedTests'], tests['failedTests'], tests['skippedTests']) == (7, 0, 1)
        assert tests['unitResults']['sourceCommit'] == reuse['unitTestSourceCommit']
        assert tests['uiResults']['sourceCommit'] == build['sourceCommit']
    return build, tests


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--record', action='store_true')
    arguments = parser.parse_args()
    build, tests = verify()
    reuse = json.loads((BUILD / 'CHECK-REUSE.json').read_text()) if (BUILD / 'CHECK-REUSE.json').is_file() else None
    report = {
        'profile': 'native-build-and-focused-simulator-checks',
        'sourceCommit': build['sourceCommit'],
        'unitTestSourceCommit': reuse['unitTestSourceCommit'] if reuse else build['sourceCommit'],
        'uiTestSourceCommit': build['sourceCommit'],
        'testEvidence': 'Reused only unit checks for identical runtime sources; UI check and screenshots executed on this commit. See CHECK-REUSE.json and separate unit/UI reports.' if reuse else 'All checks executed on this source commit.',
        'version': build['version'],
        'build': build['build'],
        'ipaSHA256': build['sha256'],
        'nativeReleaseBuild': 'passed',
        'passedTests': tests['passedTests'],
        'failedTests': tests['failedTests'],
        'skippedTests': tests.get('skippedTests', 0),
        'geometryChecks': 'Aspect preservation, encoded video rotation, screen motion axes, invalid sensor values.',
        'ordinaryVideoCheck': 'A generated H.264 movie decodes as 2D and closes without retained playback state.',
        'simulatorUIValidation': 'Launch, import controls, portrait and landscape layout; attached native captures.',
        'hardwareDependentChecks': 'Stereo sample decoding and synthetic Metal disparity checks run where the simulator supports them. Any unsupported check is explicitly skipped in TEST-RESULTS.json, not counted as passed.',
        'spatialVideoQualityValidation': 'Not performed on a physical iPhone. Automated geometry and UI checks do not prove stereo reconstruction quality.',
        'physicalDeviceValidation': 'Not performed. Device motion, sustained playback, thermals and sideload-host behavior remain for physical testing.',
    }
    destination = BUILD / 'VALIDATION-REPORT.json'
    if arguments.record:
        destination.write_text(json.dumps(report, indent=2) + '\n')
    else:
        assert json.loads(destination.read_text()) == report
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
