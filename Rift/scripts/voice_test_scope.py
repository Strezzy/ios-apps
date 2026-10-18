"""Only the history particle effect and its connected scrolling layout."""
VOICE_TESTS = [
    'RiftTests/HistoryDissolveTests',
    'RiftUITests/RiftUITests/testHistoryParticlesKeepMovingWhileBrowsing',
]
EXPECTED_TESTS = 2

def selection_for_source(source, root):
    return VOICE_TESTS, None
