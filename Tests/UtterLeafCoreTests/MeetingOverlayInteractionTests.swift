import XCTest
import AppKit
import SwiftUI
@testable import UtterLeaf

final class MeetingOverlayInteractionTests: XCTestCase {
    @MainActor func testEntireSurfaceIsDraggableWhileControlsOwnTheirHitRegions() {
        let view = MeetingOverlayInteractionView(frame: NSRect(x: 0, y: 0, width: 360, height: 136))
        view.update(paused: false, collapsed: false, recording: true); view.layoutSubtreeIfNeeded()
        for point in [NSPoint(x: 5, y: 5), NSPoint(x: 100, y: 60), NSPoint(x: 50, y: 110), NSPoint(x: 350, y: 130)] {
            XCTAssertTrue(view.hitTest(point) === view)
        }
        for button in [view.pauseButton, view.collapseButton, view.hideButton] {
            XCTAssertTrue(view.hitTest(NSPoint(x: button.frame.midX, y: button.frame.midY)) === button)
        }
        XCTAssertEqual(view.pauseButton.accessibilityLabel(), "暂停录音")
        view.frame.size = NSSize(width: 260, height: 52)
        view.update(paused: true, collapsed: true, recording: true); view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.pauseButton.accessibilityLabel(), "继续录音")
        XCTAssertEqual(view.collapseButton.accessibilityLabel(), "展开悬浮窗")
        for button in [view.pauseButton, view.collapseButton, view.hideButton] { XCTAssertTrue(view.bounds.contains(button.frame)) }
    }
    @MainActor func testPauseCollapseAndHideUseSeparateActionsAndInactivePauseIsDisabled() {
        _ = NSApplication.shared
        let view = MeetingOverlayInteractionView(frame: NSRect(x: 0, y: 0, width: 360, height: 136))
        var pause = 0, collapse = 0, hide = 0
        view.onPause = { pause += 1 }; view.onCollapse = { collapse += 1 }; view.onHide = { hide += 1 }
        view.update(paused: false, collapsed: false, recording: true)
        view.pauseButton.performClick(nil)
        XCTAssertEqual(pause, 1); XCTAssertEqual(collapse, 0); XCTAssertEqual(hide, 0)
        view.collapseButton.performClick(nil); view.hideButton.performClick(nil)
        XCTAssertEqual(pause, 1); XCTAssertEqual(collapse, 1); XCTAssertEqual(hide, 1)
        view.update(paused: true, collapsed: true, recording: false)
        XCTAssertFalse(view.pauseButton.isEnabled)
    }
    @MainActor func testNativeCompositeRoutesTextAndControlRegionsWithoutOpeningAWindow() async throws {
        guard ProcessInfo.processInfo.environment["UTTERLEAF_NATIVE_PANEL_TEST"] == "1" else { throw XCTSkip("Requires native view rendering") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root), model = MeetingModel(ledger: store)
        model.live = false; model.recording = true; model.elapsed = 748
        let nativeInteraction = MeetingOverlayInteractionView(frame: .zero)
        nativeInteraction.update(paused: false, collapsed: false, recording: true)
        let host = MeetingCaptionContentView(rootView: MeetingCaptionView(model: model, store: store).frame(width: 360, height: 136).preferredColorScheme(.dark), interaction: nativeInteraction)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 136)
        let originalApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let window = RecordingPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(100))
        func overlay(_ view: NSView) -> MeetingOverlayInteractionView? {
            if let value = view as? MeetingOverlayInteractionView { return value }
            for child in view.subviews { if let result = overlay(child) { return result } }
            return nil
        }
        let interaction = try XCTUnwrap(overlay(host))
        for point in [NSPoint(x: 5, y: 5), NSPoint(x: 100, y: 60), NSPoint(x: 50, y: 110)] {
            let hostPoint = interaction.convert(point, to: host.superview)
            XCTAssertTrue(host.hitTest(hostPoint) === interaction)
        }
        for button in [interaction.pauseButton, interaction.collapseButton, interaction.hideButton] {
            let hostPoint = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: host.superview)
            XCTAssertTrue(host.hitTest(hostPoint) === button)
        }
        if let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: image)
            let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/verification/overlay-drag-pause-preview.png")
            try image.representation(using: .png, properties: [:])?.write(to: path)
        }
        window.setContentSize(NSSize(width: 260, height: 52))
        interaction.update(paused: true, collapsed: true, recording: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(interaction.frame.size, NSSize(width: 260, height: 52))
        for button in [interaction.pauseButton, interaction.collapseButton, interaction.hideButton] {
            XCTAssertTrue(interaction.bounds.contains(button.frame))
        }
        XCTAssertFalse(window.isVisible); XCTAssertFalse(window.canBecomeKey)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, originalApp)
        XCTAssertTrue(store.database.calls.isEmpty)
    }

}
