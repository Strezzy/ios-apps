import XCTest
import SpriteKit
@testable import Moonwake

final class ProgressTests: XCTestCase {
    func testBeaconCannotBeSkipped() {
        var p = GameProgress()
        XCTAssertFalse(p.restoreBeacon(in: .moonshore))
        p.activatedRunes = ["0-0", "0-1", "0-2"]
        XCTAssertFalse(p.restoreBeacon(in: .moonshore))
        XCTAssertEqual(p.unlockedRealm, 0)
        p.defeatedBosses.insert(0)
        XCTAssertTrue(p.restoreBeacon(in: .moonshore))
        XCTAssertEqual(p.unlockedRealm, 1)
    }
    func testFiveRegionCampaignHasReachableEnding() {
        var p = GameProgress()
        for realm in Realm.allCases {
            XCTAssertGreaterThanOrEqual(p.unlockedRealm, realm.rawValue)
            for rune in 0..<3 { p.activatedRunes.insert("\(realm.rawValue)-\(rune)") }
            p.defeatedBosses.insert(realm.rawValue)
            XCTAssertTrue(p.restoreBeacon(in: realm))
        }
        XCTAssertTrue(p.finished)
        XCTAssertEqual(p.clearedRealms.count, 5)
        XCTAssertEqual(p.unlockedRealm, 4)
    }
    func testRestoringBeaconTwiceDoesNotFarmRewards() {
        var p = GameProgress(); p.activatedRunes = ["0-0", "0-1", "0-2"]; p.defeatedBosses = [0]
        XCTAssertTrue(p.restoreBeacon(in: .moonshore)); let earned = p.essence
        XCTAssertFalse(p.restoreBeacon(in: .moonshore)); XCTAssertEqual(earned, p.essence)
    }
    func testPurchasesRespectCurrencyAndCap() {
        var p = GameProgress(); XCTAssertFalse(p.buy(.sword)); XCTAssertEqual(p.swordLevel, 0)
        p.essence = 10_000
        for kind in Upgrade.allCases {
            for _ in 0..<4 { let before = p.essence; let cost = p.cost(kind); XCTAssertTrue(p.buy(kind)); XCTAssertEqual(p.essence, before - cost) }
            let balance = p.essence; XCTAssertFalse(p.buy(kind)); XCTAssertEqual(p.essence, balance)
        }
        XCTAssertEqual(p.maxHealth, 200); XCTAssertEqual(p.maxEnergy, 180); XCTAssertEqual(p.swordDamage, 51)
    }
    func testRunesDoNotLeakBetweenRealms() {
        var p = GameProgress(); p.activatedRunes = ["0-0", "0-1", "1-2"]
        XCTAssertEqual(p.runeCount(in: .moonshore), 2); XCTAssertEqual(p.runeCount(in: .briarwild), 1)
    }
}

final class SaveTests: XCTestCase {
    private var folder: URL!
    private var repository: SaveRepository!
    override func setUpWithError() throws { folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); repository = SaveRepository(directory: folder) }
    override func tearDownWithError() throws { if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) } }
    func testFullProgressSurvivesRoundTrip() throws {
        var p = GameProgress(); p.realm = 2; p.unlockedRealm = 3; p.essence = 179; p.kills = 21; p.playSeconds = 904
        p.activatedRunes = ["0-0", "0-1", "0-2", "2-1"]; p.defeatedBosses = [0,1]; p.claimedChests = ["0-0"]; p.metMoss = true
        try repository.write(p); XCTAssertEqual(repository.load(), p)
    }
    func testCorruptPrimaryRecoversPreviousValidSave() throws {
        var p = GameProgress(); p.essence = 60; try repository.write(p)
        var later = p; later.essence = 120; try repository.write(later)
        try Data("truncated{".utf8).write(to: repository.saveURL)
        XCTAssertEqual(repository.load(), p)
    }
    func testInvalidSaveCannotReplaceValidJourney() throws {
        let good = GameProgress(); try repository.write(good)
        var invalid = good; invalid.realm = 9; invalid.essence = -5
        XCTAssertThrowsError(try repository.write(invalid)); XCTAssertEqual(repository.load(), good)
    }
    func testSettingsRoundTrip() throws {
        var settings = GameSettings(); settings.storyMode = true; settings.leftHanded = true; settings.musicVolume = 0.25; settings.haptics = false
        try repository.writeSettings(settings); XCTAssertEqual(repository.loadSettings(), settings)
    }
}

