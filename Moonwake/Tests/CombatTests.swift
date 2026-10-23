import XCTest
import SpriteKit
@testable import Moonwake

@MainActor final class CombatTests: XCTestCase {
    private func game() -> (GameStore,GameScene) {
        let model=GameStore(repository:SaveRepository(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),audioEnabled:false)
        model.hasSave=true; model.mode = .playing
        let scene=GameScene(store:model); model.scene=scene; scene.begin(realm:.moonshore)
        scene.qaClearEnemies(); return (model,scene)
    }
    func testMovementAndPauseUseTheActualSimulation() {
        let (store,scene)=game(); let start=scene.qaPlayerPosition
        store.input.movement=CGVector(dx:1,dy:0); scene.qaAdvance(seconds:0.3)
        XCTAssertGreaterThan(scene.qaPlayerPosition.x,start.x+20)
        let paused=scene.qaPlayerPosition; store.open(.paused)
        store.input.movement=CGVector(dx:1,dy:0); scene.qaAdvance(seconds:1)
        XCTAssertEqual(scene.qaPlayerPosition,paused)
    }
    func testSwordConnectsAndCooldownBlocksSpam() {
        let (store,scene)=game(); let hero=scene.qaPlayerPosition
        scene.qaSpawnEnemy(.boar,at:CGPoint(x:hero.x+75,y:hero.y))
        let before=scene.qaEnemyHealth
        store.attack(); scene.qaAdvance(seconds:1.0/60)
        XCTAssertLessThan(scene.qaEnemyHealth,before); XCTAssertGreaterThan(scene.qaAttackCooldown,0)
        let after=scene.qaEnemyHealth
        store.attack(); scene.qaAdvance(seconds:1.0/60)
        XCTAssertEqual(scene.qaEnemyHealth,after)
    }
    func testPulseHitsNearbyEnemyAndConsumesLimitedEnergy() {
        let (store,scene)=game(); let hero=scene.qaPlayerPosition
        scene.qaSpawnEnemy(.boar,at:CGPoint(x:hero.x+95,y:hero.y))
        let before=scene.qaEnemyHealth
        store.pulse(); scene.qaAdvance(seconds:1.0/60)
        XCTAssertLessThan(scene.qaEnemyHealth,before)
        XCTAssertLessThan(scene.qaEnergy,70); XCTAssertGreaterThan(scene.qaEnergy,60)
        let energy=scene.qaEnergy
        store.pulse(); scene.qaAdvance(seconds:1.0/60)
        XCTAssertGreaterThanOrEqual(scene.qaEnergy,energy)
    }
    func testDashMovesAndCostsStamina() {
        let (store,scene)=game(); let start=scene.qaPlayerPosition
        store.input.movement=CGVector(dx:1,dy:0); store.dash(); scene.qaAdvance(seconds:0.1)
        XCTAssertGreaterThan(scene.qaPlayerPosition.x,start.x+35)
        XCTAssertLessThan(scene.qaStamina,80)
    }
    func testWorldCollisionCannotBeCrossedAtDashSpeed() {
        let (store,scene)=game(); let world=WorldBuilder.build(realm:.moonshore,completed:false)
        let nearEdge=CGPoint(x:world.walkBounds.minX+25,y:world.spawn.y)
        if scene.qaCanWalk(nearEdge) { scene.qaSetPlayerPosition(nearEdge) }
        store.input.movement=CGVector(dx:-1,dy:0); store.dash(); scene.qaAdvance(seconds:2)
        XCTAssertTrue(scene.qaCanWalk(scene.qaPlayerPosition))
    }
    func testOverlayCannotTakeDamageAndLethalDamageStopsPlay() {
        let (store,scene)=game(); store.open(.paused); scene.qaDamagePlayer(50); XCTAssertEqual(store.health,100)
        store.resume(); scene.qaDamagePlayer(500); XCTAssertEqual(store.mode,.defeated); XCTAssertEqual(store.health,0)
        let deaths=store.progress.deaths; scene.qaAdvance(seconds:2); XCTAssertEqual(store.progress.deaths,deaths)
    }
    func testRealSceneProgressionCanReachFinalEnding() {
        let (store,scene)=game()
        for realm in Realm.allCases {
            store.travel(to:realm); XCTAssertEqual(scene.debugRealm,realm)
            scene.debugAwakenRunes(); XCTAssertEqual(scene.debugBossCount,1)
            scene.debugAwakenRunes(); XCTAssertEqual(scene.debugBossCount,1)
            scene.debugDefeatGuardian(); XCTAssertTrue(store.progress.defeatedBosses.contains(realm.rawValue))
            guard let point=scene.debugLandmark("beacon") else { XCTFail("Missing beacon"); return }
            scene.qaSetPlayerPosition(point); scene.debugInteract()
            XCTAssertTrue(store.progress.clearedRealms.contains(realm.rawValue))
        }
        XCTAssertEqual(store.mode,.ending); XCTAssertTrue(store.progress.finished)
        XCTAssertEqual(store.repository.load()?.finished,true)
    }
}
