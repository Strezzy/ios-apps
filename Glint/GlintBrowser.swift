// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Combine
import WebKit
import UIKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let glintOpenInstagram = Notification.Name("GlintOpenInstagram")
    static let glintBrowserAction = Notification.Name("GlintBrowserAction")
}

struct GlintBrowserAction {
    let cookies: [HTTPCookie]
    let postURL: URL?
    let complete: @MainActor (Bool, String?) -> Void
}

struct GlintBrowserHost: ViewModifier {
    let busy: Bool
    @Binding var selectedTab: ContentView.AppTab
    let browser: GlintBrowserModel
    let queueBlocked: Bool
    let onAction: @MainActor (GlintBrowserAction) -> Void
    let onIdle: @MainActor () -> Void
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .glintOpenInstagram)) { notification in
                browser.load(notification.object as? URL ?? GlintInstagramURL.home)
                selectedTab = .instagram
            }
            .onReceive(NotificationCenter.default.publisher(for: .glintBrowserAction)) { notification in
                if let action = notification.object as? GlintBrowserAction { onAction(action) }
            }
            .onReceive(GlintBrowserActivity.shared.$mediaBusy) { value in if !value { DispatchQueue.main.async { onIdle() } } }
            .onChange(of: queueBlocked) { _, blocked in if !blocked { onIdle() } }
            .onChange(of: busy, initial: true) { _, value in
                GlintBrowserActivity.shared.busy = value
                if !value { onIdle() }
            }
    }
}

@MainActor final class GlintBrowserActivity: ObservableObject {
    static let shared = GlintBrowserActivity()
    @Published var busy = false
    @Published var mediaBusy = false
}

@MainActor final class GlintBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var url = GlintInstagramURL.home
    @Published var loading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var message: String?
    @Published var signedIn = false
    private var ready = false
    private var requestedURL: URL?
    private var observations: [NSKeyValueObservation] = []

    override init() {
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
        Task {
            await seedSession()
            ready = true
            if let requestedURL { load(requestedURL) }
        }
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
    func activate() { if requestedURL == nil { load(GlintInstagramURL.home) } }
    func load(_ url: URL) {
        requestedURL = url
        guard ready else { return }
        message = nil
        webView.load(URLRequest(url: url))
    }
    func refreshSession() async {
        signedIn = await cookies().contains { $0.name == "sessionid" && !$0.value.isEmpty }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward
        Task { await refreshSession() }
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

struct GlintInstagramTab: View {
    @ObservedObject var browser: GlintBrowserModel
    @ObservedObject private var activity = GlintBrowserActivity.shared
    @State private var composing = false
    @State private var sending = false
    @State private var link = ""
    @State private var linkError: String?
    var body: some View {
        GlintWebView(browser: browser)
            .overlay(alignment: .top) {
                if browser.loading { ProgressView().padding(8).glintGlass(20).padding(.top, 4).allowsHitTesting(false) }
            }
            .overlay(alignment: .bottomLeading) { navigationMenu.padding(16) }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    link = GlintInstagramURL.post(browser.url)?.absoluteString ?? ""
                    linkError = nil; composing = true
                } label: {
                    Label("Download", systemImage: activity.busy ? "plus" : "arrow.down")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 20).padding(.vertical, 15)
                }.buttonStyle(.plain).glintGlass(30).padding(16)
            }
            .overlay(alignment: .top) {
                if let message = browser.message {
                    HStack(alignment: .top, spacing: 12) {
                        Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                        Button { browser.message = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss message")
                    }.padding(14).glintGlass(20).padding(12)
                }
            }
            .sheet(isPresented: $composing) { composer }
            .task(id: browser.message) {
                let message = browser.message
                guard message != nil else { return }
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled && browser.message == message { browser.message = nil }
            }
            .onAppear { browser.activate(); Task { await browser.refreshSession() } }
            .tint(GlintPalette.accent)
    }
    private var navigationMenu: some View {
        Menu {
            Button("Back", systemImage: "chevron.left") { browser.webView.goBack() }.disabled(!browser.canGoBack)
            Button("Forward", systemImage: "chevron.right") { browser.webView.goForward() }.disabled(!browser.canGoForward)
            Button("Home", systemImage: "house") { browser.load(GlintInstagramURL.home) }
            Button("Reels", systemImage: "play.rectangle") { browser.load(URL(string: "https://www.instagram.com/reels/")!) }
            Button("Explore", systemImage: "safari") { browser.load(URL(string: "https://www.instagram.com/explore/")!) }
            Button("Reload", systemImage: "arrow.clockwise") { browser.webView.reload() }
            if !browser.signedIn {
                Button("Sign in to Instagram", systemImage: "person.crop.circle") { browser.load(URL(string: "https://www.instagram.com/accounts/login/")!) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.headline).frame(width: 48, height: 48)
        }.glintGlass(25).accessibilityLabel("Instagram navigation")
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Download post").font(.title3.bold())
                Spacer()
                Button("Cancel") { composing = false }.disabled(sending)
            }
            HStack(spacing: 10) {
                TextField("Instagram post or Reel link", text: $link)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .submitLabel(.go).onSubmit { Task { await send() } }
                PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
                    Task { @MainActor in
                        if let value = await GlintPaste.read(providers) { link = value; linkError = nil }
                        else { linkError = "The clipboard does not contain a post link." }
                    }
                }.labelStyle(.iconOnly)
            }.padding(14).glintGlass(18)
            if let linkError { Text(linkError).font(.caption).foregroundStyle(.red) }
            Button { Task { await send() } } label: {
                Label(sending ? "Adding…" : "Download", systemImage: "arrow.down")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(sending || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Highest available quality. Saved to Library while you browse. Your current Instagram login is used automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).presentationDetents([.height(310), .medium]).presentationDragIndicator(.visible)
    }
    @MainActor private func send() async {
        guard !sending else { return }
        guard let post = GlintInstagramURL.post(URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))) else {
            linkError = "Paste an Instagram post or Reel link."; return
        }
        sending = true
        let cookies = await browser.cookies()
        NotificationCenter.default.post(name: .glintBrowserAction, object: GlintBrowserAction(cookies: cookies, postURL: post) { success, message in
            sending = false
            if success { composing = false; browser.message = message }
            else { linkError = message }
        })
    }
}

