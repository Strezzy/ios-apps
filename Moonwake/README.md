# Moonwake

A complete, offline pixel-art action adventure for iPhone and iPad. Written in native Swift with SpriteKit and SwiftUI. Aster carries a sword filled with starlight through five realms to awaken the sleeping moon.

[Download the iPhone release](https://github.com/Strezzy/ios-apps/releases/tag/moonwake-1.0.0-build1) · [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/moonwake-1.0.0-build1/Moonwake.ipa)

![Moonwake running natively on the iPhone simulator](https://github.com/Strezzy/ios-apps/releases/download/moonwake-1.0.0-build1/Moonwake-Gameplay.png)

![Moonwake title screen](https://github.com/Strezzy/ios-apps/releases/download/moonwake-1.0.0-build1/Moonwake-Title.png)

## The journey

Explore Moonshore, Briarwild, Glassmarsh, Ember Ruins and Eclipse Crown. Awaken three runes in each realm, free its guardian, then restore the moonwell to open the next path. Meet Moss, follow Wisp, find keeper caches and spend stardust on sword, heart and spirit upgrades. The fifth restored moonwell concludes the story; your completed save remains available to revisit the world.

- White-haired, red-scarfed hero and an animated cyan greatsword.
- Sword combos, evasive dash, moonpulse, five enemy families and five guardians.
- Five hand-arranged environments with authored pixel textures, water, flora, ruins, particles and ambient animation.
- Amber spirit and moss guardian companions.
- Seventeen bundled original audio assets: six ambient/combat scores and eleven effects.
- Native Liquid Glass menus, local saves with backup recovery, adjustable sound, haptics, reduced effects, handedness and Story difficulty.
- Entirely offline. No accounts, advertisements, purchases, tracking or runtime downloads.

## Controls

| Action | Touch | Controller | Keyboard |
|---|---|---|---|
| Move | Thumbstick | Left stick / D-pad | WASD / arrows |
| Strike | Sword | X / right shoulder | Space |
| Dash | Dash | A | Shift |
| Moonpulse | Moon | Y | Q |
| Interact | Context button | B | E |
| Moon vial | Vial | Left shoulder | F |
| Pause | Pause | Menu | Escape |

Runes, caches, Moss and moonwells use the context button when nearby. All three runes must be awake before a guardian can be freed. The journal shows the current objective and unlocked realms. The Pause menu offers upgrades. Story mode reduces incoming damage; no progress is forfeited when you retry a moonwell.

## Build

Requires macOS, Xcode with the iOS 26 or later SDK, Python 3 and XcodeGen. The checked-in workflow uses the repository's Xcode 27.1 runner.

```sh
cd Moonwake
bash scripts/build.sh
bash scripts/test.sh
```

The build generates the icon and original WAV audio locally, generates the Xcode project, compiles the actual arm64 iPhone application, and packages `Build/Moonwake.ipa`. The package is intended for re-signing with your sideloading setup. It is not App Store distribution-signed.

## Validation

The release includes the actual build report, test result summary and SHA-256 checksum. Automated checks cover campaign gates and ending, save/recovery, upgrades/reward idempotence, every region's navigability, native textures, scene combat, and UI flows. Screenshots are captured from the running iOS simulator.

Physical iPhone frame rate, thermals, battery use, haptics, controller hardware and LiveContainer/SideStore behavior still require device playtesting. A successful simulator run does not certify those properties.

## Art and audio

Sprites, environments, effects, icon and music are authored specifically for this project in reproducible source. The visual direction follows the supplied pixel-art reference. The advertisement, promotional text and logo are not bundled. No third-party game assets or recordings are included.

Created by Strezzy.
