import SpriteKit
import UIKit

/// The entire adventure runs locally in a single SpriteKit scene. Combat uses an explicit
/// simulation clock; SKActions are used only for disposable visual effects, never damage.
@MainActor
final class GameScene: SKScene {
    private weak var store: GameStore?
    private var realm: Realm = .moonshore
    private var world: WorldMap?
    private let worldLayer = SKNode()
    private let effects = SKNode()
    private let cameraRig = SKCameraNode()
    private let hero = SKNode()
    private var heroImage = SKSpriteNode()
    private var blade = SKSpriteNode()
    private let bladePivot = SKNode()
    private var wisp = SKSpriteNode()
    private var moss = SKSpriteNode()
    private var structures: [Landmark] = []
    private var creatures: [Creature] = []
    private var projectiles: [Shot] = []
    private var pickups: [Pickup] = []
    private var arrow = SKNode()
    private var previousTime: TimeInterval = 0
    private var age: Double = 0
    private var uiTimer: Double = 0
    private var saveTimer: Double = 0
    private var walkTime: Double = 0
    private var swordTimer: Double = 0
    private var attackCooldown: Double = 0
    private var comboTimer: Double = 0
    private var combo = 0
    private var dashTimer: Double = 0
    private var dashCooldown: Double = 0
    private var pulseCooldown: Double = 0
    private var invulnerability: Double = 0
    private var hitStop: Double = 0
    private var companionTimer: Double = 0
    private var mossTimer: Double = 0
    private var ambientTimer: Double = 0
    private var localEnergy: Double = 100
    private var localStamina: Double = 100
    private var facing = CGVector(dx: 1, dy: 0)
    private var dashDirection = CGVector(dx: 1, dy: 0)
    private var cameraShake: CGFloat = 0
    private var bossMusic = false
    private var titleScene = true
    private var lastMode: GameMode = .title
    private var random = SeededRandom(seed: 8129)
    private static var haloTexture: SKTexture?

