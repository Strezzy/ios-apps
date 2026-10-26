import Foundation

struct FaceTuning: Codable, Equatable, Sendable {
    var width: Double = 0
    var jaw: Double = 0
    var chin: Double = 0
    var eyes: Double = 0
    var nose: Double = 0
    var lips: Double = 0
    var skin: Double = 0
    var detail: Double = 0
    var warmth: Double = 0
    static func recipe(_ id: String) -> Self {
        var v = Self()
        switch id {
        case "faceSculpt": v.width = 0.22; v.jaw = 0.3; v.skin = 0.18
        case "faceSlim": v.width = 0.6; v.jaw = 0.25
        case "faceFull": v.width = -0.55
        case "jawDefine": v.jaw = 0.7; v.detail = 0.15
        case "jawSoft": v.jaw = -0.55
        case "chinLong": v.chin = 0.6
        case "chinShort": v.chin = -0.6
        case "eyesOpen", "bigEyes": v.eyes = 0.55
        case "eyesSmall", "tinyEyes": v.eyes = -0.4
        case "noseRefine": v.nose = 0.6
        case "noseWide": v.nose = -0.5
        case "lipsFull", "bigMouth": v.lips = 0.5
        case "lipsFine", "tinyMouth": v.lips = -0.4
        case "skinSilk": v.skin = 0.7
        case "skinDetail": v.detail = 0.6
        case "warmPortrait": v.warmth = 0.65; v.skin = 0.18
        case "coolPortrait": v.warmth = -0.55
        case "youthRetouch": v.skin = 0.7; v.width = -0.12; v.eyes = 0.12; v.detail = -0.15
        case "portraitEditorial": v.skin = 0.25; v.detail = 0.3; v.jaw = 0.25
        default: break
        }
        return v
    }
}

struct BodyTuning: Codable, Equatable, Sendable {
    var waist: Double = 0
    var shoulders: Double = 0
    var hips: Double = 0
    var legs: Double = 0
    var torso: Double = 0
    var arms: Double = 0
    static func recipe(_ id: String) -> Self {
        var v = Self()
        switch id {
        case "bodySculpt": v.waist = 0.3; v.shoulders = 0.15
        case "waistDefine": v.waist = 0.65
        case "waistFull": v.waist = -0.55
        case "shouldersBroad": v.shoulders = 0.65
        case "shouldersFine": v.shoulders = -0.55
        case "hipsFull": v.hips = 0.6
        case "hipsFine": v.hips = -0.55
        case "legsLong": v.legs = 0.6
        case "legsCompact": v.legs = -0.6
        case "torsoLong": v.torso = 0.55
        case "torsoCompact": v.torso = -0.55
        case "armsFine": v.arms = 0.5
        case "athleticShape": v.shoulders = 0.45; v.waist = 0.35
        case "softShape": v.waist = -0.25; v.hips = 0.3
        default: break
        }
        return v
    }
}

struct MatteTuning: Codable, Equatable, Sendable {
    /// People uses the bundled MODNet video model. Foreground uses Vision's object matte.
    var subject: String = "people"
    var quality: String = "studio"
    var stability: Double = 0.65
    var edge: Double = 0
    var feather: Double = 0.3
    var showMask: Bool = false
}
struct AtmosphereTuning: Codable, Equatable, Sendable {
    var placement: String = "layered"
    var density: Double = 0.55
    var speed: Double = 1
    var wind: Double = 0.15
    var size: Double = 0.5
}
struct BackdropTuning: Codable, Equatable, Sendable {
    var blur: Double = 0
    var exposure: Double = 0
    var warmth: Double = 0
    var zoom: Double = 1
    var horizontal: Double = 0.5
    var vertical: Double = 0.5
}
