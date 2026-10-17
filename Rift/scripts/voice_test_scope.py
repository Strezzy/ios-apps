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
    return VOICE_TESTS, None
