import SwiftUI

struct OrbitSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: MediaLibrary
    @AppStorage("orbit.appearance") private var appearance = "system"
    @AppStorage("orbit.defaultDepth") private var defaultDepth = 0.65
    @AppStorage("orbit.autoLoop") private var autoLoop = true
    @AppStorage("orbit.motionEnabled") private var motionEnabled = true
    var body: some View {
        NavigationStack {
            ZStack {
                OrbitAtmosphere()
                ScrollView {
                    VStack(spacing: 19) {
                        HStack(spacing: 18) {
                            OrbitMark(size: 72)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Orbit").font(.system(.largeTitle, design: .rounded, weight: .bold))
                                Text("A new perspective").font(.subheadline).foregroundStyle(.secondary)
                                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(.vertical, 7)
                        OrbitCard {
                            Text("Make it yours").font(.headline)
                            Picker("Appearance", selection: $appearance) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }.pickerStyle(.segmented)
                            Toggle("Tilt to look around", isOn: $motionEnabled)
                            Toggle("Loop videos", isOn: $autoLoop)
                            Divider()
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Default depth").font(.subheadline)
                                    Spacer()
                                    Text("\(Int(defaultDepth * 100))%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Slider(value: $defaultDepth, in: 0...1).accessibilityLabel("Default depth strength")
                            }
                        }
                        OrbitCard {
                            Label("On your device", systemImage: "lock.shield").font(.headline)
                            Text("Orbit keeps its own local copy of each video, with no account, ads or uploads. You choose which videos to open.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Text("\(library.videos.count) videos")
                                Spacer()
                                Text(OrbitFormat.bytes(library.totalBytes)).monospacedDigit()
                            }.font(.subheadline)
                            Text("Opening a video stored in iCloud may download it through Photos or Files. Removing a video from Orbit leaves your original untouched.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        OrbitCard {
                            Label("A little movement goes a long way", systemImage: "cube.transparent").font(.headline)
                            Text("Open a spatial video recorded on iPhone. Hold your phone comfortably, tap Recenter, then tilt gently left, right, up or down. Dragging the picture works too.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Orbit reconstructs motion depth from the two recorded views. Fine edges, reflections and newly revealed areas may show artifacts. Regular videos play in 2D.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Reduce Motion turns tilt off initially. You can enable it for a video using the Tilt control.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
