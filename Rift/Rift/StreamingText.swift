import SwiftUI

struct ArrivalAttribute: TextAttribute {
    let id: Int
    let times: [TimeInterval]
    var characters: [Character] = []
}

struct BloomTextRenderer: TextRenderer {
    var now: TimeInterval
    let style: ReplyAnimationStyle
    var animatableData: Double { get { now } set { now = newValue } }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var offsets: [Int: Int] = [:]
        var particlesRemaining = [.ember, .portal, .cipher].contains(style) ? 48 : 24
        for line in layout {
            for run in line {
                guard style != .instant, let attribute = run[ArrivalAttribute.self], !attribute.times.isEmpty else {
                    context.draw(run); continue
                }
                let start = offsets[attribute.id, default: 0]
                offsets[attribute.id] = start + run.count
                let last = min(start + max(0, run.count - 1), attribute.times.count - 1)
                if now >= attribute.times[last] + style.duration { context.draw(run); continue }
                for (index, slice) in run.enumerated() {
                    let timestamp = attribute.times[min(start + index, attribute.times.count - 1)]
                    let frame = ReplyGlyphFrame.at(age: now - timestamp, style: style)
                    guard frame.opacity > 0 else { continue }
                    var copy = context
                    copy.opacity *= frame.opacity
                    let bounds = slice.typographicBounds.rect
                    let lift = frame.liftFraction * min(7, bounds.height * 0.28)
                    copy.translateBy(x: bounds.midX + frame.horizontal, y: bounds.midY + lift)
                    copy.rotate(by: .radians(frame.rotation))
                    copy.scaleBy(x: frame.scale, y: frame.scale)
                    copy.translateBy(x: -bounds.midX, y: -bounds.midY)
                    if frame.blur > 0.03 { copy.addFilter(.blur(radius: frame.blur)) }
                    let seed = attribute.id + start + index
                    let age = now - timestamp
                    let progress = min(1, max(0, age / style.duration))
                    if style == .portal {
                        ArrivalEffects.portal(in: context, bounds: bounds, progress: progress,
                            seed: seed, budget: &particlesRemaining)
                    }
                    let characterIndex = min(start + index, max(0, attribute.characters.count - 1))
                    let character = attribute.characters.isEmpty ? nil : attribute.characters[characterIndex]
                    let scrambles = style == .cipher && CipherGlyph.canScramble(character)
                    if scrambles { copy.opacity *= min(1, max(0, (progress - 0.48) / 0.24)) }
                    copy.draw(slice, options: .disablesSubpixelQuantization)
                    if style == .ember {
                        ArrivalEffects.embers(in: context, bounds: bounds, progress: progress,
                            seed: seed, budget: &particlesRemaining)
                    } else if scrambles {
                        ArrivalEffects.cipher(in: context, bounds: bounds, progress: progress,
                            seed: seed, budget: &particlesRemaining)
                    }
                    if frame.sparkle > 0.015 && seed % 3 == 0 && particlesRemaining > 0 {
                        let progress = min(1, max(0, (now - timestamp) / style.duration))
                        for particle in 0..<2 where particlesRemaining > 0 {
                            particlesRemaining -= 1
                            let side: Double = particle == 0 ? -1 : 1
                            let travel = 3 + 8 * progress
                            let x = bounds.midX + side * travel
                            let y = bounds.minY + bounds.height * 0.3 - 9 * progress + Double(seed % 4)
                            let radius = (particle == 0 ? 2.1 : 1.35) * (1 - 0.4 * progress)
                            var star = Path()
                            star.move(to: CGPoint(x: x, y: y - radius))
                            star.addLine(to: CGPoint(x: x + radius * 0.26, y: y - radius * 0.26))
                            star.addLine(to: CGPoint(x: x + radius, y: y))
                            star.addLine(to: CGPoint(x: x + radius * 0.26, y: y + radius * 0.26))
                            star.addLine(to: CGPoint(x: x, y: y + radius))
                            star.addLine(to: CGPoint(x: x - radius * 0.26, y: y + radius * 0.26))
                            star.addLine(to: CGPoint(x: x - radius, y: y))
                            star.addLine(to: CGPoint(x: x - radius * 0.26, y: y - radius * 0.26))
                            star.closeSubpath()
                            var glow = context
                            glow.opacity *= frame.sparkle * 0.85
                            glow.fill(star, with: .color(RiftTheme.accent))
                        }
                    }
                }
            }
        }
    }
}

