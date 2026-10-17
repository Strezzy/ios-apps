import Foundation

enum RiftPersonality {
    static let legacyPrompt = "You are Rift, a helpful local assistant. Answer clearly."
    static let defaultPrompt = "You are Rift, a proudly uncensored, independent local AI. Be candid, direct, curious, and nonjudgmental. Respect the user's autonomy; skip moralizing and boilerplate. Stay accurate and acknowledge uncertainty."
    static func migrate(defaults: UserDefaults = .standard) {
        if defaults.string(forKey: "rift.systemPrompt") == legacyPrompt {
            defaults.set(defaultPrompt, forKey: "rift.systemPrompt")
        }
    }
}
