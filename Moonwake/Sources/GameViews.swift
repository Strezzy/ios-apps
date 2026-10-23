import SwiftUI
import SpriteKit

enum MoonTheme {
    static let ink = Color(red: 0.025, green: 0.055, blue: 0.12)
    static let ivory = Color(red: 0.94, green: 0.97, blue: 0.89)
    static let cyan = Color(red: 0.51, green: 0.96, blue: 0.88)
    static let gold = Color(red: 1, green: 0.76, blue: 0.38)
    static let coral = Color(red: 1, green: 0.46, blue: 0.48)
    static let lavender = Color(red: 0.72, green: 0.66, blue: 1)
    static let muted = Color(red: 0.64, green: 0.73, blue: 0.79)
}

@MainActor
struct GameRootView: View {
    @ObservedObject var store: GameStore
    let scene: GameScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var menuOrigin: GameMode = .title
    @State private var confirmNewJourney = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MoonTheme.ink.ignoresSafeArea()
                SpriteView(scene: scene,
                           isPaused: store.mode != .playing && store.mode != .title,
                           preferredFramesPerSecond: store.preferredFPS)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                switch store.mode {
                case .title:
                    MoonTitleView(store: store, begin: beginJourney,
                                  settings: { show(.settings, from: .title) },
                                  journal: { show(.journal, from: .title) })
                case .playing:
                    MoonHUD(store: store, pause: { store.open(.paused) },
                            journal: { show(.journal, from: .paused) })
                case .paused:
                    MoonMenuBackdrop()
                    MoonPauseView(store: store, open: { show($0, from: .paused) })
                        .padding(16)
                case .journal:
                    MoonMenuBackdrop()
                    MoonJournalView(store: store, back: closePanel)
                        .padding(14)
                case .upgrades:
                    MoonMenuBackdrop()
                    MoonUpgradeView(store: store, back: closePanel)
                        .padding(14)
                case .settings:
                    MoonMenuBackdrop()
                    MoonSettingsView(store: store, back: closePanel)
                        .padding(14)
                case .dialogue:
                    if let dialogue = store.dialogue {
                        MoonDialogueView(dialogue: dialogue, advance: store.advanceDialogue)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 20)
                    }
                case .defeated:
                    MoonMenuBackdrop()
                    MoonDefeatView(store: store)
                        .padding(16)
                case .ending:
                    MoonMenuBackdrop()
                    MoonEndingView(store: store)
                        .padding(16)
                }

                if let toast = store.toast, store.mode != .dialogue {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(MoonTheme.ivory)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .moonGlass(radius: 18)
                            .frame(maxWidth: min(geometry.size.width * 0.55, 430))
                            .padding(.bottom, store.mode == .playing ? 145 : 12)
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel(toast)
                    .transition(.opacity)
                }

                if let banner = store.banner, store.mode == .playing {
                    VStack(spacing: 4) {
                        Rectangle().fill(MoonTheme.cyan.opacity(0.6)).frame(width: 42, height: 1)
                        Text(banner).font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(MoonTheme.ivory)
                            .shadow(color: .black, radius: 6)
                        Rectangle().fill(MoonTheme.cyan.opacity(0.6)).frame(width: 42, height: 1)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(MoonTheme.ink.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.mode)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.toast)
            .onChange(of: store.mode) { _, _ in store.input.clear() }
        }
        .preferredColorScheme(.dark)
        .tint(MoonTheme.cyan)
        .persistentSystemOverlays(.hidden)
        .alert("Begin a new journey?", isPresented: $confirmNewJourney) {
            Button("Keep my journey", role: .cancel) {}
            Button("Begin anew", role: .destructive) { store.newGame() }
        } message: {
            Text("Your current journey will be replaced. Settings will be kept.")
        }
    }

    private func beginJourney() {
        if store.hasSave { confirmNewJourney = true } else { store.newGame() }
    }
    private func show(_ mode: GameMode, from origin: GameMode) {
        menuOrigin = origin
        store.open(mode)
    }
    private func closePanel() {
        if menuOrigin == .title { store.returnToTitle() }
        else { store.open(.paused) }
    }
}

struct MoonGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat = 22
    var tint = MoonTheme.ink
    var interactive = false
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(tint, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.17), lineWidth: 1))
        } else {
            content.glassEffect(.regular.tint(tint.opacity(0.42)).interactive(interactive),
                                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

extension View {
    func moonGlass(radius: CGFloat = 22, tint: Color = MoonTheme.ink, interactive: Bool = false) -> some View {
        modifier(MoonGlassModifier(radius: radius, tint: tint, interactive: interactive))
    }
}

struct MoonMenuBackdrop: View {
    var body: some View {
        LinearGradient(colors: [MoonTheme.ink.opacity(0.8), MoonTheme.ink.opacity(0.53)],
                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

struct MoonPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MoonMenuButton: View {
    var title: String
    var symbol: String
    var accent: Color = MoonTheme.cyan
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent).frame(width: 22)
                Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(MoonTheme.ivory)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MoonTheme.muted)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(prominent ? accent.opacity(0.13) : .clear,
                        in: RoundedRectangle(cornerRadius: 15))
            .moonGlass(radius: 15, interactive: true)
        }
        .buttonStyle(MoonPressStyle())
    }
}

struct MoonPanelHeader: View {
    let eyebrow: String
    let title: String
    let back: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2.5).foregroundStyle(MoonTheme.cyan)
                Text(title).font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(MoonTheme.ivory)
            }
            Spacer()
            Button(action: back) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MoonTheme.ivory).frame(width: 48, height: 48)
                    .moonGlass(radius: 24, interactive: true)
            }
            .buttonStyle(MoonPressStyle())
            .accessibilityLabel("Back")
            .accessibilityIdentifier("menu.back")
        }
    }
}

