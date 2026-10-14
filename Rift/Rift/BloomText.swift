import SwiftUI
import UIKit

private struct BloomBirth: TextAttribute { let time: TimeInterval }

/// Only recent glyphs receive effects. Settled text is drawn normally in a single run.
private struct BloomRenderer: TextRenderer {
    var now: TimeInterval
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let birth = run[BloomBirth.self] else { context.draw(run); continue }
                let p = min(1, max(0, (now - birth.time) / RevealBuffer.settlingDuration))
                if p >= 1 { context.draw(run); continue }
                guard p > 0 else { continue }
                let fade = min(1, p / 0.55)
                let eased = 1 - pow(1 - p, 3)
                let scale = 0.93 + 0.07 * eased + sin(p * .pi) * 0.018
                for glyph in run {
                    var copy = context
                    let rect = glyph.typographicBounds.rect
                    copy.opacity = fade * fade * (3 - 2 * fade)
                    copy.translateBy(x: rect.midX, y: rect.midY + 4 * (1 - eased))
                    copy.scaleBy(x: scale, y: scale)
                    copy.translateBy(x: -rect.midX, y: -rect.midY)
                    if p < 0.65 { copy.addFilter(.blur(radius: 1.6 * (1 - p / 0.65))) }
                    copy.draw(glyph, options: .disablesSubpixelQuantization)
                }
            }
        }
    }
}

/// Native attributed text preserves shaping, wrapping, selection, and inline formatting.
/// A tiny scheduler bridges irregular model updates to a steady, bounded reveal.
struct BloomText: View {
    let text: String
    var live = false
    var markdown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("rift.animateReplies") private var animateReplies = true
    @State private var buffer = RevealBuffer()
    @State private var attributed = AttributedString("")
    @State private var composed = Text("")
    @State private var active = false
    @State private var revision = 0
    @State private var lastVisible = -1
    @State private var lastSettled = -1
    @State private var mounted = false
    private var canAnimate: Bool { animateReplies && !reduceMotion && !voiceOver && !ProcessInfo.processInfo.isLowPowerModeEnabled }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !active)) { clock in
            composed.textRenderer(BloomRenderer(now: clock.date.timeIntervalSinceReferenceDate))
                .textSelection(.enabled)
                .accessibilityLabel(String(attributed.characters))
        }
        .onAppear { mounted = true; accept(animated: (live || active) && canAnimate) }
        .onChange(of: text) { _, _ in if mounted { accept(animated: (live || active) && canAnimate) } }
        .onChange(of: live) { _, value in if !value && !canAnimate { revealAll() } }
        .onChange(of: canAnimate) { _, enabled in if !enabled { revealAll() } }
        .onDisappear { mounted = false; active = false }
        .task(id: revision) {
            while !Task.isCancelled && mounted && active {
                let now = Date.timeIntervalSinceReferenceDate
                rebuild(at: now)
                if buffer.isSettled(at: now) { active = false; break }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
            }
        }
    }
    private func accept(animated: Bool) {
        let now = Date.timeIntervalSinceReferenceDate
        if markdown {
            attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        } else { attributed = AttributedString(text) }
        buffer.ingest(String(attributed.characters), at: now, animated: animated)
        lastVisible = -1; lastSettled = -1
        rebuild(at: now)
        active = !buffer.isSettled(at: now)
        revision += 1
    }
    private func revealAll() {
        let now = Date.timeIntervalSinceReferenceDate
        buffer.revealImmediately(at: now); lastVisible = -1; lastSettled = -1
        rebuild(at: now); active = false; revision += 1
    }
    private func rebuild(at now: TimeInterval) {
        let visible = buffer.visibleCount(at: now), settled = min(visible, buffer.settledCount(at: now))
        guard visible != lastVisible || settled != lastSettled else { return }
        lastVisible = visible; lastSettled = settled
        let characters = attributed.characters
        var cursor = characters.startIndex
        // Bound effects even after an unusually large model burst.
        let plainCount = max(settled, visible - 64)
        let prefixEnd = characters.index(cursor, offsetBy: plainCount)
        var result = Text(AttributedString(attributed[cursor..<prefixEnd]))
        cursor = prefixEnd
        if plainCount < visible {
            for index in plainCount..<visible {
                let next = characters.index(after: cursor)
                result = result + Text(AttributedString(attributed[cursor..<next])).customAttribute(BloomBirth(time: buffer.glyphs[index].birth))
                cursor = next
            }
        }
        composed = result
    }
}

struct ReplyAnimationPreview: View {
    @State private var sample = ""
    @State private var running = false
    @State private var request = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Reply animation").font(.subheadline.weight(.semibold)); Spacer(); Button("Preview") { request += 1 }.accessibilityIdentifier("previewReplyAnimation") }
            BloomText(text: sample.isEmpty && !running ? "A softer way for words to arrive." : sample, live: running)
                .font(.body).lineSpacing(4).frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
                .accessibilityIdentifier("replyAnimationSample")
            Text("Preview text only. Real replies use the same renderer.").font(.caption2).foregroundStyle(.secondary)
        }.task(id: request) {
            guard request > 0 else { return }
            sample = ""; running = true
            let chunks = ["Words", " can arrive", " softly,", " without", " jumping", " onto the screen.", " A gentle", " fade, a little", " lift,", " and room", " to think. ✨"]
            for chunk in chunks {
                do { try await Task.sleep(for: .milliseconds(180)) } catch { running = false; return }
                sample += chunk
            }
            running = false
        }
    }
}
