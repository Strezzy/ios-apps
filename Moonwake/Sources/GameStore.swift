import Foundation
import SwiftUI
import UIKit

/// Versioned, atomic local saves. A previous valid save is retained for recovery.
struct SaveRepository {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Moonwake", isDirectory: true)
    }
    var saveURL: URL { directory.appendingPathComponent("journey-v1.json") }
    var backupURL: URL { directory.appendingPathComponent("journey-v1.backup.json") }
    var settingsURL: URL { directory.appendingPathComponent("settings-v1.json") }
    func load() -> GameProgress? {
        for url in [saveURL, backupURL] {
            guard let data = try? Data(contentsOf: url), let progress = try? JSONDecoder().decode(GameProgress.self, from: data), valid(progress) else { continue }
            return progress
        }
        return nil
    }
    func valid(_ p: GameProgress) -> Bool {
        p.schema == 1 && (0...4).contains(p.realm) && (0...4).contains(p.unlockedRealm) && p.realm <= p.unlockedRealm &&
        (0...4).contains(p.swordLevel) && (0...4).contains(p.vitalityLevel) && (0...4).contains(p.spiritLevel) &&
        p.essence >= 0 && (0...5).contains(p.potions) && p.playSeconds.isFinite && p.playSeconds >= 0 &&
        p.clearedRealms.allSatisfy { (0...4).contains($0) } && p.defeatedBosses.allSatisfy { (0...4).contains($0) }
    }
    func write(_ progress: GameProgress) throws {
        guard valid(progress) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(progress)
        if let previous = try? Data(contentsOf: saveURL), let p = try? JSONDecoder().decode(GameProgress.self, from: previous), valid(p) {
            try previous.write(to: backupURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        try encoded.write(to: saveURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    func loadSettings() -> GameSettings {
        guard let bytes = try? Data(contentsOf: settingsURL), var settings = try? JSONDecoder().decode(GameSettings.self, from: bytes) else { return GameSettings() }
        settings.musicVolume = settings.musicVolume.isFinite ? min(1, max(0, settings.musicVolume)) : 0.55
        settings.soundVolume = settings.soundVolume.isFinite ? min(1, max(0, settings.soundVolume)) : 0.8
        return settings
    }
    func writeSettings(_ settings: GameSettings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: settingsURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

@MainActor final class GameStore: ObservableObject {
    @Published var mode: GameMode = .title
    @Published var progress: GameProgress
    @Published var settings: GameSettings
    @Published var health = 100.0
    @Published var energy = 100.0
    @Published var stamina = 100.0
    @Published var bossName = ""
    @Published var bossFraction = 0.0
    @Published var hint = ""
    @Published var toast: String?
    @Published var dialogue: Dialogue?
    @Published var banner: String?
    @Published var hasSave = false
    @Published var saveWarning: String?
    @Published var preferredFPS = 60
    let input = GameInput()
    let services: GameServices
    weak var scene: GameScene?
    let repository: SaveRepository
    private var observers: [NSObjectProtocol] = []
    private var toastTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?

    init(repository: SaveRepository = SaveRepository(), audioEnabled: Bool = true) {
        self.repository = repository
        let previous = repository.load()
        progress = previous ?? GameProgress()
        settings = repository.loadSettings()
        hasSave = previous != nil
        services = GameServices(enabled: audioEnabled)
        restoreVitals()
        services.update(settings: settings)
        services.bindControls(to: self)
        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            })
        }
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updatePerformanceBudget() }
            })
        }
        updatePerformanceBudget()
        autosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self else { break }
                if self.hasSave, self.mode == .playing { self.save() }
            }
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        autosaveTask?.cancel(); toastTask?.cancel(); bannerTask?.cancel()
    }

    func newGame() {
        input.clear(); progress = GameProgress(); hasSave = true
        bossName = ""; bossFraction = 0; hint = ""; dialogue = nil
        restoreVitals(); save(); scene?.begin(realm: .moonshore)
        mode = .playing; services.playMusic(realm: .moonshore)
        if !ProcessInfo.processInfo.arguments.contains("--skip-intro") {
            speak("Wisp", lines: ["Aster… you're awake. The sea has gone quiet. Even the moon has stopped moving.", "Your sword still remembers the light. Find the three sleeping runes, face the guardian, and wake this moonwell.", "I'll stay with you. Move with the left thumbstick. Strike with the sword, dash through danger, and send a moonpulse when the shadows gather."])
        }
        showBanner("MOONSHORE\nWhere the sea remembers")
    }

    func continueGame() {
        guard hasSave else { newGame(); return }
        if let p = repository.load() { progress = p }
        input.clear(); restoreVitals(); dialogue = nil
        scene?.begin(realm: progress.currentRealm); mode = .playing
        services.playMusic(realm: progress.currentRealm)
        showBanner(progress.currentRealm.title.uppercased())
    }

    func resume() { input.clear(); dialogue = nil; mode = .playing; services.startMusic() }
    func open(_ next: GameMode) {
        input.clear(); mode = next
        services.play(.menu)
        if hasSave { save() }
    }
    func returnToTitle() {
        if hasSave { save() }
        input.clear(); dialogue = nil; bossFraction = 0; hint = ""; banner = nil
        mode = .title; scene?.showTitleScene(); services.playMusic(realm: .moonshore)
    }
    func retry() {
        input.clear(); restoreVitals(); bossFraction = 0; dialogue = nil
        scene?.begin(realm: progress.currentRealm); mode = .playing
        services.playMusic(realm: progress.currentRealm)
        notify("The moonwell holds your progress. Try again.")
    }
    func travel(to realm: Realm) {
        guard realm.rawValue <= progress.unlockedRealm else { notify("Wake the previous moonwell to open this path."); return }
        input.clear(); progress.realm = realm.rawValue; bossFraction = 0; dialogue = nil
        restoreVitals(); save(); scene?.begin(realm: realm); mode = .playing
        services.playMusic(realm: realm)
        showBanner("\(realm.title.uppercased())\n\(realm.subtitle)")
    }
    func purchase(_ upgrade: Upgrade) {
        guard progress.buy(upgrade) else { notify(progress.level(upgrade) >= 4 ? "This gift is fully awakened." : "Gather more stardust to awaken this gift."); return }
        restoreVitals(); save(); services.play(.reward); services.haptic(.success)
        notify("\(upgrade.title) awakened · level \(progress.level(upgrade))")
    }
    func save() {
        guard hasSave else { return }
        do { try repository.write(progress); saveWarning = nil }
        catch { saveWarning = "Your journey could not be saved. Free some storage and try again from Pause." }
    }
    func notify(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }; self?.toast = nil
        }
    }
    func showBanner(_ message: String) {
        bannerTask?.cancel(); banner = message
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }; self?.banner = nil
        }
    }
    func speak(_ speaker: String, lines: [String]) {
        guard !lines.isEmpty else { return }
        input.clear(); dialogue = Dialogue(speaker: speaker, lines: lines); mode = .dialogue
    }
    func advanceDialogue() {
        guard var next = dialogue else { resume(); return }
        next.index += 1
        if next.index < next.lines.count { dialogue = next; services.play(.menu) }
        else { dialogue = nil; mode = .playing; input.clear(); if hasSave { save() } }
    }
    func defeat() {
        guard mode == .playing else { return }
        input.clear(); progress.deaths += 1; health = 0; save()
        mode = .defeated; services.play(.defeat); services.haptic(.warning)
    }
    func completeGame() {
        input.clear(); progress.finished = true; save(); mode = .ending
        services.play(.victory); services.playMusic(realm: .moonshore); services.haptic(.success)
    }
    func restoreVitals() { health = progress.maxHealth; energy = progress.maxEnergy; stamina = 100 }
    func activateRune(index: Int, realm: Realm) {
        guard (0..<3).contains(index) else { return }
        guard progress.activatedRunes.insert("\(realm.rawValue)-\(index)").inserted else { return }
        progress.essence += 12; energy = min(progress.maxEnergy, energy + 30)
        save(); services.play(.rune); services.haptic(.success)
        let count = progress.runeCount(in: realm)
        notify(count == 3 ? "All three runes awake. The guardian is waiting." : "Moon rune \(count) of 3 awakened · +12 stardust")
    }
    func defeatBoss(in realm: Realm) {
        guard progress.defeatedBosses.insert(realm.rawValue).inserted else { return }
        progress.essence += 70 + realm.rawValue * 20; progress.kills += 1
        bossFraction = 0; restoreVitals(); save(); services.play(.victory); services.haptic(.success)
        services.playMusic(realm: realm)
        notify("\(realm.bossName) is free. Wake the moonwell.")
    }
    func lightBeacon(in realm: Realm) {
        guard progress.restoreBeacon(in: realm) else {
            if progress.clearedRealms.contains(realm.rawValue) { restoreVitals(); notify("Restored at the moonwell. Your journey is saved."); save() }
            else { notify("Awaken all three runes and free the guardian first.") }
            return
        }
        restoreVitals(); save(); services.play(.rune); services.haptic(.success)
        if realm == .eclipseCrown { completeGame() }
        else { notify("Moonwell restored. A new path opens to \(realm.next?.title ?? "the dawn").") }
    }
    func claimChest(index: Int, realm: Realm) {
        let key = "\(realm.rawValue)-\(index)"
        guard progress.claimedChests.insert(key).inserted else { return }
        progress.essence += 35; progress.potions = min(5, progress.potions + 1)
        save(); services.play(.reward); services.haptic(.success); notify("A keeper's cache · +35 stardust and a moon vial")
    }
    func addEssence(_ amount: Int) { guard amount > 0 else { return }; progress.essence += amount }
    func usePotion() {
        guard mode == .playing else { return }
        guard progress.potions > 0 else { notify("No moon vials left. Search for keeper caches."); return }
        guard health < progress.maxHealth else { notify("Your heart is already full."); return }
        progress.potions -= 1; health = min(progress.maxHealth, health + progress.maxHealth * 0.65)
        save(); services.play(.rune); services.haptic(.success)
    }
    func updateSettings() { services.update(settings: settings); try? repository.writeSettings(settings); scene?.syncSettings(); updatePerformanceBudget() }
    func resetSettings() { settings = GameSettings(); updateSettings() }
    func attack() { if mode == .playing { input.attack = true } }
    func dash() { if mode == .playing { input.dash = true } }
    func pulse() { if mode == .playing { input.pulse = true } }
    func interact() { if mode == .playing { input.interact = true } }
    func heal() { if mode == .playing { input.heal = true } }
    func suspend() {
        if mode == .playing { mode = .paused }
        input.clear(); services.stopMusic(); if hasSave { save() }
    }
    private func updatePerformanceBudget() {
        let state = ProcessInfo.processInfo.thermalState
        preferredFPS = ProcessInfo.processInfo.isLowPowerModeEnabled || state == .serious || state == .critical ? 30 : 60
    }
}
