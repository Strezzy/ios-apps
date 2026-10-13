# Rinse: physical-device acceptance checks

Status: **not performed**. Automated simulator results do not establish physical-device stability, sideloading compatibility, a forensic privacy guarantee, or long-video thermal behavior. Record the exact release version and build number when these checks are run. Use synthetic media rather than private photos when filing public issues.

## Required checks before recommending a release

| Area | Procedure | Expected outcome | Device result |
| --- | --- | --- | --- |
| Offline operation | Download fixtures first, then disable cellular and Wi-Fi. Import local JPEG, PNG, HEIC, MOV and MP4 media. Clean and save to On My iPhone. | Processing completes without account setup, model downloads or an app network connection. Cloud-only files may be unavailable. | Not tested |
| Personal metadata | Use test files containing synthetic GPS, dates, camera model, owner, comments and an innocuous visible identifying label. Compare the original and output reports. | Checked embedded personal fields are removed. The visible label remains, demonstrating that metadata cleaning is not visual redaction. | Not tested |
| Originals | Keep an independent copy and SHA-256 of each original before import. Clean, cancel a separate job, retry and clear the session. | External originals remain byte-identical. Only temporary working files and unexported session copies may be deleted. | Not tested |
| Orientation and color | Test all eight EXIF orientations, portrait photos, rotated video and transparent PNGs. | Geometry and orientation are correct. Photos are explicitly SDR sRGB. JPEG/HEIC/video recompression is not claimed to be lossless. | Not tested |
| Fingerprints | Process the same fixture twice with Fresh file fingerprint enabled. Compare output SHA-256 values and decoded pixels for PNG. | Hashes differ; PNG renderings match. Recognition by appearance is still possible. | Not tested |
| Folder access | Select a nested local folder containing supported media, unrelated files, hidden files and symbolic links where the provider permits them. | Supported regular files import recursively. Unsupported files and links do not become clean results. No source files are changed. | Not tested |
| Batch limits | Import close to the 500-item limit, including files into a partially filled queue. Repeat with mixed valid and corrupt inputs. | The app stays responsive, does not exceed the documented cap, and never presents failed items as successfully cleaned. | Not tested |
| Video duration | Use SDR clips at 24, 30 and 60 fps, variable-rate footage, and clips with audio that ends before video. Compare frame counts, timestamps, duration and lip sync externally. | No lost or duplicated displayable frames, early truncation, or introduced audio drift. | Not tested |
| Sustained video | Clean progressively longer SDR 4K60 recordings on a physical device with adequate free storage. Observe thermal state and responsiveness. | No crash or runaway memory growth. Thermal-critical stop produces an understandable failure and no exportable partial movie. | Not tested |
| Unsupported media | Try HDR, spatial, wide-color and alpha videos; RAW, animated and multi-image photos; and surround-sound movies. | Unsupported inputs are rejected or limited as documented, not silently advertised as fully preserved. Photos do not retain HDR, depth or Live Photo motion. | Not tested |
| Cancellation and storage | Stop cleaning, background the main app during a long job, and repeat with limited free storage. | Originals remain safe. Failed or unfinished outputs cannot be shared as verified copies. Saved exports remain intact. | Not tested |
| Export destinations | Save verified copies to local Files and Photos, then inspect them again. Separately test a cloud destination only with deliberate permission. | Rinse explains that Photos, file providers and sharing destinations may add metadata or upload according to the user's system settings. | Not tested |
| Share extension | With a supported normal sideload installation, share up to ten photos of at most 16 MP each. Test cancellation and export. | Clean verified still copies are offered. Larger photos and videos direct users to the main app. Containers that do not load extensions use main-app import instead. | Not tested |
| Interface | Test light/dark appearance, increased text size, VoiceOver and reduced motion on iPhone and iPad. Open Privacy and Settings and inspect export sheets. | Controls remain usable and legible. No clipped critical notices or nonfunctional controls. | Not tested |

## Evidence to record

Record the device model, iOS version, installation method, build number, fixture dimensions and duration, result and any reproducible steps. Do not include real GPS coordinates, personal metadata, private media, credentials or screenshots containing personal details in public reports. Public reproduction files must be synthetic or explicitly cleared for publication.

A passing result must identify the actual tested configuration. A skipped or unsupported test is not a pass. Never summarize these checks as proof that files are anonymous, impossible to match, or free of all conceivable hidden information.
