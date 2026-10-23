import UIKit
import SpriteKit

/// Each realm is a hand-composed navigation space. Seeded detail changes its texture,
/// while protected paths and landmark clearings keep all campaign goals reachable.
@MainActor enum WorldBuilder {
    static let worldSize = CGSize(width: 2048, height: 1536)
    static let spawn = CGPoint(x: 1024, y: 1120)
    static let runes = [CGPoint(x: 360, y: 970), CGPoint(x: 1680, y: 910), CGPoint(x: 530, y: 340)]
    static let beacon = CGPoint(x: 1024, y: 780)
    static let boss = CGPoint(x: 1024, y: 290)
    static let chests = [CGPoint(x: 1650, y: 430), CGPoint(x: 280, y: 610)]
    static let npc = CGPoint(x: 880, y: 1080)
    static let portal = CGPoint(x: 1730, y: 220)

    static func build(realm: Realm, completed: Bool) -> WorldMap {
        let palette = RealmPalette(realm)
        let layout = RealmLayout(realm)
        let root = SKNode(); root.name = "world.\(realm.rawValue)"
        let background = SKSpriteNode(texture: groundTexture(realm: realm, completed: completed))
        background.size = worldSize
        background.anchorPoint = .zero
        background.position = .zero
        background.zPosition = -1000
        root.addChild(background)

        let bounds = CGRect(x: 96, y: 96, width: 1856, height: 1164)
        let enemies = enemySpawns(realm)
        let landmarks = [layout.spawn, layout.beacon, layout.boss, layout.npc, layout.portal]
            + layout.runes + layout.chests + enemies.map(\.position)
        let paths = trailSegments(layout)
        var random = SeededRandom(seed: UInt64(4913 + realm.rawValue * 733))
        var obstacles: [CGRect] = []

        // Tall foreground elements are separate, depth-sorted sprites. Fine ground
        // detail is baked once, avoiding thousands of scene nodes on the phone.
        for _ in 0..<145 {
            let point = CGPoint(x: 130 + CGFloat(random.unit()) * 1788,
                                y: 145 + CGFloat(random.unit()) * 1075)
            if landmarks.contains(where: { $0.distance(to: point) < 135 }) { continue }
            if paths.contains(where: { distance(point, toSegment: $0.0, $0.1) < 91 }) { continue }
            if obstacles.contains(where: { $0.insetBy(dx: -80, dy: -65).contains(point) }) { continue }

            let isCrystal = realm == .glassmarsh && random.unit() > 0.45
            let isRuin = (realm == .emberRuins || realm == .eclipseCrown) && random.unit() > 0.50
            let name = isCrystal ? "crystal" : (isRuin ? "ruin" : "tree")
            let variant = realm == .moonshore || realm == .briarwild ? random.int(4) : 4 + random.int(4)
            let sprite = PixelArt.sprite(name, frame: variant, scale: isCrystal ? 2.2 : 2)
            sprite.position = point
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.10)
            sprite.zPosition = -point.y / 100
            if realm == .emberRuins && name == "tree" {
                sprite.color = PixelPainter.color(0xB589A0)
                sprite.colorBlendFactor = 0.3
            }
            root.addChild(sprite)
            let width: CGFloat = name == "tree" ? 30 : (name == "ruin" ? 74 : 44)
            let height: CGFloat = name == "tree" ? 26 : 28
            obstacles.append(CGRect(x: point.x - width/2, y: point.y - height/2, width: width, height: height))
        }

