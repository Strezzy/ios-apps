import SwiftUI

@MainActor
struct MoonPauseView: View {
    @ObservedObject var store: GameStore
    let open: (GameMode) -> Void
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 30) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("A MOMENT OF STILLNESS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                            .foregroundStyle(MoonTheme.cyan)
                        Text("Rest,\nlightkeeper.")
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundStyle(MoonTheme.ivory)
                        Text(store.progress.currentRealm.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(MoonTheme.gold)
                        Text(store.progress.currentRealm.subtitle)
                            .font(.system(.caption, design: .serif)).italic()
                            .foregroundStyle(MoonTheme.muted)
                        HStack {
                            MoonStat(value: "\(store.progress.clearedRealms.count)/5", caption: "Moonwells")
                            MoonStat(value: "\(Int(store.progress.playSeconds / 60))m", caption: "Journey", accent: MoonTheme.gold)
                        }.padding(.top, 9)
                        if let warning = store.saveWarning {
                            Text(warning).font(.caption2).foregroundStyle(MoonTheme.gold)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                ScrollView(showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        VStack(spacing: 8) {
                            MoonMenuButton(title: "Return to the night", symbol: "play.fill", prominent: true, action: store.resume)
                                .accessibilityIdentifier("pause.resume")
                            MoonMenuButton(title: "Journal & moon map", symbol: "map") { open(.journal) }
                                .accessibilityIdentifier("pause.journal")
                            MoonMenuButton(title: "Starlight upgrades", symbol: "sparkles", accent: MoonTheme.gold) { open(.upgrades) }
                                .accessibilityIdentifier("pause.upgrades")
                            MoonMenuButton(title: "Settings", symbol: "slider.horizontal.3") { open(.settings) }
                                .accessibilityIdentifier("pause.settings")
                            MoonMenuButton(title: "Save & return to title", symbol: "moon", accent: MoonTheme.muted, action: store.returnToTitle)
                                .accessibilityIdentifier("pause.title")
                        }
                    }
                }
                .frame(width: min(270, geometry.size.width * 0.45))
            }
            .padding(24)
            .frame(width: min(650, geometry.size.width), height: min(330, geometry.size.height))
            .moonGlass(radius: 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
struct MoonJournalView: View {
    @ObservedObject var store: GameStore
    let back: () -> Void
    @State private var showGuide = false

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 13) {
                MoonPanelHeader(eyebrow: "The keeper's journal", title: showGuide ? "The art of carrying light" : "Five lights. One sky.", back: back)
                HStack(spacing: 18) {
                    Button("Moon map") { showGuide = false }
                        .foregroundStyle(showGuide ? MoonTheme.muted : MoonTheme.cyan)
                    Button("Field notes") { showGuide = true }
                        .foregroundStyle(showGuide ? MoonTheme.cyan : MoonTheme.muted)
                    Spacer()
                    Text("\(store.progress.clearedRealms.count) / 5 RESTORED")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                        .foregroundStyle(MoonTheme.gold)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .buttonStyle(.plain)
                .frame(minHeight: 30)

                if showGuide {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                            guideNote("Starlight edge", symbol: "sparkles", text: "Tap Strike to weave three sword cuts. Aim with the movement stick. A third strike carries extra force.")
                            guideNote("A step between shadows", symbol: "wind", text: "Dash through danger. Watch the gold stamina line beneath the movement stick, and leave room to recover.")
                            guideNote("Moon pulse", symbol: "moon.stars", text: "Pulse releases a circle of starlight. It spends moon energy, which returns over time. Save it for crowded moments.")
                            guideNote("The sleeping runes", symbol: "diamond", text: "Find three runes in each realm and use Interact beside them. Their light wakes the guardian. Free it, then restore the moonwell.")
                            guideNote("A little company", symbol: "leaf", text: "The amber spirit and Moss travel beside you. You are never walking through this night alone.")
                            guideNote("Keep the flame", symbol: "cross.case", text: "Heal uses a potion. Gather essence from enemies and chests, then spend it on permanent upgrades in the pause menu.")
                            guideNote("Returning home", symbol: "map", text: "Restored moonwells open the next realm. Travel to discovered realms from this map. Milestones save your progress on this iPhone.")
                            guideNote("A gentler journey", symbol: "heart", text: "Gentle journey in Settings reduces incoming damage. You can also reduce effects, turn off screen shake, and swap the touch controls.")
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Realm.allCases) { realm in realmCard(realm) }
                        }
                        .padding(.vertical, 4)
                    }
                    Text("Follow the light: awaken three runes, free the guardian, restore the moonwell.")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(MoonTheme.muted)
                }
            }
            .padding(20)
            .frame(width: min(790, geometry.size.width), height: min(380, geometry.size.height))
            .moonGlass(radius: 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func realmCard(_ realm: Realm) -> some View {
        let unlocked = realm.rawValue <= store.progress.unlockedRealm
        let current = realm == store.progress.currentRealm
        let restored = store.progress.clearedRealms.contains(realm.rawValue)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                ZStack {
                    Circle().fill((restored ? MoonTheme.cyan : MoonTheme.lavender).opacity(unlocked ? 0.12 : 0.05))
                    Image(systemName: restored ? "moon.stars.fill" : unlocked ? "moonphase.waxing.crescent" : "lock.fill")
                        .font(.system(size: 19)).foregroundStyle(unlocked ? MoonTheme.cyan : MoonTheme.muted.opacity(0.5))
                }.frame(width: 38, height: 38)
                Spacer()
                Text(String(format: "%02d", realm.rawValue + 1))
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(MoonTheme.muted)
            }
            Text(realm.title).font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(unlocked ? MoonTheme.ivory : MoonTheme.muted)
            Text(unlocked ? realm.subtitle : "Beyond the sleeping tide")
                .font(.system(size: 10, design: .serif)).italic()
                .foregroundStyle(MoonTheme.muted).frame(height: 26, alignment: .top)
            HStack(spacing: 7) {
                ForEach(0..<3) { index in
                    Image(systemName: store.progress.activatedRunes.contains("\(realm.rawValue)-\(index)") ? "diamond.fill" : "diamond")
                        .font(.system(size: 8)).foregroundStyle(unlocked ? MoonTheme.cyan : MoonTheme.muted.opacity(0.35))
                }
                Spacer()
                if restored { Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(MoonTheme.gold) }
            }
            Button {
                store.travel(to: realm)
            } label: {
                Text(!store.hasSave ? "Begin a journey first" : !unlocked ? "Undiscovered" : "Travel here")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(unlocked ? MoonTheme.cyan : MoonTheme.muted.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(MoonTheme.cyan.opacity(unlocked ? 0.09 : 0.02), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(MoonPressStyle())
            .disabled(!unlocked || !store.hasSave)
            .accessibilityIdentifier("journal.realm.\(realm.rawValue)")
            .accessibilityLabel(unlocked ? "Travel to \(realm.title)" : "\(realm.title), undiscovered")
        }
        .padding(13).frame(width: 144)
        .background(.white.opacity(current ? 0.065 : 0.025), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke((current ? MoonTheme.cyan : MoonTheme.muted).opacity(current ? 0.32 : 0.12), lineWidth: 1))
    }

    private func guideNote(_ title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(MoonTheme.cyan)
                .frame(width: 22).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(.subheadline, design: .serif, weight: .semibold)).foregroundStyle(MoonTheme.ivory)
                Text(text).font(.system(.caption, design: .rounded)).foregroundStyle(MoonTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.trailing, 10)
    }
}

