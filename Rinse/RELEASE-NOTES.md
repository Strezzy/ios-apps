# Rinse 1.0.0

Clean personal metadata from photos and SDR videos entirely on your iPhone.

Includes a native Liquid Glass interface, Photos/Files/folder import, sequential
batches, fresh SHA-256 file fingerprints, verified output reports, separate-copy
export and a small-batch photo Share extension. No accounts, ads, analytics or
app networking. No model downloads.

## Before using

- Requires iOS 26+. This is an unsigned physical-device IPA for your sideloading tool.
- Supports JPEG/PNG/HEIC still photos up to 64 MP and SDR MOV/MP4 video up to 4K/60 fps.
- Photos are rebuilt as SDR sRGB. HDR/depth/Live Photo motion are not preserved.
- RAW, animated/multi-image photos and HDR/spatial/alpha/wide-color videos are unsupported.
- JPEG/HEIC and video are re-encoded, not losslessly copied. Keep your originals.
- The Share extension handles up to 10 photos, 16 MP each, and requires an installation method that loads app extensions. Main-app import works independently.
- A changed byte hash is not protection from image/audio matching. Visible or audible personal information remains.
- System cloud pickers and user-chosen exports can use the internet even though Rinse has no network client. Choose already-local media for offline use.
- Keep Rinse open while cleaning. Save copies before clearing or relaunching the session.

The attached build report records native simulator tests and the device compilation.
Physical iPhone/iPad testing, long-video thermal testing and Share-extension testing
on the user's signing/container configuration have not been performed.