    init(store: GameStore) {
        self.store = store
        super.init(size: CGSize(width: 1024, height: 576))
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.025, green: 0.045, blue: 0.105, alpha: 1)
        addChild(worldLayer)
        addChild(cameraRig)
        camera = cameraRig
        cameraRig.setScale(1)
        showTitleScene()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("Moonwake constructs its scene in Swift.") }

    override func didMove(to view: SKView) {
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.preferredFramesPerSecond = store?.preferredFPS ?? 60
        previousTime = 0
    }

    override func didChangeSize(_ oldSize: CGSize) { updateCamera(dt: 1, snap: true) }

    func begin(realm: Realm) {
        titleScene = false
        build(realm: realm)
        store?.services.playMusic(realm: realm)
        store?.showBanner("\(realm.title.uppercased())\n\(realm.subtitle)")
        updateCamera(dt: 1, snap: true)
    }

    func showTitleScene() {
        titleScene = true
        build(realm: .moonshore)
        creatures.forEach { $0.node.removeFromParent() }
        creatures.removeAll()
        updateCamera(dt: 1, snap: true)
    }

    func syncSettings() {
        guard let store else { return }
        localEnergy = min(store.progress.maxEnergy, max(0, store.energy))
        localStamina = min(100, max(0, store.stamina))
        cameraShake = 0
        world?.root.childNode(withName: "ambientEffects")?.isHidden = store.settings.reducedEffects
    }

    private func build(realm: Realm) {
        guard let store else { return }
        self.realm = realm
        worldLayer.removeAllActions()
        worldLayer.removeAllChildren()
        hero.removeAllActions()
        hero.removeAllChildren()
        hero.removeFromParent()
        bladePivot.removeAllChildren()
        bladePivot.removeFromParent()
        effects.removeAllChildren()
        effects.removeFromParent()
        arrow.removeAllChildren()
        arrow.removeFromParent()
        structures.removeAll()
        creatures.removeAll()
        projectiles.removeAll()
        pickups.removeAll()
        previousTime = 0; age = 0; uiTimer = 0; saveTimer = 0; walkTime = 0
        swordTimer = 0; attackCooldown = 0; comboTimer = 0; combo = 0
        dashTimer = 0; dashCooldown = 0; pulseCooldown = 0; invulnerability = 2
        hitStop = 0; companionTimer = 0.6; mossTimer = 1.5; ambientTimer = 0
        localEnergy = store.progress.maxEnergy; localStamina = 100
        facing = CGVector(dx: 1, dy: 0); cameraShake = 0; bossMusic = false
        random = SeededRandom(seed: UInt64(8129 + realm.rawValue * 1777))
        store.bossName = ""; store.bossFraction = 0; store.hint = ""
        store.energy = localEnergy; store.stamina = localStamina
        let map = WorldBuilder.build(realm: realm, completed: store.progress.clearedRealms.contains(realm.rawValue))
        world = map
        worldLayer.addChild(map.root)
        effects.zPosition = 300
        worldLayer.addChild(effects)

        hero.position = map.spawn
        hero.zPosition = -hero.position.y / 100
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 42, height: 14))
        shadow.fillColor = .black.withAlphaComponent(0.32); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -5); shadow.zPosition = -2
        hero.addChild(shadow)
        let aura = glow(color: cyan, size: 130, alpha: 0.23)
        aura.position = CGPoint(x: 12, y: 15); aura.zPosition = -1
        hero.addChild(aura)
        heroImage = makeSprite("hero", scale: 1.8)
        heroImage.position = CGPoint(x: 0, y: 25)
        hero.addChild(heroImage)
        blade = makeSprite("sword", scale: 1.65)
        blade.anchorPoint = CGPoint(x: 0.12, y: 0.5)
        blade.position = CGPoint(x: 8, y: 0)
        let bladeLight = glow(color: cyan, size: 110, alpha: 0.62)
        bladeLight.xScale = 1.3; bladeLight.yScale = 0.4
        bladeLight.position = CGPoint(x: 46, y: 0); bladeLight.zPosition = -1
        blade.addChild(bladeLight)
        bladePivot.position = CGPoint(x: 9, y: 20)
        bladePivot.zRotation = -0.22; bladePivot.zPosition = 2
        bladePivot.addChild(blade); hero.addChild(bladePivot)
        worldLayer.addChild(hero)

        wisp = makeSprite("wisp", scale: 1.65)
        wisp.position = map.spawn + CGVector(dx: -74, dy: 43)
        let wispLight = glow(color: amber, size: 96, alpha: 0.5)
        wispLight.zPosition = -1; wisp.addChild(wispLight)
        worldLayer.addChild(wisp)
        moss = makeSprite("moss", scale: 1.75)
        moss.position = map.spawn + CGVector(dx: 87, dy: -8)
        worldLayer.addChild(moss)

        for (index, point) in map.runes.enumerated() { addLandmark(.rune(index), at: point) }
        addLandmark(.beacon, at: map.beacon)
        for (index, point) in map.chests.enumerated() { addLandmark(.chest(index), at: point) }
        addLandmark(.keeper, at: map.npc)
        addLandmark(.portal, at: map.portal)
        if !titleScene {
            for (index, spawn) in map.enemies.enumerated() {
                guard !store.progress.clearedRealms.contains(realm.rawValue) || index % 3 == 0 else { continue }
                spawnCreature(spawn.kind, at: spawn.position)
            }
            ensureBoss()
        }
        buildArrow()
        refreshLandmarks()
        world?.root.childNode(withName: "ambientEffects")?.isHidden = store.settings.reducedEffects
    }

    private var cyan: UIColor { UIColor(red: 0.50, green: 1, blue: 0.90, alpha: 1) }
    private var amber: UIColor { UIColor(red: 1, green: 0.73, blue: 0.26, alpha: 1) }
    private var danger: UIColor { UIColor(red: 1, green: 0.38, blue: 0.40, alpha: 1) }

    private func makeSprite(_ name: String, scale: CGFloat) -> SKSpriteNode {
        let image = SKSpriteNode(texture: PixelArt.texture(name, frame: 0))
        image.setScale(scale)
        return image
    }

    private func addLandmark(_ kind: LandmarkKind, at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.zPosition = -point.y / 100
        let artName: String
        let scale: CGFloat
        switch kind {
        case .rune: artName = "rune"; scale = 2.1
        case .beacon: artName = "beacon"; scale = 2.8
        case .chest: artName = "chest"; scale = 1.8
        case .keeper: artName = "keeper"; scale = 1.9
        case .portal: artName = "portal"; scale = 2.6
        }
        let ring = SKShapeNode(ellipseOf: CGSize(width: kind.isBeacon ? 110 : 68, height: kind.isBeacon ? 50 : 28))
        ring.name = "ring"; ring.strokeColor = cyan.withAlphaComponent(0.45)
        ring.fillColor = cyan.withAlphaComponent(0.05); ring.lineWidth = 1.5; ring.zPosition = -2
        node.addChild(ring)
        let art = makeSprite(artName, scale: scale)
        art.name = "art"
        switch kind {
        case .beacon, .portal:
            // These 60-pixel-tall textures have their ground shadow in the bottom
            // tenth. Anchor that shadow to the interaction ring, not the center.
            art.anchorPoint = CGPoint(x: 0.5, y: 0.1)
            art.position.y = 0
        default:
            art.position.y = 22
        }
        node.addChild(art)
        let light = glow(color: kind.isKeeper ? amber : cyan, size: kind.isBeacon ? 190 : 110, alpha: 0.32)
        light.name = "light"; light.zPosition = -1
        switch kind {
        case .beacon: light.position.y = 112
        case .portal: light.position.y = 65
        default: light.position.y = 20
        }
        node.addChild(light)
        if kind.isKeeper {
            let label = label("KEEPER", size: 10, color: amber.withAlphaComponent(0.9))
            label.position = CGPoint(x: 0, y: 70)
            node.addChild(label)
        }
        worldLayer.addChild(node)
        structures.append(Landmark(kind: kind, node: node))
    }

    private func refreshLandmarks() {
        guard let store else { return }
        for landmark in structures {
            let art = landmark.node.childNode(withName: "art") as? SKSpriteNode
            let light = landmark.node.childNode(withName: "light")
            let ring = landmark.node.childNode(withName: "ring") as? SKShapeNode
            switch landmark.kind {
            case .rune(let index):
                let active = store.progress.activatedRunes.contains("\(realm.rawValue)-\(index)")
                art?.texture = PixelArt.texture("rune", frame: active ? 1 : 0)
                art?.color = active ? cyan : UIColor(red: 0.32, green: 0.39, blue: 0.48, alpha: 1)
                art?.colorBlendFactor = active ? 0.13 : 0.65
                light?.alpha = active ? 0.9 : 0.18
                ring?.strokeColor = active ? cyan.withAlphaComponent(0.8) : cyan.withAlphaComponent(0.2)
            case .beacon:
                let active = store.progress.clearedRealms.contains(realm.rawValue)
                art?.texture = PixelArt.texture("beacon", frame: active ? 1 : 0)
                light?.alpha = active ? 1 : 0.12
                art?.color = active ? cyan : .darkGray; art?.colorBlendFactor = active ? 0 : 0.4
                ring?.strokeColor = active ? cyan : cyan.withAlphaComponent(0.25)
            case .chest(let index):
                let claimed = store.progress.claimedChests.contains("\(realm.rawValue)-\(index)")
                art?.texture = PixelArt.texture("chest", frame: claimed ? 1 : 0)
                art?.alpha = claimed ? 0.45 : 1; light?.alpha = claimed ? 0 : 0.6
                ring?.alpha = claimed ? 0 : 0.45
            case .portal:
                let active = store.progress.clearedRealms.contains(realm.rawValue)
                art?.texture = PixelArt.texture("portal", frame: active ? 1 : 0)
                art?.alpha = active ? 1 : 0.35
                light?.alpha = active ? 1 : 0.1
                ring?.strokeColor = active ? cyan : cyan.withAlphaComponent(0.2)
            case .keeper: break
            }
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard let store, world != nil else { return }
        if previousTime == 0 { previousTime = currentTime; return }
        let elapsed = max(0, min(1.0 / 25.0, currentTime - previousTime))
        previousTime = currentTime
        let mode = store.mode
        if mode != lastMode {
            if mode == .playing {
                store.input.clear()
                localEnergy = min(store.progress.maxEnergy, store.energy)
                localStamina = store.stamina
            }
            lastMode = mode
        }
        if titleScene || mode == .title {
            age += elapsed
            animateHero(moving: false, dt: elapsed)
            updateCompanions(dt: elapsed, combat: false)
            updateCamera(dt: elapsed)
            return
        }
        guard mode == .playing else { return }
        age += elapsed
        if hitStop > 0 { hitStop -= elapsed; updateCamera(dt: elapsed); return }
        let dt = elapsed
        swordTimer = max(0, swordTimer - dt)
        attackCooldown = max(0, attackCooldown - dt)
        comboTimer = max(0, comboTimer - dt)
        dashCooldown = max(0, dashCooldown - dt)
        pulseCooldown = max(0, pulseCooldown - dt)
        invulnerability = max(0, invulnerability - dt)
        if comboTimer == 0 { combo = 0 }
        localEnergy = min(store.progress.maxEnergy, localEnergy + dt * 7)
        localStamina = min(100, localStamina + dt * 28)
        if dashTimer > 0 { dashTimer = max(0, dashTimer - dt) }
        handleInput(dt: dt)
        guard store.mode == .playing else { return }
        updateCreatures(dt: dt)
        updateProjectiles(dt: dt)
        updatePickups(dt: dt)
        updateCompanions(dt: dt, combat: true)
        updateAmbient(dt: dt)
        updateCamera(dt: dt)
        uiTimer += dt
        saveTimer += dt
        if uiTimer >= 0.1 {
            if store.energy != localEnergy { store.energy = localEnergy }
            if store.stamina != localStamina { store.stamina = localStamina }
            refreshHint()
            updateBossHUD()
            updateArrow()
            store.recordPlayTime(uiTimer)
            uiTimer = 0
        }
        if saveTimer >= 20 { store.save(); saveTimer = 0 }
    }

    private func handleInput(dt: Double) {
        guard let store else { return }
        let input = store.input
        var motion = input.movement
        if hypot(motion.dx, motion.dy) < 0.08 { motion = input.controllerMovement }
        let magnitude = hypot(motion.dx, motion.dy)
        if magnitude > 1 { motion = CGVector(dx: motion.dx / magnitude, dy: motion.dy / magnitude) }
        if magnitude > 0.09 && dashTimer <= 0 { facing = normalized(motion) }
        if input.dash {
            input.dash = false
            if dashCooldown <= 0, localStamina >= 28 {
                dashDirection = magnitude > 0.09 ? normalized(motion) : facing
                dashTimer = 0.19; dashCooldown = 0.4; invulnerability = max(invulnerability, 0.26)
                localStamina -= 28
                store.services.play(.dash); store.services.haptic(.light)
                burst(at: hero.position + CGVector(dx: 0, dy: 20), color: cyan, count: 8)
            }
        }
        if input.attack { input.attack = false; strike() }
        if input.pulse { input.pulse = false; castPulse() }
        if input.heal {
            input.heal = false
            let oldHealth = store.health
            store.usePotion()
            if store.health > oldHealth { healingEffect() }
        }
        if input.interact { input.interact = false; interact() }
        guard store.mode == .playing else { return }
        let moving = magnitude > 0.09 || dashTimer > 0
        if dashTimer > 0 {
            moveHero(CGVector(dx: dashDirection.dx * 680 * dt, dy: dashDirection.dy * 680 * dt))
            if Int(age * 60) % 3 == 0 && !store.settings.reducedEffects { ghost() }
        } else if magnitude > 0.09 {
            let speed: CGFloat = swordTimer > 0 ? 150 : 205
            moveHero(CGVector(dx: motion.dx * speed * dt, dy: motion.dy * speed * dt))
        }
        animateHero(moving: moving, dt: dt)
        hero.zPosition = -hero.position.y / 100 + 0.05
    }

    private func moveHero(_ offset: CGVector) {
        guard let world else { return }
        let steps = max(1, Int(ceil(hypot(offset.dx, offset.dy) / 9)))
        let step = CGVector(dx: offset.dx / CGFloat(steps), dy: offset.dy / CGFloat(steps))
        for _ in 0..<steps {
            let x = hero.position + CGVector(dx: step.dx, dy: 0)
            if world.canWalk(x, radius: 17) { hero.position.x = x.x }
            let y = hero.position + CGVector(dx: 0, dy: step.dy)
            if world.canWalk(y, radius: 17) { hero.position.y = y.y }
        }
    }

    private func animateHero(moving: Bool, dt: Double) {
        if moving { walkTime += dt * (dashTimer > 0 ? 18 : 10) }
        let frame = moving ? Int(walkTime) % 4 : Int(age * 2) % 2
        heroImage.texture = PixelArt.texture("hero", frame: frame)
        heroImage.xScale = abs(heroImage.xScale) * (facing.dx < -0.05 ? -1 : 1)
        heroImage.position.y = 25 + (moving ? sin(walkTime * .pi) * 1.8 : sin(age * 2) * 1)
        let angle = atan2(facing.dy, facing.dx)
        if swordTimer > 0 {
            let t = CGFloat(1 - swordTimer / 0.22)
            let sweep: CGFloat = combo == 0 ? 2.7 : 2.2
            bladePivot.zRotation = angle - sweep * 0.5 + sweep * t
            bladePivot.xScale = 1.12
        } else {
            bladePivot.zRotation = facing.dx < 0 ? .pi + 0.28 : -0.28
            bladePivot.xScale = 1
        }
        blade.alpha = 0.92 + 0.08 * CGFloat(sin(age * 3))
        if invulnerability > 0 && !titleScene {
            heroImage.alpha = Int(age * 15) % 2 == 0 ? 0.5 : 1
        } else { heroImage.alpha = 1 }
    }

    private func strike() {
        guard let store, attackCooldown <= 0, dashTimer <= 0 else { return }
        let target = creatures.filter { $0.health > 0 && $0.node.position.distance(to: hero.position) < 158 }
            .min { $0.node.position.distance(to: hero.position) < $1.node.position.distance(to: hero.position) }
        if let target { facing = direction(from: hero.position, to: target.node.position) }
        let finisher = combo == 2
        combo = (combo + 1) % 3; comboTimer = 0.82
        swordTimer = 0.22; attackCooldown = finisher ? 0.4 : 0.26
        store.services.play(.sword)
        store.services.haptic(finisher ? .medium : .light)
        let range: CGFloat = finisher ? 147 : 128
        let damage = store.progress.swordDamage * (finisher ? 1.5 : 1)
        var hits = 0
        for creature in creatures where creature.health > 0 {
            let offset = direction(from: hero.position, to: creature.node.position)
            let dot = facing.dx * offset.dx + facing.dy * offset.dy
            if creature.node.position.distance(to: hero.position) < range + creature.radius * 0.3 && dot > -0.32 {
                damageCreature(creature, amount: damage, knockback: finisher ? 40 : 20)
                hits += 1
            }
        }
        drawSlash(range: range, finisher: finisher)
        if hits > 0 { hitStop = finisher ? 0.055 : 0.025; shake(finisher ? 4 : 1.5) }
        creatures.removeAll { $0.health <= 0 }
    }

    private func castPulse() {
        guard let store, pulseCooldown <= 0, localEnergy >= 34 else { return }
        localEnergy -= 34; pulseCooldown = 1.05
        invulnerability = max(invulnerability, 0.3)
        let radius: CGFloat = 210 + CGFloat(store.progress.spiritLevel) * 12
        let damage = 46 + Double(store.progress.spiritLevel) * 15
        for creature in creatures where creature.health > 0 && creature.node.position.distance(to: hero.position) < radius {
            damageCreature(creature, amount: damage, knockback: 50)
        }
        creatures.removeAll { $0.health <= 0 }
        for shot in projectiles where !shot.friendly && shot.node.position.distance(to: hero.position) < radius {
            shot.life = 0
            burst(at: shot.node.position, color: cyan, count: 4)
        }
        for scale in [0.65, 1.0] {
            let ring = SKShapeNode(circleOfRadius: radius * scale)
            ring.position = hero.position + CGVector(dx: 0, dy: 20)
            ring.strokeColor = cyan; ring.lineWidth = 3; ring.glowWidth = 8
            ring.fillColor = cyan.withAlphaComponent(0.035)
            ring.setScale(0.08); ring.blendMode = .add
            effects.addChild(ring)
            ring.run(.sequence([.group([.scale(to: 1, duration: 0.42), .fadeOut(withDuration: 0.46)]), .removeFromParent()]))
        }
        burst(at: hero.position + CGVector(dx: 0, dy: 20), color: cyan, count: 24)
        store.services.play(.pulse); store.services.haptic(.heavy)
        shake(5)
    }

    private func spawnCreature(_ kind: EnemyKind, at point: CGPoint) {
        guard let store, creatures.count < 32 else { return }
        let creature = Creature(kind: kind)
        creature.node.position = point
        creature.home = point
        creature.phaseTimer = 0.8 + random.unit()
        creature.seed = random.unit() * 7
        let name = kind == .boss ? "boss\(realm.rawValue)" : kind.rawValue
        creature.art = makeSprite(name, scale: kind == .boss ? 2.7 : (kind == .boar ? 1.9 : 1.65))
        creature.art.position.y = kind == .boss ? 37 : 20
        creature.node.addChild(creature.art)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: kind == .boss ? 95 : 40, height: kind == .boss ? 26 : 13))
        shadow.fillColor = .black.withAlphaComponent(0.27); shadow.strokeColor = .clear
        shadow.zPosition = -2; shadow.position.y = -5; creature.node.addChild(shadow)
        let health: Double
        switch kind {
        case .slime: health = 44
        case .hornet: health = 38
        case .wraith: health = 54
        case .boar: health = 66
        case .knight: health = 82
        case .boss: health = 310 + Double(realm.rawValue) * 135
        }
        creature.maxHealth = kind == .boss ? health : health + Double(realm.rawValue) * 15
        if store.settings.storyMode { creature.maxHealth *= 0.8 }
        creature.health = creature.maxHealth
        creature.radius = kind == .boss ? 44 : (kind == .boar ? 28 : 20)
        creature.bar = SKSpriteNode(color: danger, size: CGSize(width: kind == .boss ? 85 : 38, height: 3))
        creature.bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        creature.bar.position = CGPoint(x: kind == .boss ? -42.5 : -19, y: kind == .boss ? 105 : 61)
        creature.bar.alpha = 0
        creature.node.addChild(creature.bar)
        if kind == .boss {
            let light = glow(color: UIColor(red: 0.71, green: 0.34, blue: 0.94, alpha: 1), size: 200, alpha: 0.35)
            light.position.y = 20; light.zPosition = -3; creature.node.addChild(light)
        }
        worldLayer.addChild(creature.node)
        creatures.append(creature)
    }

    private func ensureBoss() {
        guard let store, let world, !titleScene,
              store.progress.runeCount(in: realm) == 3,
              !store.progress.defeatedBosses.contains(realm.rawValue),
              !creatures.contains(where: { $0.kind == .boss && $0.health > 0 }) else { return }
        spawnCreature(.boss, at: world.boss)
        burst(at: world.boss + CGVector(dx: 0, dy: 45), color: UIColor(red: 0.74, green: 0.49, blue: 1, alpha: 1), count: 22)
    }

    private func updateCreatures(dt: Double) {
        guard let store else { return }
        let list = creatures
        for creature in list where creature.health > 0 {
            creature.phaseTimer -= dt
            creature.hitTint = max(0, creature.hitTint - dt)
            creature.art.color = .white; creature.art.colorBlendFactor = creature.hitTint > 0 ? 0.85 : 0
            let distance = creature.node.position.distance(to: hero.position)
            let animated = Int((age + creature.seed) * (creature.phase == .lunge ? 14 : 5)) % 4
            creature.art.texture = PixelArt.texture(creature.kind == .boss ? "boss\(realm.rawValue)" : creature.kind.rawValue, frame: animated)
            let flying = creature.kind == .hornet || creature.kind == .wraith || (creature.kind == .boss && realm.rawValue >= 2)
            creature.art.position.y = (creature.kind == .boss ? 37 : 20) + (flying ? CGFloat(sin(age * 4 + creature.seed)) * 6 : CGFloat(sin(age * 5 + creature.seed)) * 1.4)
            creature.node.zPosition = -creature.node.position.y / 100
            if distance > 660 { continue }
            creature.art.xScale = abs(creature.art.xScale) * (hero.position.x < creature.node.position.x ? -1 : 1)
            switch creature.phase {
            case .idle:
                if creature.kind == .boss {
                    if distance < 440 {
                        if !bossMusic { store.services.playMusic(realm: realm, tense: true); bossMusic = true }
                        if creature.phaseTimer <= 0 { beginWindup(creature) }
                        else if distance > 190 { move(creature, toward: hero.position, speed: 60, dt: dt) }
                    }
                } else if distance < (creature.kind == .wraith ? 380 : 310) {
                    let range: CGFloat = [.hornet, .wraith].contains(creature.kind) ? 250 : (creature.kind == .boar ? 190 : 73)
                    if distance < range && creature.phaseTimer <= 0 { beginWindup(creature) }
                    else if distance > range * 0.8 { move(creature, toward: hero.position, speed: creature.kind == .hornet ? 104 : 82, dt: dt) }
                } else {
                    let wander = creature.home + CGVector(dx: cos(age * 0.3 + creature.seed) * 28, dy: sin(age * 0.25 + creature.seed) * 20)
                    move(creature, toward: wander, speed: 19, dt: dt)
                }
            case .windup:
                creature.art.zRotation = CGFloat(sin(age * 45)) * 0.025
                if creature.phaseTimer <= 0 { executeAttack(creature) }
            case .lunge:
                let oldPoint = creature.node.position
                let speed: CGFloat = creature.kind == .boss ? 420 : 390
                move(creature, vector: creature.aim, distance: speed * dt)
                if oldPoint.distance(to: creature.node.position) < 0.5 || creature.phaseTimer <= 0 {
                    creature.phase = .recover; creature.phaseTimer = creature.kind == .boss ? 0.95 : 0.85
                }
                if creature.node.position.distance(to: hero.position) < creature.radius + 25 {
                    hurtHero(impactDamage(creature), from: creature.node.position)
                }
                if Int(age * 30) % 4 == 0 { burst(at: creature.node.position, color: amber.withAlphaComponent(0.6), count: 2) }
            case .recover:
                creature.art.zRotation = 0
                if creature.phaseTimer <= 0 { creature.phase = .idle; creature.phaseTimer = creature.kind == .boss ? 0.65 : 0.4 }
            }
        }
        creatures.removeAll { $0.health <= 0 }
    }

    private func beginWindup(_ creature: Creature) {
        creature.phase = .windup
        creature.aim = direction(from: creature.node.position, to: hero.position)
        creature.target = hero.position
        creature.pattern += 1
        if creature.kind == .boss {
            creature.phaseTimer = realm == .eclipseCrown ? 0.85 : 0.95
            if (realm == .moonshore || realm == .emberRuins) && creature.pattern % 2 == 1 {
                telegraphLine(from: creature.node.position, to: hero.position, duration: creature.phaseTimer)
            } else {
                telegraphCircle(at: creature.node.position, radius: realm == .briarwild ? 180 : 110, duration: creature.phaseTimer)
            }
        } else if creature.kind == .boar {
            creature.phaseTimer = 0.7
            telegraphLine(from: creature.node.position, to: hero.position, duration: 0.7)
        } else {
            creature.phaseTimer = creature.kind == .knight ? 0.68 : 0.5
            telegraphCircle(at: creature.node.position, radius: [.wraith, .hornet].contains(creature.kind) ? 38 : 64, duration: creature.phaseTimer)
        }
    }

    private func executeAttack(_ creature: Creature) {
        creature.art.zRotation = 0
        let point = creature.node.position
        if creature.kind == .boss {
            bossAttack(creature)
            return
        }
        if creature.kind == .boar {
            creature.phase = .lunge; creature.phaseTimer = 0.54
        } else if creature.kind == .wraith || creature.kind == .hornet {
            spawnShot(at: point + CGVector(dx: 0, dy: 18), direction: creature.aim,
                      speed: creature.kind == .hornet ? 225 : 180, damage: impactDamage(creature), friendly: false,
                      color: creature.kind == .hornet ? amber : UIColor(red: 0.75, green: 0.48, blue: 1, alpha: 1))
            creature.phase = .recover; creature.phaseTimer = 1.05
        } else {
            if hero.position.distance(to: point) < 90 { hurtHero(impactDamage(creature), from: point) }
            burst(at: point + CGVector(dx: creature.aim.dx * 42, dy: creature.aim.dy * 42 + 15), color: danger, count: 6)
            creature.phase = .recover; creature.phaseTimer = 0.9
        }
    }

    private func bossAttack(_ creature: Creature) {
        let point = creature.node.position
        let phaseTwo = creature.health < creature.maxHealth * 0.5
        let damage = impactDamage(creature)
        switch realm {
        case .moonshore:
            if creature.pattern % 2 == 1 {
                creature.phase = .lunge; creature.phaseTimer = phaseTwo ? 0.72 : 0.56
                return
            }
            ringShots(from: point, count: phaseTwo ? 8 : 6, speed: 155, damage: damage * 0.75, rotation: age * 0.1)
        case .briarwild:
            if hero.position.distance(to: point) < 180 { hurtHero(damage, from: point) }
            pulseVisual(at: point, radius: 180, color: danger)
            ringShots(from: point, count: phaseTwo ? 9 : 6, speed: 135, damage: damage * 0.7, rotation: Double(creature.pattern) * 0.4)
            if creature.pattern % 3 == 0 && creatures.count < 20 {
                for sign in [-1.0, 1.0] { spawnCreature(.slime, at: safePoint(point + CGVector(dx: sign * 100, dy: 80), fallback: point)) }
            }
        case .glassmarsh:
            let angle = atan2(creature.aim.dy, creature.aim.dx)
            for index in -2...2 {
                let offset = CGFloat(index) * 0.18
                spawnShot(at: point, direction: CGVector(dx: cos(angle + offset), dy: sin(angle + offset)), speed: phaseTwo ? 230 : 190,
                          damage: damage * 0.8, friendly: false, color: UIColor(red: 0.75, green: 0.57, blue: 1, alpha: 1))
            }
            if creature.pattern % 2 == 0 {
                burst(at: point, color: cyan, count: 15)
                let offset = CGVector(dx: creature.pattern % 4 == 0 ? 160 : -160, dy: 65)
                creature.node.position = safePoint(hero.position + offset, fallback: creature.home)
                burst(at: creature.node.position, color: cyan, count: 15)
            }
        case .emberRuins:
            if creature.pattern % 2 == 1 {
                creature.phase = .lunge; creature.phaseTimer = 0.58
                ringShots(from: point, count: 4, speed: 130, damage: damage * 0.6, rotation: .pi / 4)
                return
            }
            ringShots(from: point, count: phaseTwo ? 12 : 8, speed: 175, damage: damage * 0.7, rotation: Double(creature.pattern) * 0.28)
        case .eclipseCrown:
            if creature.pattern % 3 == 0 {
                creature.aim = direction(from: point, to: hero.position)
                creature.phase = .lunge; creature.phaseTimer = 0.62
                return
            }
            ringShots(from: point, count: phaseTwo ? 14 : 10, speed: phaseTwo ? 185 : 145, damage: damage * 0.72,
                      rotation: Double(creature.pattern) * 0.24)
            let aim = direction(from: point, to: hero.position)
            spawnShot(at: point, direction: aim, speed: 250, damage: damage, friendly: false, color: danger)
            if phaseTwo && creature.pattern % 4 == 0 && creatures.count < 12 {
                spawnCreature(.wraith, at: safePoint(point + CGVector(dx: -125, dy: 70), fallback: point))
                spawnCreature(.hornet, at: safePoint(point + CGVector(dx: 125, dy: 70), fallback: point))
            }
        }
        creature.phase = .recover; creature.phaseTimer = phaseTwo ? 0.8 : 1.2
    }

    private func impactDamage(_ creature: Creature) -> Double {
        let base: Double = creature.kind == .boss ? 23 : (creature.kind == .boar || creature.kind == .knight ? 16 : 11)
        return (base + Double(realm.rawValue) * 2) * (store?.settings.storyMode == true ? 0.5 : 1)
    }

    private func hurtHero(_ amount: Double, from point: CGPoint) {
        guard let store, store.mode == .playing, invulnerability <= 0, store.health > 0 else { return }
        store.health = max(0, store.health - amount)
        invulnerability = store.settings.storyMode ? 1 : 0.72
        let away = direction(from: point, to: hero.position)
        moveHero(CGVector(dx: away.dx * 25, dy: away.dy * 25))
        burst(at: hero.position + CGVector(dx: 0, dy: 25), color: danger, count: 10)
        floatingText("−\(Int(amount))", at: hero.position + CGVector(dx: 0, dy: 55), color: danger, large: false)
        store.services.play(.hurt); store.services.haptic(.heavy)
        shake(6)
        if store.health <= 0 {
            store.input.clear(); store.defeat()
        }
    }

    private func damageCreature(_ creature: Creature, amount: Double, knockback: CGFloat) {
        guard creature.health > 0, store?.mode == .playing else { return }
        creature.health = max(0, creature.health - amount)
        creature.hitTint = 0.1
        creature.bar.alpha = 1
        creature.bar.xScale = max(0, CGFloat(creature.health / creature.maxHealth))
        let away = direction(from: hero.position, to: creature.node.position)
        if creature.kind != .boss && creature.phase != .lunge { move(creature, vector: away, distance: knockback) }
        burst(at: creature.node.position + CGVector(dx: 0, dy: 25), color: cyan, count: creature.kind == .boss ? 8 : 5)
        floatingText(String(Int(amount)), at: creature.node.position + CGVector(dx: 0, dy: 63), color: .white, large: amount > 45)
        store?.services.play(.hit)
        if creature.health <= 0 { defeatCreature(creature) }
    }

    private func defeatCreature(_ creature: Creature) {
        guard let store else { return }
        let point = creature.node.position
        creature.node.removeAllActions()
        creature.node.run(.sequence([.group([.fadeOut(withDuration: 0.18), .scale(to: 0.8, duration: 0.18)]), .removeFromParent()]))
        burst(at: point + CGVector(dx: 0, dy: 20), color: creature.kind == .boss ? amber : cyan, count: creature.kind == .boss ? 28 : 10)
        if creature.kind == .boss {
            store.defeatBoss(in: realm)
            store.bossFraction = 0; store.bossName = ""
            store.services.playMusic(realm: realm, tense: false); bossMusic = false
            store.notify("\(realm.bossName) is free. Restore the moonwell.")
            spawnPickup(at: point, kind: .health, value: 45)
            spawnPickup(at: point + CGVector(dx: 28, dy: 15), kind: .energy, value: 70)
            for shot in projectiles where !shot.friendly { shot.life = 0 }
            pulseVisual(at: point, radius: 250, color: cyan)
            shake(6)
        } else {
            store.progress.kills += 1
            spawnPickup(at: point, kind: .essence, value: 7 + realm.rawValue * 2)
            if store.progress.kills % 3 == 0 { spawnPickup(at: point + CGVector(dx: 20, dy: 15), kind: .health, value: 15) }
            if store.progress.kills % 4 == 0 { spawnPickup(at: point + CGVector(dx: -22, dy: 8), kind: .energy, value: 18) }
        }
    }

    private func move(_ creature: Creature, toward target: CGPoint, speed: CGFloat, dt: Double) {
        if creature.node.position.distance(to: target) < 4 { return }
        move(creature, vector: direction(from: creature.node.position, to: target), distance: speed * dt)
    }

    private func move(_ creature: Creature, vector: CGVector, distance: CGFloat) {
        guard let world else { return }
        let offset = CGVector(dx: vector.dx * distance, dy: vector.dy * distance)
        let x = creature.node.position + CGVector(dx: offset.dx, dy: 0)
        if world.canWalk(x, radius: creature.radius * 0.65) { creature.node.position.x = x.x }
        let y = creature.node.position + CGVector(dx: 0, dy: offset.dy)
        if world.canWalk(y, radius: creature.radius * 0.65) { creature.node.position.y = y.y }
    }

    private func spawnShot(at point: CGPoint, direction: CGVector, speed: CGFloat, damage: Double, friendly: Bool, color: UIColor) {
        guard projectiles.count < 90 else { return }
        let shot = Shot()
        shot.friendly = friendly; shot.damage = damage; shot.velocity = CGVector(dx: direction.dx * speed, dy: direction.dy * speed)
        shot.node.position = point + CGVector(dx: 0, dy: 16)
        shot.node.zPosition = 100
        let core = SKSpriteNode(color: color, size: CGSize(width: friendly ? 5 : 8, height: friendly ? 5 : 8))
        core.zRotation = .pi / 4
        shot.node.addChild(core)
        let halo = glow(color: color, size: friendly ? 35 : 50, alpha: 0.72)
        halo.zPosition = -1; shot.node.addChild(halo)
        effects.addChild(shot.node)
        projectiles.append(shot)
    }

    private func ringShots(from point: CGPoint, count: Int, speed: CGFloat, damage: Double, rotation: Double) {
        for index in 0..<count {
            let angle = Double(index) / Double(count) * .pi * 2 + rotation
            spawnShot(at: point, direction: CGVector(dx: cos(angle), dy: sin(angle)), speed: speed, damage: damage, friendly: false,
                      color: realm == .emberRuins ? amber : UIColor(red: 0.83, green: 0.45, blue: 0.91, alpha: 1))
        }
    }

    private func updateProjectiles(dt: Double) {
        guard let world else { return }
        for shot in projectiles where shot.life > 0 {
            shot.life -= dt
            let old = shot.node.position
            shot.node.position = old + CGVector(dx: shot.velocity.dx * dt, dy: shot.velocity.dy * dt)
            if !world.walkBounds.insetBy(dx: -30, dy: -30).contains(shot.node.position) { shot.life = 0; continue }
            if shot.friendly {
                if let hit = creatures.first(where: { $0.health > 0 && $0.node.position.distance(to: shot.node.position) < $0.radius + 15 }) {
                    damageCreature(hit, amount: shot.damage, knockback: 3); shot.life = 0
                }
            } else if shot.node.position.distance(to: hero.position + CGVector(dx: 0, dy: 13)) < 26 {
                hurtHero(shot.damage, from: old); shot.life = 0
            }
        }
        for shot in projectiles where shot.life <= 0 { shot.node.removeFromParent() }
        projectiles.removeAll { $0.life <= 0 }
    }

    private func spawnPickup(at point: CGPoint, kind: PickupKind, value: Int) {
        guard pickups.count < 48 else { return }
        let pickup = Pickup(kind: kind, value: value)
        pickup.node.position = point
        let color: UIColor = kind == .health ? UIColor(red: 0.97, green: 0.46, blue: 0.62, alpha: 1) : (kind == .essence ? amber : cyan)
        let art = SKSpriteNode(color: color, size: CGSize(width: 9, height: 9))
        art.zRotation = .pi / 4; pickup.node.addChild(art)
        let halo = glow(color: color, size: 46, alpha: 0.58)
        halo.zPosition = -1; pickup.node.addChild(halo)
        pickup.node.zPosition = 10
        worldLayer.addChild(pickup.node)
        pickups.append(pickup)
    }

    private func updatePickups(dt: Double) {
        guard let store else { return }
        for pickup in pickups where !pickup.claimed {
            let distance = pickup.node.position.distance(to: hero.position)
            if distance < 135 {
                let vector = direction(from: pickup.node.position, to: hero.position)
                let step = min(distance, CGFloat(dt) * (240 + (135 - distance) * 3))
                pickup.node.position = pickup.node.position + CGVector(dx: vector.dx * step, dy: vector.dy * step)
            }
            pickup.node.zRotation = CGFloat(age * 1.8)
            if distance < 28 {
                pickup.claimed = true
                switch pickup.kind {
                case .essence: store.addEssence(pickup.value)
                case .health: store.health = min(store.progress.maxHealth, store.health + Double(pickup.value))
                case .energy: localEnergy = min(store.progress.maxEnergy, localEnergy + Double(pickup.value))
                }
                pickup.node.removeFromParent()
                store.services.play(.reward)
            }
        }
        pickups.removeAll { $0.claimed }
    }

    private func updateCompanions(dt: Double, combat: Bool) {
        guard let store else { return }
        let orbit = CGVector(dx: (combat ? -62 : -92) + cos(age * 1.1) * 9, dy: (combat ? 42 : 14) + sin(age * 2.3) * 10)
        let target = hero.position + orbit
        wisp.position = lerp(wisp.position, target, min(1, dt * 5))
        wisp.zPosition = -wisp.position.y / 100 + 3
        wisp.texture = PixelArt.texture("wisp", frame: Int(age * 5) % 4)
        let mossTarget = hero.position + (combat ? CGVector(dx: facing.dx > 0 ? -40 : 48, dy: -40) : CGVector(dx: 90, dy: -5))
        let mossMoving = moss.position.distance(to: mossTarget) > 12
        moss.position = lerp(moss.position, mossTarget, min(1, dt * 2.8))
        moss.zPosition = -moss.position.y / 100
        moss.texture = PixelArt.texture("moss", frame: mossMoving ? Int(age * 8) % 4 : 0)
        moss.xScale = abs(moss.xScale) * (hero.position.x < moss.position.x ? -1 : 1)
        guard combat else { return }
        companionTimer -= dt; mossTimer -= dt
        if let target = creatures.filter({ $0.health > 0 && $0.node.position.distance(to: hero.position) < 300 })
            .min(by: { $0.node.position.distance(to: hero.position) < $1.node.position.distance(to: hero.position) }) {
            if companionTimer <= 0 {
                companionTimer = 2.2
                spawnShot(at: wisp.position, direction: direction(from: wisp.position, to: target.node.position), speed: 340,
                          damage: 7 + Double(store.progress.spiritLevel) * 2, friendly: true, color: amber)
            }
            if mossTimer <= 0 && store.progress.metMoss {
                mossTimer = 3.2
                spawnShot(at: moss.position, direction: direction(from: moss.position, to: target.node.position), speed: 260,
                          damage: 12 + Double(store.progress.swordLevel) * 2, friendly: true,
                          color: UIColor(red: 0.61, green: 0.85, blue: 0.44, alpha: 1))
            }
        }
    }

    private func interact() {
        guard let store, let nearest = nearestLandmark() else { return }
        switch nearest.kind {
        case .rune(let index):
            if store.progress.activatedRunes.contains("\(realm.rawValue)-\(index)") {
                if creatures.contains(where: { $0.health > 0 && $0.node.position.distance(to: hero.position) < 260 }) {
                    store.notify("The rune cannot shelter you during a fight.")
                } else {
                    store.restoreVitals(); localEnergy = store.progress.maxEnergy; localStamina = 100
                    healingEffect(); store.notify("Restored by starlight. Your journey is saved."); store.save()
                }
            } else {
                store.activateRune(index: index, realm: realm)
                store.health = min(store.progress.maxHealth, store.health + 22)
                localEnergy = min(store.progress.maxEnergy, localEnergy + 28)
                pulseVisual(at: nearest.node.position, radius: 160, color: cyan)
                burst(at: nearest.node.position + CGVector(dx: 0, dy: 25), color: cyan, count: 18)
                refreshLandmarks(); ensureBoss()
                if store.progress.runeCount(in: realm) == 3 { store.notify("Three runes sing. The guardian has awakened to the south.") }
            }
        case .beacon:
            if store.progress.clearedRealms.contains(realm.rawValue) {
                store.restoreVitals(); localEnergy = store.progress.maxEnergy; localStamina = 100
                store.open(.upgrades)
            } else if store.progress.defeatedBosses.contains(realm.rawValue) && store.progress.runeCount(in: realm) == 3 {
                store.lightBeacon(in: realm)
                localEnergy = store.progress.maxEnergy; localStamina = 100
                refreshLandmarks()
                pulseVisual(at: nearest.node.position, radius: 380, color: cyan)
                burst(at: nearest.node.position + CGVector(dx: 0, dy: 60), color: amber, count: 35)
                store.services.play(.victory); store.services.haptic(.success)
                if realm != .eclipseCrown { store.notify("Moonwell restored. The eastern gate is open.") }
            } else if store.progress.runeCount(in: realm) < 3 {
                store.notify("Find and awaken the three moon runes first.")
            } else { store.notify("Free \(realm.bossName), then return to the moonwell.") }
        case .chest(let index):
            if !store.progress.claimedChests.contains("\(realm.rawValue)-\(index)") {
                store.claimChest(index: index, realm: realm)
                burst(at: nearest.node.position + CGVector(dx: 0, dy: 22), color: amber, count: 18)
                refreshLandmarks()
            } else { store.notify("This keeper's cache has already been gathered.") }
        case .keeper:
            if !store.progress.metMoss {
                store.progress.metMoss = true; store.save()
                store.speak("Keeper Edda", lines: [
                    "Aster. Even after all this darkness, your sword remembers the stars.",
                    "Your little friend is Moss. He has been waiting for someone brave enough to wake the moonwells. He will fight beside you now.",
                    "Awaken the three runes. Free the guardian. Then bring your light to the moonwell in the center of each realm.",
                    "Follow the little compass when you lose your way. Your blade is free to swing. Dash through danger, and use a moon pulse when you are surrounded."
                ])
            } else {
                store.speak("Keeper Edda", lines: [realm.story,
                    store.progress.clearedRealms.contains(realm.rawValue) ? "This place is breathing again. The gate will carry you onward, and the moonwell can strengthen your blade." : "The little gold lights are memories. Gather them and visit a restored moonwell to grow stronger.",
                    "You can return to any awakened shore from your journal. Every rune you light will remember you."
                ])
            }
        case .portal:
            guard store.progress.clearedRealms.contains(realm.rawValue) else { store.notify("The gate is sleeping. Restore this realm's moonwell."); return }
            if let next = realm.next { store.travel(to: next) }
            else { store.completeGame() }
        }
    }

    private func nearestLandmark() -> Landmark? {
        structures.filter { $0.node.position.distance(to: hero.position) < 108 }
            .min { $0.node.position.distance(to: hero.position) < $1.node.position.distance(to: hero.position) }
    }

    private func refreshHint() {
        guard let store else { return }
        guard let landmark = nearestLandmark() else { if store.hint != "" { store.hint = "" }; return }
        let text: String
        switch landmark.kind {
        case .rune(let index): text = store.progress.activatedRunes.contains("\(realm.rawValue)-\(index)") ? "Rest at the rune" : "Awaken moon rune"
        case .beacon: text = store.progress.clearedRealms.contains(realm.rawValue) ? "Strengthen your light" : "Restore the moonwell"
        case .chest(let index): text = store.progress.claimedChests.contains("\(realm.rawValue)-\(index)") ? "An empty keeper's cache" : "Open keeper's cache"
        case .keeper: text = "Speak with Keeper Edda"
        case .portal: text = store.progress.clearedRealms.contains(realm.rawValue) ? (realm.next == nil ? "Remember the ending" : "Travel to \(realm.next!.title)") : "The moon gate sleeps"
        }
        if store.hint != text { store.hint = text }
    }

    private func updateBossHUD() {
        guard let store else { return }
        if let boss = creatures.first(where: { $0.kind == .boss && $0.health > 0 && $0.node.position.distance(to: hero.position) < 600 }) {
            if store.bossName != realm.bossName { store.bossName = realm.bossName }
            let fraction = boss.health / boss.maxHealth
            if store.bossFraction != fraction { store.bossFraction = fraction }
        } else {
            if store.bossFraction != 0 { store.bossFraction = 0 }
            if !store.bossName.isEmpty { store.bossName = "" }
        }
    }

    private func buildArrow() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 13, y: 0)); path.addLine(to: CGPoint(x: -7, y: 6))
        path.addLine(to: CGPoint(x: -3, y: 0)); path.addLine(to: CGPoint(x: -7, y: -6)); path.closeSubpath()
        let pointer = SKShapeNode(path: path)
        pointer.fillColor = cyan; pointer.strokeColor = .clear; pointer.glowWidth = 3
        arrow.addChild(pointer)
        arrow.zPosition = 250
        worldLayer.addChild(arrow)
        arrow.isHidden = titleScene
    }

    private func objectivePoint() -> CGPoint? {
        guard let world, let store else { return nil }
        if !store.progress.metMoss { return world.npc }
        for (index, point) in world.runes.enumerated() where !store.progress.activatedRunes.contains("\(realm.rawValue)-\(index)") { return point }
        if !store.progress.defeatedBosses.contains(realm.rawValue) { return world.boss }
        if !store.progress.clearedRealms.contains(realm.rawValue) { return world.beacon }
        return world.portal
    }

    private func updateArrow() {
        guard let point = objectivePoint(), !titleScene else { arrow.isHidden = true; return }
        let vector = direction(from: hero.position, to: point)
        arrow.position = hero.position + CGVector(dx: vector.dx * 94, dy: vector.dy * 94 + 18)
        arrow.zRotation = atan2(vector.dy, vector.dx)
        arrow.alpha = 0.65 + CGFloat(sin(age * 3)) * 0.15
        arrow.isHidden = hero.position.distance(to: point) < 125
    }

    private func updateCamera(dt: Double, snap: Bool = false) {
        guard let world else { return }
        var target = hero.position + CGVector(dx: titleScene ? -size.width * 0.22 : facing.dx * 35, dy: titleScene ? 110 : 26)
        let halfWidth = size.width * cameraRig.xScale * 0.5
        let halfHeight = size.height * cameraRig.yScale * 0.5
        target.x = max(halfWidth, min(world.size.width - halfWidth, target.x))
        target.y = max(halfHeight, min(world.size.height - halfHeight, target.y))
        cameraRig.position = snap ? target : lerp(cameraRig.position, target, min(1, dt * 7))
        if cameraShake > 0 && store?.settings.screenShake == true && store?.settings.reducedEffects != true {
            cameraRig.position.x += CGFloat(sin(age * 110)) * cameraShake
            cameraRig.position.y += CGFloat(cos(age * 125)) * cameraShake * 0.6
        }
        cameraShake = max(0, cameraShake - CGFloat(dt) * 30)
    }

    private func updateAmbient(dt: Double) {
        guard let store else { return }
        ambientTimer += dt
        if ambientTimer > 0.33 && !store.settings.reducedEffects {
            ambientTimer = 0
            if let rune = structures.filter({
                if case .rune(let index) = $0.kind { return store.progress.activatedRunes.contains("\(realm.rawValue)-\(index)") }
                return false
            }).randomElement(), rune.node.position.distance(to: hero.position) < 650 {
                let spark = SKSpriteNode(color: cyan, size: CGSize(width: 3, height: 3))
                spark.position = rune.node.position + CGVector(dx: random.unit() * 50 - 25, dy: 18)
                effects.addChild(spark)
                spark.run(.sequence([.group([.moveBy(x: 4, y: 50, duration: 1.2), .fadeOut(withDuration: 1.2)]), .removeFromParent()]))
            }
        }
    }

    private func drawSlash(range: CGFloat, finisher: Bool) {
        guard store?.settings.reducedEffects != true else { return }
        let angle = atan2(facing.dy, facing.dx)
        for layer in 0..<3 {
            let path = CGMutablePath()
            let radius = range - 20 - CGFloat(layer) * 10
            path.addArc(center: .zero, radius: radius, startAngle: angle - 1.2, endAngle: angle + 1.15, clockwise: false)
            let slash = SKShapeNode(path: path)
            slash.position = hero.position + CGVector(dx: 0, dy: 19)
            slash.strokeColor = layer == 0 ? .white : cyan.withAlphaComponent(0.65)
            slash.lineWidth = layer == 0 ? (finisher ? 8 : 5) : 3
            slash.glowWidth = layer == 0 ? 7 : 4
            slash.blendMode = .add
            effects.addChild(slash)
            slash.run(.sequence([.group([.fadeOut(withDuration: 0.2), .scale(to: 1.12, duration: 0.2)]), .removeFromParent()]))
        }
        for _ in 0..<5 {
            let a = angle - 0.9 + CGFloat(random.unit()) * 1.8
            let point = hero.position + CGVector(dx: cos(a) * (range - 20), dy: sin(a) * (range - 20) + 20)
            burst(at: point, color: cyan, count: 1)
        }
    }

    private func telegraphCircle(at point: CGPoint, radius: CGFloat, duration: Double) {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.position = point
        ring.strokeColor = danger.withAlphaComponent(0.75)
        ring.fillColor = danger.withAlphaComponent(0.08)
        ring.lineWidth = 2
        effects.addChild(ring)
        ring.run(.sequence([.wait(forDuration: duration), .fadeOut(withDuration: 0.12), .removeFromParent()]))
        let inside = SKShapeNode(circleOfRadius: radius)
        inside.position = point; inside.strokeColor = .clear
        inside.fillColor = danger.withAlphaComponent(0.12); inside.setScale(0.06)
        effects.addChild(inside)
        inside.run(.sequence([.scale(to: 1, duration: duration), .fadeOut(withDuration: 0.15), .removeFromParent()]))
    }

    private func telegraphLine(from point: CGPoint, to target: CGPoint, duration: Double) {
        let vector = direction(from: point, to: target)
        let end = point + CGVector(dx: vector.dx * 300, dy: vector.dy * 300)
        let path = CGMutablePath(); path.move(to: point); path.addLine(to: end)
        let line = SKShapeNode(path: path)
        line.lineWidth = 40; line.strokeColor = danger.withAlphaComponent(0.13)
        effects.addChild(line)
        line.run(.sequence([.wait(forDuration: duration), .fadeOut(withDuration: 0.12), .removeFromParent()]))
        let edge = SKShapeNode(path: path)
        edge.lineWidth = 2; edge.strokeColor = danger.withAlphaComponent(0.8)
        effects.addChild(edge)
        edge.run(.sequence([.wait(forDuration: duration), .fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    private func pulseVisual(at point: CGPoint, radius: CGFloat, color: UIColor) {
        let circle = SKShapeNode(circleOfRadius: radius)
        circle.strokeColor = color; circle.lineWidth = 3; circle.glowWidth = 5
        circle.fillColor = color.withAlphaComponent(0.025)
        circle.position = point; circle.setScale(0.04)
        effects.addChild(circle)
        circle.run(.sequence([.group([.scale(to: 1, duration: 0.65), .fadeOut(withDuration: 0.75)]), .removeFromParent()]))
    }

    private func burst(at point: CGPoint, color: UIColor, count: Int) {
        guard effects.children.count < 420 else { return }
        let total = store?.settings.reducedEffects == true ? min(count, 3) : count
        for _ in 0..<total {
            let particle = SKSpriteNode(color: color, size: CGSize(width: CGFloat(3 + random.int(3)), height: CGFloat(3 + random.int(3))))
            particle.position = point
            let angle = random.unit() * .pi * 2
            let distance = 18 + random.unit() * 45
            let duration = 0.25 + random.unit() * 0.35
            effects.addChild(particle)
            particle.run(.sequence([.group([.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: duration), .fadeOut(withDuration: duration)]), .removeFromParent()]))
        }
    }

    private func floatingText(_ text: String, at point: CGPoint, color: UIColor, large: Bool) {
        guard effects.children.count < 420 else { return }
        let textNode = label(text, size: large ? 23 : 17, color: color)
        textNode.position = point + CGVector(dx: random.unit() * 14 - 7, dy: 0)
        effects.addChild(textNode)
        textNode.run(.sequence([.group([.moveBy(x: 0, y: 36, duration: 0.65), .sequence([.wait(forDuration: 0.24), .fadeOut(withDuration: 0.41)])]), .removeFromParent()]))
    }

    private func healingEffect() {
        burst(at: hero.position + CGVector(dx: 0, dy: 20), color: UIColor(red: 0.62, green: 1, blue: 0.7, alpha: 1), count: 16)
        pulseVisual(at: hero.position, radius: 70, color: UIColor(red: 0.62, green: 1, blue: 0.7, alpha: 1))
    }

    private func ghost() {
        let ghost = SKSpriteNode(texture: heroImage.texture)
        ghost.size = heroImage.size; ghost.xScale = heroImage.xScale; ghost.yScale = heroImage.yScale
        ghost.position = hero.position + CGVector(dx: 0, dy: 25)
        ghost.color = cyan; ghost.colorBlendFactor = 0.7; ghost.alpha = 0.38
        effects.addChild(ghost)
        ghost.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))
    }

    private func shake(_ amount: CGFloat) {
        guard store?.settings.screenShake == true && store?.settings.reducedEffects != true else { return }
        cameraShake = max(cameraShake, amount)
    }

    private func label(_ text: String, size: CGFloat, color: UIColor) -> SKLabelNode {
        let result = SKLabelNode(fontNamed: "Menlo-Bold")
        result.text = text; result.fontSize = size; result.fontColor = color
        result.horizontalAlignmentMode = .center; result.verticalAlignmentMode = .center
        return result
    }

    private func glow(color: UIColor, size: CGFloat, alpha: CGFloat) -> SKSpriteNode {
        if Self.haloTexture == nil {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
                let colors = [UIColor.white.withAlphaComponent(0.9).cgColor, UIColor.white.withAlphaComponent(0.2).cgColor, UIColor.clear.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) {
                    context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                                        endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
                }
            }
            Self.haloTexture = SKTexture(image: image)
        }
        let sprite = SKSpriteNode(texture: Self.haloTexture)
        sprite.size = CGSize(width: size, height: size)
        sprite.color = color; sprite.colorBlendFactor = 1; sprite.blendMode = .add; sprite.alpha = alpha
        return sprite
    }

    private func normalized(_ vector: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0.0001 else { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    private func direction(from: CGPoint, to: CGPoint) -> CGVector { normalized(CGVector(dx: to.x - from.x, dy: to.y - from.y)) }
    private func lerp(_ a: CGPoint, _ b: CGPoint, _ fraction: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction) }
    private func safePoint(_ point: CGPoint, fallback: CGPoint) -> CGPoint { world?.canWalk(point, radius: 24) == true ? point : fallback }

    #if DEBUG
    var qaPlayerPosition: CGPoint { hero.position }
    var qaEnemyCount: Int { creatures.count }
    var qaEnemyHealth: Double { creatures.reduce(0) { $0 + $1.health } }
    var qaAttackCooldown: Double { attackCooldown }
    var qaDashTime: Double { dashTimer }
    var qaEnergy: Double { localEnergy }
    var qaStamina: Double { localStamina }
    var qaBossHealth: Double { creatures.first(where: { $0.kind == .boss })?.health ?? 0 }
    func qaAdvance(seconds: Double) {
        guard seconds > 0 else { return }
        if previousTime == 0 { previousTime = 1; lastMode = store?.mode ?? .playing }
        for _ in 0..<Int(ceil(seconds * 60)) { update(previousTime + 1.0 / 60.0) }
    }
    func qaSetPlayerPosition(_ point: CGPoint) { debugMoveHero(to: point) }
    func qaDamagePlayer(_ amount: Double) { invulnerability = 0; hurtHero(amount, from: hero.position + CGVector(dx: -10, dy: 0)) }
    func qaSetBossHealth(_ value: Double) {
        guard let boss = creatures.first(where: { $0.kind == .boss }) else { return }
        if value <= 0 { damageCreature(boss, amount: boss.health, knockback: 0); creatures.removeAll { $0.health <= 0 } }
        else { boss.health = min(boss.maxHealth, value) }
    }
    func qaSpawnEnemy(_ kind: EnemyKind, at point: CGPoint) { spawnCreature(kind, at: point) }
    func qaCanWalk(_ point: CGPoint) -> Bool { world?.canWalk(point, radius: 17) ?? false }
    func qaClearEnemies() { creatures.forEach { $0.node.removeFromParent() }; creatures.removeAll(); projectiles.forEach { $0.node.removeFromParent() }; projectiles.removeAll() }
    var debugRealm: Realm { realm }
    var debugHeroPosition: CGPoint { hero.position }
    var debugCreatureCount: Int { creatures.count }
    var debugBossCount: Int { creatures.filter { $0.kind == .boss && $0.health > 0 }.count }
    func debugMoveHero(to point: CGPoint) { guard world?.canWalk(point) == true else { return }; hero.position = point; updateCamera(dt: 1, snap: true); refreshHint() }
    func debugAwakenRunes() { for index in 0..<3 { store?.activateRune(index: index, realm: realm) }; refreshLandmarks(); ensureBoss() }
    func debugDefeatGuardian() { guard let boss = creatures.first(where: { $0.kind == .boss }) else { return }; damageCreature(boss, amount: boss.maxHealth, knockback: 0); creatures.removeAll { $0.health <= 0 } }
    func debugInteract() { interact() }
    func debugLandmark(_ name: String) -> CGPoint? {
        guard let world else { return nil }
        switch name { case "beacon": return world.beacon; case "boss": return world.boss; case "keeper": return world.npc; case "portal": return world.portal; default: return nil }
    }
    #endif
}

