import Foundation

public struct MeetingCaptionLine: Equatable, Identifiable {
    public let id: String
    public let source: String
    public let speaker: String
    public let text: String
}
public enum MeetingCaptionPolicy {
    public static func shouldShow(recording: Bool, paused: Bool, live: Bool, enabled: Bool) -> Bool {
        recording && !paused && live && enabled
    }
    public static func updating(_ lines: [MeetingCaptionLine], source: String, row: MeetingUtterance) -> [MeetingCaptionLine] {
        let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return lines }
        let id = source + ":" + (row.start < 0 ? "pending" : String(row.start))
        let line = MeetingCaptionLine(id: id, source: source, speaker: row.speaker, text: String(text.suffix(240)))
        if lines.last == line { return lines }
        return Array((lines.filter { $0.id != id && !(row.start >= 0 && $0.id == source + ":pending") } + [line]).suffix(3))
    }
}
