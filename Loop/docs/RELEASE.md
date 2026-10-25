# Loop 1.1.0 — Follow the moment

This update adds subject-follow cropping, fixes trimmed preview playback and moves the trim shortcuts into the pinned player controls. Existing projects, exports and the app's bundle identity are preserved.

- **Trim shortcuts at the top:** Start here and End here sit beneath the video, to the right of the player controls, on every editor tab. Both use the visible frame. Trim-slider adjustments pause and preview the boundary being changed.
- **Playback after cropping and trimming:** native player limits update with the selected range. Play at the final source frame restarts the clip. Forward, reverse and ping-pong previews continue across their loop boundaries instead of freezing at an old out point.
- **Subject-follow crop:** choose an aspect, select a person or object with a movable/resizable box, then tap Track subject. Analysis runs on the iPhone across the selected clip, starting from the displayed anchor frame. The crop follows the subject through the original video.
- **Follow subject size:** optional size-follow adjusts framing as a subject approaches or recedes. The crop stays within the available video and keeps a fixed aspect ratio. A slight offline smoothing pass reduces jitter; the exported animation keeps constant pixel dimensions.
- **Stacked tracking:** subject-follow cropping works with independently tracked blur, pixelation, covers, emoji and text. Each overlay retains its source-relative path and is mapped into the moving crop in both preview and export. Existing overlay tracking behavior is retained.
- **Control and review:** disable Follow subject to return to manual framing without deleting its path. Choose another subject or re-track after extending the trim. Cancelled or incomplete new analysis is not applied. Review the full loop; occlusion or a subject leaving the picture can require a clearer anchor or a shorter clip.

Continuous scrubbing, live effects, 12× view zoom, contextual overlay controls, on-canvas X/Undo, the native emoji keyboard, Photos and **Files** import, GIF/APNG output and high-resolution export remain available. Processing stays on device, with no account, ads, watermark or upload.

**Install:** `Loop.ipa` is an arm64 iPhone/iPad package for the existing signing/sideloading workflow. Requires iOS 26 or later. Update the existing `com.billy.loop` installation to keep local projects and exports; no uninstall is needed.

**Format and framing limits:** GIF stores delays in 10 ms steps and some viewers clamp short delays. APNG supports finer timing and full color. Both formats are silent. Output remains capped at a 4096-pixel longest edge and 30,000 frames. Tracking cannot reveal pixels outside the source, and zooming does not create new detail. Supported source codecs depend on the device. Cloud-only inputs need to download through their provider before offline use.

**Validation:** Native arm64 build, real AVPlayer preview regressions, on-device Vision tracking tests, moving-crop/overlay composition, decoded export checks, project compatibility and simulator interface tests. Native screenshots and the exact test report are attached. Physical-device frame rate, thermals, long high-resolution exports and sideload-host behavior were not measured in this build session.

Complete source, generated Xcode project and checksums are attached. Other apps and historical releases are preserved.
