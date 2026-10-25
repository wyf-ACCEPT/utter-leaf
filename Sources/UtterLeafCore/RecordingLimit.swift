import Foundation

public enum RecordingLimit {
    public static let seconds = 300
    public static let warningSeconds = 30
    public static let pcmBytesPerSecond = 32_000
    public static let maximumPCMBytes = seconds * pcmBytesPerSecond
    public static func remaining(at elapsed: Double) -> Int {
        max(0, Int(ceil(Double(seconds) - max(0, elapsed))))
    }
    public static func warning(at elapsed: Double) -> String? {
        guard elapsed >= Double(seconds - warningSeconds) else { return nil }
        return "剩余 \(remaining(at: elapsed)) 秒"
    }
    public static func acceptedBytes(buffered: Int, incoming: Int) -> Int {
        min(max(0, incoming), max(0, maximumPCMBytes - buffered))
    }
}
