import XCTest
import AppKit
import SwiftUI
import UtterLeafCore
@testable import UtterLeaf

final class PillRecoveryTests: XCTestCase {
    @MainActor func testAutomaticFallbackCopiesFullTextWithoutOpeningMainAndCloseKeepsDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var copied: [String] = [], opened = 0
        let model = AppModel(store: LocalStore(root: root), captureTarget: { nil }, clipboardWriter: { copied.append($0); return true })
        model.showWindow = { opened += 1 }
        let text = String(repeating: "合成文字 🌿 English\n", count: 25)
        await model.deliver(text, automatic: true)
        XCTAssertTrue(model.showsPillRecovery); XCTAssertEqual(model.phase, .preview)
        XCTAssertLessThanOrEqual(model.pillRecoveryPreview.count, 37)
        XCTAssertFalse(model.pillRecoveryPreview.contains("\n"))
        XCTAssertEqual(opened, 0)
        model.copy()
        XCTAssertEqual(copied, [text]); XCTAssertEqual(model.draft, text)
        XCTAssertTrue(model.draftWasCopied); XCTAssertTrue(model.showsPillRecovery)
        model.dismissPillRecovery()
        XCTAssertFalse(model.showsPillRecovery); XCTAssertEqual(model.draft, text)
        XCTAssertEqual(opened, 0)
        model.preservePendingDraft()
        XCTAssertEqual(model.phase, .idle); XCTAssertTrue(model.draft.isEmpty)
    }
    @MainActor func testClipboardFailureRetainsTextAndManualPreviewStillOpensMain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var accepts = false, opened = 0
        let model = AppModel(store: LocalStore(root: root), captureTarget: { nil }, clipboardWriter: { _ in accepts })
        model.showWindow = { opened += 1 }
        await model.deliver("Synthetic retained draft", automatic: true)
        model.copy(); XCTAssertTrue(model.copyFailed); XCTAssertFalse(model.draftWasCopied)
        XCTAssertEqual(model.draft, "Synthetic retained draft"); XCTAssertTrue(model.showsPillRecovery)
        accepts = true; model.copy()
        XCTAssertFalse(model.copyFailed); XCTAssertTrue(model.draftWasCopied)
        model.draft += " edited"
        XCTAssertFalse(model.draftWasCopied)
        await model.deliver("Explicit manual preview", automatic: false)
        XCTAssertFalse(model.showsPillRecovery); XCTAssertEqual(opened, 1)
    }
    @MainActor func testRecoveryPanelRendersAndCannotTakeKeyboardFocus() async throws {
        guard ProcessInfo.processInfo.environment["UTTERLEAF_NATIVE_PANEL_TEST"] == "1" else { throw XCTSkip("Requires native panel rendering") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var copied = "", accepts = false
        let model = AppModel(store: LocalStore(root: root), captureTarget: { nil }, clipboardWriter: { copied = $0; return accepts })
        let text = "这是一段合成测试转录，用于验证胶囊预览和完整复制。\nThe entire transcript must remain available after copying."
        await model.deliver(text, automatic: true)
        let pill = PillPresentation(), panel = RecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        let host = RecordingPillHost(rootView: RecordingPill(model: model, store: model.store, presentation: pill).preferredColorScheme(.dark))
        panel.contentView = host; host.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        XCTAssertFalse(panel.canBecomeKey); XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(host.acceptsFirstMouse(for: nil))
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        pill.orderFront = { panel.orderFrontRegardless() }; pill.orderOut = { panel.orderOut(nil) }
        pill.show(.recovery, detail: "synthetic", reduceMotion: true)
        for state in ["ready", "failed", "copied"] {
            if state != "ready" { accepts = state == "copied"; model.copy() }
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(state == "ready" ? 220 : 80))
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/verification/6x31-recovery-pill-\(state).png")
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: file)
        }
        XCTAssertEqual(copied, text); XCTAssertEqual(model.draft, text)
        XCTAssertFalse(panel.isKeyWindow); XCTAssertFalse(panel.isMainWindow)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost)
        pill.closeImmediately(); panel.close()
    }
}
