# Music 0.14 (15)

- Choose **Live CD** or **Live Cassette** in Settings. Cassette artwork includes a hinged clear case and two spinning reels, using the same optical rendering pipeline.
- Songs, Albums and the mini-player use cached stills from the live renderer for a closer visual match. Library cells do not run individual WebGL animations.
- Selecting a song lifts its artwork into Now Playing in **0.5 seconds**, down from 1.05 seconds. The opening flip runs **2.4× faster** for this entrance, and the old artwork fades as the live case rises.
- Playback opens and spins the media; pause closes it while retaining gyroscopic response. Rotation continues across Next and Previous.
- Album detail retains live artwork and manual opening. Cask, original CD geometry, optical shaders and the native mini-player zoom are preserved.

All **42 native simulator checks passed**, including media switching, cached thumbnails, faster entrance timing, source-art fading, playback continuity and renderer reuse/recovery. The release rebuild verifies the device IPA signature. Physical iPhone performance and LiveContainer installation still need device testing. First-time artwork may briefly use the lightweight fallback until its initial render is ready.

Refresh your existing **Strezzy's Apps** source to get Music **0.14 (15)**. Replace the existing Music installation and keep its data container to retain your library and settings. The bundle identifier and source URL are unchanged.

The arm64 IPA is ad-hoc signed for your sideloading installer to re-sign. Requires iOS 16.0 or later; native Liquid Glass requires a supported newer iOS version. Source, checksums and simulator verification evidence are attached.
