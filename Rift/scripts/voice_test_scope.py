"""Navigation/composer update only; no inference or model download tests."""
VOICE_TESTS = [
    'RiftTests/NavigationTests',
    'RiftTests/PresentationTests/testLivingBackgroundChangesPixelsWithinTheSamePalette',
    'RiftUITests/RiftUITests/testDrawerRevealSelectionAndSettings',
    'RiftUITests/RiftUITests/testDownloadedPickerAndMorphingComposer',
    'RiftUITests/RiftUITests/testLatestReplyMovesAboveKeyboardWhileStreamingAndRotating',
    'RiftUITests/RiftUITests/testVoiceOrbStaysInsideChatAndCanCloseAndReopen',
]
EXPECTED_TESTS = 7

def selection_for_source(source, root):
    return VOICE_TESTS, None
