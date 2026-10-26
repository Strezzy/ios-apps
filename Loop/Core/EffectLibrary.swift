import Foundation

/// Stable identifiers keep saved projects independent of gallery order and naming.
enum EffectCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case looks, lens, face, body, background, atmosphere
    var id: String { rawValue }
    var title: String {
        switch self {
        case .looks: return "Looks"
        case .lens: return "Lens & texture"
        case .face: return "Face"
        case .body: return "Body"
        case .background: return "Background"
        case .atmosphere: return "Atmosphere"
        }
    }
    var symbol: String {
        switch self {
        case .looks: return "camera.filters"
        case .lens: return "camera.aperture"
        case .face: return "face.smiling"
        case .body: return "figure.stand"
        case .background: return "photo.on.rectangle.angled"
        case .atmosphere: return "sparkles"
        }
    }
    var guidance: String {
        switch self {
        case .looks: return "Full-color grades, rendered on your device."
        case .lens: return "Optical and graphic treatments. Stack with a color look."
        case .face: return "Automatic 2D face landmarks, warps and illustrated masks. Best on clearly visible, front-facing faces. Not a 3D face replacement."
        case .body: return "Styles the visible person using an on-device mask. These change appearance, not clothing or body anatomy."
        case .background: return "Replaces or styles the area behind visible people. Hair, motion blur and occlusion can affect the cutout."
        case .atmosphere: return "Animated, procedural layers. No downloads or generated video."
        }
    }
}

struct EffectPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let category: EffectCategory
}

struct EffectLayer: Codable, Equatable, Sendable {
    var preset: String
    var amount: Double = 1
    var enabled: Bool = true
}

struct EffectSettings: Codable, Equatable, Sendable {
    var layers: [EffectLayer] = []
    var bypass: Bool = false
    /// Optional for backward-compatible projects and small, local-only backgrounds.
    var backgroundImage: Data?
    var activeLayers: [EffectLayer] {
        guard !bypass else { return [] }
        // One bounded layer per category, even for hand-edited project JSON.
        return EffectCategory.allCases.compactMap { category in
            layers.last { $0.enabled && $0.amount.isFinite && $0.amount > 0 && EffectLibrary.preset($0.preset)?.category == category }
        }
    }
    func layer(_ category: EffectCategory) -> EffectLayer? {
        layers.last { EffectLibrary.preset($0.preset)?.category == category }
    }
    mutating func select(_ id: String?, category: EffectCategory) {
        layers.removeAll { EffectLibrary.preset($0.preset)?.category == category }
        if let id, EffectLibrary.preset(id)?.category == category { layers.append(EffectLayer(preset: id)) }
    }
    mutating func setAmount(_ value: Double, category: EffectCategory) {
        guard let index = layers.lastIndex(where: { EffectLibrary.preset($0.preset)?.category == category }) else { return }
        layers[index].amount = min(1, max(0, value.isFinite ? value : 1))
    }
}

