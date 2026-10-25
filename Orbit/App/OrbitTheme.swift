import SwiftUI

enum OrbitTheme {
    static let blue = Color(red: 0.20, green: 0.52, blue: 0.94)
    static let ice = Color(red: 0.47, green: 0.84, blue: 0.98)
    static let violet = Color(red: 0.56, green: 0.42, blue: 0.94)
    static let gradient = LinearGradient(colors: [blue, violet], startPoint: .bottomLeading, endPoint: .topTrailing)
}

struct OrbitAtmosphere: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.035, green: 0.045, blue: 0.085) : Color(red: 0.96, green: 0.975, blue: 0.995))
            GeometryReader { geometry in
                Circle().fill(OrbitTheme.ice.opacity(scheme == .dark ? 0.12 : 0.22))
                    .frame(width: geometry.size.width * 0.9).blur(radius: 85).offset(x: -120, y: -170)
                Circle().fill(OrbitTheme.violet.opacity(scheme == .dark ? 0.13 : 0.09))
                    .frame(width: geometry.size.width * 0.85).blur(radius: 95)
                    .offset(x: geometry.size.width * 0.4, y: geometry.size.height * 0.42)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct OrbitCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(21).frame(maxWidth: .infinity, alignment: .leading)
            .background(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)) : AnyShapeStyle(.regularMaterial), in: .rect(cornerRadius: 27))
            .overlay { RoundedRectangle(cornerRadius: 27).strokeBorder(.white.opacity(0.18), lineWidth: 0.7) }
    }
}

struct OrbitMark: View {
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.265).fill(OrbitTheme.gradient)
            Circle().fill(.white.opacity(0.94)).frame(width: size * 0.27, height: size * 0.27)
                .shadow(color: OrbitTheme.ice.opacity(0.6), radius: size * 0.12)
            Ellipse().stroke(LinearGradient(colors: [.white.opacity(0.28), .white, OrbitTheme.ice], startPoint: .top, endPoint: .bottom), lineWidth: size * 0.055)
                .frame(width: size * 0.78, height: size * 0.34).rotationEffect(.degrees(-36))
            Circle().fill(.white).frame(width: size * 0.085, height: size * 0.085)
                .offset(x: size * 0.28, y: -size * 0.20)
            RoundedRectangle(cornerRadius: size * 0.265).strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
        }.frame(width: size, height: size)
            .shadow(color: OrbitTheme.blue.opacity(0.20), radius: size * 0.17, y: size * 0.10)
            .accessibilityHidden(true)
    }
}

struct OrbitGlassPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 28
    @ViewBuilder var content: Content
    var body: some View {
        if reduceTransparency {
            content.background(Color(white: 0.13), in: .rect(cornerRadius: radius))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        }
    }
}

enum OrbitFormat {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds.rounded(.down)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
    static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
