"""Only attachments and directly connected composer behavior; no model sweep."""
VOICE_TESTS = [
    'RiftTests/AttachmentTests',
    'RiftUITests/RiftUITests/testAttachmentPreviewRemovalAndFilePicker',
    'RiftUITests/RiftUITests/testDownloadedPickerAndMorphingComposer',
    'RiftUITests/RiftUITests/testDrawerRevealSelectionAndSettings',
    'RiftUITests/RiftUITests/testVoiceOrbStaysInsideChatAndCanCloseAndReopen',
    'RiftUITests/RiftUITests/testLatestReplyMovesAboveKeyboardWhileStreamingAndRotating',
]
EXPECTED_TESTS = 10

def selection_for_source(source, root):
    return VOICE_TESTS, None
