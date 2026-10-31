import XCTest
@testable import UtterLeaf

final class PillPresentationTests: XCTestCase {
    @MainActor func testRecoveryStaysVisibleUntilDismissedOrReplaced() async throws {
        let pill = PillPresentation(dwell: .milliseconds(20), exitWait: .milliseconds(20))
        var hidden = 0; pill.orderOut = { hidden += 1 }
        pill.show(.recording, detail: "synthetic", reduceMotion: true)
        pill.finish(.recovery, reduceMotion: true)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertTrue(pill.onScreen); XCTAssertTrue(pill.revealed)
        XCTAssertEqual(pill.stage, .recovery); XCTAssertEqual(hidden, 0)
        pill.show(.recording, detail: "new synthetic session", reduceMotion: true)
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertTrue(pill.onScreen); XCTAssertEqual(pill.stage, .recording)
        pill.closeImmediately(); XCTAssertEqual(hidden, 1)
    }
    @MainActor func testRestartDuringDismissalCannotHideNewRecording() async throws {
        let pill = PillPresentation(dwell: .milliseconds(30), exitWait: .milliseconds(30))
        var shown = 0, hidden = 0
        pill.orderFront = { shown += 1 }; pill.orderOut = { hidden += 1 }
        pill.show(.recording, detail: "test", reduceMotion: false)
        try await Task.sleep(for: .milliseconds(30))
        pill.finish(.inserted, reduceMotion: false)
        try await Task.sleep(for: .milliseconds(40))
        pill.show(.recording, detail: "new", reduceMotion: false)
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertTrue(pill.onScreen); XCTAssertTrue(pill.revealed)
        XCTAssertEqual(pill.stage, .recording); XCTAssertEqual(hidden, 0); XCTAssertEqual(shown, 1)
        pill.closeImmediately()
    }
    @MainActor func testProcessingTransitionKeepsSingleNonactivatingPanelLifetime() async throws {
        let pill = PillPresentation(dwell: .milliseconds(20), exitWait: .milliseconds(20))
        var shown = 0, hidden = 0
        pill.orderFront = { shown += 1 }; pill.orderOut = { hidden += 1 }
        pill.show(.preparing, detail: "test", reduceMotion: false)
        pill.show(.recording, detail: "test", reduceMotion: false)
        pill.show(.processing, detail: "cleanup", reduceMotion: false)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(shown, 1); XCTAssertEqual(hidden, 0); XCTAssertEqual(pill.detail, "cleanup")
        pill.finish(.retained, reduceMotion: false)
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertFalse(pill.onScreen); XCTAssertEqual(hidden, 1)
    }
    @MainActor func testReducedMotionAndExplicitShutdownCancelPendingExit() async throws {
        let pill = PillPresentation(dwell: .milliseconds(20), exitWait: .milliseconds(20))
        var hidden = 0; pill.orderOut = { hidden += 1 }
        pill.show(.recording, detail: "test", reduceMotion: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(pill.revealed)
        pill.finish(.cancelled, reduceMotion: true)
        pill.closeImmediately()
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertFalse(pill.onScreen); XCTAssertEqual(hidden, 1)
    }
}
