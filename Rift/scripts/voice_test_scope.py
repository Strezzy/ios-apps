"""Only changed chat/voice presentation and directly connected behavior; no models."""
VOICE_TESTS = ['RiftTests/VoiceReplyStreamTests', 'RiftTests/VoiceOrbTests/testOpeningAndClosingCuesRingOutWithHeadroomAndFadeToSilence', 'RiftTests/VoiceOrbTests/testClosingDuringCuePreventsSpeechSetupAndMicrophoneStart', 'RiftTests/VoiceAndEffectsTests/testCipherDefaultPreservesAllSavedChoices', 'RiftTests/PresentationTests/testKeyboardResizeDoesNotTurnOffFollowing', 'RiftTests/PresentationTests/testOnlyUserScrollingCanLeaveLatestReply', 'RiftTests/PresentationTests/testWrappingIncomingTextRequestsBottomAlignment', 'RiftTests/PresentationTests/testProgrammaticScrollDoesNotCreateAnEndlessRequestLoop', 'RiftTests/PresentationTests/testShortStreamingConversationNeverRequestsBottomAlignment', 'RiftTests/PresentationTests/testLivingBackgroundChangesPixelsWithinTheSamePalette', 'RiftUITests/RiftUITests/testEmptyChatShowsOnlyCenteredMarkAndNewFooter', 'RiftUITests/RiftUITests/testShortBubbleTypingDotsAndStreamingStayAnchored', 'RiftUITests/RiftUITests/testLatestReplyMovesAboveKeyboardWhileStreamingAndRotating', 'RiftUITests/RiftUITests/testVoiceOrbStaysInsideChatAndCanCloseAndReopen']
EXPECTED_TESTS = 20

# Keep the passing checks when only this DEBUG fixture and its one UI check
# change. Any production, unit-test, project or other UI-test change runs all 20.
def selection_for_source(source, root):
    import json, subprocess
    path = root / 'Verification/1.6-build130/PREVIOUS-CHAT-CHECK.json'
    if not path.exists(): return VOICE_TESTS, None
    prior = json.loads(path.read_text())
    summary = prior['test_summary']
    failed = 'RiftUITests/testShortBubbleTypingDotsAndStreamingStayAnchored()'
    assert prior['test_selection'] == VOICE_TESTS
    assert summary['passedTests'] == 19 and summary['failedTests'] == 1 and summary['skippedTests'] == 0
    assert [failure['testIdentifierString'] for failure in summary['testFailures']] == [failed]
    unchanged = ['Rift/Rift', 'Rift/RiftTests', 'Rift/project.yml', ':(exclude)Rift/Rift/DebugChatFixture.swift']
    if subprocess.run(['git', 'diff', '--quiet', prior['source'], source, '--', *unchanged]).returncode:
        return VOICE_TESTS, None
    for revision in [prior['source'], source]:
        fixture = subprocess.check_output(['git', 'show', revision+':Rift/Rift/DebugChatFixture.swift'], text=True).strip()
        assert fixture.startswith('#if DEBUG\n') and fixture.endswith('#endif')
    def other_ui_tests(revision):
        text = subprocess.check_output(['git', 'show', revision+':Rift/RiftUITests/RiftUITests.swift'], text=True)
        start = text.index('    func testShortBubbleTypingDotsAndStreamingStayAnchored()')
        end = text.index('    func testSettingsDoesNotNeedAnAccount()', start)
        return text[:start] + text[end:]
    if other_ui_tests(prior['source']) != other_ui_tests(source): return VOICE_TESTS, None
    return ['RiftUITests/RiftUITests/testShortBubbleTypingDotsAndStreamingStayAnchored'], prior