        // Two small glowing lanterns establish the welcoming first clearing.
        for point in [CGPoint(x: 790, y: 1140), CGPoint(x: 1235, y: 1130)] {
            let pole = SKSpriteNode(color: PixelPainter.color(0x7C6C60), size: CGSize(width: 6, height: 36))
            pole.position = point; pole.anchorPoint = CGPoint(x: 0.5, y: 0); pole.zPosition = -point.y/100
            root.addChild(pole)
            let lamp = SKSpriteNode(color: PixelPainter.color(palette.lamp), size: CGSize(width: 14, height: 13))
            lamp.position = CGPoint(x: point.x, y: point.y + 34); lamp.zPosition = pole.zPosition+0.1
            root.addChild(lamp)
            let glow = glowNode(color: palette.lamp, size: 100)
            glow.position = lamp.position; glow.alpha = 0.32; glow.zPosition = 14
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.23, duration: 1.9), .fadeAlpha(to: 0.37, duration: 2.4)])))
            root.addChild(glow)
        }

        addAmbient(to: root, realm: realm, palette: palette, completed: completed)

        return WorldMap(root: root, size: worldSize, walkBounds: bounds, spawn: layout.spawn,
                        runes: layout.runes, beacon: layout.beacon, boss: layout.boss, chests: layout.chests, npc: layout.npc,
                        portal: layout.portal, enemies: enemies, obstacles: obstacles)
    }

    static func glowNode(color: UInt32, size: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: PixelArt.glowTexture())
        node.size = CGSize(width: size, height: size)
        node.color = PixelPainter.color(color); node.colorBlendFactor = 1
        node.blendMode = .add
        return node
    }

    private static func groundTexture(realm: Realm, completed: Bool) -> SKTexture {
        let palette = RealmPalette(realm)
        let layout = RealmLayout(realm)
        let paths = trailSegments(layout)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 768), format: format).image { renderer in
            let c = renderer.cgContext
            c.setShouldAntialias(false); c.interpolationQuality = .none
            let p = PixelPainter(c)
            var random = SeededRandom(seed: UInt64(1701 + realm.rawValue * 997))

            // A deep water border, a distant silhouette and a restrained crescent.
            p.rect(0, 0, 1024, 768, palette.water)
            for row in 0..<26 {
                let alpha = CGFloat(row) / 110
                p.rect(0, row*5, 1024, 5, palette.waterLight, alpha: alpha)
            }
            p.rect(0, 0, 1024, 80, palette.sky)
            for _ in 0..<52 {
                let x = random.int(1024), y = random.int(76)
                p.rect(x, y, random.int(3) == 0 ? 2 : 1, 1, 0xC1D9D9, alpha: 0.25 + CGFloat(random.unit())*0.35)
            }
            p.ellipse(585, 52, 30, 30, 0xCBDED3)
            p.ellipse(577, 49, 30, 29, palette.sky)
            mountain(p, x: -20, y: 80, width: 290, height: 37, color: palette.farMountain)
            mountain(p, x: 330, y: 83, width: 200, height: 27, color: palette.farMountain)
            mountain(p, x: 790, y: 80, width: 290, height: 42, color: palette.farMountain)
            p.rect(600, 84, 7, 1, 0x6B9DAB, alpha: 0.5)
            for _ in 0..<250 {
                let x = random.int(1024), y = 83 + random.int(62)
                p.rect(x, y, 3 + random.int(29), 1+random.int(2), palette.waterLight, alpha: 0.12 + CGFloat(random.unit())*0.16)
            }
            for y in stride(from: 87, to: 122, by: 6) {
                let spread = (y-80)/3
                p.rect(599-spread + random.int(7), y, 11+spread, 1, 0x92C8CB, alpha: 0.23)
            }
            if realm == .moonshore {
                island(p, x: 130, y: 88, width: 94, palette: palette)
                island(p, x: 850, y: 98, width: 107, palette: palette)
                boat(p, x: 625, y: 104)
            }

            // Stepped coastline. Walkable bounds are safely inset from every ledge.
            let coast: [(Int, Int)] = [(25,143),(62,143),(62,130),(130,130),(130,122),(208,122),(208,132),(285,132),(285,124),(365,124),(365,116),(458,116),(458,127),(550,127),(550,117),(636,117),(636,125),(740,125),(740,119),(823,119),(823,129),(935,129),(935,139),(996,139),(996,728),(967,728),(967,744),(879,744),(879,737),(776,737),(776,747),(680,747),(680,739),(566,739),(566,750),(449,750),(449,742),(340,742),(340,748),(247,748),(247,736),(139,736),(139,745),(65,745),(65,730),(25,730)]
            p.polygon(coast.map { ($0.0, $0.1+10) }, palette.cliffDeep)
            p.polygon(coast.map { ($0.0, $0.1+5) }, palette.cliff)
            p.polygon(coast, palette.ground)
            // Large irregular color areas keep the ground from looking like noise.
            for _ in 0..<95 {
                let x = 40+random.int(930), y = 145+random.int(560)
                p.ellipse(x, y, 25+random.int(90), 12+random.int(45), random.int(2) == 0 ? palette.groundLight : palette.groundDark, alpha: 0.36)
            }
            // Border strata and broken grass tufts emphasize vertical cliff faces.
            for x in stride(from: 30, to: 995, by: 11) {
                let lower = 740 + random.int(7)
                p.rect(x, lower, 3+random.int(9), 2, palette.cliffHighlight, alpha: 0.35)
                p.rect(x, lower+4, 2+random.int(7), 1, palette.cliffDeep)
            }
            for _ in 0..<150 {
                let side = random.int(2) == 0
                p.rect(side ? 28+random.int(16) : 979+random.int(14), 148+random.int(580), 3, 4+random.int(8), palette.cliffHighlight, alpha: 0.32)
            }

            // Hand-placed pools sit well outside the routes; the visual rims are
            // intentionally shallow decoration rather than hidden collision walls.
            for pool in pools(realm) {
                let x = Int(pool.minX/2), y = Int((worldSize.height-pool.maxY)/2)
                let w = Int(pool.width/2), h = Int(pool.height/2)
                p.ellipse(x-3, y-3, w+6, h+6, palette.groundDark)
                p.ellipse(x, y, w, h, palette.water)
                p.ellipse(x+3, y+2, w-6, h-5, palette.waterLight, alpha: 0.35)
                for _ in 0..<10 { p.rect(x+3+random.int(max(1,w-9)), y+3+random.int(max(1,h-7)), 3+random.int(6), 1, 0x85B7BD, alpha: 0.27) }
            }

            // Softly broken stone trails guide exploration without an intrusive arrow.
            for segment in paths {
                c.setStrokeColor(PixelPainter.color(palette.pathDark).cgColor)
                c.setLineWidth(24); c.setLineCap(.round); c.setLineJoin(.round)
                c.beginPath(); c.move(to: pixelPoint(segment.0)); c.addLine(to: pixelPoint(segment.1)); c.strokePath()
                c.setStrokeColor(PixelPainter.color(palette.path, alpha: 0.62).cgColor)
                c.setLineWidth(15)
                c.beginPath(); c.move(to: pixelPoint(segment.0)); c.addLine(to: pixelPoint(segment.1)); c.strokePath()
            }
            for _ in 0..<340 {
                let point = CGPoint(x: 140+CGFloat(random.unit())*1760, y: 135+CGFloat(random.unit())*1085)
                if paths.contains(where: { distance(point, toSegment: $0.0, $0.1) < 28 }) {
                    let pos = pixelPoint(point)
                    p.rect(Int(pos.x), Int(pos.y), 2+random.int(5), 1+random.int(3), palette.pathLight, alpha: 0.3)
                }
            }

            platform(p, center: pixelPoint(layout.beacon), radius: 47, palette: palette, runeMarks: true)
            platform(p, center: pixelPoint(layout.boss), radius: 90, palette: palette, runeMarks: false)
            for point in layout.runes { platform(p, center: pixelPoint(point), radius: 28, palette: palette, runeMarks: true) }
            platform(p, center: pixelPoint(layout.portal), radius: 32, palette: palette, runeMarks: false)
            // Small pixel grass clusters, wildflowers and fallen petals, drawn once.
            for _ in 0..<2800 {
                let point = CGPoint(x: 105+CGFloat(random.unit())*1838, y: 110+CGFloat(random.unit())*1130)
                if point.distance(to: layout.boss) < 172 || point.distance(to: layout.beacon) < 100 { continue }
                let nearPath = paths.contains(where: { distance(point, toSegment: $0.0, $0.1) < 30 })
                if nearPath && random.int(8) != 0 { continue }
                let pos = pixelPoint(point), x = Int(pos.x), y = Int(pos.y)
                let light = random.int(3) == 0
                let color = light ? palette.grassLight : palette.grass
                p.rect(x, y, 2, 4, color, alpha: 0.72)
                p.rect(x-2, y-2, 1, 4, color, alpha: 0.65)
                p.rect(x+3, y-1, 1, 3, color, alpha: 0.65)
                if random.int(11) == 0 {
                    let petal = palette.flowers[random.int(palette.flowers.count)]
                    p.rect(x-1, y-6, 4, 3, petal)
                    p.rect(x, y-7, 2, 5, petal)
                    p.rect(x, y-5, 2, 1, 0xE6C283)
                }
            }
            // Larger grass/flower assets add designed silhouette variation.
            for _ in 0..<185 {
                let point = CGPoint(x: 120+CGFloat(random.unit())*1810, y: 130+CGFloat(random.unit())*1090)
                if point.distance(to: layout.boss) < 190 || point.distance(to: layout.beacon) < 110 { continue }
                if paths.contains(where: { distance(point, toSegment: $0.0, $0.1) < 47 }) { continue }
                let pos = pixelPoint(point)
                let name = random.int(4) == 0 ? "flower" : "grass"
                let image = PixelArt.image(name, frame: random.int(8))
                image.draw(in: CGRect(x: pos.x-5, y: pos.y-10, width: image.size.width*0.7, height: image.size.height*0.7))
            }
            // Designed meadow clusters lend the reference's lush foreground rhythm;
            // all flowers are baked into this same terrain texture, never live nodes.
            for cluster in 0..<54 {
                let point = CGPoint(x: 145+CGFloat(random.unit())*1740,
                                    y: 170+CGFloat(random.unit())*1000)
                if point.distance(to:layout.boss) < 215 || point.distance(to:layout.beacon) < 125 { continue }
                if paths.contains(where: { distance(point,toSegment:$0.0,$0.1) < 58 }) { continue }
                let center = pixelPoint(point)
                let petalFrame = (cluster + realm.rawValue*2) % 8
                for stem in 0..<(4+random.int(5)) {
                    let x = center.x + CGFloat(random.int(33)-16)
                    let y = center.y + CGFloat(random.int(19)-9)
                    let image = PixelArt.image(stem%3 == 0 ? "grass" : "flower", frame: (petalFrame+stem%2)%8)
                    let scale: CGFloat = stem%3 == 0 ? 0.95 : 0.85
                    image.draw(in:CGRect(x:x-6,y:y-14,width:image.size.width*scale,height:image.size.height*scale))
                }
            }
            // Four repeating architectural details are placed around the arena.
            for angle in [Double.pi*0.25,Double.pi*0.75,Double.pi*1.25,Double.pi*1.75] {
                let x = Int(layout.boss.x/2 + cos(angle)*87)
                let y = Int((worldSize.height-layout.boss.y)/2 + sin(angle)*87)
                p.rect(x-4,y-8,8,13,palette.stoneDark)
                p.rect(x-5,y-10,10,4,palette.stoneLight)
                p.rect(x-2,y-8,2,10,palette.stone)
            }
            if completed {
                let pos = pixelPoint(layout.beacon)
                p.ellipse(Int(pos.x)-56, Int(pos.y)-30, 112, 60, 0xA9EBD5, alpha: 0.10)
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    private static func addAmbient(to root: SKNode, realm: Realm, palette: RealmPalette, completed: Bool) {
        var random = SeededRandom(seed: UInt64(1001 + realm.rawValue*179))
        // Ambient particles have fixed caps; disable this parent when reduced effects
        // are enabled. The scene can find it recursively by its stable name.
        let ambient = SKNode(); ambient.name = "ambientEffects"; ambient.zPosition = 40
        root.addChild(ambient)
        for index in 0..<32 {
            let point = CGPoint(x: 100+CGFloat(random.unit())*1848, y: 120+CGFloat(random.unit())*1100)
            let light = SKSpriteNode(color: PixelPainter.color(palette.mote), size: CGSize(width: index%4==0 ? 4 : 2, height: index%4==0 ? 4 : 2))
            light.position = point; light.alpha = 0.2+CGFloat(random.unit())*0.5
            light.blendMode = .add
            let dx = CGFloat(random.unit()*35-17), dy = CGFloat(random.unit()*35+15)
            let time = 2.5+random.unit()*3.5
            light.run(.repeatForever(.sequence([
                .group([.moveBy(x: dx, y: dy, duration: time), .fadeAlpha(to: 0.6, duration: time)]),
                .group([.moveBy(x: -dx, y: -dy, duration: time), .fadeAlpha(to: 0.05, duration: time)])
            ])))
            ambient.addChild(light)
        }
        for index in 0..<9 {
            let ripple = SKSpriteNode(color: PixelPainter.color(palette.waterLight), size: CGSize(width: 30+CGFloat(index%4)*17, height: 2))
            ripple.position = CGPoint(x: 150+CGFloat(index)*215, y: 1304+CGFloat(index%3)*28)
            ripple.alpha = 0.16; ripple.zPosition = -900
            let time = 2.2+Double(index%3)*0.8
            ripple.run(.repeatForever(.sequence([.group([.moveBy(x: 14,y:0,duration: time),.fadeAlpha(to:0.32,duration:time)]),.group([.moveBy(x:-14,y:0,duration:time),.fadeAlpha(to:0.08,duration:time)])])))
            root.addChild(ripple)
        }
        let moonGlow = glowNode(color: 0x86BDBB, size: 235)
        moonGlow.position = CGPoint(x: 1200, y: 1402); moonGlow.alpha = 0.12; moonGlow.zPosition = -899
        root.addChild(moonGlow)
        if realm == .glassmarsh || realm == .eclipseCrown {
            for point in [CGPoint(x: 410,y:730),CGPoint(x:1420,y:1050),CGPoint(x:1550,y:570)] {
                let glow = glowNode(color: realm == .glassmarsh ? 0x69C8D5 : 0xAE8DCB, size: 280)
                glow.position = point; glow.alpha = 0.12; glow.zPosition = -800
                root.addChild(glow)
            }
        }
    }

    private static func platform(_ p: PixelPainter, center: CGPoint, radius: Int, palette: RealmPalette, runeMarks: Bool) {
        let x = Int(center.x), y = Int(center.y)
        p.ellipse(x-radius-4,y-radius/2-4,radius*2+8,radius+8,palette.groundDark)
        p.ellipse(x-radius,y-radius/2,radius*2,radius,palette.stoneDark)
        p.ellipse(x-radius+4,y-radius/2+3,radius*2-8,radius-6,palette.stone)
        p.ellipse(x-radius+8,y-radius/2+5,radius*2-16,radius-10,palette.pathDark)
        for angle in stride(from: 0.0, to: Double.pi*2, by: Double.pi/8) {
            let px = x + Int(cos(angle)*Double(radius-3))
            let py = y + Int(sin(angle)*Double(radius-3)/2)
            p.rect(px-2,py-1,4,2,palette.stoneLight)
        }
        if runeMarks {
            p.rect(x-3,y-radius/2+8,6,2,palette.rune)
            p.rect(x-2,y+radius/2-10,4,2,palette.rune)
            p.rect(x-radius+10,y-2,2,4,palette.rune)
            p.rect(x+radius-12,y-2,2,4,palette.rune)
        }
        // Mortar cracks, carefully restrained so a platform does not become a grid.
        p.rect(x-radius/2,y-3,radius/3,1,palette.stoneDark)
        p.rect(x+radius/4,y+6,radius/3,1,palette.stoneDark)
    }

    private static func mountain(_ p: PixelPainter, x: Int, y: Int, width: Int, height: Int, color: UInt32) {
        let w = width, h = height
        p.polygon([(x,y),(x+w/9,y-h/3),(x+w/5,y-h/3),(x+w/5,y-h/2),(x+w/3,y-h/2),(x+w/3,y-h),(x+w/2,y-h),(x+w/2,y-h*2/3),(x+w*2/3,y-h*2/3),(x+w*2/3,y-h/3),(x+w*4/5,y-h/3),(x+w,y)], color)
    }

    private static func island(_ p: PixelPainter, x: Int, y: Int, width: Int, palette: RealmPalette) {
        p.ellipse(x-3,y+6,width+6,12,palette.waterLight,alpha:0.22)
        p.polygon([(x,y+9),(x+8,y+3),(x+width/3,y),(x+width*2/3,y+2),(x+width-6,y+5),(x+width,y+11),(x+width-14,y+15),(x+8,y+14)],palette.cliff)
        p.polygon([(x+5,y+5),(x+width/3,y-4),(x+width*2/3,y-2),(x+width-4,y+7),(x+width-15,y+10),(x+10,y+9)],palette.groundLight)
        p.rect(x+width/3,y-7,9,5,palette.grass)
    }

    private static func boat(_ p: PixelPainter, x: Int, y: Int) {
        p.polygon([(x,y),(x+39,y),(x+31,y+9),(x+10,y+9)],0x73504B)
        p.rect(x+17,y-24,2,25,0x8B7B68)
        p.polygon([(x+20,y-23),(x+20,y-3),(x+34,y-3),(x+31,y-20)],0xB8C4BF)
        p.rect(x+20,y-18,3,11,0xCFD7CB)
        p.rect(x+5,y+11,31,1,0xA3B9AF,alpha:0.28)
    }

    private static func pools(_ realm: Realm) -> [CGRect] {
        switch realm {
        case .moonshore: return [CGRect(x: 1320,y:1130,width:100,height:70)]
        case .briarwild: return [CGRect(x: 620,y:790,width:155,height:95)]
        case .glassmarsh: return [CGRect(x: 610,y:870,width:160,height:100),CGRect(x:1400,y:1100,width:130,height:80),CGRect(x:1480,y:470,width:110,height:80)]
        case .emberRuins: return []
        case .eclipseCrown: return [CGRect(x:680,y:950,width:100,height:65),CGRect(x:1450,y:800,width:110,height:80)]
        }
    }

    private static func enemySpawns(_ realm: Realm) -> [EnemySpawn] {
        let positions = [CGPoint(x:680,y:1010),CGPoint(x:1370,y:1010),CGPoint(x:430,y:840),
                         CGPoint(x:1690,y:740),CGPoint(x:1450,y:610),CGPoint(x:800,y:590),
                         CGPoint(x:360,y:440),CGPoint(x:1380,y:350),CGPoint(x:750,y:340),
                         CGPoint(x:1770,y:520),CGPoint(x:530,y:650),CGPoint(x:1240,y:530)]
        let groups: [[EnemyKind]] = [
            [.slime,.boar,.slime,.hornet,.boar,.slime,.boar,.hornet,.slime,.boar,.slime,.hornet],
            [.boar,.hornet,.slime,.boar,.hornet,.boar,.wraith,.hornet,.boar,.slime,.hornet,.wraith],
            [.wraith,.slime,.wraith,.hornet,.wraith,.knight,.slime,.wraith,.hornet,.knight,.wraith,.slime],
            [.knight,.boar,.knight,.wraith,.hornet,.knight,.boar,.knight,.wraith,.knight,.hornet,.wraith],
            [.knight,.wraith,.hornet,.knight,.wraith,.boar,.knight,.wraith,.knight,.hornet,.wraith,.knight]
        ]
        return zip(positions, groups[realm.rawValue]).map { EnemySpawn(kind: $0.1, position: $0.0) }
    }

    static func trailSegments() -> [(CGPoint,CGPoint)] { trailSegments(RealmLayout(.moonshore)) }

    private static func trailSegments(_ layout: RealmLayout) -> [(CGPoint,CGPoint)] {
        let fork = CGPoint(x: layout.spawn.x, y: 1010)
        let west = layout.westJunction, east = layout.eastJunction
        let south = CGPoint(x: (layout.beacon.x+layout.boss.x)/2, y: 540)
        return [(layout.spawn,fork),(fork,layout.npc),(fork,layout.beacon),
                (fork,layout.runes[0]),(layout.runes[0],west),(west,layout.beacon),
                (fork,east),(east,layout.runes[1]),(east,layout.beacon),
                (layout.beacon,south),(south,layout.boss),
                (west,layout.chests[1]),(layout.chests[1],layout.runes[2]),
                (layout.runes[2],layout.boss),(east,layout.chests[0]),
                (layout.chests[0],layout.portal),(layout.boss,layout.portal),
                (layout.chests[0],south)]
    }

    private static func pixelPoint(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x/2, y: (worldSize.height-point.y)/2) }
    private static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
        guard length > 0 else { return p.distance(to:a) }
        let t = min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/length))
        return hypot(p.x-(a.x+t*dx),p.y-(a.y+t*dy))
    }
}

