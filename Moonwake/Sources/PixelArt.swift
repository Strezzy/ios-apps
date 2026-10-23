import UIKit
import SpriteKit

/// Small, deliberately authored pixel drawings. The same cached texture is shared by
/// every matching actor; animation changes its pose rather than stretching artwork.
@MainActor enum PixelArt {
    private static var textures: [String: SKTexture] = [:]
    private static var images: [String: UIImage] = [:]

    static func texture(_ name: String, frame: Int = 0) -> SKTexture {
        let key = "\(name)-\(positiveFrame(frame))"
        if let texture = textures[key] { return texture }
        let result = SKTexture(image: image(name, frame: frame))
        result.filteringMode = .nearest
        textures[key] = result
        return result
    }

    static func sprite(_ name: String, frame: Int = 0, scale: CGFloat = 2) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture(name, frame: frame))
        node.setScale(scale)
        return node
    }

    static func image(_ name: String, frame: Int = 0) -> UIImage {
        let f = positiveFrame(frame)
        let key = "\(name)-\(f)"
        if let image = images[key] { return image }
        let dimensions: CGSize
        switch name {
        case "hero": dimensions = CGSize(width: 32, height: 40)
        case "moss": dimensions = CGSize(width: 28, height: 30)
        case "wisp": dimensions = CGSize(width: 20, height: 20)
        case "sword": dimensions = CGSize(width: 48, height: 16)
        case "tree": dimensions = CGSize(width: 64, height: 84)
        case "ruin": dimensions = CGSize(width: 64, height: 56)
        case "beacon", "portal": dimensions = CGSize(width: 48, height: 60)
        case "boss0", "boss1", "boss2", "boss3", "boss4": dimensions = CGSize(width: 48, height: 48)
        case "grass", "flower": dimensions = CGSize(width: 16, height: 20)
        case "rune", "chest": dimensions = CGSize(width: 26, height: 28)
        case "keeper": dimensions = CGSize(width: 28, height: 40)
        default: dimensions = CGSize(width: 36, height: 36)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let result = UIGraphicsImageRenderer(size: dimensions, format: format).image { renderer in
            let p = PixelPainter(renderer.cgContext)
            p.context.setShouldAntialias(false)
            p.context.interpolationQuality = .none
            switch name {
            case "hero": hero(p, f)
            case "moss": moss(p, f)
            case "wisp": wisp(p, f)
            case "sword": sword(p, f)
            case "slime": slime(p, f)
            case "boar": boar(p, f, boss: false)
            case "hornet": hornet(p, f)
            case "wraith": wraith(p, f)
            case "knight": knight(p, f)
            case "boss0": boar(p, f, boss: true)
            case "boss1": matriarch(p, f)
            case "boss2": revenant(p, f)
            case "boss3": warden(p, f)
            case "boss4": hollowMoon(p, f)
            case "tree": tree(p, f)
            case "bush": bush(p, f)
            case "flower": flower(p, f)
            case "grass": grass(p, f)
            case "rock": rock(p, f)
            case "crystal": crystal(p, f)
            case "rune": rune(p, f)
            case "beacon": beacon(p, f)
            case "chest": chest(p, f)
            case "portal": portal(p, f)
            case "keeper": keeper(p, f)
            case "ruin": ruin(p, f)
            default: crystal(p, f)
            }
        }
        images[key] = result
        return result
    }

    static func glowTexture() -> SKTexture {
        if let texture = textures["__glow"] { return texture }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { renderer in
            let c = renderer.cgContext
            let colors = [UIColor.white.withAlphaComponent(0.85).cgColor,
                          UIColor.white.withAlphaComponent(0.20).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.28, 1]) {
                c.drawRadialGradient(gradient, startCenter: CGPoint(x: 48, y: 48), startRadius: 0,
                                     endCenter: CGPoint(x: 48, y: 48), endRadius: 48, options: [])
            }
        }
        let texture = SKTexture(image: image); textures["__glow"] = texture
        return texture
    }

    private static func positiveFrame(_ frame: Int) -> Int { ((frame % 8) + 8) % 8 }

    private static func hero(_ p: PixelPainter, _ f: Int) {
        let bob = (f == 1 || f == 3) ? 1 : 0
        let step = [0, 2, 0, -2, 0, 2, 0, -2][f]
        p.ellipse(5, 37, 25, 3, 0x05111F, alpha: 0.42)
        // Separate trouser and boot shapes preserve a readable walking silhouette.
        p.rect(10 + step, 30 + bob, 7, 8 - bob, 0x101B35)
        p.rect(21 - step, 30 + bob, 7, 8 - bob, 0x101B35)
        p.rect(7 + step, 37, 10, 3, 0x081223)
        p.rect(21 - step, 37, 11, 3, 0x081223)
        p.rect(11 + step, 31 + bob, 3, 5, 0x263B52)
        p.rect(23 - step, 31 + bob, 2, 5, 0x293F56)
        p.rect(10, 24 + bob, 18, 10, 0x102C3C)
        p.rect(12, 25 + bob, 11, 7, 0x245365)
        p.rect(11, 31 + bob, 17, 3, 0x102136)
        p.rect(17, 30 + bob, 3, 2, 0xBFA770)
        p.rect(27, 25 + bob, 5, 5, 0xDBA895)
        p.rect(27, 25 + bob, 4, 2, 0xF8D2AE)
        p.rect(7, 26 + bob, 5, 6, 0x934D56)
        // Windswept scarf, shaded red and coral with a different trailing fold.
        p.polygon([(2,22+bob),(10,23+bob),(13,25+bob),(7,27+bob),(2,26+bob),(0,28+bob),(0,23+bob)], 0x9C3049)
        p.rect(0, 21 + bob + (f % 2), 6, 4, 0xD64A60)
        p.rect(5, 23 + bob, 6, 3, 0xE05C66)
        p.rect(11, 22 + bob, 17, 5, 0xBC3954)
        p.rect(11, 22 + bob, 15, 2, 0xED7180)
        p.rect(15, 23 + bob, 11, 2, 0xD54E64)
        // Warm face against cool hair. The one-pixel eyes remain crisp at all scales.
        p.rect(13, 13 + bob, 15, 10, 0xB7787B)
        p.rect(16, 13 + bob, 12, 10, 0xEDB4A1)
        p.rect(19, 14 + bob, 9, 7, 0xF8CFB4)
        p.rect(17, 16 + bob, 2, 5, 0x292130)
        p.rect(25, 16 + bob, 2, 5, 0x292130)
        p.rect(28, 17 + bob, 2, 3, 0xE7AB95)
        p.rect(21, 21 + bob, 3, 1, 0xB97D7D)
        // The pale, asymmetric silhouette echoes the supplied reference.
        p.polygon([(5,8+bob),(10,8+bob),(10,5+bob),(15,5+bob),(15,2+bob),(21,2+bob),(21,0+bob),(23,0+bob),(23,5+bob),(28,5+bob),(28,8+bob),(30,8+bob),(30,15+bob),(27,15+bob),(27,13+bob),(24,13+bob),(24,17+bob),(21,17+bob),(21,14+bob),(18,14+bob),(18,18+bob),(15,18+bob),(15,15+bob),(11,15+bob),(11,18+bob),(8,18+bob),(8,14+bob),(5,14+bob)], 0xD8E4ED)
        p.polygon([(6,9+bob),(11,9+bob),(11,6+bob),(16,6+bob),(16,3+bob),(22,3+bob),(22,6+bob),(27,6+bob),(27,9+bob),(29,9+bob),(29,12+bob),(24,12+bob),(24,14+bob),(20,14+bob),(20,12+bob),(16,12+bob),(16,15+bob),(12,15+bob),(12,13+bob),(6,13+bob)], 0xF3FFF7)
        p.rect(9, 14 + bob, 3, 3, 0xAEBACF)
        p.rect(15, 15 + bob, 2, 4, 0xC4CDDE)
        p.rect(24, 12 + bob, 3, 2, 0xD0E4E9)
    }

    private static func moss(_ p: PixelPainter, _ f: Int) {
        let s = f % 2
        p.ellipse(3, 27, 23, 3, 0x071C27, alpha: 0.4)
        p.rect(6, 21, 5, 8-s, 0xA67839); p.rect(19, 21, 5, 8+s, 0x967037)
        p.rect(3, 14+s, 23, 11, 0xA77F3E); p.rect(6, 14+s, 17, 11, 0xC09C50)
        p.rect(1, 15+s, 6, 9, 0xA17B42); p.rect(2, 15+s, 3, 7, 0xD2AF73)
        p.rect(24, 15+s, 4, 7, 0x866735); p.rect(7, 9+s, 19, 11, 0xD1A546)
        p.rect(9, 11+s, 15, 8, 0x183738); p.rect(10, 10+s, 13, 2, 0x8B773E)
        p.rect(11, 13+s, 3, 4, 0xF6D863); p.rect(19, 13+s, 3, 4, 0xF6D863)
        p.rect(14, 17+s, 5, 1, 0x355151)
        p.polygon([(8,9+s),(8,5+s),(12,5+s),(12,2+s),(17,2+s),(17,4+s),(20,4+s),(20,7+s),(23,7+s),(23,10+s)], 0x466B38)
        p.rect(10, 5+s, 7, 4, 0x64863E); p.rect(13, 2+s, 3, 5, 0x84954A)
        p.rect(18, 6+s, 2, 2, 0xC2AE4F); p.rect(10, 7+s, 2, 2, 0xCBA254)
        p.rect(9, 21, 3, 2, 0xD8B975); p.rect(19, 21, 3, 1, 0xE3C47D)
    }

    private static func wisp(_ p: PixelPainter, _ f: Int) {
        p.ellipse(0, 0, 20, 20, 0xF4AB32, alpha: 0.15)
        p.ellipse(2, 2, 16, 16, 0xF6C45B)
        p.ellipse(4, 4, 12, 12, 0xE7952B)
        p.ellipse(5, 5, 10, 10, 0xF8AC35)
        p.rect(5, 4, 3, 2, 0xFFF6BC); p.rect(4, 6, 2, 3, 0xFFF6BC)
        p.rect(7, 10, 2, f == 6 ? 1 : 3, 0xA74E2C)
        p.rect(12, 10, 2, f == 6 ? 1 : 3, 0xA74E2C)
        p.rect(9, 14, 3, 1, 0xCA6930)
    }

    private static func sword(_ p: PixelPainter, _ f: Int) {
        p.polygon([(10,4),(37,4),(37,2),(42,2),(42,4),(46,4),(46,6),(48,6),(48,10),(43,10),(43,12),(36,12),(36,11),(10,11)], 0x47DDD4, alpha: 0.45)
        p.polygon([(11,5),(37,5),(37,3),(40,3),(40,5),(45,5),(45,7),(47,7),(45,9),(39,9),(39,11),(11,10)], 0xAEFFEC)
        p.polygon([(14,6),(39,6),(39,5),(43,5),(43,7),(46,7),(43,9),(14,9)], 0xF0FFF9)
        p.rect(9, 2, 3, 12, 0x8FEDE0); p.rect(8, 3, 2, 10, 0x395E70)
        p.rect(2, 6, 7, 4, 0x837754); p.rect(3, 6, 2, 4, 0xD3C690)
        p.rect(0, 5, 3, 6, 0x588F91); p.rect(0, 6, 2, 3, 0xA5EEDB)
        p.rect(21 + (f % 4)*4, 6, 2, 1, 0xFFFFFF)
    }

    private static func slime(_ p: PixelPainter, _ f: Int) {
        let s = f % 2
        p.ellipse(4, 28, 27, 6, 0x071B24, alpha: 0.4)
        p.ellipse(5-s, 9+s*2, 26+s*2, 23-s*2, 0x214C52)
        p.ellipse(7-s, 10+s*2, 22+s*2, 19-s*2, 0x418E84)
        p.ellipse(9, 12+s, 18, 12, 0x71B7A3)
        p.rect(10, 13+s, 6, 3, 0xB6DBC1); p.rect(9, 16+s, 3, 2, 0xA1D3BA)
        p.rect(12, 22+s, 3, 4, 0x15313B); p.rect(23, 22+s, 3, 4, 0x15313B)
        p.rect(17, 27+s, 4, 1, 0x275959)
    }

    private static func boar(_ p: PixelPainter, _ f: Int, boss: Bool) {
        if boss { p.context.saveGState(); p.context.translateBy(x: 1, y: 2); p.context.scaleBy(x: 1.3, y: 1.3) }
        let s = f % 2
        p.ellipse(3, 31, 29, 4, 0x071622, alpha: 0.45)
        p.rect(7, 25, 5, 10-s, 0x332331); p.rect(25, 24, 5, 10+s, 0x392433)
        p.ellipse(4, 8+s, 28, 23, 0x4C2A3C); p.ellipse(6, 6+s, 24, 23, 0x794052)
        p.polygon([(10,8+s),(15,3+s),(22,5+s),(27,11+s),(27,25+s),(9,25+s)], 0x8F4A55)
        p.rect(15, 6+s, 7, 3, 0xB65F62); p.rect(14, 10+s, 11, 3, 0x9E5360)
        p.ellipse(8, 16+s, 20, 16, 0x523243); p.ellipse(11, 20+s, 16, 10, 0xB06A6B)
        p.rect(14, 23+s, 3, 5, 0x4E2532); p.rect(21, 23+s, 3, 5, 0x4E2532)
        p.rect(11, 17+s, 3, 3, 0xE2AB69); p.rect(24, 17+s, 3, 3, 0xE2AB69)
        p.polygon([(7,12+s),(4,14+s),(3,21+s),(5,27+s),(11,29+s),(12,25+s),(8,23+s)], 0xBDC4AB)
        p.polygon([(7,12+s),(5,16+s),(5,22+s),(8,25+s),(10,25+s),(7,21+s)], 0xF3E6BC)
        p.polygon([(28,11+s),(31,15+s),(33,22+s),(30,28+s),(25,30+s),(24,26+s),(28,22+s)], 0xBEC7AD)
        p.polygon([(28,11+s),(30,16+s),(30,22+s),(27,26+s),(29,26+s),(32,22+s),(30,16+s)], 0xEFE5BD)
        p.rect(32, 20+s, 3, 3, 0x412534); p.rect(34, 17+s, 2, 4, 0x412534)
        if boss {
            p.rect(12, 5, 3, 3, 0x6D8C52); p.rect(18, 3, 4, 3, 0x8DA462)
            p.rect(24, 7, 3, 4, 0x4F7750); p.context.restoreGState()
        }
    }

    private static func hornet(_ p: PixelPainter, _ f: Int) {
        let up = f % 2 == 0
        p.polygon(up ? [(17,14),(3,7),(1,1),(8,2),(18,10)] : [(16,15),(1,13),(2,20),(9,19),(18,17)], 0xB6DED4, alpha: 0.75)
        p.polygon(up ? [(20,14),(29,3),(35,2),(33,9),(23,17)] : [(20,15),(34,12),(35,17),(29,20),(20,18)], 0xC6E9DC, alpha: 0.72)
        p.ellipse(10, 9, 18, 22, 0x3A2630); p.ellipse(12, 11, 14, 18, 0x70503C)
        p.rect(12, 14, 14, 4, 0xC29A4D); p.rect(13, 22, 12, 3, 0xBA8F43)
        p.rect(15, 17, 3, 3, 0xF3D578); p.rect(22, 17, 3, 3, 0xF3D578)
        p.rect(18, 29, 2, 5, 0xC6C5B5); p.rect(13, 7, 2, 4, 0x332632)
        p.rect(23, 7, 2, 4, 0x332632)
    }

    private static func wraith(_ p: PixelPainter, _ f: Int) {
        let s = f % 2
        p.ellipse(5, 29, 26, 5, 0x10112C, alpha: 0.3)
        p.polygon([(7,30),(7,16+s),(10,7+s),(16,3+s),(22,4+s),(28,11+s),(29,28),(26,32),(22,28),(18,33),(14,29),(10,32)], 0x3D3867)
        p.polygon([(11,25),(10,15+s),(14,7+s),(20,6+s),(25,12+s),(25,26),(22,23),(18,29),(15,25)], 0x676CA0)
        p.polygon([(13,10+s),(19,8+s),(24,13+s),(23,19+s),(12,19+s)], 0x19243F)
        p.rect(14, 14+s, 3, 3, 0xA8FFF1); p.rect(21, 14+s, 3, 3, 0xA8FFF1)
        p.rect(13, 22+s, 3, 5, 0x8C98B9); p.rect(22, 22+s, 2, 4, 0x9096BE)
    }

    private static func knight(_ p: PixelPainter, _ f: Int) {
        let s = f % 2
        p.ellipse(4, 31, 29, 4, 0x071622, alpha: 0.4)
        p.rect(10, 26, 5, 8-s, 0x2A2841); p.rect(23, 26, 5, 8+s, 0x2A2841)
        p.rect(8, 15+s, 23, 16, 0x3F4361); p.rect(13, 17+s, 13, 11, 0x686788)
        p.rect(17, 17+s, 4, 10, 0xAF91A9); p.rect(6, 16+s, 7, 9, 0x6E7188)
        p.rect(10, 7+s, 19, 14, 0x39394F); p.rect(12, 4+s, 14, 14, 0x777B94)
        p.rect(14, 5+s, 9, 5, 0xAAA4AF); p.rect(11, 12+s, 18, 5, 0x262D45)
        p.rect(14, 13+s, 4, 2, 0xEFAB9D); p.rect(22, 13+s, 4, 2, 0xEFAB9D)
        p.rect(29, 8+s, 3, 22, 0xA4BBBE); p.rect(27, 24+s, 8, 2, 0xC7B18C)
    }

    private static func matriarch(_ p: PixelPainter, _ f: Int) {
        p.ellipse(3, 42, 42, 5, 0x071B25, alpha: 0.45)
        for i in 0..<4 {
            p.polygon([(7+i*8,33),(5+i*10,45),(10+i*9,45),(15+i*7,32)], 0x44533A)
        }
        p.ellipse(4, 14, 40, 27, 0x465E43); p.ellipse(8, 11, 32, 27, 0x6B8152)
        p.ellipse(12, 5, 25, 25, 0x907A56); p.ellipse(15, 10, 20, 19, 0x294840)
        p.rect(18, 17, 4, 4, 0xF7C475); p.rect(28, 17, 4, 4, 0xF7C475)
        p.polygon([(8,17),(3,8),(5,3),(8,10),(16,8),(18,1),(21,4),(20,12)], 0x77583F)
        p.polygon([(33,11),(35,3),(39,1),(38,9),(45,9),(43,15),(38,18)], 0x806245)
        p.ellipse(2, 10, 10, 7, 0x5C8858); p.ellipse(35, 8, 11, 8, 0x6E9059)
        p.rect(9, 9, 3, 3, 0xC695C7); p.rect(37, 7, 3, 3, 0xE4AEC5)
        p.rect(23, 27 + f%2, 3, 5, 0xC9C17B)
    }

    private static func revenant(_ p: PixelPainter, _ f: Int) {
        p.ellipse(3, 42, 42, 5, 0x10213D, alpha: 0.4)
        let c: UInt32 = f % 2 == 0 ? 0x9CE6E3 : 0xA6DAF0
        p.polygon([(6,39),(11,17),(17,8),(22,4),(30,9),(37,19),(44,40),(35,35),(31,46),(25,38),(18,45),(15,36)], 0x385B85)
        p.polygon([(13,32),(17,16),(24,8),(31,16),(36,33),(27,28),(21,38),(18,28)], 0x7AA9C4)
        p.polygon([(19,15),(25,11),(31,18),(28,24),(18,23)], 0x263D67)
        p.rect(20, 18, 3, 3, 0xE7FFFF); p.rect(27, 18, 3, 3, 0xE7FFFF)
        p.polygon([(4,23),(8,13),(12,26),(9,35)], c)
        p.polygon([(36,25),(41,12),(45,23),(40,36)], c)
        p.rect(23, 28, 4, 8, c); p.rect(24, 29, 2, 5, 0xE8FFF7)
        p.polygon([(19,7),(21,0),(24,6),(28,1),(30,8),(25,10)], 0xA9E4E5)
    }

    private static func warden(_ p: PixelPainter, _ f: Int) {
        p.ellipse(4, 43, 40, 5, 0x130F24, alpha: 0.45)
        p.rect(11, 33, 9, 13, 0x3D2D43); p.rect(30, 33, 9, 13, 0x3D2D43)
        p.rect(7, 18, 35, 23, 0x6B4354); p.rect(14, 19, 22, 19, 0x8C5961)
        p.rect(21, 20, 7, 15, 0xD77B62); p.rect(23, 23, 3, 8, 0xF5BE7E)
        p.rect(12, 7, 26, 18, 0x492F45); p.rect(16, 5, 18, 14, 0x9D6B6A)
        p.rect(13, 15, 24, 6, 0x28253C); p.rect(17, 17, 6, 2, 0xFFD692)
        p.rect(28, 17, 6, 2, 0xFFD692)
        p.polygon([(11,13),(6,5),(8,1),(14,7),(19,5),(19,11)], 0xD2A276)
        p.polygon([(31,11),(32,6),(39,1),(42,3),(39,11),(36,16)], 0xB88C6D)
        p.rect(2, 22, 8, 13, 0x9A6860); p.rect(39, 22, 7, 14, 0xA86E61)
        p.rect(2, 20+f%2, 5, 4, 0xE99D66); p.rect(40, 20+f%2, 4, 4, 0xE99D66)
    }

    private static func hollowMoon(_ p: PixelPainter, _ f: Int) {
        p.ellipse(3, 41, 42, 6, 0x0C0D24, alpha: 0.45)
        p.polygon([(4,40),(9,25),(10,15),(17,8),(31,8),(38,15),(39,25),(45,40),(37,38),(33,47),(27,40),(21,47),(15,40),(9,44)], 0x3E355D)
        p.polygon([(10,37),(16,15),(22,11),(29,12),(35,20),(39,37),(32,33),(25,41),(19,33)], 0x66547E)
        p.ellipse(13, 4, 23, 24, 0xC1CFD8); p.ellipse(17, 5, 20, 20, 0x29324F)
        p.rect(20, 12, 4, 4, 0xC8FFF0); p.rect(30, 12, 4, 4, 0xC8FFF0)
        p.rect(23, 22, 6, 2, 0x8198AF)
        p.polygon([(13,11),(10,4),(12,0),(16,5),(20,3),(21,8)], 0xD1C58D)
        p.polygon([(30,8),(33,2),(37,0),(37,7),(34,12)], 0xD1C58D)
        p.rect(23, 28 + f%2, 4, 8, 0x9BE9DA); p.rect(24, 29+f%2, 2, 5, 0xF4FFE9)
        p.rect(2, 30, 5, 6, 0x7899A4); p.rect(41, 30, 5, 6, 0x7899A4)
    }

    private static func tree(_ p: PixelPainter, _ f: Int) {
        let purple = f >= 4
        let dark: UInt32 = purple ? 0x282C4D : 0x133E3C
        let mid: UInt32 = purple ? 0x494267 : 0x235E50
        let light: UInt32 = purple ? 0x686082 : 0x407F64
        p.ellipse(8, 74, 48, 9, 0x061C2B, alpha: 0.4)
        p.polygon([(25,45),(40,43),(39,69),(47,78),(35,75),(31,81),(27,74),(18,78),(25,65)], 0x4A4144)
        p.rect(28, 48, 5, 25, 0x6D5B53); p.rect(34, 50, 3, 18, 0x413C43)
        p.ellipse(6, 20, 51, 43, dark); p.ellipse(0, 25, 35, 27, dark)
        p.ellipse(24, 12, 36, 35, dark); p.ellipse(13, 3, 36, 34, dark)
        p.ellipse(7, 21, 45, 32, mid); p.ellipse(8, 11, 41, 28, mid)
        p.ellipse(17, 4, 29, 24, light); p.ellipse(4, 27, 23, 16, light)
        p.ellipse(31, 20, 25, 18, light); p.ellipse(26, 42, 25, 11, mid)
        p.rect(21, 7, 11, 3, purple ? 0x82789B : 0x6A9978)
        p.rect(14, 16, 9, 3, purple ? 0x6E668A : 0x528E70)
        p.rect(39, 25, 9, 3, purple ? 0x83729B : 0x689675)
        p.rect(8, 33, 6, 3, purple ? 0x777193 : 0x6A9978)
        // Leaf clusters break the large canopy into overlapping lit planes. These
        // are designed shapes, rather than per-frame noise or stretched circles.
        let highlights: [(Int,Int,Int)] = [(23,5,8),(33,10,7),(17,13,8),(25,18,6),
            (9,26,7),(16,30,8),(5,35,5),(37,22,8),(44,28,7),(29,34,7),
            (34,43,7),(16,42,6),(47,36,6),(23,25,5)]
        for (index, leaf) in highlights.enumerated() {
            let color: UInt32 = index < 5 ? (purple ? 0x8F81A3 : 0x79A480) : (purple ? 0x756B91 : 0x5C9274)
            p.rect(leaf.0,leaf.1,leaf.2,2,color)
            p.rect(leaf.0+1,leaf.1-1,max(2,leaf.2-3),1,color)
            p.rect(leaf.0-1,leaf.1+2,max(2,leaf.2-2),2,purple ? 0x625A80 : 0x438467)
        }
        for leaf in [(11,22),(29,28),(38,37),(24,45),(49,31),(9,43),(34,16)] {
            p.rect(leaf.0,leaf.1,6,2,dark)
            p.rect(leaf.0+4,leaf.1+2,3,2,dark)
        }
        p.rect(3,29,3,4,mid); p.rect(0,34,3,5,mid)
        p.rect(57,28,3,5,mid); p.rect(53,37,5,3,mid)
        p.rect(18,2,6,3,mid); p.rect(37,1,4,3,mid)
        // Fine bark, twigs and hanging moss connect the crown to the ground.
        p.rect(29,55,2,14,0x8A7060); p.rect(32,63,2,10,0x3E3B42)
        p.rect(24,67,4,2,0x6E6254); p.rect(37,67,4,2,0x6E6254)
        p.rect(24,57,2,7,purple ? 0x62627C : 0x456F56)
        p.rect(40,52,2,8,purple ? 0x73718A : 0x5C855F)
        if f % 2 == 1 {
            p.rect(19, 34, 3, 3, 0xD6A3C2); p.rect(44, 29, 3, 3, 0xC88EB4)
            p.rect(30, 17, 3, 3, 0xE5B7C7)
        }
    }

    private static func bush(_ p: PixelPainter, _ f: Int) {
        p.ellipse(2, 27, 32, 7, 0x092532, alpha: 0.4)
        p.ellipse(2, 13, 20, 17, 0x204C43); p.ellipse(12, 7, 22, 23, 0x295F4C)
        p.ellipse(5, 11, 19, 15, 0x428261); p.ellipse(17, 10, 14, 11, 0x6A9669)
        p.rect(8, 13, 7, 2, 0x85AD78); p.rect(22, 12, 5, 2, 0x94B87B)
        if f % 2 == 0 { p.rect(10, 23, 3, 3, 0xC75D73); p.rect(24, 19, 3, 3, 0xDC7C86) }
    }

    private static func flower(_ p: PixelPainter, _ f: Int) {
        p.rect(7, 7, 2, 12, 0x4E805B); p.rect(4, 13, 4, 2, 0x69916C)
        p.rect(9, 11, 4, 2, 0x729E6D)
        let petals: [UInt32] = [0xD9E6D4,0xAFA6D0,0xE094B0,0xF1B774,0x99C1D6,0x917CAD,0xC76C87,0xD4D5CB]
        p.rect(4, 4, 9, 5, petals[f]); p.rect(6, 2, 5, 9, petals[f])
        p.rect(7, 5, 3, 3, 0xD4B56A); p.rect(7, 5, 2, 1, 0xF5D78C)
    }

    private static func grass(_ p: PixelPainter, _ f: Int) {
        let colors: [UInt32] = [0x4E8060,0x64976C,0x537B69,0x6B8C76,0x54757A,0x687385,0x816873,0x528B72]
        p.polygon([(7,19),(3,14),(2,8),(5,11),(8,17),(8,4),(10,3),(10,16),(13,10),(15,10),(12,18)], colors[f])
        p.rect(8, 10, 1, 8, 0xA2B384)
    }

    private static func rock(_ p: PixelPainter, _ f: Int) {
        p.ellipse(2, 27, 32, 6, 0x112938, alpha: 0.45)
        p.polygon([(3,25),(7,13),(15,8),(25,10),(32,19),(31,29),(22,32),(8,30)], 0x36485A)
        p.polygon([(6,23),(9,14),(16,10),(25,12),(29,20),(22,22),(18,28),(8,27)], 0x60717A)
        p.polygon([(10,14),(16,10),(24,12),(21,17),(14,19)], 0x7D8A8B)
        p.rect(9, 25, 8, 2, 0x637E70); p.rect(6, 22, 4, 2, 0x77916F)
        p.rect(20,16,2,5,0x485F6C); p.rect(22,20,4,1,0x485F6C)
        p.rect(11,20,3,1,0xA0A798); p.rect(25,25,2,1,0x83948F)
        p.rect(8,27,3,2,0x82976E); p.rect(13,28,4,1,0x4A7058)
        if f % 2 == 1 { p.rect(22, 14, 3, 6, 0x405768) }
    }

    private static func crystal(_ p: PixelPainter, _ f: Int) {
        let colors: [UInt32] = [0x79CFC4,0x9ABAE3,0xC8A9DD,0xECB18A,0xA8DCD2,0x8CA4D4,0xC79BD1,0x87CBB6]
        let color = colors[f]
        p.ellipse(3, 29, 31, 5, 0x112337, alpha: 0.4)
        p.polygon([(5,28),(4,16),(8,9),(13,16),(12,31)], 0x477388)
        p.polygon([(11,30),(11,13),(19,2),(25,12),(24,31)], color)
        p.polygon([(19,3),(19,29),(24,31),(25,12)], 0x5D8AA4)
        p.polygon([(19,3),(13,14),(15,25),(17,15)], 0xCEFFE9)
        p.polygon([(24,31),(24,20),(29,11),(34,19),(31,31)], color)
        p.rect(28, 18, 2, 9, 0xD1F1E6)
    }

    private static func rune(_ p: PixelPainter, _ f: Int) {
        let active = f % 2 == 1
        p.ellipse(1, 23, 24, 4, 0x082030, alpha: 0.4)
        p.polygon([(5,25),(4,10),(8,4),(18,3),(22,9),(22,25)], 0x334C61)
        p.polygon([(7,24),(7,10),(10,6),(18,5),(20,10),(20,23)], 0x567482)
        p.rect(8, 8, 2, 13, 0x6A8D93)
        let color: UInt32 = active ? 0xAFFFF0 : 0x517E8E
        p.rect(12, 10, 2, 11, color); p.rect(14, 10, 4, 2, color)
        p.rect(15, 12, 2, 3, color); p.rect(10, 15, 7, 2, color)
        p.rect(14, 19, 4, 2, color)
        p.rect(2, 24, 22, 3, 0x2D464B); p.rect(5, 24, 5, 2, 0x618465)
    }

    private static func beacon(_ p: PixelPainter, _ f: Int) {
        let active = f % 2 == 1
        p.ellipse(2, 52, 44, 7, 0x0B2135, alpha: 0.4)
        p.rect(6, 50, 36, 6, 0x40556D); p.rect(9, 46, 30, 6, 0x637587)
        p.rect(13, 40, 22, 8, 0x455F78); p.rect(16, 28, 16, 15, 0x4F6F84)
        p.rect(19, 29, 4, 13, 0x9DB6B5)
        p.rect(12, 25, 24, 6, 0x799594); p.rect(10, 22, 28, 5, 0x9BAA9D)
        p.rect(13, 20, 22, 4, 0x425B6E)
        p.polygon([(19,20),(16,13),(18,5),(22,9),(25,1),(29,9),(32,14),(29,20)], active ? 0xBFFFF0 : 0x45667D)
        p.polygon([(21,20),(21,13),(25,7),(28,13),(26,20)], active ? 0xF0FFF3 : 0x76919D)
        p.rect(8, 48, 9, 2, 0x9CB5AD); p.rect(31, 50, 8, 2, 0x7F9994)
        p.rect(22, 35, 4, 3, active ? 0xBDFDE3 : 0x7B8C88)
    }

    private static func chest(_ p: PixelPainter, _ f: Int) {
        let open = f % 2 == 1
        p.ellipse(0, 24, 26, 4, 0x0B2030, alpha: 0.4)
        p.rect(2, 13, 22, 12, 0x534438); p.rect(4, 14, 18, 9, 0x9C7246)
        p.rect(5, 15, 3, 9, 0xD1AE66); p.rect(19, 15, 3, 9, 0xC79F5A)
        p.rect(2, open ? 3 : 7, 22, open ? 8 : 9, 0x74533D)
        p.rect(4, open ? 3 : 7, 18, 3, 0xD4B16B)
        p.rect(2, open ? 9 : 13, 22, 3, 0xC9A25E)
        p.rect(11, 13, 5, 6, open ? 0xA2E1CE : 0xE7CB82)
        p.rect(12, 15, 3, 2, 0x786139)
        if open { p.rect(5, 13, 17, 2, 0x2B3640) }
    }

    private static func portal(_ p: PixelPainter, _ f: Int) {
        p.ellipse(1, 52, 46, 7, 0x0A2132, alpha: 0.42)
        p.rect(3, 17, 8, 37, 0x40556D); p.rect(37, 17, 8, 37, 0x40556D)
        p.rect(8, 10, 7, 10, 0x57758B); p.rect(33, 10, 7, 10, 0x57758B)
        p.rect(13, 5, 22, 8, 0x6F8A99); p.rect(19, 2, 10, 5, 0x98B3AE)
        p.rect(5, 21, 3, 30, 0x8DA4A4); p.rect(39, 20, 3, 31, 0x779598)
        p.rect(0, 51, 15, 6, 0x617E89); p.rect(34, 51, 14, 6, 0x617E89)
        p.rect(13, 50, 23, 3, 0x789A9F)
        let active = f % 2 == 1
        p.rect(13, 17, 22, 32, active ? 0x5CA5AD : 0x1B354E, alpha: active ? 0.35 : 0.6)
        p.rect(15, 14, 18, 35, active ? 0x78DBC8 : 0x2C4C60, alpha: 0.25)
        p.rect(18, 11, 13, 39, active ? 0xB8FFDD : 0x456F7A, alpha: 0.2)
        p.rect(22, 5, 5, 5, active ? 0xCAFFE6 : 0x567886)
        for y in stride(from: 23, to: 47, by: 10) { p.rect(5, y, 2, 3, active ? 0xA0E7D4 : 0x527280); p.rect(40, y, 2, 3, active ? 0xA0E7D4 : 0x527280) }
    }

    private static func keeper(_ p: PixelPainter, _ f: Int) {
        p.ellipse(3, 36, 23, 4, 0x061B2B, alpha: 0.4)
        p.polygon([(7,21),(20,21),(25,37),(4,37)], 0x465577)
        p.polygon([(10,22),(17,22),(21,36),(8,36)], 0x71819A)
        p.rect(5, 18, 19, 9, 0x59728D); p.rect(9, 9, 13, 14, 0xD1A897)
        p.polygon([(6,15),(7,6),(13,2),(20,5),(24,12),(21,16),(18,11),(13,12),(10,17)], 0xCAD6D4)
        p.rect(11, 14, 2, 4, 0x36434B); p.rect(18, 14, 2, 4, 0x36434B)
        p.rect(10, 21, 12, 4, 0xC4CCBA); p.rect(14, 24, 3, 6, 0xD3AE6B)
        p.rect(24, 15, 2, 24, 0x9A7D58); p.rect(22, 11, 6, 5, 0x839C91)
        p.rect(23, 12, 4, 3, f % 2 == 0 ? 0xADDCD0 : 0xC4E6D0)
    }

    private static func ruin(_ p: PixelPainter, _ f: Int) {
        p.ellipse(3, 45, 58, 10, 0x071F31, alpha: 0.4)
        p.rect(7, 20, 13, 30, 0x3F536A); p.rect(45, 14, 12, 36, 0x3F536A)
        p.rect(9, 20, 5, 29, 0x7B8C94); p.rect(46, 16, 4, 32, 0x6E8790)
        p.rect(4, 47, 19, 6, 0x536F80); p.rect(42, 47, 19, 6, 0x536F80)
        p.rect(6, 14, 16, 9, 0x7E9299); p.rect(42, 9, 17, 8, 0x81989F)
        p.rect(14, 7, 16, 9, 0x566E84); p.rect(30, 2, 21, 9, 0x668493)
        p.rect(17, 8, 7, 3, 0xA5AAA5); p.rect(32, 3, 15, 2, 0xA6B6B1)
        p.rect(8, 31, 11, 2, 0x294658); p.rect(44, 28, 12, 2, 0x2A4657)
        p.rect(15,22,2,5,0x354C60); p.rect(13,26,3,2,0x354C60)
        p.rect(13,28,1,3,0x354C60); p.rect(51,18,2,6,0x354C60)
        p.rect(49,22,3,2,0x354C60); p.rect(47,35,3,1,0xA0ACAA)
        p.rect(10,37,3,1,0xA0ACAA); p.rect(11,40,2,3,0x557181)
        p.rect(43,42,5,2,0x485E71); p.rect(52,32,3,2,0x485E71)
        p.rect(19,9,1,4,0x314B61); p.rect(36,5,2,4,0x405D73)
        p.rect(8,17,5,1,0xB8C0B4); p.rect(46,12,7,1,0xB8C0B4)
        p.rect(7, 45, 4, 7, 0x436C56); p.rect(10, 42, 4, 5, 0x5A8061)
        p.rect(50, 41, 6, 9, f > 3 ? 0x6A607B : 0x50705A)
        p.rect(8,36,2,8,f > 3 ? 0x77738E : 0x6B8C69)
        p.rect(6,38,3,2,f > 3 ? 0x858095 : 0x7B996E)
        p.rect(10,33,2,4,f > 3 ? 0x77738E : 0x6B8C69)
        p.rect(49,46,3,2,f > 3 ? 0x94849F : 0x7A9369)
    }
}

