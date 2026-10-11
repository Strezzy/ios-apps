import SwiftUI

struct DepthCheckRootView: View {
    @EnvironmentObject private var store: StudioStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { CreateView() }
                .tabItem { Label("Create", systemImage: "square.3.layers.3d") }
                .tag(StudioTab.create)
            NavigationStack { ExportsView() }
                .tabItem { Label("Exports", systemImage: "square.stack") }
                .tag(StudioTab.exports)
            NavigationStack { StudioSettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(StudioTab.settings)
        }
        .tint(DepthCheckTheme.accent)
        .preferredColorScheme(.dark)
        .alert(item: Binding(get: { store.previewIsPresented ? nil : store.alert }, set: { store.alert = $0 })) { alert in
            alert.systemAlert
        }
    }
}
