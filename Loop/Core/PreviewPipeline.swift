import Foundation
import CoreGraphics
import CoreVideo

/// One running operation and one replaceable pending value. A completed operation is
/// presented even if newer work arrived, so continuous gestures cannot starve the UI.
/// Invalidating a session drops its results without starting overlapping render workers.
@MainActor final class LatestPreviewWork<Input, Output> {
    private var pending: Input?
    private var worker: Task<Void, Never>?
    private var epoch = 0
    private let operation: (Input) async throws -> Output
    private let didProduce: (Output) -> Void
    private let didFail: (Error) -> Void
    var isWorking: Bool { worker != nil }
    var queuedCount: Int { pending == nil ? 0 : 1 }

    init(operation: @escaping (Input) async throws -> Output,
         didProduce: @escaping (Output) -> Void,
         didFail: @escaping (Error) -> Void) {
        self.operation = operation
        self.didProduce = didProduce
        self.didFail = didFail
    }

    func submit(_ input: Input) {
        pending = input
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while let input = self.pending {
                self.pending = nil
                let generation = self.epoch
                do {
                    let output = try await self.operation(input)
                    if self.epoch == generation { self.didProduce(output) }
                } catch {
                    if self.epoch == generation { self.didFail(error) }
                }
            }
            self.worker = nil
        }
    }

    func invalidate() { epoch += 1; pending = nil }

    /// Call after invalidating and stopping producers to release any input buffer
    /// retained by the running render before starting another decoder-heavy task.
    func waitUntilIdle() async {
        let running = worker
        await running?.value
    }
}

enum PreviewCadence {
    static func preferredRate(sourceRate: Double, speed: Double, displayMaximum: Int) -> Float {
        let source = sourceRate.isFinite && sourceRate > 0 ? sourceRate : 30
        let playback = speed.isFinite && speed > 0 ? speed : 1
        return Float(min(Double(max(1, displayMaximum)), max(1, source * playback)))
    }
}

enum PreviewSource: @unchecked Sendable {
    case image(CGImage)
    case buffer(CVPixelBuffer, CGAffineTransform)
}

enum PreviewPresentationMode: Equatable, Sendable {
    case source, editing, result
}

struct PreviewRenderRequest: @unchecked Sendable {
    var source: PreviewSource
    var project: LoopProject
    var sourceTime: Double
    var session: UUID
    var presentation: PreviewPresentationMode
}

struct PreviewRenderedFrames: @unchecked Sendable {
    var source: CGImage
    var editing: CGImage?
    var result: CGImage?
    var sourceTime: Double
    var session: UUID

    static func render(_ request: PreviewRenderRequest) throws -> PreviewRenderedFrames {
        try autoreleasepool {
            let source: CGImage
            switch request.source {
            case .image(let image): source = image
            case .buffer(let buffer, let transform):
                source = try FrameRenderer.previewSource(buffer, preferredTransform: transform, maximumDimension: 960)
            }
            // Only the visible surface is composited. Keeping both effects passes active
            // would double per-frame work while one of them is hidden behind the editor.
            let editing: CGImage?
            let result: CGImage?
            switch request.presentation {
            case .source:
                editing = nil; result = nil
            case .editing:
                editing = try FrameRenderer.renderEditing(source, project: request.project,
                                                          time: request.sourceTime, maximumDimension: 960, effectsSession: RealismSessions.preview(request.session))
                result = nil
            case .result:
                editing = nil
                result = try FrameRenderer.render(source, project: request.project,
                                                 time: request.sourceTime, maximumDimension: 960, effectsSession: RealismSessions.preview(request.session))
            }
            return PreviewRenderedFrames(source: source, editing: editing, result: result,
                                         sourceTime: request.sourceTime, session: request.session)
        }
    }
}