@MainActor
struct MoonUpgradeView: View {
    @ObservedObject var store: GameStore
    let back: () -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                MoonPanelHeader(eyebrow: "Shape the light you carry", title: "Starlight upgrades", back: back)
                HStack {
                    Text("Small promises become lasting strength.")
                        .font(.system(.caption, design: .serif)).italic().foregroundStyle(MoonTheme.muted)
                    Spacer()
                    Label("\(store.progress.essence)", systemImage: "sparkles")
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(MoonTheme.gold)
                }
                ScrollView(showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Upgrade.allCases) { upgrade in upgradeCard(upgrade) }
                    }
                }
            }
            .padding(20)
            .frame(width: min(720, geometry.size.width), height: min(370, geometry.size.height))
            .moonGlass(radius: 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func upgradeCard(_ upgrade: Upgrade) -> some View {
        let level = store.progress.level(upgrade)
        let cost = store.progress.cost(upgrade)
        let color = upgrade == .vitality ? MoonTheme.coral : upgrade == .spirit ? MoonTheme.lavender : MoonTheme.cyan
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: upgrade.symbol).font(.system(size: 23)).foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                Text("\(level) / 4").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(MoonTheme.muted)
            }
            Text(upgrade.title).font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(MoonTheme.ivory).lineLimit(2).minimumScaleFactor(0.8)
            Text(upgrade.detail).font(.system(size: 11, design: .rounded)).foregroundStyle(MoonTheme.muted)
                .frame(height: 32, alignment: .top)
            HStack(spacing: 5) {
                ForEach(0..<4) { index in
                    Capsule().fill(index < level ? color : color.opacity(0.12)).frame(height: 3)
                }
            }
            Button { store.purchase(upgrade) } label: {
                HStack(spacing: 5) {
                    Image(systemName: level == 4 ? "checkmark" : "sparkles")
                    Text(level == 4 ? "Fully awakened" : "Awaken · \(cost)")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(level < 4 && store.progress.essence >= cost ? color : MoonTheme.muted.opacity(0.65))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(MoonPressStyle())
            .disabled(level == 4 || store.progress.essence < cost)
            .accessibilityIdentifier("upgrades.\(upgrade.rawValue)")
            .accessibilityLabel("\(upgrade.title), level \(level) of 4. \(level < 4 ? "Upgrade costs \(cost) essence" : "Maximum level")")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.15), lineWidth: 1))
    }
}

