import Foundation

enum DownloadEvent: Sendable { case progress(Double); case file(URL) }
/// URLSessionDownloadTask streams to disk. The app receives progress and a URL,
/// never the multi-gigabyte response body. All mutable lifecycle state is locked.
final class DownloadJob: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: AsyncThrowingStream<DownloadEvent, Error>.Continuation?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var finished = false
    private var lastProgress: TimeInterval = 0
    private var lastSpaceCheck: TimeInterval = 0
    private let destination: URL
    private let expectedBytes: Int64
    init(destination: URL, expectedBytes: Int64) { self.destination = destination; self.expectedBytes = expectedBytes }
    func start(url: URL, cellular: Bool, resumeData: Data? = nil) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let config = URLSessionConfiguration.ephemeral
            config.allowsCellularAccess = cellular; config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 24 * 60 * 60
            config.httpCookieStorage = nil; config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
            let connection = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            let download: URLSessionDownloadTask
            if let resumeData, !resumeData.isEmpty, resumeData.count < 2 * 1_048_576 { download = connection.downloadTask(withResumeData: resumeData) }
            else { download = connection.downloadTask(with: url) }
            lock.lock(); self.stream = continuation; session = connection; task = download; lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.cancel() }
            download.resume()
        }
    }
    func cancel() { lock.lock(); let active = task; lock.unlock(); active?.cancel() }
    func pause() async -> Data? {
        await withCheckedContinuation { continuation in
            lock.lock(); let active = task; lock.unlock()
            guard let active else { continuation.resume(returning: nil); return }
            active.cancel { data in continuation.resume(returning: data) }
        }
    }
    private func yield(_ event: DownloadEvent) {
        lock.lock(); let continuation = finished ? nil : stream; lock.unlock()
        continuation?.yield(event)
    }
    private func finish(_ error: Error? = nil) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = stream, connection = session
        stream = nil; task = nil; session = nil
        lock.unlock()
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        connection?.finishTasksAndInvalidate()
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedBytes {
            downloadTask.cancel(); finish(RiftFailure("The host sent a larger file than the catalog specifies. The download was stopped.")); return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastSpaceCheck > 1 {
            lastSpaceCheck = now
            let directory = destination.deletingLastPathComponent()
            if let free = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, free < 128 * 1_048_576 {
                downloadTask.cancel(); finish(RiftFailure("The download stopped because storage is nearly full. Free up space before resuming.")); return
            }
        }
        if now - lastProgress >= 0.2 || totalBytesWritten == expectedBytes {
            lastProgress = now
            yield(.progress(min(1, Double(totalBytesWritten) / Double(max(1, expectedBytes)))))
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
                throw RiftFailure("The model host returned HTTP \(code). No model was installed. Retry later or import the file from its author.")
            }
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Int64(size) == expectedBytes else { throw RiftFailure("The download is incomplete. Nothing was installed.") }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            yield(.file(destination)); finish()
        } catch { finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(error) }
    }
}
