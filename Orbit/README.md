# Orbit

**A little more depth.** A native iPhone spatial-video player with a full-screen view that responds to your phone's movement.

Open an original spatial video from Photos or Files, press play, and gently tilt your phone left, right, up, or down. Orbit uses the two recorded camera views to estimate depth and render a small change of viewpoint. Portrait and landscape layouts share the same playback controls and Liquid Glass interface.

## Using Orbit

- Import a video from **Photos** or **Files**, or open a movie with Orbit from the Files share sheet.
- Your imported videos appear in a local library. Imports preserve the original movie; Orbit does not transcode your spatial recording.
- Tap the video to show or hide its controls. Play, pause, scrub, mute, loop, and choose fit or fill.
- Adjust depth strength, switch tilt on or off, and recenter while holding your phone at a comfortable angle. Dragging provides a manual look-around alternative.
- Regular movies can play in 2D. They do not acquire real depth simply by being imported.

The native interface uses ice-blue and violet accents, coordinated geometric artwork, light and dark appearances, and iOS Liquid Glass controls. No accounts, ads, analytics, remote models, or media uploads are included. The system Photos or Files picker may download an original from iCloud when you select it.

## What the depth effect can do

Spatial video records two camera views. Orbit decodes those views with AVFoundation, computes a bounded stereo depth field on the GPU, and uses Metal to move foreground and background by different amounts. Core Motion supplies device tilt. Audio remains on the same AVPlayer clock as the video.

This is a custom motion-parallax effect for the iPhone screen. It does not use the private Photos spatial-scene renderer, provide headset stereoscopy, or reconstruct a complete scene that you can walk around. Modest tilt works best. Fast motion, reflections, transparent objects, large occlusions, and textureless areas can reduce the accuracy of stereo matching. The app limits view displacement to reduce exposed edges and reconstruction artifacts.

Keep the **original spatial movie** when sharing or exporting from Photos. A flattened export contains only one view and will play in 2D. Orienting the viewer vertically does not change how the original video was recorded; both source orientation and the iPhone's current screen orientation are handled separately.

## Build and install

Requires iOS 26 or later. The project uses SwiftUI, AVFoundation, Metal, and Core Motion with no external runtime dependencies.

On a Mac with Xcode 27.1 and XcodeGen:

```sh
cd Orbit
bash scripts/build.sh
bash scripts/validate.sh
```

The native arm64 package is written to `Build/Orbit.ipa`. The package is not distribution signed and is intended for the repository's existing sideloading workflow. Use SideStore or your usual compatible sideload host to sign/install it. Full-screen playback quality and motion behavior should be checked on a physical iPhone.

`.github/workflows/orbit.yml` builds the app, runs focused geometry and interface checks, publishes a new immutable release on `main`, and refreshes the existing app catalog. Releases include the IPA, source, checksums, and build/validation evidence. The source includes `project.yml`, which XcodeGen uses to generate the Xcode project. Only verified native captures are attached. The first release is published from an existing successful native build with the original passing functional-test evidence; its validation report identifies both source commits and the checks that were reused.

## Validation scope

The automated checks cover aspect ratio, source rotation, motion-axis mapping, invalid sensor inputs, ordinary-video decoding, app launch, import controls, and portrait/landscape layout. A checksum-pinned Apple spatial-video sample is fetched into the test bundle only, and stereo decoding is checked when the simulator supports it. Hardware-dependent skips are reported explicitly. The checks do not measure physical-device depth quality, prolonged thermal behavior, or LiveContainer/SideStore compatibility. A release report distinguishes those unperformed device checks from the native build and simulator checks that actually ran.
