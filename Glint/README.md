# Glint

A source-first iPhone media downloader with a warm native Liquid Glass interface. Built for Strezzy's Apps.

## Install

The **Build Glint** GitHub Actions workflow compiles the native application and publishes a preview release only after compilation and automated tests succeed. Each successful release includes:

- **Glint.ipa**: standard unsigned app with its Share Extension. Sign/install with your existing sideloading tool.
- **Glint-LiveContainer.ipa**: the same app without the Share Extension, which LiveContainer cannot host. Paste links in Glint instead.
- **Glint-Source.zip**, dependency provenance, test reports and SHA-256 checksums.

The repository's existing `apps.json` is updated after a successful release, using the LiveContainer IPA. Glint is registered with the shared catalog generator so later app releases retain its listing. No new source URL is necessary. A workflow/source upload is not proof that an IPA has finished building: check the workflow and its release assets.

This is a **preview**, not a device-certified release. Native compilation and automated tests do not verify real Instagram authentication, a real HDR Reel, Photos import, LiveContainer compatibility, background continuation or on-device thermal behavior. Those require physical iPhone testing. Background tasks are subject to iOS scheduling and sideloading entitlements; they are not guaranteed to continue indefinitely or after force-quitting.

## Interface

Three primary tabs: **Download**, **Library**, **Settings**. The main screen offers paste, best-stream download and a separate quality inspector. Queues, history, image/audio modes, subtitles, account cookies and advanced engine settings remain available without taking over the home screen. The diagnostic console is hidden until enabled in Settings.

Liquid Glass uses the native iOS 26 API on supported systems, with material and reduced-transparency fallbacks. The interface supports light/dark appearance and respects Reduce Motion for its added transitions. The icon and background are rendered locally; no remote design assets are needed.

## Quality and HDR

- **Download best quality** chooses the largest available resolution, then HDR, frame rate and bitrate. A larger SDR stream wins over a smaller HDR stream; HDR wins at equal resolution. SDR-only and unknown-range videos remain downloadable. Connect Instagram and use the quality inspector to see additional streams the service exposes.
- The main video action ignores previously saved codec, resizing, custom argument and conversion preferences. Exact manual format selections remain explicit alternatives. Automatic video queues use the same maximum-resolution policy.
- Source downloading copies the delivered encoded streams without re-encoding. iOS checks whether the result can play and import into Photos. Compatible files remain unchanged.
- The quality picker shows **reported stream metadata**. It does not claim that a file has already been downloaded or verified.
- Library's **Save** action offers Photos and Files export plus native FFprobe inspection. HDR verification requires appropriate transfer, BT.2020 primaries and at least 10-bit evidence. Bit depth alone is never labeled HDR.
- Incompatible files are prepared automatically. Glint first preserves an independent original in Files → Glint → Originals, then tries MP4 with the video stream copied without re-encoding. If necessary it creates HEVC/AAC with a generous source- and pixel-rate-based bitrate, without resizing, capping frame rate or tone-mapping HDR. Conversion can introduce loss; the untouched original remains available.
- Prepared copies must retain resolution, orientation, duration/frame timing, audio and verified HLG/PQ HDR. iOS also checks playback and Photos compatibility. A failed copy is discarded while the original download remains successful and available. Device limits, heat or insufficient storage can prevent preparation; the app explains this and allows retry from Library.
- Dolby Vision metadata detection is distinct from HLG/PQ verification. **Converting a copy does not preserve Dolby Vision metadata.** Playback support depends on codec, container, player and device.
- Instagram does not provide arbitrary access to the creator's camera-original upload. Here, “source” means the encoded streams the service actually makes available. It cannot invent 4K, HDR or detail missing from those streams.

Instagram login is optional for accessible public downloads. Connect through its official website when additional streams or HDR extraction need an authenticated session. Availability is not guaranteed for every account, post or region. Missing HDR never blocks an otherwise available download. Requests are paced and automated retry is disabled by default. The HDR extractor stops on access restrictions. Using an automated client can still trigger verification or account limitations; stop and resolve those in Instagram rather than repeatedly retrying.

## Privacy

Downloads and processing happen on the iPhone; no Glint download server or analytics service is added. Network access is still necessary for the requested media service, its CDN and login pages. Optional advanced package updates contact package repositories. Pure-Python packages and the pinned HDR plugin are bundled for first use.

The sign-in browser uses an ephemeral website data store. Only Instagram-domain cookies are imported by the focused login flow. Session files live in an app-private Application Support directory, outside Files-visible Documents, protected until first device unlock and excluded from device backups. This uses iOS file protection, not a separate custom encryption scheme. Remove imported sessions through Settings > Download preferences > Cookies. Do not share session exports or logs containing private URLs.

Only download content you own or have permission to save. Glint does not bypass DRM or grant access to private content your account cannot access.

## Build

Requires Apple's Xcode toolchain on macOS, which the workflow supplies through GitHub's hosted macOS runner. No local Mac or paid developer account is needed for the unsigned CI artifact; signing and installation are separate.

```sh
# On a macOS machine with Xcode, gh, git, Python 3, and GitHub authentication:
bash Glint/build.sh
```

`assemble.py` applies fail-fast changes to pinned upstream source rather than tracking a floating branch. The build bundles Python, the native FFmpeg and curl bridges, and pure-Python packages. Dependencies and source archives are attached to the corresponding-source package. Release assets are versioned and are never overwritten in place.

## Credits and license

Glint's additions are **GPL-3.0-or-later** and form a derivative of **Palladium**, copyright its original contributors, licensed GPLv3. Existing copyright notices and the full upstream license are retained in the assembled source and app bundle.

- Palladium: https://github.com/tfourj/Palladium at `9793491d168b63a36c50bee425140f2459d08c5a`.
- Instagram HDR plugin: https://github.com/viniciusron7/yt-dlp-instagram-hdr at `812fbd7ad2b33e1f4b03f49b386e065f199054fd`, MIT.
- yt-dlp, gallery-dl, Python/Python-Apple-support, PythonKit, FFmpeg/SwiftFFmpeg-iOS, SwiftCurlCffi-iOS/curl-cffi, QuickJS-NG, Mutagen, and the yt-dlp WebKit/EJS integrations retain their respective licenses and acknowledgments.

The source release contains the modified app, overlays/build recipe, bundled Python source, pinned plugin source, native wrapper/runtime source archives and dependency release references. Refer to those upstream build recipes and their pinned source references for transitive native components. Glint is not affiliated with Instagram or Meta.
