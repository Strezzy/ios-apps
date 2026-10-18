"""Only the history particle effect and its connected scrolling/streaming layout."""
VOICE_TESTS = [
    'RiftTests/HistoryDissolveTests',
    'RiftUITests/RiftUITests/testHistoryDissolveReassemblesAndPreservesMessageLayout',
    'RiftUITests/RiftUITests/testShortBubbleTypingDotsAndStreamingStayAnchored',
]
EXPECTED_TESTS = 3

def selection_for_source(source, root):
    return VOICE_TESTS, None
