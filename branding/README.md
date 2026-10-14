# Strezzy app-suite identity

Prism is the visual reference and remains unchanged. Music is separate and is not part of this suite update.

| App | Previous name | Native bundle identifier | Interface |
| --- | --- | --- | --- |
| Facet | Depth Check | `com.billy.facet` | Existing blue/cyan interface retained |
| Veil | Rinse | `com.billy.veil` | Emerald and mint, including the Share extension |
| Lucid | LumaLift | `com.billy.lucid` | Existing pink-purple interface retained |
| Echo | VoiceGlass | `com.billy.echo` | Purple and lavender controls, waveforms and backgrounds |

The family uses short names, sculpted geometric symbols, coordinated gradients, consistent scale and a distinct color for each tool. Veil uses a compact header, Photos/Files/Folder import cards, larger-text layouts and reduced-transparency alternatives. Its Share extension uses `com.billy.veil.share` and the display name **Clean with Veil**.

## Artwork and native packages

`assets/` contains rounded catalog icons. `branding/app-icons/` contains the opaque, full-bleed 1024-pixel native masters. `scripts/suite_branding.py` reproduces those assets with Pillow and NumPy. `branding/verification.json` verifies artwork only; it is not evidence that an IPA was rebuilt.

**Published native-build evidence is stored in `branding/native-releases/`.** Each report records the actual version and build, bundle identity, IPA checksum, and comparison of compiled home-screen icon pixels with the approved master. The GitHub release also contains the installable IPA and simulator captures. A report is added only after the corresponding package passes its publication checks. The app source links to that verified release, not an old IPA with a renamed listing.

The native package has the new `CFBundleDisplayName`, `CFBundleName`, bundle identifier and application-folder name. Internal Swift module, source-directory and executable names may remain unchanged; they are implementation details, not the installed product identity.

Native compilation, simulator launch and automated checks are not physical-iPhone testing. Read each report's explicit limitations. In particular, Lucid's hardware-only RIFE tests are not reported as passed on an unsupported simulator.

## One-time installation change

These new bundle identifiers were requested as part of the native rename. They create separate app identities, rather than automatically transferring the old app's sandbox. Keep the old installation and export important media or voice recordings before removing it. Model downloads and preferences may need to be set up again. See [the installation note](../docs/NATIVE-SUITE-UPGRADE.md).

After the one-time rename, retain the new identifiers for ordinary updates. Keep historical releases and their original filenames available. Never replace a published IPA with different bytes at the same version and build number.
