"""Only the glass-orb update and its connected voice lifecycle."""
VOICE_TESTS = ['RiftTests/VoiceOrbTests', 'RiftTests/VoiceAndEffectsTests/testClosingBeforeAutomaticStartupCannotRecord', 'RiftTests/VoiceAndEffectsTests/testPausingDuringSetupStillFinishesAssetCheckWithoutStartingMicrophone', 'RiftTests/VoiceAndEffectsTests/testDismissalDuringSetupCannotRestartSession', 'RiftTests/VoiceAndEffectsTests/testOpeningAutomaticallyAttemptsTurnOnceAssetsAreReady', 'RiftUITests/RiftUITests/testVoiceOrbStaysInsideChatAndCanCloseAndReopen', 'RiftUITests/RiftUITests/testVoicePreferencesLiveInSettingsAndPersist']
EXPECTED_TESTS = 13

# Reuse only evidence for byte-identical app/unit code and the unchanged orb UI check.
# A subsequent app change automatically runs the full voice scope again.
def selection_for_source(source, root):
    import json, subprocess
    prior_path = root / 'Verification/1.5-build129/PREVIOUS-VOICE-CHECK.json'
    if not prior_path.exists(): return VOICE_TESTS, None
    prior = json.loads(prior_path.read_text())
    summary = prior['test_summary']
    failed = 'RiftUITests/testVoicePreferencesLiveInSettingsAndPersist()'
    assert prior['test_selection'] == VOICE_TESTS
    assert summary['passedTests'] == 12 and summary['failedTests'] == 1 and summary['skippedTests'] == 0
    assert [failure['testIdentifierString'] for failure in summary['testFailures']] == [failed]
    unchanged = ['Rift/Rift', 'Rift/RiftTests', 'Rift/project.yml']
    if subprocess.run(['git', 'diff', '--quiet', prior['source'], source, '--', *unchanged]).returncode:
        return VOICE_TESTS, None
    def orb_test(revision):
        text = subprocess.check_output(['git', 'show', revision+':Rift/RiftUITests/RiftUITests.swift'], text=True)
        return text.split('    func testVoiceOrbStaysInsideChatAndCanCloseAndReopen()')[1].split('    func testVoicePreferencesLiveInSettingsAndPersist()')[0]
    if orb_test(prior['source']) != orb_test(source): return VOICE_TESTS, None
    return [VOICE_TESTS[-1]], prior
