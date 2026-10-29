// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit

enum GlintInstagramURL {
    static let home = URL(string: "https://www.instagram.com/")!
    static func normalized(_ url: URL?) -> URL? {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, parts.port == nil,
              let host = parts.host?.lowercased(), host == "instagram.com" || host.hasSuffix(".instagram.com") else { return nil }
        parts.scheme = "https"; parts.host = "www.instagram.com"
        parts.query = nil; parts.fragment = nil
        return parts.url
    }
    static func post(_ url: URL?) -> URL? {
        guard let url = normalized(url) else { return nil }
        let pattern = #"^/(?:[A-Za-z0-9_.]+/)?(p|reels?|tv)/([A-Za-z0-9_-]+)/?$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: url.path, range: NSRange(url.path.startIndex..., in: url.path)),
              let kindRange = Range(match.range(at: 1), in: url.path),
              let codeRange = Range(match.range(at: 2), in: url.path) else { return nil }
        let kind = String(url.path[kindRange]) == "reels" ? "reel" : String(url.path[kindRange])
        let code = String(url.path[codeRange])
        guard code != "audio" else { return nil }
        return URL(string: "https://www.instagram.com/\(kind)/\(code)/")
    }
    static func profile(_ url: URL?) -> URL? {
        guard let url = normalized(url) else { return nil }
        let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let reserved = ["p", "reel", "reels", "tv", "explore", "accounts", "direct", "stories", "about", "legal"]
        guard !reserved.contains(name.lowercased()), name.range(of: #"^[A-Za-z0-9_.]{1,30}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.instagram.com/\(name)/")
    }
}

struct GlintOrigin: Codable, Equatable {
    var version = 1
    var postURL: URL
    var creatorURL: URL?
    var username: String?
    var title: String?
}

enum GlintOriginStore {
    static func key(_ url: URL) -> String {
        SHA256.hash(data: Data(url.lastPathComponent.precomposedStringWithCanonicalMapping.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24).description
    }
    static func sidecar(_ url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".glint-origin-\(key(url)).json")
    }
    static func read(_ url: URL) -> GlintOrigin? {
        guard let data = try? Data(contentsOf: sidecar(url)), data.count <= 16384,
              var origin = try? JSONDecoder().decode(GlintOrigin.self, from: data),
              let post = GlintInstagramURL.post(origin.postURL) else { return nil }
        origin.postURL = post
        origin.creatorURL = GlintInstagramURL.profile(origin.creatorURL)
        origin.username = origin.creatorURL?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return origin
    }
    static func write(_ origin: GlintOrigin, for url: URL) throws {
        try JSONEncoder().encode(origin).write(to: sidecar(url), options: .atomic)
    }
    static func copy(from source: URL, to destination: URL) throws {
        if let origin = read(source) { try write(origin, for: destination) }
    }
    static func ensure(paths: [String], sourceURL: URL?) {
        guard let post = GlintInstagramURL.post(sourceURL) else { return }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if read(url) == nil { try? write(GlintOrigin(postURL: post), for: url) }
        }
    }
    static func writeLink(for url: URL) throws {
        guard let origin = read(url) else { return }
        let name = String(url.deletingPathExtension().lastPathComponent.prefix(65))
        let link = url.deletingLastPathComponent().appendingPathComponent("\(name) — Original post \(key(url).prefix(8)).webloc")
        try PropertyListSerialization.data(fromPropertyList: ["URL": origin.postURL.absoluteString], format: .xml, options: 0).write(to: link, options: .atomic)
    }
    static func writeLinks(in folder: URL) throws {
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            try writeLink(for: url)
        }
    }
}

enum GlintBrowserCookies {
    static func parse(_ text: String, now: Date = Date()) -> [HTTPCookie] {
        text.components(separatedBy: .newlines).compactMap { line in
            let httpOnly = line.hasPrefix("#HttpOnly_")
            let raw = httpOnly ? String(line.dropFirst(10)) : line
            guard !raw.hasPrefix("#") else { return nil }
            let fields = raw.components(separatedBy: "\t")
            guard fields.count == 7 else { return nil }
            let domain = fields[0].lowercased(), host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            guard host == "instagram.com" || host.hasSuffix(".instagram.com"),
                  !fields[5].isEmpty, let expiry = TimeInterval(fields[4]), expiry == 0 || expiry > now.timeIntervalSince1970 else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: fields[2].isEmpty ? "/" : fields[2], .name: fields[5], .value: fields[6]]
            if fields[3] == "TRUE" { properties[.secure] = "TRUE" }
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if expiry > 0 { properties[.expires] = Date(timeIntervalSince1970: expiry) }
            return HTTPCookie(properties: properties)
        }
    }
    static func instagramOnly(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies.filter { cookie in
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return (host == "instagram.com" || host.hasSuffix(".instagram.com")) && (cookie.expiresDate == nil || cookie.expiresDate! > Date())
        }
    }
}
