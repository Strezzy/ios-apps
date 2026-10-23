import AVFoundation
import UniformTypeIdentifiers

/// Retain this owner for as long as its player is visible. AVURLAsset does not
/// retain the resource-loader delegate. Call invalidate on dismissal or lock.
final class SecureVideoPlayback {
    let player: AVPlayer
    private let loader: EncryptedMovieResourceLoader
    init(reader: VaultVideoReader) {
        loader = EncryptedMovieResourceLoader(reader: reader)
        let url = URL(string: "velvet-encrypted://movie/\(UUID().uuidString).mp4")!
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.allowsExternalPlayback = false
    }
    func invalidate() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        loader.invalidate()
    }
    deinit { loader.invalidate() }
}

private final class EncryptedMovieResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    let queue = DispatchQueue(label: "app.velvet.movie-reader", qos: .userInitiated)
    private let reader: VaultVideoReader
    private var pending: [ObjectIdentifier: AVAssetResourceLoadingRequest] = [:]
    private var invalidated = false
    init(reader: VaultVideoReader) { self.reader = reader }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard loadingRequest.request.url?.scheme == "velvet-encrypted" else { return false }
        guard !invalidated else { loadingRequest.finishLoading(with: CameraError.invalidRange); return true }
        if let information = loadingRequest.contentInformationRequest {
            information.contentType = UTType.mpeg4Movie.identifier
            information.contentLength = reader.totalLength
            information.isByteRangeAccessSupported = true
        }
        pending[ObjectIdentifier(loadingRequest)] = loadingRequest
        service(loadingRequest)
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        pending.removeValue(forKey: ObjectIdentifier(loadingRequest))
    }

    private func service(_ request: AVAssetResourceLoadingRequest) {
        let id = ObjectIdentifier(request)
        guard !invalidated, pending[id] != nil, !request.isCancelled, !request.isFinished else { pending.removeValue(forKey: id); return }
        guard let dataRequest = request.dataRequest else { complete(request); return }
        let offset = max(dataRequest.requestedOffset, dataRequest.currentOffset)
        guard offset >= 0 else { fail(request); return }
        let end: Int64
        if dataRequest.requestsAllDataToEndOfResource { end = reader.totalLength }
        else {
            let (requestedEnd, overflow) = dataRequest.requestedOffset.addingReportingOverflow(Int64(dataRequest.requestedLength))
            guard !overflow, dataRequest.requestedLength >= 0 else { fail(request); return }
            end = min(reader.totalLength, requestedEnd)
        }
        guard offset < end else { complete(request); return }
        do {
            // One bounded response per queue turn lets cancellation and lock run
            // promptly even when AVPlayer asks for the whole remaining resource.
            let count = Int(min(256 * 1024, end - offset))
            let data = try reader.read(offset: offset, length: count)
            guard data.count == count else { fail(request); return }
            dataRequest.respond(with: data)
            queue.async { [weak self, weak request] in
                guard let self, let request else { return }
                self.service(request)
            }
        } catch { fail(request) }
    }

    private func complete(_ request: AVAssetResourceLoadingRequest) {
        pending.removeValue(forKey: ObjectIdentifier(request))
        request.finishLoading()
    }
    private func fail(_ request: AVAssetResourceLoadingRequest) {
        pending.removeValue(forKey: ObjectIdentifier(request))
        request.finishLoading(with: CameraError.invalidRange)
    }
    func invalidate() {
        reader.invalidate()
        queue.async { [self] in
            invalidated = true
            for request in pending.values where !request.isCancelled && !request.isFinished { request.finishLoading(with: CameraError.invalidRange) }
            pending.removeAll()
        }
    }
}
