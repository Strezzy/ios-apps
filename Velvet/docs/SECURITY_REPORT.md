# Velvet security implementation and limits

This describes the implemented source, not an independent security certification. Build and automated-test results belong in the release workflow and `VERIFICATION.md`. Camera, Keychain prompts, Data Protection while locked, filesystem interruption, and offline behavior require the physical-device procedure in that document. A simulator cannot establish those properties on an iPhone.

## Protected storage

- CryptoKit AES-256-GCM protects originals, thumbnails, video segments, video manifests, metadata, OCR, Vision feature prints, and semantic vectors. Each seal uses CryptoKit's fresh random nonce. Authenticated context includes a format version, domain, item identifier, and segment sequence. Context fields have unambiguous lengths and integer encodings.
- Each item has an independently generated 256-bit key. A 256-bit master key wraps item keys with authenticated item identifiers. The encrypted catalogue holds those envelopes and all private filenames, descriptions, album membership, favorites, timestamps, dimensions, hashes, and references.
- The master key and catalogue integrity anchors reside together in a nonsynchronizing Keychain item with `WhenPasscodeSetThisDeviceOnly` accessibility and `userPresence` access control. Device-owner authentication permits Face ID and the device passcode. This is a Keychain-protected symmetric key, not a claim that AES operations occur inside Secure Enclave.
- The vault tree and every durable sensitive file use Complete file protection and exclusion from automatic backups. Atomic temporary writes contain ciphertext from their creation. No app-owned plaintext image, movie, thumbnail, or private-index file is created.
- Opaque UUID paths and ciphertext sizes remain visible to someone who can list the container. Item count, approximate media size, and file modification timing are not hidden. The search runtime can read bundled public model assets; it is not given vault filesystem paths.

## Integrity, commits, and interrupted work

A catalogue commit first authorizes the old and proposed ciphertext hashes in Keychain, atomically writes the new encrypted catalogue, and then retains only the new hash. An interrupted commit accepts whichever of those authenticated versions actually reached disk and immediately finalizes that version on unlock. A successfully finalized old catalogue cannot simply be copied back over the current one. During the narrow interrupted-commit window, either authorized version is accepted. This is not a hardware monotonic counter and does not defend against rollback of both the protected Keychain record and the complete filesystem by a compromised operating system.

Media blobs reach storage before their catalogue reference. Recovery removes unreferenced ciphertext directories only after the catalogue authenticates successfully. Authentication or key failures never cause existing vault content to be reset. If the entire vault directory is absent after an uninstall, an authenticated Keychain key that survived uninstall can initialize an empty catalogue for an explicit encrypted-backup restore. A partial directory with a missing catalogue remains a failure.

Photo originals are stored byte for byte. ImageIO validates dimensions and derives only a bounded preview in memory. Still imports are limited to 80 MiB and 200 million pixels to bound parsing and memory use; full-resolution viewing and analysis may have stricter display limits. Missing, malformed, or oversized input is rejected.

Video delegates deliver initialization and media segments to a synchronous writer. Each segment is authenticated independently with its sequence and item ID, and is at most 32 MiB. A final encrypted manifest commits the exact sequence, count, plaintext sizes, ciphertext hashes, and total length. Incomplete recordings have no catalogue entry. The resource loader reads authenticated byte ranges using at most one cached decrypted segment; it never assembles a plaintext movie file. Invalid tags, substitutions, missing segments, invalid lengths, and stale but otherwise valid ciphertext stop playback.

## Locking and deletion

Session capabilities revoke synchronously on lock. Readers drop their decrypted caches and keys; recording writers drop keys and stop accepting data. UI state is cleared, and operations finishing after lock cannot return private content into a newer session. The application conceals inactive scenes and locks on backgrounding, protected-data unavailability, and detected screen capture or mirroring.

System authentication can briefly make a scene inactive; concealment is separate from permanent session destruction. iOS screenshots cannot be universally prevented. Camera and system frameworks can maintain private internal buffers beyond the application's control. Swift, CryptoKit, Vision, and AVFoundation allocations cannot be guaranteed to be zeroized or absent from a compromised process's memory.

Trash has no silent expiration: records remain encrypted until the user restores them or explicitly deletes them. Permanent deletion first removes catalogue records and wrapped item keys, invalidates readers, and removes managed asset files and local prepared backup exports. Recovery retries removal of orphaned ciphertext. Flash wear leveling, filesystem snapshots, already exported archives, and prior copies prevent any guarantee of physical or cryptographic secure erasure.

## Explicit encrypted backup

The backup format uses a new random 256-bit recovery key for each export. That key encrypts an authenticated manifest containing the source master key, encrypted catalogue, ordered file descriptors, lengths, and ciphertext hashes. Existing encrypted asset files then stream directly to the archive; plaintext originals are never written. The recovery key is displayed separately and is not stored in the archive or hardcoded. Losing the key makes that archive unrecoverable; possessing both the archive and key grants access to its contents.

Restore authenticates the manifest, validates the catalogue and item envelopes, requires an exact file set and archive length, verifies each ciphertext digest and AES-GCM tag, validates video ordering and content hashes, and only then commits merged records under the destination master key. It preserves existing items. Failed restoration removes newly staged ciphertext or leaves it for authenticated recovery after an uncertain commit. Seeking and copying are bounded per file or segment, rather than loading entire movies or archives. The encrypted backup manifest is capped at 64 MiB.

The share sheet and document picker are explicit user actions. A destination chosen by the user may sync an encrypted archive, and a system picker may fetch a selected file from iCloud. This is separate from Velvet's own offline media processing. Recovery keys should be kept separately from archives and out of synced clipboards. Exported archives survive later deletion from the live vault and must be managed separately by their owner.

## Test coverage and remaining validation

XCTest sources cover round trips including empty plaintext; randomized nonces; tag tampering; truncation; domain/item/sequence substitution; item-key binding; bounded video seeking across segments; repeated or missing initialization; manifest order, duplicates, and totals; stale segment replacement; synchronous session revocation; encrypted original/thumbnail/metadata/search storage; missing keys; missing catalogues; catalogue rollback; interrupted anchor finalization; reinstall recovery; trash/index deletion; still and video backup round trips; wrong recovery keys; archive truncation; and all-or-nothing restoration of a tampered archive. These assertions establish only the behaviors exercised when the CI test run passes.

Remaining device checks include actual Keychain ACL behavior and passcode removal, biometric cancellation, device locking during a write, lock-screen filesystem protection, low storage, AVAssetWriter segment output on each advertised codec, orientation and audio, playback seeking during lock/capture detection, memory/thermal behavior, app-switcher snapshots, and airplane-mode/network inspection. No claim is made that these device checks have passed without recorded evidence. The runtime has no accounts, analytics, remote inference, automatic Photos save, or plaintext-share feature. Third-party model/runtime behavior and licensing are documented separately in `AI.md`.
