# Collectr

Native SwiftUI iPhone app for photo collector cards. iOS 26+, native Liquid Glass, no web viewer, accounts or remote inference.

Create → import from Photos → edit depth/light/color/frame → choose rarity and fixed edition size → save draft → confirm original deletion in Photos → seal into Collections. Inspect cards by tilt or drag, remove the sleeve, or flip to the edition certificate. Trade moves one copy to a nearby phone after acceptance; for a swap, offer one card each.

`1 OF 300` denotes serial 1 in a fixed 300-copy edition, rather than a limit on successive owners. All numbered copies are created together and grouped in Collections. The copy picker selects a specific serial. Ownership stamps are appended with each transfer.

## Build

On macOS with Xcode 26+ and XcodeGen:

```sh
python3 scripts/build_ios.py
```

The script downloads the same checksum-pinned DA3 Base 504 FP16 Core ML package used by Depth Check, verifies all bytes, compiles it with the active Xcode, generates the icon/project, builds an unsigned arm64 IPA, runs simulator tests including real depth inference, and saves a launch screenshot and build report. No model weights are checked into Git. GitHub Actions publishes only after these checks pass, then registers the IPA in the existing LiveContainer source.

## Data and recovery

Cards, draft and transfer journal live in Documents/Collectr. Media is written before an atomic collection index transaction. Do not delete the app's data container: it contains the owned copies. A failed database read blocks mutations and preserves files.

The sender retains and locks a copy while an offer is pending. The recipient durably stages assets before accepting. Upon acceptance, the sender durably removes ownership and records a commit outbox entry before sending the commit. The receiver adds ownership once, then acknowledges. Reconnecting the same installations retries unfinished handoffs. After acceptance, cancellation is disabled; reconnect both devices to finish. This prioritizes avoiding duplicate local ownership over availability during a disconnect. It is not an atomic two-card swap or a globally authoritative scarcity protocol.

Photo deletion requires PhotoKit read/write access and iOS confirmation. Limited access may require granting access to the selected original. Photos retains deleted images in Recently Deleted; the app cannot permanently purge them. Saving a draft before deletion avoids losing the imported card during interruption. If interrupted after deletion but before confirmation was persisted, full Photos access lets the retry verify absence. Originals elsewhere, screenshots, backups and re-imports cannot be prevented.

## References

Visual reference: Music's adaptation of Ann Nguyen's CD Case at upstream `efba8dfb956cca848422f18e8ede1bdf96033fca`. Collectr uses original SwiftUI sleeve rendering and a native Metal depth surface, without shipping the CD app's JavaScript/Three.js. Palette extraction follows Music's saturation-weighted bins and three-cluster refinement. DepthEstimator and DepthNormalization are adapted from this repository's Depth Check, retaining its aspect-fit input, padding crop, DA3 depth inversion and percentile normalization.

DA3 model: `mlboydaisuke/Depth-Anything-3-Base-CoreML` revision `8e2e01d73a6b78f89beaac573ce3a009cf1fbb50`, upstream Depth Anything 3 Base Apache-2.0. Notices are bundled in Resources/Licenses. SHA-256 values and exact sizes are recorded in scripts/prepare_models.py.

See RELEASE-NOTES.md for the current validation limits.
