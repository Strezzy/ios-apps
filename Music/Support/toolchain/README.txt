LINUX iOS BUILD RECOVERY
========================

These scripts preserve the Linux build setup that was previously lost when
the temporary workspace was pruned. They build a real native arm64 iOS
executable. There is no iOS simulator or device runtime in this environment.

Requirements
------------
Linux x86_64, glibc 2.38 or newer, Python 3.9+, dpkg-deb, and the ordinary
Ubuntu 24.04 runtime libraries. The official Ubuntu snapshot archive must be
reachable for the initial tool download. No root package installation is
performed. On a Mac, use the project's build-macos.sh with Xcode instead.

Commands (run from the Music project directory)
-----------------------------------------------
  python3 Support/toolchain/bootstrap.py
  python3 Support/toolchain/build_linux.py

The default compiler directory is ../ios-toolchain. The bootstrap checks
the exact byte count and SHA-256 of pinned LLVM 20.1.2 Ubuntu packages before
extracting them. Existing verified downloads can be reused. If the matching
libLLVM runtime is absent it is downloaded too; --bundle-llvm forces a local
copy. No system compiler configuration is modified.

The build driver compiles Sources/main.m with ARC, blocks, arm64/iOS 16,
optimization and warnings as errors; runs verify_objc_layout.py; then links
against SDK-26-versioned public framework stubs with an ad-hoc signature.
It explicitly uses classic dyld information (-no_fixup_chains), preserving the
known-working LiveContainer loading configuration.

The resulting executable is Build/GlassMusic. Packaging is a separate,
explicit operation:
  python3 Support/toolchain/build_linux.py --package

That option builds first and invokes the project's package_and_verify.py,
which stages the app, validates its IPA and signature code-page hashes, and
writes the normal reports/deliverables. It is intended for the final reviewed
source. An ad-hoc IPA still needs the user's installer to re-sign it.

For a compile-only check, use --compile-only. To avoid touching a release
build, provide --build-dir /absolute/path/to/review-build. --project accepts a
separate source snapshot, and --toolchain accepts a custom compiler directory.

Link stubs and new APIs
----------------------
symbols.json records each imported symbol's exact two-level namespace from
the recovered Music 0.10 executable. It contains only explicit known
symbols, not the complete Apple SDK. make_sdk.py turns that manifest into
link-only TAPI .tbd files under Build/sdk. Apple's framework implementations
are supplied by iOS at runtime; no Apple libraries are copied into the IPA.

New native API imports require both accurate public SDK declarations and an
explicit entry under the correct public framework in symbols.json. Unknown
symbols intentionally fail to link. Do not use flat-namespace linking,
-undefined dynamic_lookup, private framework paths, or a catch-all export list
to conceal a missing or incorrect API mapping.

capture_imports.py can recover the import mapping from another known-working
thin arm64 executable. Its --output argument is explicit so it does not silently
replace the checked manifest. Preserve public umbrella mappings such as
NSFontAttributeName -> UIKit and AVAudioSession -> AVFAudio.

The narrow MiniSDK is used only for the Linux build. Do not remove NSObject's
Class isa field: the layout checker catches the launch-corrupting constant
offset regression fixed in Music 0.1.1. App packaging checks and source-level
API review cannot substitute for a device runtime test.

Optional local renderer verification
------------------------------------
  python3 Support/toolchain/bootstrap_browser.py

This restores the official Chrome-for-Testing 151.0.7922.34 headless shell
from Google's published ZIP, with exact size and SHA-256 verification. The
normal Playwright download endpoint returned an invalid HTML payload in this
environment, while the direct official download worked. No user browser or
profile is accessed, and Chromium is never included in the app or source ZIP.
Only this small recovery script is preserved with the project.

The resulting executable is
../ios-toolchain/browser/chrome-headless-shell-linux64/chrome-headless-shell.
Pass that as Playwright's executablePath with these software-WebGL arguments:
--no-sandbox --disable-dev-shm-usage --use-gl=angle --use-angle=swiftshader
--enable-unsafe-swiftshader

An actual WebGL2 context and pixel readback were verified with this tool. It
can validate the local renderer/shaders; it does not reproduce an iPhone's
WebKit, gyroscope, UIKit touch routing, or thermal/GPU characteristics.

