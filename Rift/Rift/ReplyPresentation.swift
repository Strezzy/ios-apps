import Foundation

enum ReplyAnimationStyle: String, CaseIterable, Identifiable, Sendable {
    case bloom, fade, instant
    var id: String { rawValue }
    var title: String { switch self { case .bloom: return "Bloom"; case .fade: return "Soft fade"; case .instant: return "Instant" } }
    static func resolved(_ value: String) -> Self { Self(rawValue: value) ?? .bloom }
    func effective(reduceMotion: Bool, lowPower: Bool, voiceOver: Bool) -> Self {
        if voiceOver { return .instant }
        if self == .bloom && (reduceMotion || lowPower) { return .fade }
        return self
    }
}

/// Values used by the production renderer and its pixel-level regression tests.
struct ReplyGlyphFrame: Equatable {
    let opacity: Double
    let scale: Double
    let liftFraction: Double
    let blur: Double
    static func at(age: TimeInterval, style: ReplyAnimationStyle) -> Self {
        if style == .instant || age >= RevealSchedule.settleDuration { return .init(opacity: 1, scale: 1, liftFraction: 0, blur: 0) }
        if age < 0 { return .init(opacity: 0, scale: 1, liftFraction: 0, blur: 0) }
        let progress = min(1, age / RevealSchedule.settleDuration)
        let fade = min(1, progress / 0.74)
        let opacity = fade * fade * (3 - 2 * fade)
        guard style == .bloom else { return .init(opacity: opacity, scale: 1, liftFraction: 0, blur: 0) }
        let settle = 1 - exp(-7.5 * progress) * cos(9 * progress)
        return .init(opacity: opacity, scale: 0.88 + 0.12 * settle, liftFraction: 1 - settle, blur: 1.4 * pow(1 - progress, 2))
    }
}

struct ChatViewport: Equatable {
    var height: Double = 0
    var contentHeight: Double = 0
    var bottomDistance: Double = 0
    var atBottom: Bool { bottomDistance < 60 }
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
    mutating func observe(old: ChatViewport, new: ChatViewport) -> Bool {
        if userScrolling { followsLatest = new.atBottom; return false }
        return followsLatest && (abs(new.height - old.height) > 0.5 || abs(new.contentHeight - old.contentHeight) > 0.5)
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
