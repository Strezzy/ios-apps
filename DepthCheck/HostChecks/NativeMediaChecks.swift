import Darwin
import Foundation
import Metal
import VideoToolbox
import XCTest

/// A macOS-only entry point for an exact existing test, never part of the iOS app.
/// Compile the existing media XCTest files unchanged into this executable, linked to an
/// enable-testing DepthCheck module built from the unchanged production files.
@main
@MainActor
enum NativeMediaChecks {
    private static let spatialTestName = "testSpatialVideoPreservesBothEyeLayersAndLastFrameDurationWithLongerAudio"
    private static let sustainedTestNames: Set<String> = [
        "test874FramesWithAudioTailReproduce920FrameEstimate",
        "test920FramesOf60FPSSBSWithAACEndingBeforeVideo",
        "testThreeMinute60FPSSBSWithDelayedAAC",
        "test920FramesOf4K60FPSPreservesFullSBSWithAAC",
        "testThreeMinute4K60FPSPreservesFullSBSWithAAC"
    ]

    static func main() {
        guard CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--test",
              CommandLine.arguments[3] == "--result" else {
            FileHandle.standardError.write(Data("Usage: NativeMediaChecks --test ExactTestMethod --result /path/to/result.json\n".utf8))
            exit(64)
        }
        let testName = CommandLine.arguments[2]
        let resultURL = URL(fileURLWithPath: CommandLine.arguments[4])
        let supported = VTIsStereoMVHEVCEncodeSupported()
        let device = MTLCreateSystemDefaultDevice()
        var result: [String: Any] = [
            "platform": "macOS",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "test": testName,
            "native_mvhevc_supported": supported,
            "metal_device": device?.name ?? "unavailable",
            "execution_count": 0,
            "skip_count": 0,
            "failure_count": 0,
        ]
        let spatial = testName == spatialTestName
        guard spatial || sustainedTestNames.contains(testName) else {
            result["status"] = "invalid_test_selection"
            result["reason"] = "The requested method is not one of the required native media checks."
            finish(result, at: resultURL, exitCode: 64)
        }
        guard device != nil, !spatial || supported else {
            result["status"] = "unsupported"
            result["reason"] = spatial
                ? "The native Mac must expose both Metal and stereo MV-HEVC encoding. This is not a passing validation."
                : "Sustained full-resolution validation requires native Metal. This is not a passing validation."
            finish(result, at: resultURL, exitCode: 78)
        }

        // Select an exact method-name token from XCTest's own discovered cases,
        // preserving its async invocation and all original test assertions.
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted
        let discovered = spatial ? MediaExportTests.defaultTestSuite.tests : SustainedVideoExportTests.defaultTestSuite.tests
        let selected = discovered.filter { $0.name.components(separatedBy: separators).contains(testName) }
        guard selected.count == 1 else {
            result["status"] = "invalid_test_selection"
            result["selected_test_count"] = selected.count
            result["discovered_tests"] = discovered.map(\.name)
            finish(result, at: resultURL, exitCode: 1)
        }
        let observer = NativeIssueObserver()
        XCTestObservationCenter.shared.addTestObserver(observer)
        let suite = XCTestSuite(name: "Native media validation: \(testName)")
        suite.addTest(selected[0])
        suite.run()
        XCTestObservationCenter.shared.removeTestObserver(observer)

        guard let run = suite.testRun else {
            result["status"] = "missing_test_run"
            finish(result, at: resultURL, exitCode: 1)
        }
        result["execution_count"] = run.executionCount
        result["test_case_count"] = run.testCaseCount
        result["skip_count"] = run.skipCount
        result["failure_count"] = run.totalFailureCount
        result["duration_seconds"] = run.totalDuration
        result["completed"] = run.stopDate != nil
        result["issues"] = observer.recordedIssues
        let evidence = spatial ? nil : SustainedVideoExportTests.nativeEvidence[testName]
        if let evidence { result["coverage"] = evidence }
        if !spatial, evidence == nil {
            result["evidence_error"] = "The sustained test did not record completed frame, timing, audio, and terminal-frame verification."
        }
        let passed = run.executionCount == 1 && run.testCaseCount == 1
            && run.skipCount == 0 && run.totalFailureCount == 0 && run.hasSucceeded && run.stopDate != nil
            && (spatial || evidence != nil)
        result["status"] = passed ? "passed" : "failed"
        finish(result, at: resultURL, exitCode: passed ? 0 : 1)
    }

    private static func finish(_ result: [String: Any], at url: URL, exitCode: Int32) -> Never {
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(exitCode)
        } catch {
            FileHandle.standardError.write(Data("Could not record native validation: \(error)\n".utf8))
            exit(1)
        }
    }
}

private final class NativeIssueObserver: NSObject, XCTestObservation {
    private let lock = NSLock()
    private var issues: [String] = []

    var recordedIssues: [String] {
        lock.lock()
        defer { lock.unlock() }
        return issues
    }

    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        let message = "\(testCase.name): \(issue.compactDescription)"
        lock.lock()
        issues.append(message)
        lock.unlock()
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
