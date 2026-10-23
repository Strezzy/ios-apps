import AVFoundation
import GameController
import UIKit

enum SoundCue: String, CaseIterable { case sword, hit, dash, pulse, rune, reward, hurt, defeat, victory, menu, step }
enum FeedbackKind { case light, medium, heavy, success, warning }

@MainActor final class GameServices {
    private let enabled: Bool
    private var settings = GameSettings()
    private var music: AVAudioPlayer?
    private var musicName = "moonshore"
    private var effects: [SoundCue: [AVAudioPlayer]] = [:]
    private var effectIndex: [SoundCue: Int] = [:]
    private var observers: [NSObjectProtocol] = []
    private weak var store: GameStore?
    private var heldKeys: Set<Int> = []
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    init(enabled: Bool = true) {
        self.enabled = enabled
        if enabled {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { Task { @MainActor in self?.store?.suspend() } }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func update(settings: GameSettings) {
        self.settings = settings
        music?.setVolume(Float(settings.musicVolume), fadeDuration: 0.3)
    }
    private func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio") ?? Bundle.main.url(forResource: name, withExtension: "wav")
    }
    func play(_ cue: SoundCue) {
        guard enabled, settings.soundVolume > 0 else { return }
        if effects[cue] == nil, let asset = url(cue.rawValue) {
            effects[cue] = (0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf: asset) }
            effects[cue]?.forEach { $0.prepareToPlay() }
        }
        guard let pool = effects[cue], !pool.isEmpty else { return }
        let index = (effectIndex[cue] ?? 0) % pool.count
        let player = pool[index]; player.currentTime = 0; player.volume = Float(settings.soundVolume) * 0.7
        player.play(); effectIndex[cue] = index + 1
    }
    func playMusic(realm: Realm, tense: Bool = false) {
        let selected = tense ? "guardian" : ["moonshore", "briarwild", "glassmarsh", "ember", "eclipse"][realm.rawValue]
        if musicName == selected, music != nil { startMusic(); return }
        musicName = selected
        guard enabled, let asset = url(selected) else { return }
        music?.stop()
        music = try? AVAudioPlayer(contentsOf: asset)
        music?.numberOfLoops = -1; music?.volume = Float(settings.musicVolume)
        music?.prepareToPlay(); music?.play()
    }
    func startMusic() {
        guard enabled else { return }
        if music == nil, let asset = url(musicName) {
            music = try? AVAudioPlayer(contentsOf: asset)
            music?.numberOfLoops = -1; music?.volume = Float(settings.musicVolume)
        }
        music?.play()
    }
    func stopMusic() { music?.pause(); effects.values.flatMap { $0 }.forEach { $0.stop() } }
    func haptic(_ kind: FeedbackKind) {
        guard enabled, settings.haptics else { return }
        switch kind {
        case .light: light.impactOccurred(intensity: 0.55)
        case .medium: medium.impactOccurred(intensity: 0.7)
        case .heavy: heavy.impactOccurred(intensity: 0.85)
        case .success: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        }
    }

    func bindControls(to store: GameStore) {
        self.store = store
        for name in [NSNotification.Name.GCControllerDidConnect, NSNotification.Name.GCKeyboardDidConnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.connectInputs() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store?.input.controllerMovement = .zero }
        })
        connectInputs()
    }
    private func connectInputs() {
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
                Task { @MainActor in self?.store?.input.controllerMovement = CGVector(dx: CGFloat(x), dy: CGFloat(y)) }
            }
            pad.dpad.valueChangedHandler = { [weak self] _, x, y in
                Task { @MainActor in self?.store?.input.controllerMovement = CGVector(dx: CGFloat(x), dy: CGFloat(y)) }
            }
            bind(pad.buttonX) { $0.attack() }; bind(pad.buttonA) { $0.dash() }
            bind(pad.buttonY) { $0.pulse() }; bind(pad.buttonB) { $0.interact() }
            bind(pad.leftShoulder) { $0.heal() }
            bind(pad.rightShoulder) { $0.attack() }
            bind(pad.buttonMenu) { model in if model.mode == .playing { model.open(.paused) } else if model.mode == .paused { model.resume() } }
        }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] _, _, key, pressed in
            Task { @MainActor in self?.keyChanged(key, pressed: pressed) }
        }
    }
    private func bind(_ button: GCControllerButtonInput, action: @escaping @MainActor (GameStore) -> Void) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in guard let store = self?.store else { return }; action(store) }
        }
    }
    private func keyChanged(_ key: GCKeyCode, pressed: Bool) {
        guard let store else { return }
        if pressed { heldKeys.insert(key.rawValue) } else { heldKeys.remove(key.rawValue) }
        func down(_ key: GCKeyCode) -> CGFloat { heldKeys.contains(key.rawValue) ? 1 : 0 }
        let x = down(.keyD) + down(.rightArrow) - down(.keyA) - down(.leftArrow)
        let y = down(.keyW) + down(.upArrow) - down(.keyS) - down(.downArrow)
        let length = max(1, hypot(x, y))
        store.input.controllerMovement = CGVector(dx: x / length, dy: y / length)
        guard pressed else { return }
        switch key {
        case .spacebar: store.attack()
        case .leftShift, .rightShift: store.dash()
        case .keyQ: store.pulse()
        case .keyE: if store.mode == .dialogue { store.advanceDialogue() } else { store.interact() }
        case .keyF: store.heal()
        case .escape: if store.mode == .playing { store.open(.paused) } else if store.mode == .paused { store.resume() }
        default: break
        }
    }
}
