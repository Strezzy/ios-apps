# Orbit 1.0

A full-screen spatial-video viewer for iPhone, in the same native Liquid Glass family as the other apps.

- Import original spatial movies from Photos or Files without transcoding.
- Tilt left/right and up/down to explore a small depth-aware change of viewpoint.
- Watch in portrait or landscape, with play/pause, scrubbing, mute, looping, fit/fill, depth strength, and recenter controls.
- Use touch dragging as an alternative to device motion.
- Keep imported movies in a local library; ordinary videos remain clearly identified as 2D.
- Ice-blue/violet design, geometric app artwork, native Liquid Glass controls, light and dark appearances.
- On-device processing without accounts, ads, analytics, media uploads, or runtime model downloads.

Requires iOS 26 or later. The included native arm64 IPA is unsigned for the existing sideloading workflow.

The tilt effect is a custom, bounded motion-parallax reconstruction from the two recorded views. It does not use Apple's private Photos spatial-scene renderer or reconstruct hidden sides of objects. Stereo artifacts can occur with occlusions, reflections, low texture, or rapid motion. Use an original spatial recording; flattened exports play in 2D. Physical iPhone playback quality, motion, thermals, and sideload-host behavior still need device testing.