/// A compact shared topology with distinct positions produces clear, connected
/// routes for every realm. All values stay well inside the playable coast.
private struct RealmLayout {
    let spawn = CGPoint(x: 1024, y: 1120)
    let npc = CGPoint(x: 880, y: 1080)
    let runes: [CGPoint]
    let beacon: CGPoint
    let boss: CGPoint
    let chests: [CGPoint]
    let portal: CGPoint
    let westJunction: CGPoint
    let eastJunction: CGPoint

    init(_ realm: Realm) {
        switch realm {
        case .moonshore:
            runes = [CGPoint(x:360,y:970),CGPoint(x:1680,y:910),CGPoint(x:530,y:340)]
            beacon = CGPoint(x:1024,y:780); boss = CGPoint(x:1024,y:290)
            chests = [CGPoint(x:1650,y:430),CGPoint(x:280,y:610)]
            portal = CGPoint(x:1730,y:220)
            westJunction = CGPoint(x:610,y:850); eastJunction = CGPoint(x:1440,y:840)
        case .briarwild:
            runes = [CGPoint(x:400,y:900),CGPoint(x:1580,y:1080),CGPoint(x:1600,y:440)]
            beacon = CGPoint(x:820,y:740); boss = CGPoint(x:1060,y:300)
            chests = [CGPoint(x:1250,y:580),CGPoint(x:360,y:370)]
            portal = CGPoint(x:1750,y:220)
            westJunction = CGPoint(x:550,y:600); eastJunction = CGPoint(x:1430,y:800)
        case .glassmarsh:
            runes = [CGPoint(x:420,y:1050),CGPoint(x:530,y:480),CGPoint(x:1670,y:680)]
            beacon = CGPoint(x:1260,y:770); boss = CGPoint(x:1050,y:280)
            chests = [CGPoint(x:1630,y:1080),CGPoint(x:300,y:720)]
            portal = CGPoint(x:1770,y:220)
            westJunction = CGPoint(x:700,y:820); eastJunction = CGPoint(x:1540,y:880)
        case .emberRuins:
            runes = [CGPoint(x:340,y:870),CGPoint(x:1610,y:950),CGPoint(x:1710,y:390)]
            beacon = CGPoint(x:1010,y:850); boss = CGPoint(x:930,y:300)
            chests = [CGPoint(x:1390,y:600),CGPoint(x:400,y:310)]
            portal = CGPoint(x:1780,y:210)
            westJunction = CGPoint(x:570,y:640); eastJunction = CGPoint(x:1400,y:810)
        case .eclipseCrown:
            runes = [CGPoint(x:480,y:1000),CGPoint(x:1600,y:1030),CGPoint(x:500,y:380)]
            beacon = CGPoint(x:1050,y:730); boss = CGPoint(x:1050,y:270)
            chests = [CGPoint(x:1580,y:480),CGPoint(x:270,y:650)]
            portal = CGPoint(x:1750,y:220)
            westJunction = CGPoint(x:610,y:780); eastJunction = CGPoint(x:1440,y:780)
        }
    }
}

