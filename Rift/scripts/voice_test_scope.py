"""Only voice inventory, prompt migration and animated composer responsiveness."""
VOICE_TESTS = [
    'RiftTests/VoicePatchTests',
    'RiftUITests/RiftUITests/testComposerRespondsImmediatelyAfterReplyAndVoiceOpen',
]
EXPECTED_TESTS = 4

def selection_for_source(source, root):
    return VOICE_TESTS, None