private enum LandmarkKind {
    case rune(Int), beacon, chest(Int), keeper, portal
    var isBeacon: Bool { if case .beacon = self { return true }; return false }
    var isKeeper: Bool { if case .keeper = self { return true }; return false }
}
private struct Landmark { let kind: LandmarkKind; let node: SKNode }
private enum CreaturePhase { case idle, windup, lunge, recover }
@MainActor private final class Creature {
    let kind: EnemyKind
    let node = SKNode()
    var art = SKSpriteNode()
    var bar = SKSpriteNode()
    var health: Double = 1
    var maxHealth: Double = 1
    var radius: CGFloat = 20
    var home = CGPoint.zero
    var phase: CreaturePhase = .idle
    var phaseTimer: Double = 0
    var aim = CGVector(dx: 1, dy: 0)
    var target = CGPoint.zero
    var pattern = 0
    var hitTint: Double = 0
    var seed: Double = 0
    init(kind: EnemyKind) { self.kind = kind }
}
@MainActor private final class Shot {
    let node = SKNode()
    var velocity = CGVector.zero
    var life: Double = 5
    var damage: Double = 10
    var friendly = false
}
private enum PickupKind { case essence, health, energy }
@MainActor private final class Pickup {
    let node = SKNode()
    let kind: PickupKind
    let value: Int
    var claimed = false
    init(kind: PickupKind, value: Int) { self.kind = kind; self.value = value }
}
