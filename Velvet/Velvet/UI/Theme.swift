import SwiftUI

enum VelvetTheme {
    static let accent = Color(red: 0.83, green: 0.49, blue: 0.62)
    static let surface = Color(red: 0.075, green: 0.065, blue: 0.075)
    static let gridSpacing: CGFloat = 2
    static var photoColumns: [GridItem] { [GridItem(.adaptive(minimum: 108), spacing: gridSpacing)] }
}

struct PrivacyFootnote: View {
    let text: String
    var body: some View { Label(text, systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).padding(.vertical, 6) }
}

struct EmptyLibrary: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(subtitle) }
    }
}
