import Foundation

enum ReplyAnimationStyle: String, CaseIterable, Identifiable, Sendable {
    case ember, bloom, fade, instant, starlight, wave, bounce, portal, cipher
    static let defaultStyle: Self = .cipher
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ember: return "Ember"
        case .portal: return "Portal"
        case .cipher: return "Cipher"
        case .bloom: return "Bloom"
        case .fade: return "Soft fade"
        case .instant: return "Instant"
        case .starlight: return "Starlight"
        case .wave: return "Wave"
        case .bounce: return "Bubble"
        }
    }
    var icon: String {
        switch self {
        case .ember: return "flame"
        case .portal: return "circle.hexagongrid"
        case .cipher: return "character.cursor.ibeam"
        case .bloom: return "sparkle"
        case .fade: return "sun.haze"
        case .instant: return "bolt"
        case .starlight: return "sparkles"
        case .wave: return "water.waves"
        case .bounce: return "bubbles.and.sparkles"
        }
    }
    var detail: String {
        switch self {
        case .ember: return "Warm sparks drift into the air"
        case .portal: return "Letters emerge through luminous rings"
        case .cipher: return "Scattered glyphs resolve into words"
        case .bloom: return "Softly lifts into focus"
        case .fade: return "Quiet and understated"
        case .instant: return "No visual delay"
        case .starlight: return "A trail of tiny stars"
        case .wave: return "A flowing, curling arrival"
        case .bounce: return "Playful elastic letters"
        }
    }
    var duration: TimeInterval {
        switch self {
        case .ember: return 0.88
        case .portal: return 0.76
        case .cipher: return 0.68
        case .starlight: return 0.64
        case .wave, .bounce: return 0.58
        default: return RevealSchedule.settleDuration
        }
    }
    var isExpressive: Bool { [.ember, .starlight, .wave, .bounce, .portal, .cipher].contains(self) }
    static func resolved(_ value: String) -> Self { Self(rawValue: value) ?? .defaultStyle }
    func effective(reduceMotion: Bool, lowPower: Bool, voiceOver: Bool) -> Self {
        if voiceOver { return .instant }
        if (self == .bloom || isExpressive) && (reduceMotion || lowPower) { return .fade }
        return self
    }
}

/// Values shared by the actual text renderer and rendered-pixel regression tests.
struct ReplyGlyphFrame: Equatable {
    let opacity: Double
    let scale: Double
    let liftFraction: Double
    let blur: Double
    var rotation: Double = 0
    var horizontal: Double = 0
    var sparkle: Double = 0
    static func at(age: TimeInterval, style: ReplyAnimationStyle) -> Self {
        if style == .instant || age >= style.duration { return .init(opacity: 1, scale: 1, liftFraction: 0, blur: 0) }
        if age < 0 { return .init(opacity: 0, scale: 1, liftFraction: 0, blur: 0) }
        let p = min(1, age / style.duration)
        let f = min(1, p / 0.74)
        let opacity = f * f * (3 - 2 * f)
        switch style {
        case .ember:
            let tail = pow(1 - p, 3)
            return .init(opacity: min(1, opacity * 2), scale: 1 - 0.18 * tail,
                liftFraction: 1.5 * tail, blur: 1.8 * tail,
                rotation: 0.06 * tail * sin(p * 10), horizontal: sin(p * 9) * 1.6 * tail)
        case .portal:
            let tail = pow(1 - p, 3)
            return .init(opacity: min(1, opacity * 1.8), scale: 1 - 0.58 * tail,
                liftFraction: -1.4 * tail, blur: 2.4 * tail,
                rotation: -0.65 * tail, horizontal: 5 * tail)
        case .cipher:
            let tail = pow(1 - p, 2)
            return .init(opacity: min(1, opacity * 2.6), scale: 1 + 0.12 * tail,
                liftFraction: -0.8 * tail, blur: 0.3 * tail,
                rotation: sin(p * 37) * 0.09 * tail, horizontal: sin(p * 51) * 2.2 * tail)
        case .bloom:
            let settle = 1 - exp(-7.5 * p) * cos(9 * p)
            return .init(opacity: opacity, scale: 0.88 + 0.12 * settle, liftFraction: 1 - settle, blur: 1.4 * pow(1 - p, 2))
        case .starlight:
            let tail = pow(1 - p, 2)
            return .init(opacity: min(1, opacity * 1.6), scale: 1 - 0.25 * tail,
                liftFraction: 1.2 * tail, blur: 2 * tail, sparkle: pow(sin(.pi * p), 2))
        case .wave:
            let tail = pow(1 - p, 3)
            return .init(opacity: min(1, opacity * 1.4), scale: 1 - 0.14 * tail,
                liftFraction: 1.7 * tail * cos(8 * p), blur: 0.5 * tail,
                rotation: -0.38 * tail * cos(7 * p), horizontal: -4 * tail)
        case .bounce:
            let spring = exp(-6.5 * p) * cos(14 * p)
            return .init(opacity: min(1, opacity * 1.8), scale: 1 - 0.46 * spring,
                liftFraction: 1.8 * spring, blur: 0, rotation: -0.12 * spring)
        default:
            return .init(opacity: opacity, scale: 1, liftFraction: 0, blur: 0)
        }
    }
}

struct ChatViewport: Equatable {
    var height: Double = 0
    var contentHeight: Double = 0
    var bottomDistance: Double = 0
    var atBottom: Bool { bottomDistance < 60 }
    var overflows: Bool { height > 0 && contentHeight > height + 1 }
}

/// Only a user's scroll can stop following. Keyboard or text layout changes
/// must not be mistaken for the user scrolling away from the latest reply.
struct ChatFollowingState: Equatable {
    private(set) var followsLatest = true
    private(set) var userScrolling = false
    mutating func followLatest() { followsLatest = true; userScrolling = false }
    mutating func interaction(_ active: Bool, viewport: ChatViewport) {
        if userScrolling && !active { followsLatest = viewport.atBottom }
        userScrolling = active
    }
    func shouldScroll(in viewport: ChatViewport) -> Bool {
        followsLatest && !userScrolling && viewport.overflows
    }
    mutating func observe(old: ChatViewport, new: ChatViewport) -> Bool {
        if userScrolling { followsLatest = new.atBottom; return false }
        return shouldScroll(in: new) && (abs(new.height - old.height) > 0.5 || abs(new.contentHeight - old.contentHeight) > 0.5)
    }
}

struct AppMemorySnapshot: Equatable, Sendable {
    var remaining: UInt64 = 0
    var footprint: UInt64 = 0
    var estimatedBudget: UInt64? {
        guard remaining > 0, footprint > 0 else { return nil }
        let (sum, overflow) = remaining.addingReportingOverflow(footprint)
        return overflow ? nil : sum
    }
}

/// The retired preference must never silently block a requested model download.
enum PrivacyPreferences {
    static func migrate(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "rift.offline")
    }
}
