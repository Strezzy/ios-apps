# Music 0.15 (16)

- Removes the old drawn CD/cassette fallback. Static artwork comes from the same production renderer as the live cases.
- Saves rendered artwork on disk for both media styles. Cached cases are available when a cell first appears, survive app relaunches and memory eviction, and are reused throughout the library and mini-player.
- Restores original covers and album metadata before the first library display, avoiding the startup change from missing covers to populated artwork.
- Cassette cases now open forward and downward around the bottom edge, with matching hinges and animation framing.
- Playlist rows and detail covers, plus Search album and artist previews, now use the selected CD or cassette style.
- Preserves Cask, the original optical shaders, CD choreography, playback animation continuity and the faster song-to-player transition.

All **117 native simulator checks passed**: 63 playback/UI/cache checks and 54 checks after a separate process launch. Native iPhone compilation and signature verification also passed. New or changed artwork requires one initial render; subsequent displays reuse the saved image. Physical iPhone performance and LiveContainer installation remain to be tested on a device.

Refresh your existing **Strezzy's Apps** source to get Music **0.15 (16)**. Update the existing Music installation and keep its data container to retain your library and settings. The bundle identifier and source URL are unchanged.

The arm64 IPA is ad-hoc signed for your sideloading installer to re-sign. Requires iOS 16.0 or later; native Liquid Glass requires a supported newer iOS version. Source, checksums and simulator verification evidence are attached.