private struct RealmPalette {
    let sky: UInt32, farMountain: UInt32, water: UInt32, waterLight: UInt32
    let ground: UInt32, groundLight: UInt32, groundDark: UInt32, grass: UInt32, grassLight: UInt32
    let path: UInt32, pathDark: UInt32, pathLight: UInt32, cliff: UInt32, cliffDeep: UInt32, cliffHighlight: UInt32
    let stone: UInt32, stoneLight: UInt32, stoneDark: UInt32, rune: UInt32, lamp: UInt32, mote: UInt32
    let flowers: [UInt32]

    init(_ realm: Realm) {
        switch realm {
        case .moonshore:
            sky=0x0D1537; farMountain=0x293B5C; water=0x173A62; waterLight=0x467C98
            ground=0x304E51; groundLight=0x3C6058; groundDark=0x233F49; grass=0x4C765F; grassLight=0x79916B
            path=0x74776A; pathDark=0x4E625E; pathLight=0xB6B49B; cliff=0x677377; cliffDeep=0x2E485E; cliffHighlight=0x97A2A0
            stone=0x61777B; stoneLight=0xA8B6AD; stoneDark=0x3B5463; rune=0x7AABA5; lamp=0xFFCC8C; mote=0xB3DFB0
            flowers=[0xDBDCCE,0xB6A2CA,0xDF9BA5,0xD8B576,0x9CBAD0]
        case .briarwild:
            sky=0x101B34; farMountain=0x294445; water=0x183F4C; waterLight=0x447D7A
            ground=0x294A46; groundLight=0x33574B; groundDark=0x213B40; grass=0x517C5C; grassLight=0x7A9B69
            path=0x6D7360; pathDark=0x485F50; pathLight=0xB2B490; cliff=0x586C66; cliffDeep=0x293F4D; cliffHighlight=0x859A83
            stone=0x556E6D; stoneLight=0x98A791; stoneDark=0x354F52; rune=0x91BAA1; lamp=0xE9CB91; mote=0xC0E9A0
            flowers=[0xE2C9BF,0xB9A0C1,0xDB8FAD,0xCEBB85,0xAEC9B6]
        case .glassmarsh:
            sky=0x171A3B; farMountain=0x3A4269; water=0x293D62; waterLight=0x638AA3
            ground=0x394F63; groundLight=0x465C70; groundDark=0x2B3E56; grass=0x5F8090; grassLight=0x8EA4A0
            path=0x7B8391; pathDark=0x556375; pathLight=0xBAC4CE; cliff=0x68788F; cliffDeep=0x354363; cliffHighlight=0x9BAEC2
            stone=0x728193; stoneLight=0xB4C5D2; stoneDark=0x465A75; rune=0xADD9E2; lamp=0xA3E6EA; mote=0xC2EAF2
            flowers=[0xCFD9E9,0xBCB2DF,0xD7BBDD,0x93D3D4,0xAEC2E7]
        case .emberRuins:
            sky=0x251A38; farMountain=0x493B55; water=0x3E3A56; waterLight=0x7B687D
            ground=0x50444F; groundLight=0x615054; groundDark=0x3D3748; grass=0x806667; grassLight=0xAA8273
            path=0x928075; pathDark=0x6B5C5D; pathLight=0xCBB49A; cliff=0x8D7475; cliffDeep=0x4A3D54; cliffHighlight=0xB69486
            stone=0x82727B; stoneLight=0xC4AAAB; stoneDark=0x544B60; rune=0xD7A9A3; lamp=0xFFB67D; mote=0xEFB38A
            flowers=[0xC9B4A5,0xAD90AF,0xCD8395,0xD3A574,0xB29CA8]
        case .eclipseCrown:
            sky=0x14132F; farMountain=0x343250; water=0x272B49; waterLight=0x626782
            ground=0x3D3C57; groundLight=0x4D4866; groundDark=0x2F304A; grass=0x6F6686; grassLight=0x9D8FA7
            path=0x827B91; pathDark=0x58566E; pathLight=0xBCB8C5; cliff=0x79778F; cliffDeep=0x3B3C57; cliffHighlight=0xAAA9B8
            stone=0x7C7C94; stoneLight=0xBEC6CF; stoneDark=0x4E526D; rune=0xB7CFE0; lamp=0xB7D8F4; mote=0xD4C8EF
            flowers=[0xD6D5DE,0xB1A3CD,0xC5A9CE,0xB8C5D5,0xD4C6AB]
        }
    }
}
