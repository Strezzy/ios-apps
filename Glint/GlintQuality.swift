// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum GlintSourceQuality {
    static func downloadArguments(includeAudio: Bool = true) -> String {
        let selector = includeAudio ? "bv*+ba/b" : "bv/b"
        // Resolution comes first. Prefer HDR at equal resolution; SDR and unknown
        // range remain eligible. Merge by stream copy, without retaining duplicate
        // elementary tracks in the user's library. Preserve the finished original
        // separately whenever a playable copy needs conversion.
        return "-f \"\(selector)\" --format-sort-force -S \"res,hdr,fps,br\""
    }
}
