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
        case .face: return "Source-pixel shaping, edge-preserving skin treatments and local neural aging. No illustrated masks. Clear, mostly front-facing faces work best."
        case .body: return "Pose-guided proportion edits at render resolution. No painted silhouettes, clothing replacement or invented limbs."
        case .background: return "Replaces or styles the area behind visible people. Hair, motion blur and occlusion can affect the cutout."
        case .atmosphere: return "Layered GPU particles, refractive bubbles and drifting fog with subject occlusion. Entirely offline."
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
    var faceTuning: FaceTuning?
    var bodyTuning: BodyTuning?
    var matteTuning: MatteTuning?
    var atmosphereTuning: AtmosphereTuning?
    var backdropTuning: BackdropTuning?
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
        if category == .face { faceTuning = nil }
        if category == .body { bodyTuning = nil }
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
            ("faceSculpt", "Portrait Sculpt"), ("faceSlim", "Slimmer Face"), ("faceFull", "Fuller Face"),
            ("jawDefine", "Defined Jaw"), ("jawSoft", "Soft Jaw"), ("chinLong", "Longer Chin"),
            ("chinShort", "Shorter Chin"), ("eyesOpen", "Open Eyes"), ("eyesSmall", "Smaller Eyes"),
            ("noseRefine", "Refined Nose"), ("noseWide", "Wider Nose"), ("lipsFull", "Fuller Lips"),
            ("lipsFine", "Finer Lips"), ("skinSilk", "Silk Skin"), ("skinDetail", "Skin Detail"),
            ("warmPortrait", "Warm Portrait"), ("coolPortrait", "Cool Portrait"),
            ("portraitEditorial", "Editorial Portrait"), ("youthRetouch", "Youthful Retouch"),
            ("ageMature", "Mature · Neural"), ("ageOlder", "Older · Neural"),
            ("faceBlur", "Face Blur"), ("facePixel", "Face Pixelation")
        ]) + group(.body, [
            ("bodySculpt", "Body Sculpt"), ("waistDefine", "Defined Waist"), ("waistFull", "Fuller Waist"),
            ("shouldersBroad", "Broader Shoulders"), ("shouldersFine", "Narrower Shoulders"),
            ("hipsFull", "Fuller Hips"), ("hipsFine", "Narrower Hips"),
            ("legsLong", "Longer Legs"), ("legsCompact", "Shorter Legs"),
            ("torsoLong", "Longer Torso"), ("torsoCompact", "Shorter Torso"),
            ("armsFine", "Refined Arms"), ("athleticShape", "Athletic Shape"), ("softShape", "Soft Shape")
        ]) + group(.background, [
            ("ph_venice_sunset", "Venice Sunset"), ("ph_kiara_1_dawn", "Savanna Dawn"),
            ("ph_forest_slope", "Forest Light"), ("ph_modern_buildings_2", "City Courtyard"),
            ("ph_studio_small_03", "Photo Studio"), ("ph_moonless_golf", "Moonlit Landscape"),
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
