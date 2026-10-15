import SwiftUI
import UIKit

enum RiftSheet: String, Identifiable { case models, history, settings; var id: String { rawValue } }
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft=""
    @State private var sheet: RiftSheet?
    @State private var voiceSession: VoiceController?
    private var voiceVisible: Bool { voiceSession != nil }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composing: Bool
    @State private var following = ChatFollowingState()
    @State private var viewport = ChatViewport()
    @State private var bottomRequest = UUID()
    var body: some View {
        NavigationStack {
            ZStack {
                if let startup=model.startupError { ContentUnavailableView("Local data unavailable",systemImage:"externaldrive.badge.exclamationmark",description:Text(startup)).padding() }
                else {
                    VStack(spacing:0) {
                        ErrorBanner()
                        if model.activeChat?.messages.isEmpty != false { welcome }
                        else { messages }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { RiftBackground() }
            .overlay(alignment: .bottomTrailing) {
                if let voiceSession {
                    VoiceConversationView(voice: voiceSession)
                        .id(ObjectIdentifier(voiceSession))
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .scale(scale: 0.12, anchor: .bottomTrailing).combined(with: .opacity)))
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: voiceVisible)
            .onChange(of: sheet) { _, value in if value != nil { closeVoice(feedback: false) } }
            .onChange(of: composing) { _, value in if value { closeVoice(feedback: false) } }
            .safeAreaInset(edge: .bottom, spacing: 0) { if model.startupError == nil { composer } }
            .navigationTitle("Rift").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button { sheet = .history } label: { Image(systemName:"line.3.horizontal").frame(width:28,height:28) }.accessibilityLabel("Chat history") }
                ToolbarItem(placement:.principal) {
                    Button { composing=false; sheet = .models } label: {
                        VStack(spacing:2) { Text("Rift").font(.headline).foregroundStyle(.primary); HStack(spacing:4) { Text(model.selectedModel?.name ?? "Choose a model").lineLimit(1); Image(systemName:"chevron.down").font(.system(size:8,weight:.bold)) }.font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain).accessibilityIdentifier("modelPicker")
                }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button { closeVoice(); model.newChat(); draft="" } label: { Image(systemName:"square.and.pencil") }.disabled(model.generating).accessibilityLabel("New chat")
                    Menu { Button("Models",systemImage:"cpu") { sheet = .models }; Button("Settings",systemImage:"slider.horizontal.3") { sheet = .settings } } label: { Image(systemName:"ellipsis") }.accessibilityLabel("More options")
                }
            }
            .sheet(item:$sheet) { choice in
                switch choice { case .models: ModelLibraryView(); case .history: HistoryView(); case .settings: SettingsView() }
            }
        }.background { RiftBackground().ignoresSafeArea(.all) }
    }
    private var welcome: some View {
        ZStack { RiftMark() }.frame(width: 84, height: 102)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rift").accessibilityIdentifier("emptyChatMark")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(model.activeChat?.messages ?? []) { message in
                        MessageView(message: message, isStreaming: model.generating && message.id == model.activeChat?.messages.last?.id)
                            .id(message.id)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("chatMessage-\(message.id.uuidString)")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }
            .accessibilityIdentifier("chatScrollView")
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .alignment)
            .onScrollGeometryChange(for: ChatViewport.self) { geometry in
                ChatViewport(height: Double(geometry.containerSize.height),
                    contentHeight: Double(geometry.contentSize.height),
                    bottomDistance: Double(max(0, geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height)))
            } action: { old, new in
                viewport = new
                if following.observe(old: old, new: new) { bottomRequest = UUID() }
            }
            .onScrollPhaseChange { _, phase in
                following.interaction(phase == .tracking || phase == .interacting || phase == .decelerating, viewport: viewport)
            }
            .onChange(of: composing) { _, focused in
                if focused { followLatest() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                // Re-anchor after keyboard layout, including frame changes which
                // do not produce a focus-state transition.
                if following.followsLatest && !following.userScrolling { bottomRequest = UUID() }
            }
            .onChange(of: model.activeChat?.messages.last?.id) { _, _ in followLatest() }
            .onChange(of: model.activeChatID) { _, _ in followLatest() }
            .onAppear { followLatest() }
            .task(id: bottomRequest) {
                await Task.yield()
                guard !Task.isCancelled, following.shouldScroll(in: viewport) else { return }
                // Keep the latest line above the composer; per-letter motion is
                // handled by the renderer, not by a long scroll on every token.
                withTransaction(Transaction(animation: nil)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !following.followsLatest {
                    Button { followLatest() } label: { Label("Latest reply", systemImage: "arrow.down").font(.caption).padding(6) }
                        .buttonStyle(.glass).padding(12).accessibilityIdentifier("jumpToLatest")
                }
            }
        }
    }
    private func followLatest() {
        following.followLatest()
        bottomRequest = UUID()
    }
    private var composer: some View {
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(.body).lineLimit(1...4).focused($composing)
                    .padding(.leading, 14).padding(.vertical, 10)
                    .submitLabel(.send).onSubmit(send).accessibilityIdentifier("messageInput")
                Button {
                    composing = false
                    if voiceVisible { closeVoice() }
                    else {
                        VoiceOrbFeedback.play(appearing: true)
                        voiceSession = VoiceController(model: model)
                    }
                } label: {
                    Image(systemName: voiceVisible ? "xmark" : "waveform").font(.system(size: 18, weight: .medium))
                        .frame(width: 40, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(voiceVisible ? "Close voice mode" : "Voice mode")
                    .accessibilityIdentifier(voiceVisible ? "closeVoiceMode" : "openVoiceMode")
                    .disabled(!voiceVisible && (model.generating || model.busy))
                Button {
                    if model.generating { model.stop() } else { send() }
                } label: {
                    Image(systemName: model.generating ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(RiftTheme.accent, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(!model.generating && (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.selectedModel == nil || !model.ready || model.busy))
                    .accessibilityLabel(model.generating ? "Stop reply" : "Send message")
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .contain).accessibilityIdentifier("composerBar")
            Text("Unrestricted On-device AI")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityIdentifier("chatFooter")
        }.padding(.horizontal, 12).padding(.top, 5).padding(.bottom, 3)
    }
    private func closeVoice(feedback: Bool = true) {
        guard let voiceSession else { return }
        // Stop audio immediately, even while the disappearing glass is animating.
        voiceSession.close()
        if feedback { VoiceOrbFeedback.play(appearing: false) }
        self.voiceSession = nil
    }
    private func send() {
        if model.send(draft) { draft = ""; followLatest() }
    }
}
struct MessageView: View {
    @EnvironmentObject var model: AppModel
    let message: ChatMessage
    let isStreaming: Bool
    var body: some View {
        let user=message.role == "user", parts=ReplyParts.parse(message.content)
        HStack(alignment:.top) {
            if user { Spacer(minLength:35) }
            VStack(alignment:.leading,spacing:10) {
                if !user { HStack(spacing:7) { Image(systemName:"sparkle").foregroundStyle(RiftTheme.accent); Text(message.modelName ?? "Rift").foregroundStyle(.secondary) }.font(.caption.weight(.medium)) }
                if !parts.thought.isEmpty {
                    DisclosureGroup(isStreaming && parts.answer.isEmpty ? "Thinking" : "Thought process") { Text(parts.thought).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.font(.caption).tint(RiftTheme.accent)
                }
                if !parts.answer.isEmpty { MarkdownMessage(text:parts.answer, isStreaming:isStreaming, interrupted:message.interrupted, fillsWidth: !user) }
                if !user && isStreaming && parts.answer.isEmpty { ReplyTypingIndicator() }
                if !user && !isStreaming {
                    if message.isFailedReply || (message.interrupted && message.content.isEmpty) {
                        Label(message.failureDescription == nil ? "Reply stopped" : "Reply not started", systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing:18) {
                        Button { UIPasteboard.general.string=message.content } label: { Image(systemName:"document.on.document") }.accessibilityLabel("Copy reply")
                        if message.id == model.activeChat?.messages.last?.id { Button { model.regenerate() } label: { Label(message.isFailedReply ? "Retry reply" : "Regenerate", systemImage:"arrow.clockwise") }.disabled(model.generating).accessibilityLabel("Regenerate reply") }
                        if message.interrupted { Text("Interrupted").font(.caption2) }
                    }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
                }
            }.padding(user ? 14 : 0).background { if user { RoundedRectangle(cornerRadius:22).fill(RiftTheme.accent.opacity(0.11)) } }
                .accessibilityIdentifier(user ? "sentMessageBubble-\(message.id.uuidString)" : "replyBody-\(message.id.uuidString)")
            if !user { Spacer(minLength:0) }
        }.contextMenu { Button("Copy",systemImage:"document.on.document") { UIPasteboard.general.string=message.content } }
    }
}
struct MarkdownMessage: View {
    let text: String
    var isStreaming = false
    var interrupted = false
    var fillsWidth = true
    var body: some View {
        let chunks = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                if index % 2 == 0 {
                    StreamingText(text: chunk, isStreaming: isStreaming, interrupted: interrupted)
                        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(chunk.components(separatedBy: "\n").first ?? "Code").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { UIPasteboard.general.string = chunk.components(separatedBy: "\n").dropFirst().joined(separator: "\n") } label: { Image(systemName: "document.on.document") }.accessibilityLabel("Copy code")
                        }
                        ScrollView(.horizontal) {
                            StreamingText(text: chunk.components(separatedBy: "\n").dropFirst().joined(separator: "\n"), isStreaming: isStreaming, interrupted: interrupted, monospaced: true)
                        }
                    }.padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

/// A quiet reply cue with stable layout; its dots never affect scroll geometry.
struct ReplyTypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var body: some View {
        let still = reduceMotion || lowPower || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: still)) { tick in
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    let wave = still ? 0.5 : (sin(tick.date.timeIntervalSinceReferenceDate * 5 - Double(index) * 0.8) + 1) / 2
                    Circle().fill(RiftTheme.accent.opacity(0.35 + wave * 0.5))
                        .frame(width: 7, height: 7).offset(y: still ? 0 : -wave * 3)
                }
            }.padding(.horizontal, 14).frame(height: 34)
                .background(RiftTheme.accent.opacity(0.09), in: Capsule())
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Replying")
        .accessibilityIdentifier("replyTypingIndicator")
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
