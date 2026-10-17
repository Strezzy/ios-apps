"""Only neural speech, personal voices, Apple fallback and connected controls."""
VOICE_TESTS = [
    'RiftTests/PersonalVoiceTests',
    'RiftTests/PocketSpeechIntegrationTests',
    'RiftTests/VoicePatchTests/testStartupWaitsForInstalledVoiceAndHonorsSelection',
    'RiftTests/VoicePatchTests/testCloseDuringVoiceLookupIgnoresLateResult',
    'RiftTests/VoiceReplyStreamTests/testSpeaksCompletedPhraseBeforeGenerationFinishesWithoutRepeatingIt',
    'RiftUITests/RiftUITests/testPersonalVoiceAndAppleFallbackSettingsAreReachable',
    'RiftUITests/RiftUITests/testComposerRespondsImmediatelyAfterReplyAndVoiceOpen',
]
EXPECTED_TESTS = 10

def selection_for_source(source, root):
    import json, subprocess
    from pathlib import Path
    root = Path(root)
    baseline = '8bf64ccc22bdc4aa5bd11d4303d185d76191a39c'
    def git(*args): return subprocess.check_output(['git', *args], cwd=root.parent, text=True).strip()
    # Reuse only the nine passing results on byte-identical app/dependency/UI
    # source. The sole corrected test compares directory paths, not URL spelling.
    changed = git('diff', '--name-only', baseline, source, '--', 'Rift/Rift', 'Rift/project.yml', 'Rift/RiftUITests')
    if changed: return VOICE_TESTS, None
    test = 'Rift/RiftTests/PersonalVoiceTests.swift'
    old = git('show', baseline + ':' + test)
    new = git('show', source + ':' + test)
    corrected = old.replace('library.profileURL(voice.id).deletingLastPathComponent(), root)',
                            'library.profileURL(voice.id).deletingLastPathComponent().path, root.path)')
    if new != corrected or git('diff', '--name-only', baseline, source, '--', 'Rift/RiftTests') != test:
        return VOICE_TESTS, None
    evidence = json.loads((root/'Verification/pocket-preflight/BUILD-REPORT.json').read_text())
    summary = evidence['test_summary']
    assert evidence['source'] == baseline
    assert summary['passedTests'] == 9 and summary['failedTests'] == 1 and summary['skippedTests'] == 0
    assert len(summary['testFailures']) == 1
    assert summary['testFailures'][0]['testIdentifierString'] == 'PersonalVoiceTests/testProfilesPersistAndDeleteWithoutUsingNamesAsPaths()'
    return ['RiftTests/PersonalVoiceTests/testProfilesPersistAndDeleteWithoutUsingNamesAsPaths'], {
        'source': baseline, 'run': 39076196915, 'passedTests': 9,
        'artifact_sha256': '6330c8806d3a03e4871087b9fdb8ab8f68522fc9c0c6484a08bc87583faa67fb',
        'report': 'Rift/Verification/pocket-preflight/BUILD-REPORT.json',
        'scope': 'Retains only nine passing checks; failed URL-spelling assertion corrected and rerun'
    }
