import SwiftUI

enum DepthCheckTheme {
    static let accent = Color(red: 0.32, green: 0.93, blue: 0.88)
    static let secondaryAccent = Color(red: 0.31, green: 0.58, blue: 1)
    static let primaryButtonInk = Color(red: 0.02, green: 0.10, blue: 0.13)
}

struct StudioBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.045, blue: 0.075)
            RadialGradient(colors: [Color(red: 0.03, green: 0.24, blue: 0.29).opacity(0.8), .clear], center: .topLeading, startRadius: 0, endRadius: 650)
            RadialGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.31).opacity(0.65), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct GlassCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct Eyebrow: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(text.uppercased()).tracking(1.6)
        }
        .font(.system(.caption2, design: .rounded).weight(.bold))
        .foregroundStyle(DepthCheckTheme.accent)
    }
}

struct InfoNote: View {
    let text: String
    var symbol = "info.circle"

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(DepthCheckTheme.accent.opacity(0.85))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

struct MetadataPill: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule())
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    let subtitle: String
    let control: Control

    init(_ title: String, subtitle: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            control
        }
    }
}

struct QualityFacts: View {
    let source: MediaSource
    let options: ConversionOptions

    var body: some View {
        let output = options.format.outputSize(for: source.size)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Export dimensions").foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(output.label)
                    .fontDesign(.monospaced)
                    .multilineTextAlignment(.trailing)
            }
            if source.kind == .video {
                HStack(alignment: .firstTextBaseline) {
                    Text("Frame timing").foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(source.frameRate > 0 ? "\(StudioFormat.fps(source.frameRate)) fps · original" : "Original timestamps")
                        .fontDesign(.monospaced)
                        .multilineTextAlignment(.trailing)
                }
            }
            if options.format == .sideBySide {
                InfoNote(text: "Full side-by-side places two \(source.size.label) views next to each other. The output is twice as wide.")
            } else if options.format == .overUnder {
                InfoNote(text: "Full over-under stacks two \(source.size.label) views. The output is twice as tall.")
            } else if options.format == .separateEyes {
                InfoNote(text: "Two separate files, each at \(source.size.label).")
            }
            if source.isHDR {
                InfoNote(text: "HDR is tone-mapped to SDR in this version. Dimensions and original frame timing are preserved.", symbol: "sun.max")
            } else if source.kind == .photo {
                InfoNote(text: "Full-resolution SDR export. RAW photos are developed into the selected image format.", symbol: "camera.aperture")
            }
        }
        .font(.footnote)
    }
}

enum StudioFormat {
    static func fps(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
        return String(format: "%d:%02d", minutes, remainder)
    }

    static func percentage(_ fraction: Double) -> String {
        min(1, max(0, fraction.isFinite ? fraction : 0)).formatted(.percent.precision(.fractionLength(0)))
    }
}
