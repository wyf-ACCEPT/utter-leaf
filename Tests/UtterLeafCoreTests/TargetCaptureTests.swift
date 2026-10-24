import XCTest
@testable import UtterLeaf

@MainActor private final class CaptureTestTarget: DictationTarget {
    let displayName = "Synthetic editor"
    func insert(_ text: String, allowActivation: Bool) async throws -> InsertionMethod { .clipboardPaste }
}

final class TargetCaptureTests: XCTestCase {
    @MainActor func testTransientFocusFailureRecoversBeforeRecording() async throws {
        var reads = 0
        let expected = CaptureTestTarget()
        let capture = TargetCapture(bundleID: "test.editor", sameContext: { true }) {
            reads += 1
            return reads < 3 ? .unavailable("capture_focus_ax_-25204", retry: true) : .captured(expected)
        }
        let target = try await capture.resolve(delays: [.zero, .zero, .zero])
        XCTAssertTrue(target === expected)
        XCTAssertEqual(capture.attempts, 3)
        XCTAssertNil(capture.errorCode)
    }
    @MainActor func testApplicationOrWindowSwitchNeverRecapturesDestination() async throws {
        var reads = 0
        let capture = TargetCapture(bundleID: "test.editor", sameContext: { false }) {
            reads += 1; return .unavailable("capture_focus_ax_-25204", retry: true)
        }
        let target = try await capture.resolve(delays: [.zero])
        XCTAssertNil(target); XCTAssertEqual(reads, 1)
        XCTAssertEqual(capture.errorCode, "capture_context_changed")
    }
    @MainActor func testSecureOrOwnAppFailureNeverRetries() async throws {
        for code in ["capture_secure", "capture_utterleaf_foreground", "capture_permission"] {
            var reads = 0
            let capture = TargetCapture(bundleID: nil, sameContext: { true }) {
                reads += 1; return .unavailable(code, retry: false)
            }
            let target = try await capture.resolve(delays: [.zero, .zero])
            XCTAssertNil(target); XCTAssertEqual(reads, 1); XCTAssertEqual(capture.errorCode, code)
        }
    }
    @MainActor func testRetriesAreBoundedAndKeepLastAXError() async throws {
        let capture = TargetCapture(bundleID: "test.editor", sameContext: { true }) {
            .unavailable("capture_selection_ax_-25204", retry: true)
        }
        let target = try await capture.resolve(delays: [.zero, .zero, .zero])
        XCTAssertNil(target); XCTAssertEqual(capture.attempts, 4)
        XCTAssertEqual(capture.errorCode, "capture_selection_ax_-25204")
    }
    @MainActor func testCancellationStopsRecapture() async throws {
        let capture = TargetCapture(bundleID: "test.editor", sameContext: { true }) {
            .unavailable("capture_focus_ax_-25204", retry: true)
        }
        let task = Task { try await capture.resolve(delays: [.seconds(1)]) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled capture must not continue") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(capture.attempts, 1)
    }
}
