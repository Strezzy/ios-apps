import SwiftUI
import CoreGraphics

@MainActor
struct MoonHUD: View {
    @ObservedObject var store: GameStore
    let pause: () -> Void
    let journal: () -> Void

    private var objective: String {
        let realm = store.progress.currentRealm
        if store.progress.clearedRealms.contains(realm.rawValue) {
            return realm == .eclipseCrown ? "Every light has found its way home" : "Follow the moon gate onward"
        }
        let runes = store.progress.runeCount(in: realm)
        if runes < 3 { return "Awaken the sleeping runes  ·  \(runes)/3" }
        if !store.progress.defeatedBosses.contains(realm.rawValue) { return "Free \(realm.bossName)" }
        return "Return to the moonwell"
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 9) {
                            ZStack {
                                Circle().fill(MoonTheme.ink.opacity(0.75))
                                MoonPortrait(name: "hero").frame(width: 26, height: 30)
                            }.frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(MoonTheme.coral)
                                    MoonProgress(fraction: store.health / store.progress.maxHealth, color: MoonTheme.coral, height: 6)
                                    Text("\(max(0, Int(store.health)))")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(MoonTheme.ivory)
                                        .frame(width: 24, alignment: .trailing)
                                }
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkle").font(.system(size: 8)).foregroundStyle(MoonTheme.cyan)
                                    MoonProgress(fraction: store.energy / store.progress.maxEnergy, color: MoonTheme.cyan, height: 4)
                                    Text("\(max(0, Int(store.energy)))")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(MoonTheme.muted)
                                        .frame(width: 24, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .moonGlass(radius: 19)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Health \(Int(store.health)) of \(Int(store.progress.maxHealth)). Moon energy \(Int(store.energy)) of \(Int(store.progress.maxEnergy)).")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.progress.currentRealm.title.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.7)
                                .foregroundStyle(MoonTheme.ivory)
                            Text(objective).font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(MoonTheme.ivory.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 7)
                        .shadow(color: .black.opacity(0.9), radius: 4)
                    }
                    .frame(width: min(230, geometry.size.width * 0.29))

                    Spacer(minLength: 5)

