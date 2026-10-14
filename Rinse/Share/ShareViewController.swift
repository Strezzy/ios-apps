import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let model = ShareModel(providers: providers)
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            model.cancel()
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
    }
}

@MainActor final class ShareModel: ObservableObject {
    @Published var results: [CleanResult] = []
    @Published var status = "Preparing photos…"
    @Published var busy = true
    private var operation: Task<Void, Never>?
    init(providers: [NSItemProvider]) {
        operation = Task { [weak self] in
            do {
                try Workspace.prepare(reset: true)
                guard !providers.isEmpty, providers.count <= 10 else { throw RinseError.message("Share up to 10 photos at a time. Use the main app for larger batches and videos.") }
                var failures = 0
                for (index, provider) in providers.enumerated() {
                    try Task.checkCancellation()
                    self?.status = "Cleaning photo \(index + 1) of \(providers.count)…"
                    do {
                        let input = try await ProviderImporter.copy(provider)
                        defer { try? FileManager.default.removeItem(at: input) }
                        guard MediaKind.of(input) == .photo else { throw RinseError.message("Use the main Rinse app to clean videos.") }
                        var options = CleanOptions(); options.maxPhotoPixels = 16_000_000
                        let worker = Task.detached { try await RinseEngine.clean(input, options: options) }
                        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                        self?.results.append(result)
                    } catch is CancellationError { throw CancellationError() }
                    catch { failures += 1; self?.status = error.localizedDescription }
                }
                self?.status = failures > 0 ? "\(failures) item(s) could not be cleaned here. Use the main app for details, videos or photos above 16 MP." : "Clean copies verified. Share or save them below."
            } catch { self?.status = error.localizedDescription }
            self?.busy = false
        }
    }
    func cancel() { operation?.cancel() }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let close: () -> Void
    @State private var export = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "drop.fill").font(.system(size: 56)).foregroundStyle(.teal)
                Text("Clean with Veil").font(.title.bold())
                Text(model.status).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if model.busy { ProgressView() }
                if !model.results.isEmpty && !model.busy {
                    Label("\(model.results.count) verified copies", systemImage: "checkmark.seal")
                    Button("Share clean copies", systemImage: "square.and.arrow.up") { export = true }
                        .buttonStyle(.glassProminent).controlSize(.large)
                }
                Text("Creates SDR still photos. Originals stay unchanged. No uploads, accounts or analytics. Visual content is not redacted.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinearGradient(colors: [Color.teal.opacity(0.1), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: close) } }
                .sheet(isPresented: $export) { ExportSheet(urls: model.results.map(\.output)) }
        }.tint(.teal)
    }
}
