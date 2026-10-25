#!/usr/bin/env python3
"""Reuse actual simulator evidence only for the exact unchanged runtime sources."""
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys
from verify_release import sha256

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'Build'
SOURCE = '8abeda5be908b06b3a49c715d06d6d142f6d34fe'
PATHS = ['Orbit/App', 'Orbit/Core', 'Orbit/Rendering', 'Orbit/Tests/Unit',
         'Orbit/project.yml', 'Orbit/Resources/Assets.xcassets']
source = Path(sys.argv[1])
old_build = json.loads((source / 'BUILD-REPORT.json').read_text())
old_validation = json.loads((source / 'VALIDATION-REPORT.json').read_text())
tests = json.loads((source / 'TEST-RESULTS.json').read_text())
current = json.loads((BUILD / 'BUILD-REPORT.json').read_text())
assert old_build['sourceCommit'] == SOURCE
assert old_validation['sourceCommit'] == SOURCE
assert old_validation['nativeReleaseBuild'] == 'passed'
assert old_validation['ipaSHA256'] == old_build['sha256'] == sha256(source / 'Orbit.ipa')
assert tests['passedTests'] == 7 and tests['failedTests'] == 0 and tests['skippedTests'] == 1
assert old_validation['passedTests'] == 7 and old_validation['failedTests'] == 0
old_log = (source / 'test.log').read_text()
assert '** TEST SUCCEEDED **' in old_log
subprocess.run(['git', 'diff', '--quiet', SOURCE, current['sourceCommit'], '--', *PATHS],
               cwd=ROOT.parent, check=True)
expected = {
    ('GeometryTests', 'testAspectFitAndFillPreserveVideoShape'): 'passed',
    ('GeometryTests', 'testMotionAxesFollowInterfaceOrientation'): 'passed',
    ('GeometryTests', 'testRotatedVideoUsesCorrectEncodedTextureCoordinates'): 'passed',
    ('GeometryTests', 'testTiltStaysBoundedAndRejectsInvalidSensorValues'): 'passed',
    ('SpatialPlaybackTests', 'testMonoMovieStaysFlatAndCloses'): 'passed',
    ('SpatialPlaybackTests', 'testRealSpatialMovieDecodesBothEyesAndSeeks'): 'skipped',
    ('StereoMatchingTests', 'testRecordedStereoShiftProducesCorrectDepth'): 'passed',
}
matches = re.findall(r"^Test Case '-\[OrbitTests\.(\w+) (\w+)\]' (passed|skipped|failed)", old_log, re.MULTILINE)
assert len(matches) == 7 and {(suite, name): result for suite, name, result in matches} == expected
units = {
    'reportKind': 'Unit-only results extracted from the original XCTest log',
    'sourceCommit': SOURCE, 'sourceRunID': 40185812644,
    'passedTests': 6, 'failedTests': 0, 'skippedTests': 1,
    'tests': [{'suite': suite, 'name': name, 'result': result} for suite, name, result in matches],
    'originalSummary': 'ORIGINAL-TEST-RESULTS.json',
    'originalLog': 'unit-source-test.log',
}
(BUILD / 'UNIT-TEST-RESULTS.json').write_text(json.dumps(units, indent=2) + '\n')
shutil.copyfile(source / 'TEST-RESULTS.json', BUILD / 'ORIGINAL-TEST-RESULTS.json')
shutil.copyfile(source / 'test.log', BUILD / 'unit-source-test.log')
files = ['UNIT-TEST-RESULTS.json', 'ORIGINAL-TEST-RESULTS.json', 'unit-source-test.log']
report = {
    'unitTestSourceCommit': SOURCE,
    'currentSourceCommit': current['sourceCommit'],
    'sourceRunID': 40185812644,
    'sourceArtifactID': 12595908818,
    'reason': 'Reuse only the 6 passed and 1 skipped unit checks for unchanged runtime/unit-test/project/icon sources. UI checks and screenshots run afresh on the current commit; the current device IPA is freshly built.',
    'unchangedPaths': PATHS,
    'files': {name: sha256(BUILD / name) for name in files},
}
(BUILD / 'CHECK-REUSE.json').write_text(json.dumps(report, indent=2) + '\n')
print('Verified unit evidence only: 6 passed, 1 skipped. UI checks and screenshots must now run afresh.')
