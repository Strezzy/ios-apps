#!/usr/bin/env python3
"""Publish already-built, checksum-pinned evidence; never rebuild or invent checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'OrbitVerifiedRelease'
REPOSITORY = 'Strezzy/ios-apps'
CURRENT = '564d52ddfc4e433f73737347624cf18c5d1abefb'
TESTED = '8abeda5be908b06b3a49c715d06d6d142f6d34fe'
CURRENT_SHA256 = '691a31195f2cc6dba4b38be58a0efadc01753e88b1c799c22a4d1e8ae33a2f64'
TESTED_SHA256 = '33cad18af1f6562c2ec960a5f09c260bf38503a9db73fd57a853181ecca69b62'
TAG = 'orbit-1.0-build1'
RUNTIME_PATHS = ['Orbit/App', 'Orbit/Core', 'Orbit/Rendering', 'Orbit/Tests/Unit',
                 'Orbit/project.yml', 'Orbit/Resources/Assets.xcassets']


def run(arguments, cwd=ROOT, capture=False, check=True):
    return subprocess.run(arguments, cwd=cwd, check=check, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None)


def load(path):
    return json.loads(path.read_text())


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def fetch_commit(sha):
    if run(['git', 'cat-file', '-e', sha + '^{commit}'], capture=True, check=False).returncode:
        run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', sha])


def download(run_id, artifact_id, sha, destination):
    metadata = json.loads(run(['gh', 'api', f'repos/{REPOSITORY}/actions/artifacts/{artifact_id}'], capture=True).stdout)
    assert metadata['id'] == artifact_id and metadata['name'] == 'Orbit-Build-and-Checks'
    assert not metadata['expired']
    assert metadata['workflow_run']['id'] == run_id
    assert metadata['workflow_run']['head_sha'] == sha
    run(['gh', 'run', 'download', str(run_id), '--name', 'Orbit-Build-and-Checks', '--dir', str(destination)])


def verify_package(folder, sha, expected_hash):
    report = load(folder / 'BUILD-REPORT.json')
    assert report['sourceCommit'] == sha
    assert report['configuration'] == 'Release' and report['architecture'] == 'arm64'
    assert report['bundleIdentifier'] == 'com.billy.orbit'
    assert (report['version'], report['build']) == ('1.0', '1')
    assert report['sdk'].startswith('iphoneos')
    ipa = folder / 'Orbit.ipa'
    assert report['sha256'] == expected_hash == digest(ipa)
    assert report['ipaBytes'] == ipa.stat().st_size
    assert '** BUILD SUCCEEDED **' in (folder / 'device-build.log').read_text()
    with zipfile.ZipFile(ipa) as archive:
        info = plistlib.loads(archive.read('Payload/Orbit.app/Info.plist'))
        assert info['CFBundleIdentifier'] == 'com.billy.orbit'
        assert (info['CFBundleShortVersionString'], info['CFBundleVersion']) == ('1.0', '1')
        assert info['MinimumOSVersion'] == '26.0'
        assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
        binary = archive.read('Payload/Orbit.app/' + info['CFBundleExecutable'])
        assert binary[:4] == b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I', binary, 4)[0] == 0x0100000C
        assert 'Payload/Orbit.app/default.metallib' in archive.namelist()
        privacy = plistlib.loads(archive.read('Payload/Orbit.app/PrivacyInfo.xcprivacy'))
        assert privacy['NSPrivacyTracking'] is False
        if sha == CURRENT:
            assert any(item['NSPrivacyAccessedAPIType'] == 'NSPrivacyAccessedAPICategoryDiskSpace'
                       and 'E174.1' in item['NSPrivacyAccessedAPITypeReasons']
                       for item in privacy['NSPrivacyAccessedAPITypes'])
    return report


def prepare(first, current):
    fetch_commit(TESTED)
    fetch_commit(CURRENT)
    run(['git', 'diff', '--quiet', TESTED, CURRENT, '--', *RUNTIME_PATHS])
    old = verify_package(first, TESTED, TESTED_SHA256)
    build = verify_package(current, CURRENT, CURRENT_SHA256)
    tests = load(first / 'TEST-RESULTS.json')
    old_validation = load(first / 'VALIDATION-REPORT.json')
    assert old_validation['sourceCommit'] == TESTED and old_validation['ipaSHA256'] == old['sha256']
    assert (tests['passedTests'], tests['failedTests'], tests['skippedTests']) == (7, 0, 1)
    log = (first / 'test.log').read_text()
    assert '** TEST SUCCEEDED **' in log
    passed = re.findall(r"^Test Case '-\[(OrbitTests|OrbitUITests)\.(\w+) (\w+)\]' passed", log, re.MULTILINE)
    assert len(passed) == 7
    assert ('OrbitUITests', 'OrbitUITests', 'testHomeInPortraitAndLandscape') in passed
    assert ('OrbitTests', 'StereoMatchingTests', 'testRecordedStereoShiftProducesCorrectDepth') in passed
    assert "testRealSpatialMovieDecodesBothEyesAndSeeks]' skipped" in log
    portrait = first / 'Orbit-Home-Portrait.png'
    assert portrait.stat().st_size > 10000
    data = portrait.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    width, height = struct.unpack_from('>II', data, 16)
    assert height > width > 300
    OUT.mkdir(exist_ok=True)
    for name in ['Orbit.ipa', 'BUILD-REPORT.json']:
        shutil.copyfile(current / name, OUT / name)
    for name in ['TEST-RESULTS.json', 'Orbit-Home-Portrait.png', 'Orbit-Icon.png']:
        shutil.copyfile(first / name, OUT / name)
    run(['git', 'archive', '--format=zip', '--output', str(OUT / 'Orbit-Source.zip'), CURRENT + ':Orbit'])
    report = {
        'profile': 'Verified existing native build with original functional-test evidence',
        'product': 'Orbit', 'version': '1.0', 'build': '1',
        'binarySourceCommit': CURRENT, 'testSourceCommit': TESTED,
        'nativeBuildRunID': 40186782262, 'nativeBuildArtifactID': 12596685766,
        'testRunID': 40185812644, 'testArtifactID': 12595908818,
        'ipaSHA256': build['sha256'], 'ipaBytes': build['ipaBytes'],
        'nativeReleaseBuild': 'passed', 'passedTests': 7, 'failedTests': 0, 'skippedTests': 1,
        'unchangedRuntimePaths': RUNTIME_PATHS,
        'testEvidence': 'Original XCTest results, not newly executed tests. Runtime UI, playback, rendering, unit tests, project and icon sources match exactly between tested and packaged commits.',
        'functionalCoverage': 'Aspect geometry, encoded orientation, screen motion axes, invalid motion input, ordinary-video decoding, actual Metal stereo shift matching, home launch, portrait/landscape orientation and reachable import controls.',
        'stereoDecoderCheck': 'Explicitly skipped because the simulator reports stereo MV-HEVC decoding unsupported. Real two-eye iPhone playback is not device-verified.',
        'portraitCapture': {'file': 'Orbit-Home-Portrait.png', 'sourceCommit': TESTED, 'width': width, 'height': height},
        'landscapeCapture': 'Omitted. The original app-window screenshot was incorrectly cropped. Functional rotation/control assertions passed, but landscape visual validation is not claimed.',
        'laterScreenshotAttempt': 'Run 40186782262 timed out during simulator/test-runner preparation before UI assertions were recorded. It supplies no additional test pass or screenshot validation.',
        'sourceArchive': 'Created directly from the packaged binary source commit. project.yml generates the Xcode project.',
        'physicalDeviceValidation': 'Not performed. Spatial reconstruction quality, real device motion, sustained thermals and sideload-host behavior still require physical iPhone testing.',
    }
    (OUT / 'VALIDATION-REPORT.json').write_text(json.dumps(report, indent=2) + '\n')
    notes = (
        '# Orbit 1.0\n\nA full-screen spatial-video viewer with two-axis tilt depth, portrait and landscape playback, '
        'Photos/Files import, a local library, touch look-around, depth strength, recenter, fit/fill, scrubbing, mute and looping. '
        'Native ice-blue/violet Liquid Glass interface; processing stays on device. Requires iOS 26.\n\n'
        'The arm64 IPA is unsigned for the existing sideloading workflow. Use original spatial recordings; ordinary or flattened videos play in 2D. '
        'Depth is a bounded custom stereo reconstruction, with possible artifacts around occlusions, reflections and low-texture areas.\n\n'
        f'## Validation\n\nThe native Release IPA was successfully built at `{CURRENT}`. '
        f'The original functional tests at `{TESTED}` recorded **7 passed, 0 failed, 1 skipped**. '
        'The app, playback, renderer, unit-test, project and icon sources are identical between these commits. '
        'Those existing results are reused; no new test execution is claimed. The skipped check is real stereo MV-HEVC decoding, unsupported by the simulator. '
        'The GPU disparity test and portrait/landscape rotation and import-control assertions passed.\n\n'
        'Only the verified original portrait capture is attached. The incorrectly cropped landscape capture is omitted. '
        'A later screenshot retry timed out during simulator/test-runner preparation before assertions were recorded; it is not counted as a pass. '
        'Physical iPhone depth quality, motion, thermals and sideload-host behavior remain untested.\n\n'
        'The source archive matches the packaged native build and includes the XcodeGen project specification.\n\n'
        f'IPA SHA-256: `{CURRENT_SHA256}`\n'
    )
    (OUT / 'RELEASE-NOTES.md').write_text(notes)
    # Explicit allowlist: the rejected landscape capture can never be published.
    assets = [OUT / name for name in ['Orbit.ipa', 'Orbit-Source.zip', 'Orbit-Icon.png',
              'Orbit-Home-Portrait.png', 'BUILD-REPORT.json', 'VALIDATION-REPORT.json', 'TEST-RESULTS.json']]
    (OUT / 'SHA256SUMS.txt').write_text(''.join(f'{digest(path)}  {path.name}\n' for path in assets))
    return assets + [OUT / 'SHA256SUMS.txt']


def publish(assets):
    existing = run(['gh', 'release', 'view', TAG, '--json', 'isDraft,isPrerelease,targetCommitish,assets'], capture=True, check=False)
    if existing.returncode == 0:
        release = json.loads(existing.stdout)
        assert release['targetCommitish'] == CURRENT and not release['isPrerelease']
        assert {path.name for path in assets} <= {asset['name'] for asset in release['assets']}
        with tempfile.TemporaryDirectory() as folder:
            run(['gh', 'release', 'download', TAG, '--dir', folder])
            for path in assets:
                assert digest(Path(folder) / path.name) == digest(path), 'Existing release bytes are immutable'
        if release['isDraft']:
            run(['gh', 'release', 'edit', TAG, '--draft=false', '--latest=false'])
    else:
        run(['gh', 'release', 'create', TAG, *map(str, assets), '--target', CURRENT,
             '--title', 'Orbit 1.0 (1) · A little more depth', '--notes-file', str(OUT / 'RELEASE-NOTES.md'), '--draft'])
        run(['gh', 'release', 'edit', TAG, '--draft=false', '--latest=false'])
    with tempfile.TemporaryDirectory() as folder:
        worktree = Path(folder) / 'catalog'
        run(['git', 'fetch', 'origin', 'main'])
        run(['git', 'worktree', 'add', '--detach', str(worktree), 'origin/main'])
        try:
            run(['git', 'config', 'user.name', 'github-actions[bot]'], cwd=worktree)
            run(['git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com'], cwd=worktree)
            for attempt in range(4):
                run(['git', 'fetch', 'origin', 'main'], cwd=worktree)
                run(['git', 'reset', '--hard', 'origin/main'], cwd=worktree)
                run(['python3', 'scripts/update_catalog.py', '--tag', TAG], cwd=worktree)
                run(['git', 'add', 'apps.json', 'README.md'], cwd=worktree)
                if run(['git', 'diff', '--cached', '--quiet'], cwd=worktree, check=False).returncode == 0:
                    return
                run(['git', 'commit', '-m', 'Publish verified Orbit 1.0 in the iPhone app catalog'], cwd=worktree)
                if run(['git', 'push', 'origin', 'HEAD:main'], cwd=worktree, check=False).returncode == 0:
                    return
            raise RuntimeError('Release published; catalog push could not complete after concurrent updates')
        finally:
            run(['git', 'worktree', 'remove', '--force', str(worktree)], check=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--first-artifact', type=Path)
    parser.add_argument('--current-artifact', type=Path)
    args = parser.parse_args()
    assert bool(args.first_artifact) == bool(args.current_artifact)
    assert not args.first_artifact or args.prepare_only, 'Local inputs are for read-only preparation'
    assert os.environ.get('GH_REPO', REPOSITORY) == REPOSITORY
    with tempfile.TemporaryDirectory() as folder:
        first = args.first_artifact or Path(folder) / 'first'
        current = args.current_artifact or Path(folder) / 'current'
        if not args.first_artifact:
            download(40185812644, 12595908818, TESTED, first)
            download(40186782262, 12596685766, CURRENT, current)
        assets = prepare(first, current)
        print(f'Verified {len(assets)} release assets; no build or simulator was started.', flush=True)
        if not args.prepare_only:
            publish(assets)
            print(f'Published https://github.com/{REPOSITORY}/releases/tag/{TAG}', flush=True)


if __name__ == '__main__':
    main()
