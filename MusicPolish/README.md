# Music 0.13 CD polish

Continue from the verified Music 0.12 (13) source. Apply the prepared renderer reuse, artwork caching, higher-density grid rendering, and pose-aware framing changes without replacing the native Liquid Glass navigation or changing the app's bundle identifier.

Before publication, regenerate the bundled renderer, build with Apple's SDK, exercise production CD controls and renderer reuse in the iOS simulator, and review the resulting captures. Publish only the tested device IPA and update the existing `apps.json` in this repository. The LiveContainer source URL and all other app entries must remain unchanged.

Physical-device frame pacing, gyroscope behavior, and thermal performance must be reported separately from simulator checks.
