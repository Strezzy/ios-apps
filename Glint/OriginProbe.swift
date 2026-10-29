// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main struct OriginProbe {
    static func main() throws {
        let post = URL(string: "https://www.instagram.com/reel/ABC_123/")!
        precondition(GlintInstagramURL.post(URL(string: "http://instagram.com/name/reels/ABC_123/?igsh=secret")) == post)
        for value in ["https://instagram.com/name/", "https://instagram.com/reels/", "https://instagram.com/reels/audio/123/", "https://instagram.com.evil.test/reel/ABC/", "javascript://instagram.com/reel/ABC/", "https://user:pass@instagram.com/reel/ABC/", "https://instagram.com:999/reel/ABC/"] {
            precondition(GlintInstagramURL.post(URL(string: value)) == nil, value)
        }
        let cookies = GlintBrowserCookies.parse("""
        # Netscape HTTP Cookie File
        #HttpOnly_.instagram.com\tTRUE\t/\tTRUE\t0\tsessionid\ttest-only
        .instagram.com\tTRUE\t/\tFALSE\t1\texpired\told
        .evil.test\tTRUE\t/\tTRUE\t0\tsessionid\tother
        .instagram.com.evil.test\tTRUE\t/\tTRUE\t0\tsessionid\tother
        """)
        precondition(cookies.count == 1 && cookies[0].isSecure && cookies[0].isHTTPOnly)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original.mp4"), copy = folder.appendingPathComponent("renamed (1) — iPhone.mp4")
        precondition(GlintOriginStore.key(folder.appendingPathComponent("café.mp4")) == GlintOriginStore.key(folder.appendingPathComponent("cafe\u{301}.mp4")))
        try Data("encoded source".utf8).write(to: source)
        let record = GlintOrigin(postURL: post, creatorURL: URL(string: "https://www.instagram.com/artist/"), username: "artist", title: "A post")
        try GlintOriginStore.write(record, for: source)
        try GlintOriginStore.copy(from: source, to: copy)
        precondition(GlintOriginStore.read(copy) == record)
        let originalBytes = try Data(contentsOf: source)
        precondition(originalBytes == Data("encoded source".utf8))
        try GlintOriginStore.writeLink(for: copy)
        let links = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "webloc" }
        precondition(links.count == 1)
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: links[0]), options: [], format: nil) as! [String: String]
        precondition(plist["URL"] == post.absoluteString)
        try Data("invalid json".utf8).write(to: GlintOriginStore.sidecar(copy))
        precondition(GlintOriginStore.read(copy) == nil)
        GlintOriginStore.ensure(paths: [copy.path], sourceURL: post)
        precondition(GlintOriginStore.read(copy)?.postURL == post)
        print("Native provenance checks passed: canonical post URLs, hostile URL rejection, cookie scope/expiry/HTTPOnly, rename/copy retention, source bytes, portable shortcut, malformed metadata, fallback link.")
    }
}
