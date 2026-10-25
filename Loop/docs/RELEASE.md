# Loop 1.1.2 — Overlay timing and stronger subject tracking

## Selected-overlay timing

- On **Overlays**, **Start here** sets when the selected layer appears and **End here** sets its last visible moment, using the video frame currently displayed.
- The selected layer's time range appears beneath the playhead and in its Timing controls. Select a layer to enable the buttons. Other tabs keep the existing clip-trim behavior.
- Changing visibility preserves the layer's position keyframes. If the new interval extends beyond an automatic track, the layer is marked for review or re-tracking.

## Tracking improvements

- The tracker checks the selected region's appearance and motion before accepting a new Vision box, reducing the risk of switching to someone behind or beside the subject.
- Analysis samples the source cadence up to 60 FPS, compared with the previous 30 FPS cap.
- Brief obstructions trigger a bounded recovery search. Uncertain observations do not update the trusted appearance reference, and ambiguous or unresolved tracking leaves the previous saved path intact.
- Crop following and tracked blur, pixelation, emoji, covers and text share the improved tracker while keeping independent source-coordinate paths.
- The 4K memory protections and immediate crop-result saving from 1.1.1 remain in place. Analysis remains bounded to 960 pixels on the longest edge; source quality and high-resolution export options remain available. Processing is entirely offline.

**For existing projects:** Re-run **Track subject** or an overlay's **Track** to generate a path with the improved tracker. Saved paths are preserved until replaced. Similar-looking subjects, long obstructions or leaving the frame can still require a clearer selection or manual correction; this update does not promise perfect identity recognition.

## Validation and installation

At the app owner's request, this release uses **native arm64 Release compilation and package/checksum verification only**. The simulator unit/interface suite and physical-device testing were not run for this update. `VALIDATION-REPORT.json` records the scope; no previous release's test counts or screenshots are presented as current results. The owner will test the new timing behavior and real-world subject crossings on their iPhone.

Update the existing `com.billy.loop` installation through the usual signing/sideloading workflow. The IPA requires iOS 26 or later. Complete source, the generated Xcode project and checksums are attached. Existing projects and prior releases are retained.