@MainActor
struct MoonSettingsView: View {
    @ObservedObject var store: GameStore
    let back: () -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 13) {
                MoonPanelHeader(eyebrow: "Make the journey yours", title: "Settings", back: back)
                ScrollView {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 13) {
                            sectionLabel("SOUND")
                            volumeRow("Music", symbol: "music.note", keyPath: \.musicVolume)
                            volumeRow("World & combat", symbol: "waveform", keyPath: \.soundVolume)
                            settingToggle("Haptics", detail: "Feel the sword and the moonwells.", keyPath: \.haptics)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("PLAY")
                            settingToggle("Gentle journey", detail: "Reduce incoming damage.", keyPath: \.storyMode)
                            settingToggle("Swap controls", detail: "Movement on the right.", keyPath: \.leftHanded)
                            settingToggle("Screen shake", detail: "A little weight behind each hit.", keyPath: \.screenShake)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("COMFORT")
                            settingToggle("Reduced effects", detail: "Quieter particles and flashes.", keyPath: \.reducedEffects)
                            Text("The interface follows your system preferences for contrast, transparency, and reduced motion.")
                                .font(.system(size: 10, design: .rounded)).foregroundStyle(MoonTheme.muted)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
                            Button("Restore defaults", action: store.resetSettings)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(MoonTheme.cyan)
                                .frame(minHeight: 48)
                                .accessibilityIdentifier("settings.reset")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
                Text("Entirely on your iPhone. No account, advertisements, or in-app purchases.")
                    .font(.system(size: 9, design: .rounded)).foregroundStyle(MoonTheme.muted.opacity(0.8))
            }
            .padding(20)
            .frame(width: min(790, geometry.size.width), height: min(370, geometry.size.height))
            .moonGlass(radius: 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.8)
            .foregroundStyle(MoonTheme.gold).padding(.bottom, 3)
    }
    private func binding<Value>(_ keyPath: WritableKeyPath<GameSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in
            store.settings[keyPath: keyPath] = value
            store.updateSettings()
        })
    }
    private func volumeRow(_ title: String, symbol: String, keyPath: WritableKeyPath<GameSettings, Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(MoonTheme.ivory)
                Spacer()
                Text("\(Int(store.settings[keyPath: keyPath] * 100))%")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(MoonTheme.muted)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            Slider(value: binding(keyPath), in: 0...1).tint(MoonTheme.cyan)
                .accessibilityLabel(title)
        }
    }
    private func settingToggle(_ title: String, detail: String, keyPath: WritableKeyPath<GameSettings, Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: binding(keyPath))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MoonTheme.ivory).tint(MoonTheme.cyan)
                .controlSize(.mini)
                .accessibilityIdentifier("settings.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            Text(detail).font(.system(size: 10, design: .rounded)).foregroundStyle(MoonTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

@MainActor
struct MoonDefeatView: View {
    @ObservedObject var store: GameStore
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                Image(systemName: "moonphase.waning.crescent").font(.system(size: 36))
                    .foregroundStyle(MoonTheme.lavender)
                Text("Even stars need to rest.")
                    .font(.system(size: 29, weight: .semibold, design: .serif)).foregroundStyle(MoonTheme.ivory)
                    .multilineTextAlignment(.center)
                Text("Your light is still here.\nThe runes you awakened remember you.")
                    .font(.system(.subheadline, design: .serif)).foregroundStyle(MoonTheme.muted)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    MoonMenuButton(title: "Rise again", symbol: "arrow.clockwise", prominent: true, action: store.retry)
                        .accessibilityIdentifier("defeat.retry")
                    MoonMenuButton(title: "Return to title", symbol: "moon", accent: MoonTheme.muted, action: store.returnToTitle)
                        .accessibilityIdentifier("defeat.title")
                }
                .frame(maxWidth: 450)
                Text("Tip: dash through a guardian's strike, then answer with starlight.")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(MoonTheme.muted.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: 600)
            .moonGlass(radius: 26)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }
}

