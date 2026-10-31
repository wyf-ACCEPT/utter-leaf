import AppKit
import UtterLeafCore
import QuartzCore
import SwiftUI

/// Owns the app's explicit titlebar gesture, independently of the system double-click preference.
@MainActor final class UtterLeafWindow: NSWindow, NSWindowDelegate {
    private var transitioningFullScreen = false
    private var changingFrame = false
    private var fillAfterExitingFullScreen = false
    private var fillState: WindowFillState?
    private let restoreKey = "UtterLeafDesktopRestoreFrame"
    private let filledKey = "UtterLeafDesktopFilledFrame"
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2,
           !transitioningFullScreen, !changingFrame, attachedSheet == nil, isTitlebarPoint(event.locationInWindow) {
            toggleDesktopFill()
            return
        }
        super.sendEvent(event)
    }
    private func toggleDesktopFill() {
        if styleMask.contains(.fullScreen) {
            fillAfterExitingFullScreen = true
            toggleFullScreen(nil)
            return
        }
        guard let screen = screen ?? NSScreen.main else { return }
        if fillState == nil {
            let defaults = UserDefaults.standard
            let restore = defaults.string(forKey: restoreKey).map(NSRectFromString)
            let filled = defaults.string(forKey: filledKey).map(NSRectFromString)
            fillState = WindowFillState(restoreFrame: restore?.width ?? 0 > 0 ? restore : nil,
                                        filledFrame: filled?.width ?? 0 > 0 ? filled : nil)
        }
        let target = fillState!.destination(current: frame, visibleFrame: screen.visibleFrame)
        let defaults = UserDefaults.standard
        if let saved = fillState?.restoreFrame, let filled = fillState?.filledFrame {
            defaults.set(NSStringFromRect(saved), forKey: restoreKey)
            defaults.set(NSStringFromRect(filled), forKey: filledKey)
        } else {
            defaults.removeObject(forKey: restoreKey); defaults.removeObject(forKey: filledKey)
        }
        changingFrame = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setFrame(target, display: true); changingFrame = false
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.changingFrame = false }
            }
        }
    }
    private func isTitlebarPoint(_ point: NSPoint) -> Bool {
        let height = max(28, frame.height - contentLayoutRect.maxY)
        guard point.x >= 0, point.x <= frame.width, point.y >= frame.height - height, point.y <= frame.height else { return false }
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = standardWindowButton(kind), button.convert(button.bounds, to: nil).insetBy(dx: -5, dy: -5).contains(point) { return false }
        }
        return true
    }
    func windowWillEnterFullScreen(_ notification: Notification) { transitioningFullScreen = true }
    func windowWillExitFullScreen(_ notification: Notification) { transitioningFullScreen = true }
    func windowDidEnterFullScreen(_ notification: Notification) { transitioningFullScreen = false }
    func windowDidExitFullScreen(_ notification: Notification) {
        transitioningFullScreen = false
        if fillAfterExitingFullScreen { fillAfterExitingFullScreen = false; toggleDesktopFill() }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { transitioningFullScreen = false }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { transitioningFullScreen = false; fillAfterExitingFullScreen = false }
}

@MainActor final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class RecordingPillHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
