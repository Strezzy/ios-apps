import SwiftUI

private struct ArrivalAttribute: TextAttribute {
    let id: Int
    let times: [TimeInterval]
}

/// Native glyph rendering keeps line wrapping and text shaping in SwiftUI.
/// Settled runs are drawn in one operation; only the newest glyphs use effects.
private struct BloomTextRenderer: TextRenderer {
    let now: TimeInterval
    let motion: Bool
    let enabled: Bool
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var offsets: [Int: Int] = [:]
        for line in layout {
            for run in line {
                guard enabled, let attribute = run[ArrivalAttribute.self],
                      let latest = attribute.times.last,
                      now < latest + RevealSchedule.settleDuration else {
                    context.draw(run)
                    continue
                }
                let start = offsets[attribute.id, default: 0]
                for (index, slice) in run.enumerated() {
                    let timestamp = attribute.times[min(start + index, attribute.times.count - 1)]
                    let age = now - timestamp
                    guard age >= 0 else { continue }
                    if age >= RevealSchedule.settleDuration {
                        context.draw(slice)
                        continue
                    }
                    let progress = min(1, age / RevealSchedule.settleDuration)
                    var copy = context
                    let fade = min(1, progress / 0.64)
                    copy.opacity = fade * fade * (3 - 2 * fade)
                    if motion {
                        // A small damped overshoot, rather than bouncing the line.
                        let settle = 1 - exp(-7.5 * progress) * cos(9 * progress)
                        let bounds = slice.typographicBounds.rect
                        let scale = 0.94 + 0.06 * settle
                        let lift = (1 - settle) * min(5, bounds.height * 0.22)
                        copy.translateBy(x: bounds.midX, y: bounds.midY + lift)
                        copy.scaleBy(x: scale, y: scale)
                        copy.translateBy(x: -bounds.midX, y: -bounds.midY)
                        let radius = 1.1 * pow(1 - progress, 2)
                        if radius > 0.03 { copy.addFilter(.blur(radius: radius)) }
                    }
                    copy.draw(slice, options: .disablesSubpixelQuantization)
                }
                offsets[attribute.id] = start + run.count
            }
        }
    }
}

struct StreamingText: View {
    let text: String
    let isStreaming: Bool
    var interrupted = false
    var monospaced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("rift.replyAnimation") private var animation = "bloom"
    @State private var schedule = RevealSchedule()
    @State private var richText = AttributedString()
    @State private var initialized = false
    @State private var settled = true
    @State private var hasStreamed = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let assembled = composedText()
        TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 30 : 1.0 / 60, paused: settled || animation == "instant" || voiceOver)) { tick in
            assembled
                .font(monospaced ? .system(.callout, design: .monospaced) : .body)
                .lineSpacing(monospaced ? 2 : 4)
                .textRenderer(BloomTextRenderer(now: tick.date.timeIntervalSinceReferenceDate,
                    motion: animation == "bloom" && !reduceMotion && !lowPower,
                    enabled: animation != "instant" && !voiceOver && !settled))
                .textSelection(.enabled)
                .onChange(of: tick.date) { _, date in
                    if !settled && date.timeIntervalSinceReferenceDate >= schedule.completion { settled = true }
                }
        }
        .accessibilityLabel(String(richText.characters))
        .onChange(of: text, initial: true) { _, _ in update() }
        .onChange(of: isStreaming) { _, active in if active { hasStreamed = true } }
        .onChange(of: interrupted) { _, stopped in if stopped { finish() } }
        .onChange(of: animation) { _, _ in if animation == "instant" { finish() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
    private func update() {
        let parsed: AttributedString
        if monospaced { parsed = AttributedString(text) }
        else { parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text) }
        let now = Date.timeIntervalSinceReferenceDate
        let animate = initialized && (isStreaming || hasStreamed) && !interrupted && animation != "instant" && !voiceOver
        richText = parsed
        schedule.ingest(String(parsed.characters), now: now, animate: animate)
        initialized = true
        hasStreamed = hasStreamed || isStreaming
        settled = !animate || now >= schedule.completion
    }
    private func finish() {
        schedule.finishImmediately(now: Date.timeIntervalSinceReferenceDate)
        settled = true
    }
    private func composedText() -> Text {
        var output = Text("")
        var offset = 0
        for run in richText.runs {
            let fragment = AttributedString(richText[run.range])
            let count = fragment.characters.count
            let times = Array(schedule.arrivals.dropFirst(offset).prefix(count))
            let part = Text(fragment)
            if !times.isEmpty { output = output + part.customAttribute(ArrivalAttribute(id: offset, times: times)) }
            else { output = output + part }
            offset += count
        }
        return output
    }
}

struct ReplyAnimationPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var playing = false
    @State private var runID = UUID()
    private let sample = "A quieter kind of conversation. Your thoughts arrive softly, one letter at a time, and settle into place.\n\nNothing leaves your iPhone. Just a little room to think. 🌸"
    var body: some View {
        NavigationStack {
            ZStack {
                RiftBackground()
                VStack(alignment: .leading, spacing: 24) {
                    Label("Animation preview", systemImage: "sparkle").font(.caption).foregroundStyle(.secondary)
                    StreamingText(text: text, isStreaming: playing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("animationPreviewText")
                    Spacer()
                    Text("Sample text, not an AI response. The preview deliberately feeds uneven chunks to the same renderer used in chat.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { runID = UUID() } label: { Label("Replay", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).padding(.vertical, 10) }
                        .buttonStyle(.glassProminent)
                }.padding(24)
            }.navigationTitle("Reply animation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .task(id: runID) {
                    text = ""; playing = true
                    let characters = Array(sample)
                    let bursts = [4, 13, 2, 17, 6, 9]
                    var offset = 0, burst = 0
                    do {
                        try await Task.sleep(for: .milliseconds(180))
                        while offset < characters.count {
                            try Task.checkCancellation()
                            offset = min(characters.count, offset + bursts[burst % bursts.count])
                            text = String(characters.prefix(offset)); burst += 1
                            try await Task.sleep(for: .milliseconds(burst % 3 == 0 ? 160 : 75))
                        }
                        playing = false
                    } catch { playing = false }
                }
        }
    }
}
