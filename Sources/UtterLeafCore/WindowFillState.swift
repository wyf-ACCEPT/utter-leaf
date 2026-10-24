import Foundation
import CoreGraphics

/// Desktop fill remembers the complete user frame, including its position.
public struct WindowFillState {
    public private(set) var restoreFrame: CGRect?
    public private(set) var filledFrame: CGRect?
    public init(restoreFrame: CGRect? = nil, filledFrame: CGRect? = nil) {
        self.restoreFrame = restoreFrame; self.filledFrame = filledFrame
    }
    public mutating func destination(current: CGRect, visibleFrame: CGRect) -> CGRect {
        if let restoreFrame, let filledFrame, Self.matches(current, filledFrame) {
            self.restoreFrame = nil; self.filledFrame = nil
            return Self.fitting(restoreFrame, in: visibleFrame)
        }
        // A manually moved/resized frame becomes the new restoration point.
        restoreFrame = current; filledFrame = visibleFrame
        return visibleFrame
    }
    public static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }
    private static func fitting(_ frame: CGRect, in screen: CGRect) -> CGRect {
        if screen.contains(frame) { return frame }
        let width = min(frame.width, screen.width), height = min(frame.height, screen.height)
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
}
