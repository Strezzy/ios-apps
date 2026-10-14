import Foundation

enum DownloadEvent: Sendable { case progress(Double); case file(URL) }
final class DownloadJob: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: AsyncThrowingStream<DownloadEvent, Error>.Continuation?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var finished = false
    private let destination: URL
    private let expectedBytes: Int64
    init(destination: URL, expectedBytes: Int64) { self.destination=destination; self.expectedBytes=expectedBytes }
    func start(url: URL, cellular: Bool, resumeData: Data? = nil) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream(bufferingPolicy:.bufferingNewest(8)) { continuation in
            self.stream=continuation
            let config=URLSessionConfiguration.ephemeral
            config.allowsCellularAccess=cellular; config.waitsForConnectivity=true
            config.timeoutIntervalForRequest=90; config.timeoutIntervalForResource=24*60*60
            config.httpCookieStorage=nil; config.urlCache=nil
            let queue=OperationQueue(); queue.maxConcurrentOperationCount=1
            self.session=URLSession(configuration:config,delegate:self,delegateQueue:queue)
            if let resumeData { self.task=self.session?.downloadTask(withResumeData:resumeData) }
            else { self.task=self.session?.downloadTask(with:url) }
            continuation.onTermination={ [weak self] _ in self?.cancel() }
            self.task?.resume()
        }
    }
    func cancel() { lock.lock(); let t=task; lock.unlock(); t?.cancel() }
    func pause() async -> Data? {
        await withCheckedContinuation { continuation in
            guard let task else { continuation.resume(returning:nil); return }
            task.cancel { data in continuation.resume(returning:data) }
        }
    }
    private func finish(_ error: Error? = nil) {
        lock.lock(); guard !finished else { lock.unlock(); return }; finished=true
        let continuation=stream; stream=nil; lock.unlock()
        if let error { continuation?.finish(throwing:error) } else { continuation?.finish() }
        session?.finishTasksAndInvalidate()
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedBytes+1_048_576 { downloadTask.cancel(); finish(RiftFailure("The download exceeded the catalog size and was stopped.")); return }
        stream?.yield(.progress(min(1,Double(totalBytesWritten)/Double(max(1,expectedBytes)))))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response=downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw RiftFailure("The model host did not allow this download. A gated or unavailable model must be obtained from its author and imported through Files.") }
            let size=try location.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard Int64(size)==expectedBytes else { throw RiftFailure("The download is incomplete. Nothing was installed.") }
            try? FileManager.default.removeItem(at:destination)
            try FileManager.default.moveItem(at:location,to:destination)
            stream?.yield(.file(destination)); finish()
        } catch { finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(error) }
    }
}