@MainActor final class WorldTests: XCTestCase {
    func testEveryWorldHasDistinctUsableGeometryAndReachableObjectives() {
        for realm in Realm.allCases {
            let world = WorldBuilder.build(realm: realm, completed: false)
            XCTAssertEqual(world.runes.count, 3); XCTAssertGreaterThanOrEqual(world.chests.count, 2)
            XCTAssertTrue(world.canWalk(world.spawn), "Invalid spawn in \(realm.title)")
            XCTAssertGreaterThan(world.enemies.count, 5)
            let destinations = world.runes + world.chests + [world.beacon, world.boss, world.npc, world.portal]
            for p in destinations { XCTAssertTrue(world.canWalk(p), "Blocked landmark \(p) in \(realm.title)") }
            let step: CGFloat = 32
            let cols = Int(world.size.width / step) + 1, rows = Int(world.size.height / step) + 1
            func key(_ p: CGPoint) -> Int { Int((p.y / step).rounded()) * cols + Int((p.x / step).rounded()) }
            let start = key(world.spawn); var reached: Set<Int> = [start]; var queue = [start]; var cursor = 0
            while cursor < queue.count {
                let current = queue[cursor]; cursor += 1
                let x = current % cols, y = current / cols
                for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                    let xx=x+dx, yy=y+dy; guard xx>=0, xx<cols, yy>=0, yy<rows else { continue }
                    let next=yy*cols+xx
                    if !reached.contains(next), world.canWalk(CGPoint(x:CGFloat(xx)*step, y:CGFloat(yy)*step)) { reached.insert(next); queue.append(next) }
                }
            }
            for target in destinations {
                let k = key(target)
                XCTAssertTrue(reached.contains(k) || [-1,1,-cols,cols].contains(where: { reached.contains(k+$0) }), "Unreachable objective in \(realm.title): \(target)")
            }
        }
    }
    func testTexturesExistAndKeepCrispPixels() {
        for name in ["hero","moss","wisp","slime","boar","hornet","wraith","knight","boss0","boss1","boss2","boss3","boss4","sword","rune","beacon","chest","portal","keeper"] {
            let t = PixelArt.texture(name)
            XCTAssertGreaterThan(t.size().width, 3); XCTAssertGreaterThan(t.size().height, 3)
            XCTAssertEqual(t.filteringMode, .nearest)
        }
    }
    func testWorldBoundsAndObstaclesStopMovement() {
        let world = WorldBuilder.build(realm: .moonshore, completed: false)
        XCTAssertFalse(world.canWalk(CGPoint(x:-100,y:200)))
        XCTAssertFalse(world.canWalk(CGPoint(x:world.size.width+100,y:200)))
        for obstacle in world.obstacles.prefix(10) { XCTAssertFalse(world.canWalk(CGPoint(x:obstacle.midX,y:obstacle.midY))) }
    }
}

@MainActor final class StoreTests: XCTestCase {
    private func makeStore() -> GameStore { GameStore(repository: SaveRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), audioEnabled: false) }
    func testPauseRejectsCombatInputAndPotionUse() {
        let store=makeStore(); store.hasSave=true; store.mode = .paused; store.health=20
        store.attack(); store.dash(); store.pulse(); store.interact(); store.heal(); store.usePotion()
        XCTAssertFalse(store.input.attack); XCTAssertFalse(store.input.dash); XCTAssertFalse(store.input.pulse); XCTAssertEqual(store.health,20); XCTAssertEqual(store.progress.potions,3)
    }
    func testPotionUseConsumesOnceAndClampsHealth() {
        let store=makeStore(); store.hasSave=true; store.mode = .playing; store.health=90
        store.usePotion(); XCTAssertEqual(store.health,100); XCTAssertEqual(store.progress.potions,2)
        store.usePotion(); XCTAssertEqual(store.progress.potions,2)
    }
    func testTravelCannotSkipLockedAreas() {
        let store=makeStore(); store.travel(to:.eclipseCrown); XCTAssertEqual(store.progress.realm,0)
    }
    func testRuneAndChestRewardsAreIdempotent() {
        let store=makeStore(); store.hasSave=true
        store.activateRune(index:0,realm:.moonshore); store.activateRune(index:0,realm:.moonshore)
        XCTAssertEqual(store.progress.essence,12)
        store.claimChest(index:0,realm:.moonshore); store.claimChest(index:0,realm:.moonshore)
        XCTAssertEqual(store.progress.essence,47)
    }
    func testDeathAndRetryPreserveProgress() {
        let store=makeStore(); store.hasSave=true; store.mode = .playing; store.progress.essence=70; store.progress.activatedRunes=["0-0"]
        store.defeat(); store.defeat(); XCTAssertEqual(store.progress.deaths,1); XCTAssertEqual(store.mode,.defeated)
        store.retry(); XCTAssertEqual(store.health,100); XCTAssertEqual(store.progress.essence,70); XCTAssertEqual(store.progress.activatedRunes,["0-0"])
    }
    func testEndingRequiresFinalRestoredMoonwell() {
        let store=makeStore(); store.hasSave=true; store.progress.realm=4; store.progress.unlockedRealm=4
        store.lightBeacon(in:.eclipseCrown); XCTAssertNotEqual(store.mode,.ending)
        store.progress.activatedRunes=["4-0","4-1","4-2"]; store.progress.defeatedBosses=[4]
        store.lightBeacon(in:.eclipseCrown); XCTAssertEqual(store.mode,.ending); XCTAssertTrue(store.progress.finished)
    }
}
