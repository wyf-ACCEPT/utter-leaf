import XCTest
import AppKit
import UtterLeafCore
@testable import UtterLeaf

final class MeetingCaptionTests: XCTestCase {
    func testPanelOnlyAppearsForActiveLiveRecordingAndEnabledPreference() {
        XCTAssertTrue(MeetingCaptionPolicy.shouldShow(recording: true, paused: false, live: true, enabled: true))
        XCTAssertFalse(MeetingCaptionPolicy.shouldShow(recording: false, paused: false, live: true, enabled: true))
        XCTAssertFalse(MeetingCaptionPolicy.shouldShow(recording: true, paused: true, live: true, enabled: true))
        XCTAssertFalse(MeetingCaptionPolicy.shouldShow(recording: true, paused: false, live: false, enabled: true))
        XCTAssertFalse(MeetingCaptionPolicy.shouldShow(recording: true, paused: false, live: true, enabled: false))
    }
    func testCaptionPresentationDefaultsAndInvalidStoredValues() {
        XCTAssertEqual(MeetingCaptionPolicy.opacity(nil), 0.75)
        XCTAssertEqual(MeetingCaptionPolicy.opacity(.nan), 0.75)
        XCTAssertEqual(MeetingCaptionPolicy.opacity(0), 0.35)
        XCTAssertEqual(MeetingCaptionPolicy.opacity(2), 1)
        XCTAssertEqual(MeetingCaptionPolicy.lineCount(nil), 3)
        XCTAssertEqual(MeetingCaptionPolicy.lineCount(100), 3)
        XCTAssertEqual(MeetingCaptionPolicy.lineCount(5), 5)
    }
    func testPartialUtteranceReplacesPreviousTextAndRetainsSourceIdentity() {
        let row = MeetingUtterance(id: "u0", start: 0, end: 1, speaker: "1", text: "First")
        var lines = MeetingCaptionPolicy.updating([], source: "microphone", row: row)
        let update = MeetingUtterance(id: "u0", start: 0, end: 2, speaker: "1", text: "First sentence")
        lines = MeetingCaptionPolicy.updating(lines, source: "microphone", row: update)
        XCTAssertEqual(lines.count, 1); XCTAssertEqual(lines.last?.text, "First sentence")
        lines = MeetingCaptionPolicy.updating(lines, source: "system", row: row)
        XCTAssertEqual(lines.count, 2); XCTAssertNotEqual(lines[0].id, lines[1].id)
    }
    func testCaptionBufferAndDisplayedTextStayBounded() {
        var lines: [MeetingCaptionLine] = []
        for i in 0..<20 {
            lines = MeetingCaptionPolicy.updating(lines, source: "system", row: .init(id: "u\(i)", start: Double(i), end: Double(i + 1), speaker: "1", text: String(repeating: "字", count: 1000) + "最新发言"))
        }
        XCTAssertEqual(lines.count, 5); XCTAssertEqual(lines.last?.text.count, 240)
        XCTAssertTrue(lines.last?.text.hasSuffix("最新发言") == true)
        XCTAssertEqual(MeetingCaptionPolicy.updating(lines, source: "system", row: .init(id: "u", start: 100, end: 101, speaker: "1", text: "  \n")), lines)
    }
    @MainActor func testFloatingCaptionDefaultAndDisabledPreferenceSurviveRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = MeetingModel(ledger: LocalStore(root: folder))
        XCTAssertTrue(model.live); XCTAssertTrue(model.floatingCaptions)
        model.floatingCaptions = false; model.captionOpacity = 0.4; model.captionLineCount = 5; model.saveOptions()
        let restored = MeetingModel(ledger: LocalStore(root: folder))
        XCTAssertTrue(restored.live); XCTAssertFalse(restored.floatingCaptions)
        XCTAssertEqual(restored.captionOpacity, 0.4); XCTAssertEqual(restored.captionLineCount, 5)
    }
}

