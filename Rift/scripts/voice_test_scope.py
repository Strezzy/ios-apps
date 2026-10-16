"""Only the composer and full-height drawer patch; no model downloads or inference."""
VOICE_TESTS = [
    'RiftUITests/RiftUITests/testComposerRespondsImmediatelyAfterReplyAndVoiceOpen',
    'RiftUITests/RiftUITests/testDrawerRevealSelectionAndSettings',
    'RiftUITests/RiftUITests/testLatestReplyMovesAboveKeyboardWhileStreamingAndRotating',
]
EXPECTED_TESTS = 3

def selection_for_source(source, root):
    return VOICE_TESTS, None
