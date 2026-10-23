Velvet is a native, offline iPhone camera and encrypted media vault with bundled EmbeddingGemma 2 Text-Vision 440M and native Vision analysis.

This is an early-access build. GitHub Actions compiles the complete arm64 app and passes its simulator security/search/video tests before publishing. The attached build report identifies the exact source, SDK, Xcode and IPA hash.

Download `Velvet-unsigned.ipa` and sign/install it with your own trusted sideloading workflow. It is unsigned; opening the file alone does not install it. Requires iOS 27.0 or newer. No signing credentials are collected. The local AI model is included; no runtime download is needed.

Implemented: real AVCapture photo/video, AES-GCM item encryption, device-owner authentication, encrypted thumbnails/catalogue/search, authenticated segmented playback, albums/favorites/trash/duplicate detection, still-photo import, encrypted backup/restore, native Liquid Glass controls and a suite-matched icon.

Needs Device Validation: actual camera quality/modes, long recording/seek/orientation/audio, model relevance/memory/thermal behavior, lifecycle snapshots, device filesystem and network audits. Use disposable media until the device checklist passes. See `docs/VERIFICATION.md`, `docs/THREAT_MODEL.md`, `docs/CAMERA.md`, and `docs/AI.md`.

Unvalidated HDR, Log, ProRes and 100/120 fps controls are not enabled. Video search covers the preview frame, not individual moments. Plaintext export, live composition coaching, Live Photos/depth are not included.
