import SwiftUI
import UIKit

enum RiftSheet: String, Identifiable { case models, settings; var id: String { rawValue } }
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
    @State private var drawerOpen = false
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.42, dampingFraction: 0.86))) private var drawerDrag: CGFloat = 0
    var body: some View {
        GeometryReader { geometry in
            let width = min(340.0, geometry.size.width * 0.82)
            let progress = DrawerMotion.progress(open: drawerOpen, translation: drawerDrag, width: width)
            ZStack(alignment: .leading) {
                ConversationDrawer(onSelect: { setDrawer(false) }, onSettings: {
                    setDrawer(false); sheet = .settings
                })
                .frame(width: width)
                .opacity(progress > 0 ? 1 : 0)
                .accessibilityHidden(!drawerOpen)
                chatSurface(width: geometry.size.width)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: progress * 32, style: .continuous))
                    .overlay {
                        if progress > 0 {
                            RoundedRectangle(cornerRadius: progress * 32, style: .continuous)
                                .fill(.black.opacity(progress * 0.12))
                                .contentShape(Rectangle())
                                .onTapGesture { setDrawer(false) }
                                .gesture(drawerGesture(width: width))
                                .accessibilityLabel("Close conversations")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("closeConversations")
                        }
                    }
                    .shadow(color: .black.opacity(progress * 0.55), radius: 24, x: -8)
                    .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.035, anchor: .trailing)
                    .offset(x: width * progress)
                    .accessibilityHidden(drawerOpen)
                if !drawerOpen {
                    Color.clear.frame(width: 22).contentShape(Rectangle())
                        .gesture(drawerGesture(width: width))
                        .accessibilityHidden(true)
                }
            }
            .background(Color(red: 0.035, green: 0.045, blue: 0.065).ignoresSafeArea())
            .clipped()
        }
        .ignoresSafeArea(.container)
        .transaction { if reduceMotion { $0.animation = nil } }
        .sheet(item: $sheet) { choice in
            switch choice { case .models: ModelLibraryView(); case .settings: SettingsView() }
        }
        .onChange(of: sheet) { _, value in if value != nil { closeVoice(feedback: false) } }
    }
    private func setDrawer(_ open: Bool) {
        if open { composing = false; closeVoice(feedback: false) }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86)) {
            drawerOpen = open
        }
    }
    private func drawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    composing = false; closeVoice(feedback: false)
                }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                setDrawer(DrawerMotion.shouldOpen(open: drawerOpen, projected: value.predictedEndTranslation.width, width: width))
            }
    }
    private func chatSurface(width: CGFloat) -> some View {
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
            .onChange(of: composing) { _, value in if value { closeVoice(feedback: false) } }
            .safeAreaInset(edge: .bottom, spacing: 0) { if model.startupError == nil { composer(width: width) } }
            .navigationTitle("Rift").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { setDrawer(true) } label: { Image(systemName: "line.3.horizontal").frame(width: 28, height: 28) }
                        .accessibilityLabel("Chat history")
                }
                ToolbarItem(placement: .principal) {
                    Menu {
                        if model.installed.isEmpty { Text("No downloaded models") }
                        ForEach(model.installed) { installed in
                            Button {
                                composing = false; closeVoice(feedback: false); model.select(installed)
                            } label: {
                                if installed.id == model.selectedModelID { Label(installed.name, systemImage: "checkmark") }
                                else { Text(installed.name) }
                            }.disabled(model.generating)
                        }
                        Divider()
                        Button("Manage Models", systemImage: "cpu") { composing = false; sheet = .models }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Rift").font(.headline).foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                Text(model.selectedModel?.name ?? "Choose a model").lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }.menuIndicator(.hidden).accessibilityIdentifier("modelPicker")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { closeVoice(); model.newChat(); draft = "" } label: {
                        Image(systemName: "square.and.pencil").frame(width: 28, height: 28)
                    }.disabled(model.generating).accessibilityLabel("New chat")
                }
            }
        }.background { RiftBackground() }
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
    private var composerAction: ComposerAction {
        ComposerAction.resolve(draft: draft, voice: voiceVisible, generating: model.generating)
    }
    private func composer(width: CGFloat) -> some View {
        let action = composerAction
        return VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 4) {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(.body).lineLimit(1...4).focused($composing)
                    .padding(.leading, 16).padding(.vertical, 14)
                    .submitLabel(.send).onSubmit(send).accessibilityIdentifier("messageInput")
                Button {
                    switch action {
                    case .close: closeVoice()
                    case .stop: model.stop()
                    case .send: send()
                    case .voice:
                        composing = false
                        VoiceOrbFeedback.play(appearing: true)
                        voiceSession = VoiceController(model: model)
                    }
                } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(action == .send ? .white : RiftTheme.accent)
                        .frame(width: 46, height: 46)
                        .glassEffect(.regular.tint(action == .send ? RiftTheme.accent : .clear).interactive(), in: Circle())
                        .phaseAnimator([1.0, 0.88, 1.07, 1.0], trigger: action) { content, scale in
                            content.scaleEffect(reduceMotion ? 1 : scale)
                        } animation: { _ in .spring(response: 0.22, dampingFraction: 0.65) }
                        .padding(3)
                }.buttonStyle(.plain)
                    .accessibilityLabel(action.label).accessibilityIdentifier(action.identifier)
                    .disabled(action == .send ? (model.selectedModel == nil || !model.ready || model.busy) : (action == .voice && model.busy))
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 29))
            .accessibilityElement(children: .contain).accessibilityIdentifier("composerBar")
            Text("Unrestricted On-device AI")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityIdentifier("chatFooter")
        }
        .frame(width: max(0, (width - 24) * 0.8))
        .frame(maxWidth: .infinity)
        .padding(.top, 5).padding(.bottom, 3)
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
