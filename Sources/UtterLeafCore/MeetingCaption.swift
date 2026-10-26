import Foundation

public struct MeetingCaptionLine: Equatable, Identifiable {
    public let id: String
    public let source: String
    public let speaker: String
    public let text: String
}
public enum MeetingCaptionPolicy {
    public static let lineOptions = [2, 3, 5]
    public static func lineCount(_ value: Int?) -> Int { lineOptions.contains(value ?? 3) ? (value ?? 3) : 3 }
    public static func opacity(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0.75 }
        return min(1, max(0.35, value))
    }
    public static func shouldShow(recording: Bool, paused: Bool, live: Bool, enabled: Bool) -> Bool {
        recording && enabled
    }
    public static func recordingTime(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, min(10800, seconds.rounded(.down)))) : 0
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
    public static func updating(_ lines: [MeetingCaptionLine], source: String, row: MeetingUtterance) -> [MeetingCaptionLine] {
        let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return lines }
        let id = source + ":" + (row.start < 0 ? "pending" : String(row.start))
        let line = MeetingCaptionLine(id: id, source: source, speaker: row.speaker, text: String(text.suffix(240)))
        if lines.last == line { return lines }
        return Array((lines.filter { $0.id != id && !(row.start >= 0 && $0.id == source + ":pending") } + [line]).suffix(5))
    }
}
