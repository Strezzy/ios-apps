// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import WebKit
import UIKit

extension Notification.Name {
    static let glintOpenInstagram = Notification.Name("GlintOpenInstagram")
    static let glintBrowserAction = Notification.Name("GlintBrowserAction")
    static let glintBrowserDownloadStarted = Notification.Name("GlintBrowserDownloadStarted")
}

struct GlintBrowserTarget: Identifiable {
    let id = UUID()
    let url: URL
}

struct GlintBrowserAction {
    let cookies: [HTTPCookie]
    let postURL: URL?
    let complete: @MainActor (Bool, String?) -> Void
}

@MainActor final class GlintBrowserActivity: ObservableObject {
    static let shared = GlintBrowserActivity()
    @Published var busy = false
}

@MainActor final class GlintBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    struct Post: Identifiable, Decodable {
        let url: URL
        let label: String
        var id: URL { url }
    }
    let webView: WKWebView
    @Published var url = GlintInstagramURL.home
    @Published var loading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var message: String?
    @Published var finding = false
    private var observations: [NSKeyValueObservation] = []

    init(initialURL: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in if let url = view.url { self?.url = url } }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.loading = view.isLoading
                    self?.canGoBack = view.canGoBack; self?.canGoForward = view.canGoForward
                }
            }
        ]
        Task { await seedSession(); load(initialURL) }
    }

    private func seedSession() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "palladium.useCookies") || defaults.bool(forKey: "palladium.defaultUseCookies") else { return }
        let name = defaults.string(forKey: "palladium.selectedCookieFileName") ?? ""
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
              let directory = try? GlintPrivateStorage.cookiesDirectory(),
              let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else { return }
        for cookie in GlintBrowserCookies.parse(text) {
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
    }

    func cookies() async -> [HTTPCookie] {
        GlintBrowserCookies.instagramOnly(await webView.configuration.websiteDataStore.httpCookieStore.allCookies())
    }
    func load(_ url: URL) {
        message = nil
        webView.load(URLRequest(url: url))
    }
    func posts() async -> [Post] {
        finding = true
        defer { finding = false }
        guard GlintInstagramURL.normalized(webView.url) != nil else {
            message = "Open an Instagram post, profile, or feed to choose a download."
            return []
        }
        var posts: [Post] = []
        if let post = GlintInstagramURL.post(webView.url) { posts.append(Post(url: post, label: "Current post")) }
        do {
            let value = try await webView.evaluateJavaScript(GlintBrowserScript.posts)
            if let json = value as? String, let data = json.data(using: .utf8) {
                for candidate in try JSONDecoder().decode([Post].self, from: data) {
                    guard let url = GlintInstagramURL.post(candidate.url), !posts.contains(where: { $0.url == url }) else { continue }
                    posts.append(Post(url: url, label: candidate.label))
                }
            }
        } catch { message = "Could not read post links. Open the post, or paste its link in Download." }
        if posts.isEmpty { message = "No post links found in this view. Open a post from its timestamp or menu, then try again. You can also copy its link and paste it in Download." }
        return posts
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { message = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, ["http", "https", "about"].contains(url.scheme?.lowercased() ?? "") else {
            message = "This link tries to open another app. Use Instagram’s website controls to stay in Glint."
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { webView.load(action.request) }
        return nil
    }
}

private struct GlintWebView: UIViewRepresentable {
    let browser: GlintBrowserModel
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct GlintInstagramBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser: GlintBrowserModel
    @ObservedObject private var activity = GlintBrowserActivity.shared
    @State private var posts: [GlintBrowserModel.Post] = []
    @State private var choosing = false
    @State private var sending = false
    init(url: URL) { _browser = StateObject(wrappedValue: GlintBrowserModel(initialURL: url)) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!browser.canGoBack).accessibilityLabel("Back")
                    Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!browser.canGoForward).accessibilityLabel("Forward")
                    Text(browser.url.host ?? "Instagram").font(.caption).lineLimit(1).frame(maxWidth: .infinity)
                    Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reload")
                }.padding(.horizontal, 22).padding(.vertical, 12)
                HStack(spacing: 12) {
                    route("Home", path: "/", icon: "house")
                    route("Reels", path: "/reels/", icon: "play.rectangle")
                    route("Explore", path: "/explore/", icon: "safari")
                }.padding(.horizontal).padding(.bottom, 10)
                if browser.loading { ProgressView().frame(maxWidth: .infinity).padding(4) }
                GlintWebView(browser: browser)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 9) {
                    if let message = browser.message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    if activity.busy { Text("You can browse while Glint works. Download another post when it finishes.").font(.caption).foregroundStyle(.secondary) }
                    Button {
                        Task { posts = await browser.posts(); choosing = !posts.isEmpty }
                    } label: {
                        Label(browser.finding ? "Finding posts…" : "Choose post to download", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(activity.busy || browser.finding || sending)
                    Text("Instagram’s website · Sign in here or use your selected session.").font(.caption2).foregroundStyle(.secondary)
                }.padding(14).background(.regularMaterial)
            }
            .navigationTitle("Instagram").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use login") { Task { await send(post: nil) } }.disabled(activity.busy || sending)
                }
            }
            .sheet(isPresented: $choosing) {
                NavigationStack {
                    List(posts) { post in
                        Button { Task { await send(post: post.url) } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(post.label.isEmpty ? "Download post" : post.label, systemImage: "arrow.down.circle").font(.headline).lineLimit(2)
                                Text(post.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                        }.disabled(sending || activity.busy)
                    }.navigationTitle("Choose a post")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosing = false } } }
                }.presentationDetents([.medium, .large])
            }
        }.tint(GlintPalette.accent)
    }
    private func route(_ title: String, path: String, icon: String) -> some View {
        Button { browser.load(URL(string: "https://www.instagram.com\(path)")!) } label: {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
        }.buttonStyle(.plain).glintGlass(18)
    }
    @MainActor private func send(post: URL?) async {
        guard !sending, !activity.busy else { return }
        sending = true
        defer { sending = false }
        let cookies = await browser.cookies()
        if post == nil && !cookies.contains(where: { $0.name == "sessionid" && !$0.value.isEmpty }) {
            browser.message = "Finish signing in on Instagram, then tap Use login."
            return
        }
        NotificationCenter.default.post(name: .glintBrowserAction, object: GlintBrowserAction(cookies: cookies, postURL: post) { success, message in
            browser.message = message
            if success && post != nil { choosing = false; dismiss() }
        })
    }
}

