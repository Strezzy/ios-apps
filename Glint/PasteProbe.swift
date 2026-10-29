// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main
struct PasteProbe {
    @MainActor static func main() async {
        let url = URL(string: "https://www.instagram.com/reel/Example123/")!
        let fromURL = await GlintPaste.read([NSItemProvider(object: url as NSURL)])
        precondition(fromURL == url.absoluteString, "URL paste payload failed")
        let fromText = await GlintPaste.read([NSItemProvider(object: "Watch this: \(url.absoluteString)" as NSString)])
        precondition(fromText == url.absoluteString, "Link inside text paste payload failed")
        let empty = await GlintPaste.read([NSItemProvider(object: "No link here" as NSString)])
        precondition(empty == nil, "Invalid paste should be explained instead of downloaded")
        print("3 native paste payload tests passed: URL, shared text, invalid text.")
    }
}
