# Loop 1.0 — Moments, on repeat

Create GIFs and full-color APNG animations locally on iPhone and iPad. Native SwiftUI and Liquid Glass, with a teal-and-lime identity alongside the other Strezzy apps.

Import from Photos or Files, trim, adjust portrait/landscape/square crops, choose resolution and frame rate, and export. Includes reverse and ping-pong playback, speed, loop count, adaptive GIF palettes and dithering, local projects and an export library.

Add circular or rectangular blur, pixelation, solid covers, emoji and text. Overlays can be timed, tracked on device with Vision and adjusted with manual keyframes. Review tracked content before sharing; tracking is not infallible.

**Format limits:** GIF delays use 10 ms steps. The 60 FPS option samples 60 frames per second and approximates their timing; some viewers play fast GIFs more slowly. APNG offers finer timing and full color, subject to the receiving app's support. Both formats are silent. Native/custom resolution is capped at a 4096-pixel longest edge, with a 30,000-frame export guard. Supported input depends on the iPhone's video decoders. Cloud-only source items must first be downloaded through their provider.

**Install:** `Loop.ipa` is an arm64 iPhone package for the existing sideloading/signing workflow. Requires iOS 26 or later. No account, subscription, ads, watermark, analytics, model downloads or app-initiated network requests.

**Validation:** Native arm64 compilation and automated simulator tests are attached as reports. Physical iPhone thermals, long high-resolution exports and SideStore/LiveContainer behavior have not been tested on a physical device in this build session.

The complete source archive and generated Xcode project are attached. Existing apps and historical releases are preserved.
