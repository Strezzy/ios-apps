import SwiftUI
import UniformTypeIdentifiers

struct BackupScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var recoveryKey = ""
    @State private var restoreKey = ""
    @State private var importing = false
    @State private var recordedKey = false
    @State private var temporaryURL: URL?
    @State private var restored = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Create a backup") {
                    Text("Create an encrypted archive and store its recovery key separately. Anyone with both can decrypt the archive. Velvet cannot recover a lost key.")
                    Button("Prepare encrypted backup") { Task { await prepare() } }.disabled(busy)
                    if busy { ProgressView("Preparing backup…") }
                }
                if !recoveryKey.isEmpty {
                    Section("Recovery key") {
                        Text(recoveryKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Toggle("I have recorded this key separately", isOn: $recordedKey)
                        if let temporaryURL {
                            ShareLink(item: temporaryURL) { Label("Save encrypted archive", systemImage: "square.and.arrow.up") }.disabled(!recordedKey)
                        }
                        Text("The key is shown only in this session. Avoid copying it into a synced clipboard or saving it beside the archive.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Restore a backup") {
                    SecureField("Recovery key", text: $restoreKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Choose encrypted archive") { importing = true }.disabled(busy || restoreKey.isEmpty)
                    Text("Photos and videos are added to your library. Existing items are preserved.").font(.caption).foregroundStyle(.secondary)
                    if restored { Label("Backup restored", systemImage: "checkmark.circle") }
                }
            }.navigationTitle("Encrypted backup").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                    if case .success(let url) = result { Task { await restore(url) } }
                }
                .onDisappear {
                    recoveryKey = ""; restoreKey = ""
                    if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
                }
        }
    }
    private func prepare() async {
        busy = true
        defer { busy = false }
        do {
            let backup = try await vault.createEncryptedBackup()
            guard vault.isUnlocked else { return }
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
            temporaryURL = backup.fileURL
            recoveryKey = backup.recoveryKey; recordedKey = false
        } catch { model.error = error.localizedDescription }
    }
    private func restore(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        busy = true
        defer { busy = false }
        do { try await vault.restoreEncryptedBackup(from: url, recoveryKey: restoreKey); restored = true; restoreKey = "" }
        catch { model.error = "Restore failed. Check the recovery key and archive. Your existing library is preserved." }
    }
}