enum EffectLibrary {
    private static func group(_ category: EffectCategory, _ entries: [(String, String)]) -> [EffectPreset] {
        entries.map { EffectPreset(id: $0.0, name: $0.1, category: category) }
    }
    static let presets: [EffectPreset] =
        group(.looks, [
            ("cinema", "Cinema"), ("tealGold", "Teal & Gold"), ("goldenHour", "Golden Hour"),
            ("moonlight", "Moonlight"), ("neonNight", "Neon Night"), ("roseFilm", "Rose Film"),
            ("emerald", "Emerald"), ("desert", "Desert"), ("arctic", "Arctic"),
            ("noir", "Noir"), ("silver", "Silver Screen"), ("matte", "Matte Film"),
            ("instant", "Instant Camera"), ("faded", "Faded Summer"), ("sepia", "Sepia"),
            ("chrome", "Chrome Color"), ("vivid", "Vivid"), ("pastel", "Pastel"),
            ("bleach", "Bleach Bypass"), ("horror", "Horror"), ("vampire", "Crimson Night"),
            ("underwater", "Underwater"), ("peach", "Peach"), ("lavender", "Lavender"),
            ("autumn", "Autumn"), ("forest", "Deep Forest"), ("sunset", "Sunset"),
            ("infrared", "Infrared Style"), ("duotone", "Indigo Duotone"), ("crossProcess", "Cross Process")
        ]) + group(.lens, [
            ("bloom", "Dream Bloom"), ("softFocus", "Soft Focus"), ("vignette", "Spotlight"),
            ("grain", "Film Grain"), ("vhs", "VHS"), ("scanlines", "Scanlines"),
            ("comic", "Comic Ink"), ("poster", "Poster Print"), ("halftone", "Halftone"),
            ("crystal", "Crystal"), ("kaleidoscope", "Kaleidoscope"), ("prism", "Prism")
        ]) + group(.face, [
            ("bigEyes", "Big Eyes"), ("tinyEyes", "Tiny Eyes"), ("bigMouth", "Big Smile"),
            ("tinyMouth", "Tiny Mouth"), ("wideNose", "Button Nose"), ("alien", "Alien"),
            ("ogre", "Ogre"), ("doll", "Doll"), ("sunglasses", "Sunglasses"),
            ("heartEyes", "Heart Eyes"), ("laserEyes", "Laser Eyes"), ("neonVisor", "Neon Visor"),
            ("cat", "Cat"), ("fox", "Fox"), ("bunny", "Bunny"), ("devil", "Little Devil"),
            ("angel", "Halo"), ("crown", "Crown"), ("pirate", "Pirate"),
            ("robot", "Robot"), ("skull", "Skull Mask"), ("clown", "Clown"),
            ("blush", "Blush"), ("glam", "Glam"), ("neonMask", "Neon Mask")
        ]) + group(.body, [
            ("hologram", "Hologram"), ("goldStatue", "Golden Statue"), ("silverStatue", "Silver Statue"),
            ("galaxyBody", "Galaxy"), ("thermalBody", "Thermal Style"), ("neonBody", "Neon Outline"),
            ("ghostBody", "Ghost"), ("inkBody", "Ink Figure"), ("pixelBody", "Pixel Figure"),
            ("silhouette", "Silhouette"), ("paperBody", "Paper Cutout"), ("electricBody", "Electric"),
            ("auroraBody", "Aurora Figure"), ("rainbowBody", "Spectrum")
        ]) + group(.background, [
            ("portraitBlur", "Portrait Blur"), ("monoBackground", "Color Pop"), ("blackStudio", "Black Studio"),
            ("whiteStudio", "White Studio"), ("roseStudio", "Rose Studio"), ("blueStudio", "Blue Studio"),
            ("sunsetSky", "Sunset Sky"), ("auroraSky", "Aurora"), ("deepSpace", "Deep Space"),
            ("neonGrid", "Neon Grid"), ("matrix", "Digital Rain"), ("warmBokeh", "Warm Bokeh"),
            ("coolBokeh", "Cool Bokeh"), ("paperBackdrop", "Paper"), ("comicBackdrop", "Comic Backdrop"),
            ("pixelBackdrop", "Pixel Backdrop"), ("spotlightBackdrop", "Stage Light"), ("customBackground", "Your Photo")
        ]) + group(.atmosphere, [
            ("snow", "Snow"), ("rain", "Rain"), ("embers", "Embers"), ("sparkles", "Stardust"),
            ("dust", "Film Dust"), ("bubbles", "Bubbles"), ("confetti", "Confetti"),
            ("fog", "Drifting Fog"), ("lightLeak", "Light Leaks"), ("fireflies", "Fireflies")
        ])
    private static let byID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
    static func preset(_ id: String) -> EffectPreset? { byID[id] }
    static func inCategory(_ category: EffectCategory) -> [EffectPreset] { presets.filter { $0.category == category } }
}
