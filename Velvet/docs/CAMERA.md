# Camera and encrypted movie pipeline

## Implemented path

`CameraController` owns UI state on the main actor. `CaptureEngine` confines capture session configuration, camera settings, sample delivery, and recording state to a serial user-initiated queue. Camera permission is requested when opening the camera. Microphone permission is requested only when beginning an audio-enabled video. Denied microphone access permits a silent movie and updates the microphone control.

Photos use `AVCapturePhotoOutput.fileDataRepresentation()` and preserve the returned HEIF, JPEG or DNG bytes unchanged. RAW mode requests RAW plus a processed JPEG and saves the two originals as separate vault entries. ProRAW is enabled only when the active output reports support; otherwise a supported Bayer RAW format is used. No Photos save or file-backed capture API is used. The maximum photo dimensions come from the active format and are requested on both the output and settings. This is an upper bound, not a guarantee of 24/48 MP; actual dimensions are recorded with each item. Flash, physical lens selection, tap focus/exposure, exposure bias, zoom, custom exposure and white balance use public capability checks. The UI provides a timer, grid, manual photo ISO/shutter and white-balance channel gains. ISO and shutter slider limits come from the active format; color gain limits come from the device. Automatic reset restores focus, exposure and white balance. Beginning video restores automatic exposure so a long manual photo shutter does not contradict the requested frame rate.

Video uses `AVCaptureVideoDataOutput` and optional `AVCaptureAudioDataOutput`. The writer is initialized with a content type, **without a file URL**. Apple HLS fragmented MPEG-4 output uses a two-second preferred segment interval and H.264 or HEVC SDR encoding. The first video timestamp starts the writer session and its segment interval. Audio samples before this point are dropped. Real-time input backpressure drops samples instead of accumulating a queue. A writer callback synchronously encrypts each initialization/media segment before its only app-owned durable write. Each segment is capped at 32 MiB. Save errors stop capture and cancel the incomplete asset. Finishing succeeds only after the writer has completed and the vault has committed an authenticated segment manifest. The small video cover is generated in memory and encrypted separately.

Available video choices are the intersection of exact device format dimensions, supported frame-rate ranges and writer output settings. The current selection includes 720p/1080p/4K, 24/25/30/60 fps, H.264 and HEVC where advertised. Preview-sized buffers are disabled during recording, exact selected dimensions are requested, and each video buffer is checked against the advertised dimensions before encoding. In-flight frames captured before the recording boundary are discarded. These checks are compatibility checks, not proof that every combination will run reliably on every device. The start path can fail safely and recommends 1080p30. Microphone encoding is currently mono AAC at 48 kHz / 128 kbps. Video orientation is fixed when recording starts through the writer input transform; photo orientation is stored using the output connection. Preview rotation follows the current scene orientation. Standard stabilization is requested only if supported.

## Playback and lifecycle

`SecureVideoPlayback` retains the player, custom-scheme asset, and resource-loader delegate. The resource loader supplies the MPEG-4 UTI, exact authenticated length and byte-range support. Requests honor `currentOffset`, finite requested ranges, and requests-to-end without overflowing integer arithmetic. It returns at most 256 KiB per queue turn, allowing cancellation between chunks. The vault reader verifies segment hash, AES-GCM context, index and plaintext length before returning a range, caching at most one decrypted segment. It never creates a decrypted movie file. AVPlayer can seek by requesting different byte ranges. AirPlay/external playback is disabled.

On lock, the vault synchronously revokes all readers and writers. The app stops capture, clears sensitive UI, and tears down the player. Interrupted or backgrounded recordings are discarded. Completed encrypted assets remain intact. Camera runtime errors and interruptions abort active capture; normal interruption end can restart the preview if it is still desired. Frameworks may keep private buffers; Swift/AVFoundation memory cannot be guaranteed zeroized. The no-plaintext-disk claim covers app-owned writes, not undocumented OS internals.

## Deliberately unavailable

100/120 fps, Dolby Vision/HDR, Log/Log 2, ProRes/ProRes RAW, Live Photos, spatial audio, stereo microphone selection, external-drive recording, depth/portrait auxiliary data, and automatic framing/pose guidance are not advertised as working features. They need format-specific implementation and device validation without violating the encrypted path. No paid Apple Camera-only feature or future SDK capability is assumed.

## Verification

`VideoPipelineTests` generates pixel buffers in memory, encodes actual H.264 fragments, authenticates the encrypted manifest, checks that only `.vlt` files exist, loads the encrypted resource through AVFoundation, checks its video track and duration, and verifies reader revocation. A second test rejects empty recordings. Vault tests separately cover altered/swapped segments, range boundaries and session lock.

Physical-device release gates remain mandatory:

1. Capture and view HEIF, JPEG and each available RAW type, verify metadata, actual dimensions and unchanged encoded originals.
2. Record at least 30 seconds in every offered lens/resolution/fps/codec combination; play audio, inspect rotation, and seek near the beginning/middle/end. Repeat portrait and both landscape orientations; front-camera output is not promised to match mirrored preview.
3. Inspect app container during capture, playback and seeking for plaintext media; inspect file protection and backup exclusion.
4. Lock, background, interrupt with calls, revoke microphone/camera access, and terminate during capture. Confirm only incomplete ciphertext is removed and no item is committed without a validated manifest.
5. Exercise low storage, encoder failure, segment corruption, long recording memory, thermal pressure and repeated record/stop/lens-switch cycles. Confirm every failure preserves prior assets.
6. Confirm capture/search/playback in airplane mode after initial installation. System photo-picker iCloud behavior is separate from capture.

## Apple references

- [Author fragmented MPEG-4 content with AVAssetWriter, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10011/) — data-only initializer, profiles and segment delegate.
- [Maximum photo dimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions) — supported dimensions and upper-bound semantics.
- [RAW and Apple ProRAW capture](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats) — runtime support and RAW format selection.
- [Video rotation angle](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle) — photo metadata, pixel rotation and writer transforms.
- [Resource loading current offset](https://developer.apple.com/documentation/avfoundation/avassetresourceloadingdatarequest/currentoffset) — incremental responses.
- [Writer output settings validation](https://developer.apple.com/documentation/avfoundation/avassetwriter/canapply%28outputsettings%3Aformediatype%3A%29) — container/encoding compatibility checks.
