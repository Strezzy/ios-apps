# LumaLift 1.0.0 Beta

A separate, offline video-enhancement app with native SwiftUI, Liquid Glass controls, and a pastel pink-purple identity.

## Included

Bundled Real-ESRGAN detail restoration, original-size enhancement, 2x/4x output, independent RIFE 30/60 FPS controls, adjustable strength, a two-second preview, original audio preservation, a local export library, sharing, pause/cancel and thermal safeguards. No accounts, uploads, analytics or first-launch model downloads. Originals are never overwritten.

## What was actually tested

The arm64 iPhone app compiles with Xcode. Eleven simulator tests must pass before this beta is published, including actual Core ML restoration, a complete enhanced export at the original frame rate, tile orientation/color, preserved audio timing, portrait orientation, cancellation and unavailable-GPU error handling. Each export is decoded again to verify presentation timing and frame count, rather than incorrectly treating compressed decode order as display order.

**Two tests are explicitly pending, not passed:** real RIFE GPU inference and a combined enhancement-plus-60-FPS export. The hosted simulator crashes inside Apple's MPSGraph device initialization before model inference, so simulator builds now return a clear unsupported-runtime error. The physical-device IPA retains the actual RIFE Metal implementation. It has not yet been run on a physical iPhone. This limitation is recorded in BUILD-REPORT.json and is why this is a prerelease.

## Limits

Standard-color SDR only, up to 4K output, and up to 1080p input for AI interpolation. H.264 MOV output. No HDR or 120 FPS mode. Framewise restoration can invent fine detail or introduce flicker. Physical-device speed, heat, memory behavior, LiveContainer compatibility and long-export reliability remain unverified. Start with a short preview and keep the app open. Jobs cannot resume after app termination.

The app uses private local working storage. Photos/Files may fetch cloud-hosted inputs or sync an export, depending on the destination and your system settings. Choose already-downloaded local inputs for fully offline operation. This is not an anonymizer.

## Install and evidence

Use LumaLift.ipa with your existing sideloading/signing workflow. It is an unsigned arm64 device build, not an App Store release. The app-source listing is explicitly labeled Beta. Attached: IPA, source archive including bundled models, icon, simulator launch screenshot, build/test report and SHA-256 checksums.
