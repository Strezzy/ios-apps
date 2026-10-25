import SwiftUI

enum LoopTheme {
    static let teal = Color(red: 0.03, green: 0.60, blue: 0.55)
    static let lime = Color(red: 0.71, green: 0.87, blue: 0.35)
    static let deep = Color(red: 0.02, green: 0.24, blue: 0.25)
    static let gradient = LinearGradient(colors: [teal, lime], startPoint: .bottomLeading, endPoint: .topTrailing)
}

struct LoopAtmosphere: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.025, green: 0.065, blue: 0.07) : Color(red: 0.965, green: 0.98, blue: 0.955))
            GeometryReader { geometry in
                Circle().fill(LoopTheme.teal.opacity(scheme == .dark ? 0.17 : 0.13))
                    .frame(width: geometry.size.width * 0.9).blur(radius: 85).offset(x: -120, y: -150)
                Circle().fill(LoopTheme.lime.opacity(scheme == .dark ? 0.09 : 0.17))
                    .frame(width: geometry.size.width * 0.8).blur(radius: 75)
                    .offset(x: geometry.size.width * 0.45, y: geometry.size.height * 0.55)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct LoopCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 17) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)) : AnyShapeStyle(.regularMaterial), in: .rect(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.16), lineWidth: 0.75) }
    }
}

struct LoopMark: View {
    var size: CGFloat = 116
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26).fill(LoopTheme.gradient)
            Image(systemName: "infinity").font(.system(size: size * 0.62, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .rotationEffect(.degrees(-22))
                .shadow(color: LoopTheme.deep.opacity(0.3), radius: 3, x: 0, y: 6)
            RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(.white.opacity(0.3), lineWidth: 1)
        }.frame(width: size, height: size)
            .shadow(color: LoopTheme.teal.opacity(0.22), radius: size * 0.16, y: size * 0.1)
            .accessibilityHidden(true)
    }
}

struct EditorSectionTitle: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ValueSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0.01
    var display: String
    var accessibilityID: String? = nil
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(display).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityIdentifier(accessibilityID ?? title)
        }
    }
}

enum LoopFormat {
    static func time(_ value: Double) -> String {
        guard value.isFinite else { return "0:00.00" }
        let seconds = max(0, value)
        return String(format: "%d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }
    static func rate(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.01 ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}