struct GlintOriginCard: View {
    let url: URL
    @State private var origin: GlintOrigin?
    @State private var browser: GlintBrowserTarget?
    @State private var editing = false
    @State private var link = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Original post", systemImage: "link").font(.headline)
            if let origin {
                Button { browser = GlintBrowserTarget(url: origin.postURL) } label: { Label("Open original post", systemImage: "arrow.up.right.square") }
                Text(origin.postURL.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let creator = origin.creatorURL {
                    Button { browser = GlintBrowserTarget(url: creator) } label: {
                        Label("Browse @\(origin.username ?? "creator")", systemImage: "person.crop.circle")
                    }
                } else { Text("Open the post and tap its creator to visit their profile.").font(.caption).foregroundStyle(.secondary) }
                ShareLink(item: origin.postURL) { Label("Share post link", systemImage: "square.and.arrow.up") }
            } else {
                Text("This file has no saved post link. New Instagram downloads keep it automatically.").font(.caption).foregroundStyle(.secondary)
                Button("Add original link") { editing = true }
            }
            if editing {
                TextField("Instagram post link", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save link") {
                    guard let post = GlintInstagramURL.post(URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))) else { error = "Enter an Instagram post or Reel link."; return }
                    do {
                        let value = GlintOrigin(postURL: post)
                        try GlintOriginStore.write(value, for: url)
                        try GlintOriginStore.writeLink(for: url)
                        origin = value; editing = false; error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.buttonStyle(.borderless).padding(18).glintGlass(22)
            .task(id: url) { origin = GlintOriginStore.read(url) }
            .sheet(item: $browser) { target in GlintInstagramBrowser(url: target.url) }
    }
}

extension ContentView {
    @MainActor func glintHandleBrowserAction(_ action: GlintBrowserAction) {
        guard !isRunning, !isPackageRunning, !isResolvingFormats, !isResolvingGallery else {
            action.complete(false, "Wait for the current operation to finish before downloading another post.")
            return
        }
        let cookies = GlintBrowserCookies.instagramOnly(action.cookies)
        do {
            if cookies.contains(where: { $0.name == "sessionid" && !$0.value.isEmpty }) {
                let text = try NetscapeCookieExporter.text(from: cookies)
                let name = "instagram-browser-cookies.txt"
                let file = try GlintPrivateStorage.cookiesDirectory().appendingPathComponent(name)
                try Data(text.utf8).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                selectedCookieFileName = name; defaultUseCookies = true; useCookies = true
                refreshImportedCookieFiles()
            }
            guard let post = GlintInstagramURL.post(action.postURL) else {
                action.complete(true, "Instagram session selected for downloads. It stays in Glint’s private storage.")
                return
            }
            // Follow the browser's current login state for this download.
            useCookies = cookies.contains(where: { $0.name == "sessionid" && !$0.value.isEmpty })
            selectedTab = .download
            selectedPreset = .autoVideo
            urlText = post.absoluteString
            runDownloadFlow(urlOverride: post.absoluteString, presetOverride: .autoVideo)
            action.complete(true, nil)
            NotificationCenter.default.post(name: .glintBrowserDownloadStarted, object: nil)
        } catch { action.complete(false, error.localizedDescription) }
    }
}

struct GlintFolderSourceView: View {
    let folder: URL
    @State private var creator: URL?
    @State private var browser: GlintBrowserTarget?
    var body: some View {
        Group {
            if let creator {
                Button { browser = GlintBrowserTarget(url: creator) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle").font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Browse @\(creator.lastPathComponent)").font(.subheadline.weight(.semibold))
                            Text("Visit the original creator and download more.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "arrow.up.right")
                    }.padding(16).glintGlass(22).padding(.horizontal).padding(.vertical, 8)
                }.buttonStyle(.plain)
            }
        }.task(id: folder) {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let origins = files.compactMap(GlintOriginStore.read)
            let creators = Set(origins.compactMap(\.creatorURL))
            creator = !origins.isEmpty && origins.allSatisfy { $0.creatorURL != nil } && creators.count == 1 ? creators.first : nil
        }.sheet(item: $browser) { target in GlintInstagramBrowser(url: target.url) }
    }
}
