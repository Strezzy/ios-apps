Collectr turns a photo into a gently rounded, numbered collector card.

- Three native Liquid Glass tabs: Create, Collections and Trade.
- Offline Depth Anything 3 Base FP16 from the same pinned Core ML conversion used in Depth Check. Included in the IPA; no model setup or photo upload.
- Adjustable depth, light, saturation, warmth and framing; flat cards supported.
- Clear beveled sleeves with reflections, tilt and drag inspection, sleeve removal and a flip-to-certificate view.
- Photo-matched ambient gradients using Music's weighted three-color clustering method.
- Fixed editions of 1–1,000 copies. Each copy retains its rarity, serial and ownership history.
- Before sealing, a recoverable draft is saved and Photos asks permission to delete the selected original. Cancelling keeps the draft. iOS controls the confirmation and Recently Deleted.
- Nearby transfers with recipient acceptance, persisted ownership handoff and reconnection recovery. For a swap, both collectors offer a copy in turn.

The build workflow compiles for iPhone, runs native persistence/trade/normalization/renderer tests and real bundled DA3 inference, then launches the simulator before publishing. See the attached build report for executed results.

Physical-device validation is still required for gyroscope feel, Photos/iCloud deletion, two-phone connectivity and LiveContainer permissions. This IPA is unsigned, intended for the same sideloading workflow as the other apps in this repository. Nearby trade records enforce fixed editions within the app's local data; there is no authoritative online scarcity server or protection against modified app databases, device backups or modified clients.
