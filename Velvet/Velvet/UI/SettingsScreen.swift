import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var model: AppModel
    @State private var capability = "Checking local model…"
    @State private var reindexing = false
    @State private var showBackup = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image("Brand").resizable().frame(width: 62, height: 62).clipShape(.rect(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Velvet").font(.system(.title2, design: .serif))
                            Text("Private by design.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("Your vault") {
                    LabeledContent("Items", value: "\(vault.items.count)")
                    LabeledContent("Original media", value: ByteCountFormatter.string(fromByteCount: vault.items.reduce(0) { $0 + $1.byteCount }, countStyle: .file))
                    Label("Face ID or device passcode", systemImage: "faceid")
                    Label("Locks when backgrounded", systemImage: "lock.shield")
                    Button("Lock now", systemImage: "lock") { model.lock(); model.concealed = false }
                }
                Section("Local intelligence") {
                    Text(capability).font(.subheadline)
                    Button {
                        reindexing = true
                        Task { await model.reindex(); reindexing = false; capability = await model.search.capabilityDescription }
                    } label: { HStack { Text(reindexing ? "Indexing on this iPhone…" : "Reindex library"); Spacer(); if reindexing || model.indexing { ProgressView() } } }
                        .disabled(reindexing || model.indexing)
                    Text("Indexing runs only while Velvet is open and unlocked. Videos are searched by their cover image, not individual moments.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Backup") {
                    Button("Encrypted backup and restore", systemImage: "externaldrive.badge.checkmark") { showBackup = true }
                    Text("Vault contents are excluded from automatic backups. Keep an explicit encrypted backup and its separate recovery key to recover your library.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy, plainly") {
                    Label("No accounts, analytics or cloud inference", systemImage: "network.slash")
                    Label("Never saves captures to Apple Photos", systemImage: "photo.badge.checkmark")
                    Text("Screen recording and mirroring conceal and lock Velvet. iOS screenshots cannot be universally prevented. Device compromise and operating-system internals are outside Velvet's control.")
                    Text("Deleting removes Velvet-managed files and records. Flash-storage wear leveling means physical secure erasure cannot be guaranteed.")
                    Text("There is no plaintext export in this release. Photos imports leave the originals in Photos; Apple's picker may retrieve an iCloud asset.")
                }.font(.footnote)
                Section("Build") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                    Text("Early access · Camera, secure video playback and model performance need physical iPhone validation. See the repository's verification report before trusting this release with irreplaceable media.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").task { capability = await model.search.capabilityDescription }
                .sheet(isPresented: $showBackup) { BackupScreen() }
        }
    }
}