/// Selection returns after streaming and its final reveal have both finished.
struct ReplyRenderSurface: View {
    let text: Text
    let now: TimeInterval
    let style: ReplyAnimationStyle
    var body: some View {
        text.textRenderer(BloomTextRenderer(now: now, style: style))
            .textSelection(.disabled)
            .transaction { $0.animation = nil }
    }
}

enum ReplyTextComposition {
    static func make(_ richText: AttributedString, arrivals: [TimeInterval]) -> Text {
        var output = Text("")
        var offset = 0
        for run in richText.runs {
            var beginning = run.range.lowerBound
            var cursor = beginning
            var count = 0
            while cursor < run.range.upperBound {
                let character = richText.characters[cursor]
                cursor = richText.characters.index(after: cursor)
                count += 1
                if character.isWhitespace || cursor == run.range.upperBound {
                    let fragment = AttributedString(richText[beginning..<cursor])
                    let times = Array(arrivals.dropFirst(offset).prefix(count))
                    let part = Text(fragment)
                    output = output + (times.isEmpty ? part : part.customAttribute(ArrivalAttribute(id: offset, times: times, characters: Array(fragment.characters))))
                    offset += count; beginning = cursor; count = 0
                }
            }
        }
        return output
    }
}

struct StreamingText: View {
    let text: String
    let isStreaming: Bool
    var interrupted = false
    var monospaced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("rift.replyAnimation") private var animation = ReplyAnimationStyle.defaultStyle.rawValue
    @State private var schedule = RevealSchedule()
    @State private var richText = AttributedString()
    @State private var assembled = Text("")
    @State private var settled = true
    @State private var hasStreamed = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var style: ReplyAnimationStyle {
        ReplyAnimationStyle.resolved(animation).effective(reduceMotion: reduceMotion, lowPower: lowPower, voiceOver: voiceOver)
    }
    private var animationCompletion: TimeInterval {
        schedule.completion + max(0, style.duration - RevealSchedule.settleDuration)
    }
    var body: some View {
        Group {
            if (isStreaming || !settled) && style != .instant {
                TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 30 : 1.0 / 60, paused: settled)) { tick in
                    ReplyRenderSurface(text: assembled, now: tick.date.timeIntervalSinceReferenceDate, style: style)
                }
            } else {
                Text(richText).textSelection(.enabled)
            }
        }
        .font(monospaced ? .system(.callout, design: .monospaced) : .body)
        .lineSpacing(monospaced ? 2 : 4)
        .accessibilityLabel(String(richText.characters))
        .onChange(of: text, initial: true) { _, _ in update() }
        .onChange(of: isStreaming) { _, _ in update() }
        .onChange(of: interrupted) { _, stopped in if stopped { finish() } }
        .onChange(of: style) { _, chosen in if chosen == .instant { finish() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: animationCompletion) {
            guard !settled, animationCompletion.isFinite else { return }
            let wait = max(0, animationCompletion - Date.timeIntervalSinceReferenceDate)
            do { try await Task.sleep(for: .seconds(wait)); settled = true } catch { }
        }
    }
    private func update() {
        if monospaced { richText = AttributedString(text) }
        else { richText = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text) }
        let now = Date.timeIntervalSinceReferenceDate
        let animate = (isStreaming || hasStreamed) && !interrupted && style != .instant
        schedule.ingest(String(richText.characters), now: now, animate: animate)
        assembled = ReplyTextComposition.make(richText, arrivals: schedule.arrivals)
        hasStreamed = hasStreamed || isStreaming
        settled = !animate || now >= animationCompletion
    }
    private func finish() {
        schedule.finishImmediately(now: Date.timeIntervalSinceReferenceDate)
        assembled = ReplyTextComposition.make(richText, arrivals: schedule.arrivals)
        settled = true
    }
}

