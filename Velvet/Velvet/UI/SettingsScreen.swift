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
                            Text("Camera and photos").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("Library") {
                    LabeledContent("Items", value: "\(vault.items.count)")
                    LabeledContent("Original media", value: ByteCountFormatter.string(fromByteCount: vault.items.reduce(0) { $0 + $1.byteCount }, countStyle: .file))
                    Label("Face ID or device passcode", systemImage: "faceid")
                    Label("Locks when backgrounded", systemImage: "lock.shield")
                    Button("Lock now", systemImage: "lock") { model.lock(); model.concealed = false }
                }
                Section("Search") {
                    Text(capability).font(.subheadline)
                    Button {
                        reindexing = true
                        Task { await model.reindex(); reindexing = false; capability = await model.search.capabilityDescription }
                    } label: { HStack { Text(reindexing ? "Updating Search…" : "Update Search"); Spacer(); if reindexing || model.indexing { ProgressView() } } }
                        .disabled(reindexing || model.indexing)
                    Text("Search updates while Velvet is open and unlocked. Video matches use cover images.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Backup") {
                    Button("Encrypted backup and restore", systemImage: "externaldrive.badge.checkmark") { showBackup = true }
                    Text("Your library is excluded from automatic backups. Save an encrypted backup and its recovery key separately.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Label("No accounts, tracking or cloud processing", systemImage: "network.slash")
                    Label("Never saves captures to Apple Photos", systemImage: "photo.badge.checkmark")
                    DisclosureGroup("Privacy details") {
                        Text("Screen recording and mirroring lock Velvet. Screenshots can still be taken.")
                        Text("Velvet cannot protect against a compromised iPhone or control how iOS handles data.")
                        Text("Deleted files are removed from Velvet. Physical erasure from flash storage can’t be guaranteed.")
                        Text("Photo and video export isn’t available yet. Imports leave originals in Apple Photos. iCloud photos may need a download.")
                    }
                }.font(.footnote)
                Section("Build") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3")
                    Text("Camera, video playback and model performance still need testing on a physical iPhone.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").task { capability = await model.search.capabilityDescription }
                .sheet(isPresented: $showBackup) { BackupScreen() }
        }
    }
}
