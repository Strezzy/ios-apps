# Velvet threat model and capture architecture

## Boundaries
Protect an offline user's original media, thumbnails, metadata and search features against filesystem/backup disclosure, accidental Photos writes, and casual access to an unlocked phone. Require device-owner authentication (Face ID with device passcode fallback). This does not defeat a compromised OS, memory forensics, coercion, another camera photographing the screen, screenshots, or all OS-private caches. Swift and framework memory cannot be guaranteed zeroized.

## Keys and storage
A random 256-bit master key is protected in Keychain with WhenPasscodeSetThisDeviceOnly and userPresence. Every asset has an independent random 256-bit AES-GCM key. Master-key-authenticated envelopes wrap item keys and encrypt the catalogue. Every blob uses a fresh CryptoKit random nonce and authenticated domain, asset ID, and sequence metadata. All durable app-owned sensitive content is ciphertext. Use Complete file protection and exclude the entire vault tree from backups. A locked session releases decrypted state and invalidates operations. Failure must not initialize over an unreadable existing key or index.

## Photos
AVCapturePhotoOutput produces original HEIF/JPEG/DNG bytes in memory. Encrypt originals without re-encoding. Derive thumbnails and Vision features in memory and encrypt them. Never call Photos save APIs. Photo picker imports are explicitly requested; the picker can use iCloud independently and originals remain in Photos. Limit imports to bounded in-memory still-image data.

## Video
Use AVCaptureVideoDataOutput and AVCaptureAudioDataOutput feeding an AVAssetWriter configured for fragmented MPEG-4 segment-data delegate output, without a plaintext output URL. Authenticate and encrypt each initialization/media segment before its only durable write. Finish with an authenticated manifest listing the ordered segment lengths and count. Incomplete recordings are discarded. A custom AVAssetResourceLoaderDelegate serves authenticated byte ranges from bounded decrypted segments to AVPlayer. No decrypted movie is assembled on disk. Unvalidated professional formats stay unavailable.

## Lifecycle
Obscure all content when inactive; lock when backgrounded, protected data becomes unavailable, or screen capture/mirroring is detected. Stop capture, cancel indexing, clear thumbnail caches and tear down playback. System authentication may briefly make the scene inactive, so concealment is distinct from destruction of the authenticated session. Durable mutations are atomic. Recovery removes only unreferenced ciphertext after a valid index is loaded. Deletion removes managed data and envelopes; flash wear leveling prevents a physical secure-erasure guarantee. Plaintext export is unavailable in the initial release; encrypted backup uses an explicit separate user-held recovery key.

## Verification gates
Crypto tamper/order/context tests, encrypted filesystem audit, interruption/low-space tests, simulator compilation and tests, plus a mandatory physical-device capture/playback/offline checklist. Never equate compiling or simulator success with hardware validation.