/// Shared immediate-mode drawing helpers retain hard pixel edges in all authored art.
struct PixelPainter {
    let context: CGContext
    init(_ context: CGContext) { self.context = context }
    func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: UInt32, alpha: CGFloat = 1) {
        guard w > 0, h > 0 else { return }
        context.setFillColor(Self.color(color, alpha: alpha).cgColor)
        context.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    func ellipse(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: UInt32, alpha: CGFloat = 1) {
        guard w > 0, h > 0 else { return }
        let rx = Double(w) / 2, ry = Double(h) / 2
        for row in 0..<h {
            let ny = (Double(row) + 0.5 - ry) / ry
            let half = Int((rx * sqrt(max(0, 1 - ny * ny))).rounded())
            rect(x + w / 2 - half, y + row, half * 2, 1, color, alpha: alpha)
        }
    }
    func polygon(_ vertices: [(Int, Int)], _ color: UInt32, alpha: CGFloat = 1) {
        guard let first = vertices.first else { return }
        context.setFillColor(Self.color(color, alpha: alpha).cgColor)
        context.beginPath(); context.move(to: CGPoint(x: first.0, y: first.1))
        for point in vertices.dropFirst() { context.addLine(to: CGPoint(x: point.0, y: point.1)) }
        context.closePath(); context.fillPath()
    }
    static func color(_ rgb: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }
}