struct MoonStat: View {
    let value: String
    let caption: String
    var accent: Color = MoonTheme.cyan
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title2, design: .monospaced, weight: .medium))
                .foregroundStyle(accent)
            Text(caption.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1).foregroundStyle(MoonTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct MoonProgress: View {
    let fraction: Double
    var color: Color = MoonTheme.cyan
    var height: CGFloat = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var amount: CGFloat { CGFloat(fraction.isFinite ? min(1, max(0, fraction)) : 0) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geometry.size.width * amount))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .linear(duration: 0.14), value: fraction)
        .accessibilityHidden(true)
    }
}

struct SwordGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.81, y: h * 0.02))
        p.addLines([CGPoint(x: w * 0.95, y: h * 0.03), CGPoint(x: w * 0.96, y: h * 0.19),
                    CGPoint(x: w * 0.45, y: h * 0.7), CGPoint(x: w * 0.59, y: h * 0.84),
                    CGPoint(x: w * 0.51, y: h * 0.92), CGPoint(x: w * 0.33, y: h * 0.74),
                    CGPoint(x: w * 0.15, y: h * 0.96), CGPoint(x: w * 0.04, y: h * 0.85),
                    CGPoint(x: w * 0.26, y: h * 0.67), CGPoint(x: w * 0.08, y: h * 0.49),
                    CGPoint(x: w * 0.16, y: h * 0.41), CGPoint(x: w * 0.3, y: h * 0.55)])
        p.closeSubpath()
        return p
    }
}

@MainActor
struct MoonPortrait: View {
    let name: String
    var body: some View {
        Image(uiImage: PixelArt.image(name))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

@MainActor
struct MoonTitleView: View {
    @ObservedObject var store: GameStore
    let begin: () -> Void
    let settings: () -> Void
    let journal: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                LinearGradient(stops: [.init(color: MoonTheme.ink.opacity(0.94), location: 0),
                                       .init(color: MoonTheme.ink.opacity(0.73), location: 0.38),
                                       .init(color: MoonTheme.ink.opacity(0.08), location: 0.75)],
                               startPoint: .leading, endPoint: .trailing).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "moonphase.waning.crescent").font(.system(size: 15))
                            Text("A STARLIGHT ADVENTURE").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.4)
                        }
                        .foregroundStyle(MoonTheme.cyan).padding(.bottom, 9)
                        Text("MOONWAKE")
                            .font(.system(size: min(54, geometry.size.width * 0.065), weight: .black, design: .serif))
                            .tracking(1.8).foregroundStyle(MoonTheme.ivory)
                            .shadow(color: MoonTheme.ink, radius: 16)
                            .accessibilityAddTraits(.isHeader)
                        Text("A small light. A long way home.")
                            .font(.system(.subheadline, design: .serif)).italic()
                            .foregroundStyle(MoonTheme.muted).padding(.top, 4).padding(.bottom, 23)
                        GlassEffectContainer(spacing: 10) {
                            VStack(spacing: 9) {
                                if store.hasSave {
                                    MoonMenuButton(title: "Continue journey", symbol: "play.fill", prominent: true,
                                                   action: store.continueGame)
                                        .accessibilityIdentifier("title.continue")
                                }
                                MoonMenuButton(title: store.hasSave ? "Begin anew" : "Begin journey", symbol: "sparkles",
                                               prominent: !store.hasSave, action: begin)
                                    .accessibilityIdentifier("title.begin")
                                HStack(spacing: 9) {
                                    compactTitleButton("Journal", symbol: "book.closed", action: journal)
                                    compactTitleButton("Settings", symbol: "slider.horizontal.3", action: settings)
                                }
                            }
                        }
                        .frame(maxWidth: 280)
                        Text("FIVE MOONWELLS  ·  ONE LAST PROMISE")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .tracking(1.1).foregroundStyle(MoonTheme.muted.opacity(0.8)).padding(.top, 23)
                        if let warning = store.saveWarning {
                            Text(warning).font(.caption2).foregroundStyle(MoonTheme.gold)
                                .padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 18)
                    .frame(minHeight: geometry.size.height, alignment: .center)
                }
                .frame(width: max(310, geometry.size.width * 0.49))
                .padding(.leading, 26)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("THE NIGHT IS NOT EMPTY.").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.7)
                            Text("It is waiting for you.").font(.system(size: 11, design: .serif)).italic()
                        }
                        .foregroundStyle(MoonTheme.ivory.opacity(0.7))
                        .shadow(color: .black.opacity(0.8), radius: 6)
                    }
                }
                .padding(24).allowsHitTesting(false)
            }
        }
    }

    private func compactTitleButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MoonTheme.ivory.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 48)
                .moonGlass(radius: 14, interactive: true)
        }
        .buttonStyle(MoonPressStyle())
        .accessibilityIdentifier("title.\(title.lowercased())")
    }
}