                    if store.bossFraction > 0 {
                        VStack(spacing: 6) {
                            Text(store.bossName).font(.system(size: 12, weight: .semibold, design: .serif))
                                .foregroundStyle(MoonTheme.ivory).lineLimit(1).minimumScaleFactor(0.8)
                            MoonProgress(fraction: store.bossFraction, color: MoonTheme.lavender, height: 5)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(width: min(220, geometry.size.width * 0.25))
                        .moonGlass(radius: 16)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(store.bossName), \(Int(store.bossFraction * 100)) percent health")
                    }

                    Spacer(minLength: 5)

                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Label("\(store.progress.essence)", systemImage: "sparkles")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MoonTheme.gold)
                                .lineLimit(1).minimumScaleFactor(0.75)
                                .frame(maxWidth: 58)
                                .padding(.horizontal, 13).frame(height: 48)
                                .moonGlass(radius: 22)
                                .accessibilityLabel("\(store.progress.essence) starlight essence")
                            topButton("map", label: "Journal and map", identifier: "game.journal", action: journal)
                            topButton("pause.fill", label: "Pause game", identifier: "game.pause", action: pause)
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 8) {
                    if store.settings.leftHanded { actionCluster }
                    else { movementStick }

                    Spacer(minLength: 4)
                    VStack(spacing: 8) {
                        if !store.hint.isEmpty {
                            Text(store.hint)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(MoonTheme.ivory)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .moonGlass(radius: 15)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("game.hint")
                        }
                    }
                    .frame(maxWidth: 250)
                    .padding(.bottom, 14)
                    .allowsHitTesting(false)
                    Spacer(minLength: 4)

                    if store.settings.leftHanded { movementStick }
                    else { actionCluster }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
    }

    private var movementStick: some View {
        VStack(spacing: 8) {
            MoonJoystick(input: store.input)
            MoonProgress(fraction: store.stamina / 100, color: MoonTheme.gold, height: 3)
                .frame(width: 68)
                .accessibilityLabel("Stamina \(Int(store.stamina)) percent")
        }
        .padding(.leading, store.settings.leftHanded ? 0 : 6)
        .padding(.trailing, store.settings.leftHanded ? 6 : 0)
        .padding(.bottom, 5)
    }

    private var actionCluster: some View {
        ZStack {
            MoonActionButton(symbol: "sword", label: "Strike", tint: MoonTheme.cyan, size: 74,
                             identifier: "game.attack", action: store.attack)
                .position(x: 180, y: 76)
            MoonActionButton(symbol: "wind", label: "Dash", tint: MoonTheme.ivory, size: 56,
                             identifier: "game.dash", action: store.dash)
                .position(x: 104, y: 114)
            MoonActionButton(symbol: "sparkles", label: "Pulse", tint: MoonTheme.cyan, size: 56,
                             identifier: "game.pulse", action: store.pulse)
                .position(x: 104, y: 40)
            MoonActionButton(symbol: "hand.tap", label: "Interact", tint: MoonTheme.gold, size: 48,
                             identifier: "game.interact", action: store.interact)
                .opacity(store.hint.isEmpty ? 0.57 : 1)
                .position(x: 33, y: 40)
            ZStack(alignment: .topTrailing) {
                MoonActionButton(symbol: "cross.case.fill", label: "Heal", tint: MoonTheme.coral, size: 48,
                                 identifier: "game.heal", action: store.heal)
                Text("\(store.progress.potions)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(MoonTheme.ivory).padding(4)
                    .background(MoonTheme.ink, in: Circle())
                    .offset(x: 1, y: -3)
                    .allowsHitTesting(false)
            }
            .opacity(store.progress.potions == 0 ? 0.45 : 1)
            .position(x: 33, y: 111)
        }
        .frame(width: 224, height: 152)
    }

    private func topButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MoonTheme.ivory).frame(width: 48, height: 48)
                .moonGlass(radius: 24, interactive: true)
        }
        .buttonStyle(MoonPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

@MainActor
struct MoonJoystick: View {
    let input: GameInput
    @State private var offset = CGSize.zero
    @State private var active = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let diameter: CGFloat = 108
    private let travel: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(reduceTransparency ? MoonTheme.ink : MoonTheme.ink.opacity(0.28))
            Circle().stroke(MoonTheme.ivory.opacity(active ? 0.29 : 0.15), lineWidth: 1)
            Circle().stroke(MoonTheme.ivory.opacity(0.08), lineWidth: 1).padding(17)
            ForEach(0..<4) { index in
                Capsule().fill(MoonTheme.ivory.opacity(0.19))
                    .frame(width: 2, height: 5)
                    .offset(y: -45)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            Circle()
                .fill(MoonTheme.ivory.opacity(0.14))
                .overlay(Circle().stroke(MoonTheme.ivory.opacity(0.33), lineWidth: 1))
                .frame(width: 42, height: 42)
                .overlay(Circle().fill(MoonTheme.cyan.opacity(active ? 0.85 : 0.35)).frame(width: 5, height: 5))
                .offset(offset)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.location.x - diameter / 2
                let dy = value.location.y - diameter / 2
                let distance = hypot(dx, dy)
                let multiplier = distance > travel ? travel / max(1, distance) : 1
                offset = CGSize(width: dx * multiplier, height: dy * multiplier)
                active = true
                if distance < 7 { input.movement = .zero }
                else { input.movement = CGVector(dx: offset.width / travel, dy: -offset.height / travel) }
            }
            .onEnded { _ in reset() })
        .onDisappear(perform: reset)
        .accessibilityLabel("Movement joystick")
        .accessibilityHint("Drag in the direction you want Aster to move.")
        .accessibilityIdentifier("game.joystick")
    }

    private func reset() {
        offset = .zero
        active = false
        input.movement = .zero
    }
}

struct MoonActionButton: View {
    let symbol: String
    let label: String
    let tint: Color
    let size: CGFloat
    let identifier: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if symbol == "sword" {
                    SwordGlyph().fill(tint).frame(width: 30, height: 30)
                        .shadow(color: tint.opacity(0.45), radius: 6)
                } else {
                    Image(systemName: symbol).font(.system(size: size > 50 ? 19 : 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(label.uppercased()).font(.system(size: size > 60 ? 8 : 6, weight: .bold, design: .monospaced))
                    .tracking(0.5).foregroundStyle(MoonTheme.ivory.opacity(0.8))
            }
            .frame(width: size, height: size)
            .moonGlass(radius: size / 2, tint: MoonTheme.ink, interactive: true)
            .overlay(Circle().stroke(tint.opacity(symbol == "sword" ? 0.4 : 0.13), lineWidth: 1))
            .contentShape(Circle())
        }
        .buttonStyle(MoonPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
