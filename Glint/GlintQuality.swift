// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum GlintSourceQuality {
    static func downloadArguments(includeAudio: Bool = true) -> String {
        // Positive HDR evidence is required. Unknown range and SDR cannot match.
        let hdr = "[dynamic_range~='^(HLG|HDR10[+]?|HDR|PQ|DV|Dolby Vision)$']"
        let selector = includeAudio ? "bv*\(hdr)+ba/b\(hdr)" : "bv\(hdr)/b\(hdr)"
        // Filter to HDR first, then maximize source dimensions, fps and bitrate.
        return "-f \"\(selector)\" --format-sort-force -S \"res,fps,br\" --keep-video"
    }
}