struct ReplyStylePicker: View {
    var contextID = "inline"
    @AppStorage("rift.replyAnimation") private var style = ReplyAnimationStyle.defaultStyle.rawValue
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(ReplyAnimationStyle.allCases) { item in
                Button { style = item.rawValue } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.icon).font(.title3)
                        Text(item.title).font(.caption.weight(.semibold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(style == item.rawValue ? RiftTheme.accent : .primary)
                        .background(RiftTheme.accent.opacity(style == item.rawValue ? 0.15 : 0.035), in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(RiftTheme.accent.opacity(style == item.rawValue ? 0.65 : 0.08), lineWidth: 1) }
                }.buttonStyle(.plain).accessibilityIdentifier("replyStyle-" + contextID + "-" + item.rawValue)
                    .accessibilityLabel(item.title).accessibilityHint(item.detail)
                    .accessibilityAddTraits(style == item.rawValue ? .isSelected : [])
            }
        }.accessibilityIdentifier("replyStylePicker-" + contextID)
    }
}

struct ReplyAnimationSample: View {
    var contextID = "inline"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("rift.replyAnimation") private var style = ReplyAnimationStyle.defaultStyle.rawValue
    @State private var text = ""
    @State private var playing = false
    @State private var replay = UUID()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private struct PlaybackID: Hashable { let style: String; let replay: UUID }
    private var playbackID: PlaybackID { .init(style: style, replay: replay) }
    private let sample = "A quieter kind of conversation. Your thoughts arrive softly and settle into place.\n\nJust a little room to think. 🌸"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live preview", systemImage: "sparkle").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { replay = UUID() } label: { Label("Replay", systemImage: "arrow.clockwise") }
                    .font(.caption).accessibilityIdentifier("replayAnimation-" + contextID)
            }
            ZStack(alignment: .topLeading) {
                Text(sample).font(.body).lineSpacing(4).hidden().accessibilityHidden(true)
                StreamingText(text: text, isStreaming: playing).id(playbackID)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep a stable accessible surface while the animated Text changes
            // rendering branches. The expanded sheet has a separate identity
            // from the Settings preview underneath it.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityValue(playing ? "Playing preview" : "Preview complete")
            .accessibilityIdentifier("animationPreview-" + contextID)
            if voiceOver { Text("VoiceOver is on. Text appears instantly.").font(.caption).foregroundStyle(.secondary) }
            else if reduceMotion || lowPower {
                Text(reduceMotion ? "Reduce Motion is on. Expressive effects use a gentle fade." : "Low Power Mode is on. Expressive effects use a lighter fade.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Sample text, not an AI response.").font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: playbackID) {
            text = ""; playing = true
            do {
                try await Task.sleep(for: .milliseconds(120))
                let characters = Array(sample)
                let bursts = [4, 13, 2, 17, 6, 9]
                var offset = 0, burst = 0
                while offset < characters.count {
                    try Task.checkCancellation()
                    offset = min(characters.count, offset + bursts[burst % bursts.count])
                    text = String(characters.prefix(offset)); burst += 1
                    try await Task.sleep(for: .milliseconds(burst % 3 == 0 ? 180 : 105))
                }
                playing = false
            } catch { /* A new style or Replay owns the replacement task. */ }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}

struct ReplyAnimationPreview: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                RiftBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ReplyStylePicker(contextID: "expanded")
                        ReplyAnimationSample(contextID: "expanded")
                    }.padding(24)
                }.accessibilityIdentifier("expandedAnimationPreview")
            }.navigationTitle("Reply animation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
