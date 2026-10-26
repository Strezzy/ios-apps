# Loop 1.2.0 (build 6)

## Offline effects studio

A new Effects tab adds 109 effect choices across six categories: 30 color looks, 12 lens/texture treatments, 25 face effects, 14 whole-person styles, 18 background choices (including your own photo), and 10 animated atmosphere layers. Everything renders on the device using Core Image, Vision and procedural artwork. No cloud rendering, accounts, filter downloads or third-party model packs.

Stack one effect from each category, adjust individual intensities, save favorites, search the gallery, compare with the original, and remove effects without disturbing the rest of the edit. Gallery thumbnails are generated from a still frame of your clip; tap Refresh previews to update them. The main video preview shows the selected effects in motion.

Face effects include landmark-based warps and illustrated masks/accessories. They are 2D effects, not Snapchat's Lens library or photorealistic 3D character replacements. Body styles use person segmentation; they do not replace clothing, reconstruct hidden anatomy or generate new motion. Background and face quality depends on visible subjects, lighting, occlusion and motion blur. Missed faces are left unchanged. Complex stacks can reduce preview frame rate; export processes every selected frame at the chosen resolution. No 4K real-time benchmark is claimed.

## Video export

Export H.264 MP4 or HEVC/H.265 MP4 alongside the existing GIF and APNG options. Video supports full-color SDR output up to a 4096-pixel long edge and 60 FPS when the device encoder supports the chosen settings. Select native-crop resolution and source frame rate in Export to preserve source dimensions/rate within those limits. Defaults for existing export settings remain unchanged.

The selected crop, timing, playback direction, effects, captions and privacy overlays are rendered into the output. Forward video can retain source audio, including trim and speed edits; reverse and ping-pong video exports are silent and labeled accordingly. Videos appear in Library with native playback, sharing, thumbnails and Save to Photos. Encoding streams frames instead of retaining the entire clip. Even video dimensions may round an odd edge down by one pixel. HDR/Dolby Vision sources are converted to SDR.

## Full video on import

New projects now select the complete imported video instead of the first six seconds. Existing projects retain their saved trim ranges. Cropping, subject tracking, overlay timing controls, gestures and the rest of the editor have not been redesigned.

## Verification

Native Release compilation and package verification are required before publication. Focused source checks cover the catalog, migration and integration points. New regression test source is included; simulator tests and physical-device performance, appearance and audio-sync validation are not claimed unless explicitly recorded in the build report.
