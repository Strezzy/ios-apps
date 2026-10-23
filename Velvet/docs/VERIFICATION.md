# Verification and device acceptance

The GitHub release is an **early-access unsigned build**, not a claim of production security or hardware validation. CI must compile the complete app and pass XCTest before publishing. Each release attaches the actual toolchain, source SHA, IPA hash, and test summary. The Linux workstation cannot compile Apple frameworks.

## Automated gates

- `python3 scripts/audit.py`: rejects network-client APIs, Photos-write APIs, file-writing camera/movie paths, logging and cloud entitlements in first-party app Swift. This is a regression guard, not proof about system internals or all binary dependencies.
- `bash scripts/build.sh`: checksum-verifies bundled model, resolves pinned MediaPipe, compiles iPhone arm64 Release, packages an unsigned IPA. No Apple signing credentials used.
- `bash scripts/test.sh`: runs meaningful AES-GCM, confidentiality, catalogue, key handling, video, backup and search tests on an available iOS 27 simulator. The actual test count and failures are in `TEST-RESULTS.json`.
- Synthetic video tests use the real writer/delegate and custom AVAsset loader. Real cameras, microphones, optical quality, codec limits and HDR cannot be certified by the simulator.

## Required iPhone 17 Pro checks — Needs Device Validation

Use non-sensitive disposable test media first. Record iOS version, hardware model, free storage, thermal state, battery level and the release SHA. Do not rely on this build for irreplaceable media before these checks.

1. **Authentication:** cold launch, Face ID success/failure/cancellation, device passcode fallback, remove/re-add biometric enrollment, reboot, and protected-data lock. Confirm no thumbnails or query remain visible before authentication. A missing key with existing ciphertext must fail closed, preserving data.
2. **Snapshot/capture:** open a photo, a search and playing video; rapidly go Home, switch apps, lock the phone, receive a call, and start/stop screen recording or mirroring. Confirm app-switcher images conceal content and background return requires authentication. Test screenshots to document iOS's unavoidable limitation.
3. **Photos:** each physical lens and front camera, flash modes, focus, EV, HEIF/JPEG/RAW plus processed capture. Compare dimensions, EXIF and color to actual output; do not infer 48 MP from a request. Verify originals are preserved byte-for-byte after encryption and decryption.
4. **Video:** each displayed resolution/fps/codec tuple, 1 s / 10 s / 10 min durations, silent/audio recordings, microphone denial, camera switching between recordings, portrait and both landscape orientations. Scrub backward/forward at segment boundaries, through the end, and rapidly seek. Compare duration, orientation, sound sync and frame rate with the requested mode. No external-drive output is supported.
5. **Interruptions:** background/lock during countdown, photo processing, recording, encryption, import and indexing. Force-kill before/after catalogue commits, simulate a failed write and nearly full disk. Incomplete recordings must not appear as successful captures; completed prior items must remain readable. Verify authenticated recovery of catalogue transactions.
6. **Storage audit:** inspect the developer app container after capture, playback, failed recording, import, search and backup. Vault originals, thumbnails, index, metadata and video segments must all be ciphertext; filenames are opaque identifiers. Scan app-owned files for JPEG/HEIF/MP4 headers and known plaintext markers. Check Complete protection and backup-exclusion resource flags. Keychain is ThisDeviceOnly/userPresence. Inspect OS-managed caches separately and document what the app cannot control.
7. **Offline/network:** install a build with the model bundled. Disable Wi-Fi and cellular and enable Airplane Mode. Unlock, capture, record, seek, classify, OCR, semantic-query, favorite, trash, restore and create an encrypted backup. Run a network instrument/proxy with connectivity separately: no first-party app network requests should occur. The system Photos/Files picker may retrieve cloud content only following explicit user selection.
8. **Search:** use a controlled set with window portraits, warm/red/black/night/blue scenes plus negative examples. Validate top results, real text/image model output, Vision-only fallback if unavailable, deletion from results, reindexing, model memory/thermal behavior and cancellation on lock. Video search describes the cover, not moments.
9. **Backup:** export to Files, retain the key separately, restore into a fresh disposable vault; compare item counts/content hashes, favorites/albums/metadata/search and video playback. Wrong key, altered archive, missing parts and duplicate IDs must fail safely. Archive contents stream as authenticated ciphertext; validation decrypts bounded asset parts.
10. **Delete:** move to Trash, confirm media is absent from normal/search views, restore, then permanently delete. Verify all managed blobs/records/features are removed and an already-open reader is revoked. Backups outside the app remain user-managed. Flash secure erasure is not claimed.
11. **Accessibility/performance:** VoiceOver controls and labels, largest Dynamic Type, Reduce Motion/Transparency, high contrast, one-handed use, rotation, 10k thumbnails, memory pressure and hot-device capture. Record p50/p95 indexing/search latency and peak resident memory.

## Release gates still open

Physical camera/microphone validation, long-video seek compatibility, real-world model relevance/performance, device filesystem/backup audit, device network instrumentation, and independent cryptographic review. Advanced 100/120 fps, HDR/Dolby Vision, Log, ProRes/ProRes RAW, Live Photos/depth, external recording, live pose/composition coaching and video-moment indexing are unavailable rather than represented by pretend controls.
