import SwiftUI

@main
struct CollectrApp: App {
    @StateObject private var store: CollectionStore
    @StateObject private var editor = EditorModel()
    @StateObject private var nearby: NearbyTrade
    init() {
        let store: CollectionStore
        #if DEBUG && targetEnvironment(simulator)
        if PreviewFixtures.enabled {
            store = CollectionStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("CollectrVisualQA"))
            PreviewFixtures.prepare(store)
        } else { store = CollectionStore() }
        #else
        store = CollectionStore()
        #endif
        _store = StateObject(wrappedValue: store)
        _nearby = StateObject(wrappedValue: NearbyTrade(store: store))
    }
    var body: some Scene {
        WindowGroup {
            CollectrRoot(editor: editor,nearby: nearby).environmentObject(store).preferredColorScheme(.dark).tint(.white)
        }
    }
}

struct CollectrRoot: View {
    @EnvironmentObject private var store: CollectionStore
    @ObservedObject var editor: EditorModel
    @ObservedObject var nearby: NearbyTrade
    @State private var tab = 0
    @State private var focused: CollectorCard?
    @State private var tradeCard: UUID?
    @State private var palette = RGB.defaults
    @Namespace private var cardNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack {
            AmbientBackground(palette: palette)
            TabView(selection: $tab) {
                Tab("Create",systemImage: "plus.circle",value: 0) {
                    CreateView(editor: editor,active: tab == 0 && focused == nil,onCreated: { card in
                        tab = 1; inspect(card)
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    },onPalette: { if tab == 0 { palette = $0 } })
                }
                Tab("Collections",systemImage: "square.stack",value: 1) {
                    CollectionsView(focused: focused,namespace: cardNamespace,onOpen: inspect,onCreate: { tab = 0 })
                }
                Tab("Trade",systemImage: "arrow.left.arrow.right",value: 2) {
                    TradeView(nearby: nearby,selectedCard: $tradeCard)
                }
            }.opacity(focused == nil ? 1 : 0).allowsHitTesting(focused == nil)
            if let focused {
                CardInspector(initial: focused,namespace: cardNamespace,onClose: closeInspector,onTrade: { card in
                    tradeCard = card.id; closeInspector(); tab = 2
                }).transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                    .zIndex(2)
            }
            if let error = store.error {
                ContentUnavailableView("Collection unavailable",systemImage: "externaldrive.badge.exclamationmark",description: Text(error)).background(.black.opacity(0.9)).zIndex(3)
            }
        }
        .onAppear {
            #if DEBUG && targetEnvironment(simulator)
            if CommandLine.arguments.contains("--preview-create") { editor.configurePreview() }
            if CommandLine.arguments.contains("--preview-collections") { tab = 1 }
            if CommandLine.arguments.contains("--preview-card"), let card = store.cards.first { tab = 1; inspect(card) }
            if CommandLine.arguments.contains("--preview-trade") { tab = 2; tradeCard = store.cards.first?.id }
            #endif
        }
        .onChange(of: tab) { _,selected in
            if focused == nil { palette = selected == 0 ? editor.palette : RGB.defaults }
            if selected != 2 { nearby.stop() }
        }
        .onChange(of: scenePhase) { _,phase in if phase != .active { nearby.stop() } }
    }
    private func inspect(_ card: CollectorCard) {
        palette = card.palette
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.65,dampingFraction: 0.85)) { focused = card }
    }
    private func closeInspector() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.6,dampingFraction: 0.85)) { focused = nil }
        palette = tab == 0 ? editor.palette : RGB.defaults
    }
}