@MainActor
struct MoonEndingView: View {
    @ObservedObject var store: GameStore
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 13) {
                HStack(spacing: 13) {
                    ForEach(0..<5) { _ in
                        Image(systemName: "sparkle").font(.system(size: 13)).foregroundStyle(MoonTheme.gold)
                    }
                }
                Text("And the tide came home.")
                    .font(.system(size: 32, weight: .semibold, design: .serif)).foregroundStyle(MoonTheme.ivory)
                    .multilineTextAlignment(.center)
                Text("Aster lowered his sword. Moss planted a seed.\nThe little spirit watched the sunrise, and finally remembered its name.")
                    .font(.system(.subheadline, design: .serif)).foregroundStyle(MoonTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("Hope.").font(.system(.title3, design: .serif)).italic().foregroundStyle(MoonTheme.cyan)
                HStack {
                    MoonStat(value: "5 / 5", caption: "Lights restored")
                    MoonStat(value: "\(store.progress.kills)", caption: "Shadows freed", accent: MoonTheme.gold)
                    MoonStat(value: "\(Int(store.progress.playSeconds / 60))m", caption: "Your journey", accent: MoonTheme.lavender)
                }.padding(.vertical, 7)
                HStack(spacing: 12) {
                    MoonMenuButton(title: "Keep exploring", symbol: "map", prominent: true) {
                        store.travel(to: .moonshore)
                    }.accessibilityIdentifier("ending.explore")
                    MoonMenuButton(title: "Return to title", symbol: "moon", action: store.returnToTitle)
                        .accessibilityIdentifier("ending.title")
                }.frame(maxWidth: 470)
                Text("MOONWAKE  ·  A GAME BY STREZZY")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(2)
                    .foregroundStyle(MoonTheme.muted.opacity(0.8))
            }
            .padding(24).frame(maxWidth: 650)
            .moonGlass(radius: 26).frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }
}

@MainActor
struct MoonDialogueView: View {
    let dialogue: Dialogue
    let advance: () -> Void
    @State private var visibleCharacters = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private var shown: String { String(dialogue.text.prefix(visibleCharacters)) }
    private var complete: Bool { visibleCharacters >= dialogue.text.count }

    var body: some View {
        VStack {
            Spacer()
            Button {
                if complete { advance() } else { visibleCharacters = dialogue.text.count }
            } label: {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 17).fill(MoonTheme.gold.opacity(0.1))
                        MoonPortrait(name: portraitName).frame(width: 49, height: 53)
                    }.frame(width: 65, height: 65)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dialogue.speaker.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                            .foregroundStyle(MoonTheme.gold)
                        Text(shown.isEmpty ? " " : shown)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(MoonTheme.ivory)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 7) {
                        Image(systemName: complete ? "chevron.right" : "ellipsis")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(MoonTheme.cyan)
                        Text("\(dialogue.index + 1)/\(dialogue.lines.count)")
                            .font(.system(size: 8, design: .monospaced)).foregroundStyle(MoonTheme.muted)
                    }.frame(width: 24)
                }
                .padding(20)
                .frame(maxWidth: 720)
                .moonGlass(radius: 23)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dialogue.advance")
            .accessibilityLabel("\(dialogue.speaker). \(dialogue.text)")
            .accessibilityHint("Continue the conversation.")
        }
        .task(id: "\(dialogue.speaker)-\(dialogue.index)-\(dialogue.text)") {
            visibleCharacters = reduceMotion || voiceOver ? dialogue.text.count : 0
            while visibleCharacters < dialogue.text.count {
                do { try await Task.sleep(nanoseconds: 20_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                visibleCharacters += 1
            }
        }
    }

    private var portraitName: String {
        let speaker = dialogue.speaker.lowercased()
        if speaker.contains("moss") { return "moss" }
        if speaker.contains("wisp") || speaker.contains("spirit") { return "wisp" }
        if speaker.contains("aster") { return "hero" }
        return "keeper"
    }
}