struct GlintOriginCard: View {
    let url: URL
    @State private var origin: GlintOrigin?
    @State private var editing = false
    @State private var link = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Original post", systemImage: "link").font(.headline)
            if let origin {
                Button { NotificationCenter.default.post(name: .glintOpenInstagram, object: origin.postURL) } label: { Label("Open original post", systemImage: "arrow.up.right.square") }
                Text(origin.postURL.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let creator = origin.creatorURL {
                    Button { NotificationCenter.default.post(name: .glintOpenInstagram, object: creator) } label: {
                        Label("Browse @\(origin.username ?? "creator")", systemImage: "person.crop.circle")
                    }
                } else { Text("Open the post and tap its creator to visit their profile.").font(.caption).foregroundStyle(.secondary) }
                Button { UIPasteboard.general.url = origin.postURL } label: { Label("Copy post link", systemImage: "doc.on.doc") }
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
    }
}

extension ContentView {
    var glintBrowserQueueBlocked: Bool {
        showDownloadActionSheet || sharePayload != nil || showAlert || awaitingQueueItemID != nil
    }
    @MainActor func glintHandleBrowserAction(_ action: GlintBrowserAction) {
        guard let post = GlintInstagramURL.post(action.postURL) else { action.complete(false, "Enter a post or Reel link."); return }
        let cookies = GlintBrowserCookies.instagramOnly(action.cookies)
        let signedIn = cookies.contains { $0.name == "sessionid" && !$0.value.isEmpty }
        do {
            var cookieName = ""
            if signedIn {
                let text = try NetscapeCookieExporter.text(from: cookies)
                // Each queued request keeps its own session snapshot. Signing out or
                // switching accounts cannot change a download already in the queue.
                cookieName = "instagram-\(UUID().uuidString).txt"
                let directory = try GlintPrivateStorage.cookiesDirectory()
                try Data(text.utf8).write(to: directory.appendingPathComponent(cookieName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                let selectedName = "instagram-browser-cookies.txt"
                try Data(text.utf8).write(to: directory.appendingPathComponent(selectedName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                selectedCookieFileName = selectedName; defaultUseCookies = true; useCookies = true
                refreshImportedCookieFiles()
            }
            var configuration = QueuedDownloadConfiguration(
                presetRawValue: DownloadPreset.autoVideo.rawValue, presetArgumentsJSON: "{}", extraArguments: "",
                downloadPlaylist: false, downloadSubtitles: downloadSubtitles, embedThumbnail: false,
                autoRetryFailedDownloads: false, subtitleLanguagePattern: resolvedSubtitleLanguagePattern,
                useCookies: signedIn, cookieFileName: cookieName,
                afterDownloadBehaviorRawValue: AfterDownloadBehavior.saveToApplicationFolder.rawValue,
                postProcessing: PostProcessingPreferences(), filenameExportPreset: filenameExportPreset,
                customFilenameTemplate: customFilenameTemplate)
            configuration.glintBrowserRequest = true
            downloadQueue.append(linksText: post.absoluteString, configuration: configuration)
            persistDownloadQueue()
            glintBrowserQueueRequested = !downloadQueue.isActive
            glintStartBrowserQueueIfReady()
            action.complete(true, isRunning ? "Added to downloads. Keep browsing; your video will appear in Library." : "Queued. Downloads resume when the current operation finishes.")
        } catch { action.complete(false, error.localizedDescription) }
    }

    @MainActor func glintStartBrowserQueueIfReady() {
        guard !GlintBrowserActivity.shared.mediaBusy, !isRunning, !isPackageRunning,
              !isResolvingFormats, !isResolvingGallery, !isResolvingQueueQuality,
              awaitingQueueItemID == nil, !showDownloadActionSheet, sharePayload == nil, !showAlert else { return }
        if glintBrowserQueueRequested {
            completedDownloadResult = nil
            glintBrowserQueueRequested = false
            startDownloadQueue()
        } else { runNextQueuedDownloadIfNeeded() }
    }
}

struct GlintFolderSourceView: View {
    let folder: URL
    @State private var creator: URL?
    var body: some View {
        Group {
            if let creator {
                Button { NotificationCenter.default.post(name: .glintOpenInstagram, object: creator) } label: {
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
        }
    }
}
