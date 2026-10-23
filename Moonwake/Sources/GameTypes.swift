import Foundation
import CoreGraphics
import SpriteKit

enum Realm: Int, Codable, CaseIterable, Identifiable {
    case moonshore, briarwild, glassmarsh, emberRuins, eclipseCrown
    var id: Int { rawValue }
    var title: String { ["Moonshore", "Briarwild", "Glassmarsh", "Ember Ruins", "Eclipse Crown"][rawValue] }
    var subtitle: String { ["Where the sea remembers", "A forest holding its breath", "Stars beneath still water", "The embers of an old promise", "The night that forgot to end"][rawValue] }
    var bossName: String { ["The Thornback", "Briar Matriarch", "The Glass Revenant", "The Cinder Warden", "The Hollow Moon"][rawValue] }
    var story: String { [
        "The tide stopped the night the moon broke. Aster wakes on the shore with a sword full of starlight, and a small spirit who remembers his name.",
        "Roots have grown around the second moonwell. Moss remembers this forest. He was made here, before the trees learned fear.",
        "The marsh keeps every star that has ever fallen. Three sleeping runes hold its guardian in a dream.",
        "The old keepers burned their homes to protect the last light. Their promise still glows beneath the ash.",
        "There is no monster inside the moon. Only a keeper who has carried the dark for too long. Bring the light home."
    ][rawValue] }
    var next: Realm? { Realm(rawValue: rawValue + 1) }
}

enum GameMode: String { case title, playing, paused, journal, upgrades, settings, dialogue, defeated, ending }
enum EnemyKind: String, CaseIterable, Codable { case slime, boar, hornet, wraith, knight, boss }
enum Upgrade: String, CaseIterable, Identifiable { case sword, vitality, spirit; var id: String { rawValue }
    var title: String { switch self { case .sword: return "Starlight edge"; case .vitality: return "Keeper's heart"; case .spirit: return "Moon reservoir" } }
    var detail: String { switch self { case .sword: return "Strengthen every sword strike."; case .vitality: return "Gain 25 maximum health."; case .spirit: return "Gain 20 moon energy and stronger pulses." } }
    var symbol: String { switch self { case .sword: return "sparkles"; case .vitality: return "heart.fill"; case .spirit: return "moon.stars.fill" } }
}

struct GameProgress: Codable, Equatable {
    var schema = 1
    var realm = 0
    var unlockedRealm = 0
    var clearedRealms: Set<Int> = []
    var defeatedBosses: Set<Int> = []
    var activatedRunes: Set<String> = []
    var claimedChests: Set<String> = []
    var essence = 0
    var swordLevel = 0
    var vitalityLevel = 0
    var spiritLevel = 0
    var potions = 3
    var kills = 0
    var deaths = 0
    var playSeconds: Double = 0
    var metMoss = false
    var finished = false
    var maxHealth: Double { 100 + Double(vitalityLevel) * 25 }
    var maxEnergy: Double { 100 + Double(spiritLevel) * 20 }
    var swordDamage: Double { 23 + Double(swordLevel) * 7 }
    var currentRealm: Realm { Realm(rawValue: realm) ?? .moonshore }
    func level(_ upgrade: Upgrade) -> Int { switch upgrade { case .sword: return swordLevel; case .vitality: return vitalityLevel; case .spirit: return spiritLevel } }
    func cost(_ upgrade: Upgrade) -> Int { 45 + level(upgrade) * 40 }
    func runeCount(in realm: Realm) -> Int { (0..<3).filter { activatedRunes.contains("\(realm.rawValue)-\($0)") }.count }
    mutating func buy(_ upgrade: Upgrade) -> Bool {
        let price = cost(upgrade)
        guard level(upgrade) < 4, essence >= price else { return false }
        essence -= price
        switch upgrade { case .sword: swordLevel += 1; case .vitality: vitalityLevel += 1; case .spirit: spiritLevel += 1 }
        return true
    }
    mutating func restoreBeacon(in realm: Realm) -> Bool {
        guard defeatedBosses.contains(realm.rawValue), runeCount(in: realm) == 3 else { return false }
        let isNew = clearedRealms.insert(realm.rawValue).inserted
        if isNew { essence += 55 + realm.rawValue * 15; potions = min(5, potions + 2) }
        unlockedRealm = min(4, max(unlockedRealm, realm.rawValue + 1))
        if realm == .eclipseCrown { finished = true }
        return isNew
    }
}

struct GameSettings: Codable, Equatable {
    var musicVolume = 0.55
    var soundVolume = 0.8
    var haptics = true
    var screenShake = true
    var reducedEffects = false
    var leftHanded = false
    var storyMode = false
}

struct Dialogue: Equatable {
    var speaker: String
    var lines: [String]
    var index = 0
    var text: String { lines.isEmpty ? "" : lines[min(index, lines.count - 1)] }
}

@MainActor final class GameInput {
    var movement = CGVector.zero
    var controllerMovement = CGVector.zero
    var attack = false
    var dash = false
    var pulse = false
    var interact = false
    var heal = false
    func clear() { movement = .zero; controllerMovement = .zero; attack = false; dash = false; pulse = false; interact = false; heal = false }
}

struct EnemySpawn { var kind: EnemyKind; var position: CGPoint }
struct WorldMap {
    var root: SKNode
    var size: CGSize
    var walkBounds: CGRect
    var spawn: CGPoint
    var runes: [CGPoint]
    var beacon: CGPoint
    var boss: CGPoint
    var chests: [CGPoint]
    var npc: CGPoint
    var portal: CGPoint
    var enemies: [EnemySpawn]
    var obstacles: [CGRect]
    func canWalk(_ point: CGPoint, radius: CGFloat = 15) -> Bool {
        guard walkBounds.insetBy(dx: radius, dy: radius).contains(point) else { return false }
        return !obstacles.contains { $0.insetBy(dx: -radius, dy: -radius).contains(point) }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint { CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy) }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func int(_ upper: Int) -> Int { Int(next() % UInt64(max(1, upper))) }
}
