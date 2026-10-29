// SPDX-License-Identifier: GPL-3.0-or-later
// Compiled with the production policy on the macOS build runner.
import Foundation

@main
struct QualityProbe {
    static func main() throws {
        let arguments = [
            "video": GlintSourceQuality.downloadArguments(),
            "mute": GlintSourceQuality.downloadArguments(includeAudio: false)
        ]
        let data = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
