import Foundation
import Darwin
struct RiftFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
private func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}
private final class Peak: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func sample() { let next = footprint(); lock.lock(); value = max(value, next); lock.unlock() }
    func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
}
@main struct TransferProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 5, let url = URL(string: args[1]), let bytes = Int64(args[3]) else { throw RiftFailure("Expected URL destination bytes SHA256") }
        let destination = URL(fileURLWithPath: args[2]), peak = Peak(), baseline = footprint()
        let monitor = Task.detached {
            while !Task.isCancelled { peak.sample(); try? await Task.sleep(nanoseconds: 25_000_000) }
        }
        defer { monitor.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        let job = DownloadJob(destination: destination, expectedBytes: bytes)
        var events = 0, completed = false
        for try await event in job.start(url: url, cellular: true) {
            peak.sample()
            switch event { case .progress: events += 1; case .file: completed = true }
        }
        guard completed else { throw RiftFailure("No completed file") }
        let digest = try await Task.detached { try GGUFInspector.hash(destination) { _ in peak.sample() } }.value
        let info = try await Task.detached { try GGUFInspector.inspect(destination) }.value
        guard digest == args[4], info.bytes == bytes else { throw RiftFailure("Transfer identity mismatch") }
        let growth = peak.read() > baseline ? peak.read() - baseline : 0
        guard growth < 160 * 1_048_576 else { throw RiftFailure("Download/verification footprint grew by more than 160 MiB") }
        let report: [String: Any] = ["sha256": digest, "bytes": info.bytes, "architecture": info.architecture,
            "dimensions": info.dimensions, "peak_footprint_bytes": peak.read(), "baseline_bytes": baseline,
            "growth_bytes": growth, "progress_events": events, "seconds": ProcessInfo.processInfo.systemUptime - start,
            "production_download_and_verification": true, "physical_iPhone_test": false]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