extension MeetingCaptionTests {
    func testProvisionalRowsDoNotDiscardSpeechWhileIdentityIsUnconfirmed() throws {
        let payload: [String: Any] = ["result": ["utterances": [
            ["text": "Unfinished prefix", "start_time": -1, "end_time": -1],
            ["text": "Current speech", "start_time": 1000, "end_time": 2000, "additions": ["speaker_id": ""]]
        ]]]
        XCTAssertThrowsError(try MeetingProtocol.segments(payload))
        let rows = try MeetingProtocol.segments(payload, provisional: true)
        XCTAssertEqual(rows.count, 2); XCTAssertEqual(rows[1].text, "Current speech")
        XCTAssertEqual(rows[0].start, -1); XCTAssertEqual(rows[1].speaker, "unknown")
        var lines = MeetingCaptionPolicy.updating([], source: "system", row: rows[0])
        lines = MeetingCaptionPolicy.updating(lines, source: "system", row: .init(id: "u0", start: 0, end: 1, speaker: "1", text: "Confirmed prefix"))
        XCTAssertEqual(lines.count, 1); XCTAssertEqual(lines[0].text, "Confirmed prefix")
    }
}

extension MeetingCaptionTests {
    @MainActor func testNativePanelShowsAndHidesWithoutTakingKeyboardFocus() async throws {
        guard ProcessInfo.processInfo.environment["UTTERLEAF_NATIVE_PANEL_TEST"] == "1" else { throw XCTSkip("Requires an interactive macOS desktop") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root), model = MeetingModel(ledger: LocalStore(root: root))
        let controller = MeetingCaptionPanel(); controller.attach(model: model, store: store)
        defer { controller.close() }
        let originalKey = NSApp.keyWindow
        let originalApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        model.recording = true
        model.captionLines = MeetingCaptionPolicy.updating([], source: "system", row: .init(id: "u0", start: 0, end: 3, speaker: "1", text: "今天先确认方案，明天准备设计稿。"))
        model.captionStatus = "实时转录 · 说话人暂定"
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(controller.panel?.isVisible == true)
        XCTAssertFalse(controller.panel?.isKeyWindow == true)
        XCTAssertEqual(NSApp.keyWindow, originalKey)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, originalApp)
        if let panel = controller.panel, let screen = NSScreen.main {
            XCTAssertEqual(panel.frame.midX, screen.visibleFrame.midX, accuracy: 1)
            XCTAssertEqual(panel.frame.midY, screen.visibleFrame.midY, accuracy: 1)
        }
        if let view = controller.panel?.contentView {
            view.layoutSubtreeIfNeeded()
            if let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: image)
                let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/verification/floating-caption-preview.png")
                try image.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        let originalFrame = try XCTUnwrap(controller.panel?.frame)
        // Simulate a user-selected location without synthesizing system input.
        let moved = originalFrame.offsetBy(dx: 25, dy: 20)
        controller.panel?.setFrame(moved, display: true)
        model.captionLineCount = 5
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.panel!.frame.minX, moved.minX, accuracy: 1)
        XCTAssertEqual(controller.panel!.frame.maxY, moved.maxY, accuracy: 1)
        XCTAssertEqual(controller.panel!.frame.height, 240, accuracy: 1)
        model.captionsCollapsed = true
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.panel!.frame.width, 260, accuracy: 1)
        XCTAssertEqual(controller.panel!.frame.height, 52, accuracy: 1)
        XCTAssertTrue(model.recording); XCTAssertTrue(model.live)
        model.captionsCollapsed = false
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.panel!.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(controller.panel!.frame.height, 240, accuracy: 1)
        XCTAssertEqual(NSApp.keyWindow, originalKey)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, originalApp)
        model.paused = true; try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(controller.panel?.isVisible == true)
        model.paused = false; try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.panel?.isVisible == true)
        model.floatingCaptions = false; try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(controller.panel?.isVisible == true)
        XCTAssertTrue(model.live)
        model.floatingCaptions = true; model.recording = false; try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(controller.panel?.isVisible == true)
    }
}
