import SwiftUI
import QuartzCore

@MainActor final class EditorPreview: ObservableObject {
    @Published var sourceFrame: CGImage?
    @Published var renderedFrame: CGImage?
    @Published var time: Double = 0
    @Published var playing = false
    @Published var error: String?
    private var request: Task<Void, Never>?
    private var playback: Task<Void, Never>?
    private var generation = 0

    func refresh(project: LoopProject, url: URL) {
        guard !playing else { return }
        request?.cancel()
        generation += 1
        let token = generation
        let requestedTime = min(max(project.trimStart, time), max(project.trimStart, project.trimEnd - 0.001))
        request = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(45))
                try Task.checkCancellation()
                let source = try await MediaEngine.thumbnail(url: url, time: requestedTime, maximumDimension: 1000)
                try Task.checkCancellation()
                let rendered = try await Task.detached(priority: .userInitiated) {
                    try FrameRenderer.render(source, project: project, time: requestedTime, maximumDimension: 900)
                }.value
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.sourceFrame = source; self.renderedFrame = rendered; self.error = nil
            } catch is CancellationError { }
            catch { if self?.generation == token { self?.error = error.localizedDescription } }
        }
    }

    func toggle(project: LoopProject, url: URL) {
        if playing { stop(); refresh(project: project, url: url); return }
        request?.cancel(); generation += 1; playing = true
        let initial = Date()
        let duration = max(0.02, project.duration)
        let offset = min(duration, max(0, time - project.trimStart))
        playback = Task { [weak self] in
            while !Task.isCancelled {
                let elapsed = (Date().timeIntervalSince(initial) * project.export.speed + offset)
                let cycle = project.export.playback == .bounce ? duration * 2 : duration
                let position = elapsed.truncatingRemainder(dividingBy: cycle)
                let sourceOffset: Double
                switch project.export.playback {
                case .forward: sourceOffset = position
                case .reverse: sourceOffset = duration - position
                case .bounce: sourceOffset = position <= duration ? position : duration * 2 - position
                }
                let t = min(project.trimEnd - 0.001, project.trimStart + sourceOffset)
                do {
                    let source = try await MediaEngine.thumbnail(url: url, time: t, maximumDimension: 800)
                    try Task.checkCancellation()
                    let rendered = try await Task.detached(priority: .userInitiated) {
                        try FrameRenderer.render(source, project: project, time: t, maximumDimension: 800)
                    }.value
                    try Task.checkCancellation()
                    self?.time = t; self?.sourceFrame = source; self?.renderedFrame = rendered; self?.error = nil
                    try await Task.sleep(for: .milliseconds(40))
                } catch is CancellationError { break }
                catch { self?.error = error.localizedDescription; break }
            }
            self?.playing = false
        }
    }

    func stop() { playback?.cancel(); playback = nil; playing = false }
    func clear() { stop(); request?.cancel(); sourceFrame = nil; renderedFrame = nil }
}
