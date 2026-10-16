# Strezzy’s iPhone Apps

I'm Strezzy. These are passion projects I build for myself and share here for free. This page has my app downloads, a quick explanation of what each one does, and directions for installing and updating them in LiveContainer.

## Downloads

| App | Version | Download | Requires |
| --- | --- | --- | --- |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Music.png" width="44" alt=""/> **Music** — Offline music player | 0.15 (16) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/music-0.15-build16/Music.ipa) | iOS 16.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Echo.png" width="44" alt=""/> **Echo** — Turn text into speech with your voice | 1.1 (104) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/echo-1.1-build104/Echo.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Prism.png" width="44" alt=""/> **Prism** — Generate and edit images with AI | 1.2 (3) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/prism-1.2-build3/Prism.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Facet.png" width="44" alt=""/> **Facet** — Convert photos and videos to 3D | 1.1 (301) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/facet-1.1-build301/Facet.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Veil.png" width="44" alt=""/> **Veil** — Remove metadata from photos and videos | 1.1 (201) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/veil-1.1-build201/Veil.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Lucid.png" width="44" alt=""/> **Lucid** — Offline video enhancement · Beta | 1.1 (204) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/lucid-1.1-build204/Lucid.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Rift.png" width="44" alt=""/> **Rift** — Private offline AI chat | 1.8.1 (133) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/rift-1.8.1-build133/Rift.ipa) | iOS 26.0+ |

The number in parentheses is the build number. If the version number stays the same, a higher build number means a newer update. You can read what's changed on the [releases page](https://github.com/Strezzy/ios-apps/releases).

## Yes, they're vibe-coded

**All of my apps are vibe-coded.** I use AI tools to help write the code, while I direct development, give detailed instructions, beta test, and work through bugs and revisions. I spend **$200+ a month** on those tools and **5–8+ hours a day** on development and testing.

These are personal passion projects, shared for free. Constructive feedback is welcome. If AI-assisted development is a dealbreaker, you're free to pass. If you'd prefer a different process, you're also welcome to contribute the budget and put in the hours. The tools help with the code; the bill and the time are still mine.

## What each app does

### Music

Play music stored on your iPhone offline. Browse songs, albums, and playlists; explore interactive clear CD cases with spinning artwork; and customize themes, album art, lyrics, and scrolling animations.

### Echo

Turn typed text into speech using a short voice recording. Record or import a sample, save voices, and export clips as WAV files. Download a model before using it offline. Voice generation in this release still needs testing on a real iPhone.

### Prism

Create images from a text description, or add reference pictures and describe the edits you want. Download a model before using it offline, then save and export images from the gallery. Image generation in this release still needs testing on a real iPhone.

### Facet

Convert photos and videos into 3D on your iPhone. Export Apple Spatial, side-by-side, over-under and other stereo formats at the original pixel dimensions and video frame timing. Includes two offline depth models. HDR video is converted to SDR.

### Veil

Clean photos and videos on your iPhone without accounts, uploads or analytics. Import individual files, batches or folders; create separate copies; compare metadata reports and SHA-256 fingerprints; save or share the results. Supports JPEG, PNG and HEIC photos, and ordinary SDR MOV/MP4 videos up to 4K/60 fps. Photos export as SDR. Includes a small-batch photo Share extension where supported by your installation method. Originals are unchanged. Metadata removal does not hide visible content or prevent image matching. Physical iPhone testing is still required for this first release.

### Lucid

FIRST BETA. Restore video detail at its original resolution or upscale 2x/4x with bundled Real-ESRGAN. Native pastel pink-purple SwiftUI and Liquid Glass controls, adjustable strength, a 2-second preview, original audio preservation, pause/cancel, thermal safeguards, and a private local export library. RIFE 30/60 FPS motion interpolation is implemented and bundled in the iPhone build, but its two GPU tests require physical-device testing and are explicitly not reported as passed. Simulator tests cover restoration, exports, audio timing, orientation, cancellation and error handling. No accounts, uploads, analytics or model downloads. Standard-color SDR input only; up to 4K output and 1080p input for motion. H.264 MOV exports; originals stay untouched. Physical iPhone performance, heat, LiveContainer compatibility and long-export reliability remain unverified.

### Rift

Private offline iPhone chat with downloaded uncensored community models or an imported GGUF. Version 1.8 adds local image and file attachments from the composer’s plus button. Qwen3.5 4B image understanding uses the matching publisher vision encoder, an optional verified 676 MB download. Text and text-based PDFs are read locally. The same uncensored weights are retained, with no added content filter or cloud moderation. Includes the left conversation drawer, quick model menu, morphing composer and living crimson background. No accounts, analytics, uploaded recordings or cloud inference. Larger models and images depend on device and host memory. Version 1.8.1 fixes composer responsiveness and keeps the conversation drawer transition full height.

## Add my apps to LiveContainer

You only need to add this source once.

1. Open **LiveContainer → Sources → +**.
2. Paste the address below and add the source.
3. Open **Strezzy’s Apps** and tap **Install** beside the app you want.

```text
https://raw.githubusercontent.com/Strezzy/ios-apps/main/apps.json
```

You can also download an IPA from the table above and import it through **Apps → + → Install IPA File** in LiveContainer.

## Native suite rename

**The first native Facet, Veil, Lucid and Echo releases use new bundle IDs.** Keep the old installation and export important files before removing it. Data does not automatically transfer to the new app identity. See [the one-time installation note](docs/NATIVE-SUITE-UPGRADE.md). Prism and Music are unchanged.

## Update an app and keep your data

**Leave the old version installed.** Replacing that existing copy lets LiveContainer reuse its data container, where the app keeps your files and settings. Keep a separate copy of any files you can't replace before updating.

1. Open **Sources** in LiveContainer and tap the circular refresh button (**Refresh All**).
2. Open **Strezzy’s Apps** and tap **Install** beside the app you want to update. The button can still say **Install** for an update.
3. When LiveContainer finds the existing app, select that existing entry in the **Installation** prompt. It may appear as a name ending in `.app`. **Install as new** creates a separate copy.
4. Wait for the installation to finish, then open the app using the same data container as before.

**Updating with a downloaded IPA:** Download the newer IPA, open **Apps → + → Install IPA File**, and select the file. Choose the existing app entry in the installation prompt.

### If the app opens with an empty library

Check which data container is selected. If you use more than one, long-press the app in LiveContainer and choose your previous one under **Containers**. A different container can make the app look empty even when your files are still in the original one. Avoid deleting the app or clearing its data while you're checking.

These steps cover updates to an app already inside LiveContainer. Moving an app from a separate installation into LiveContainer needs its own data transfer.

## Found a problem?

[Open an issue](https://github.com/Strezzy/ios-apps/issues) with the app name, version and build number, your iPhone model, and your iOS version. Tell me what you were doing and what happened. Screenshots help when they show the problem; please keep personal files and voice recordings out of public reports.

---

[Publishing and catalog maintenance](docs/PUBLISHING.md)
