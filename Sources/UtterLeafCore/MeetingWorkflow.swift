import Foundation

public enum MeetingTextSection: String, CaseIterable, Identifiable {
    case notes, raw, cleaned, brief
    public var id: String { rawValue }
    public var title: String {
        switch self { case .notes: return "我的笔记"; case .raw: return "原始转录"; case .cleaned: return "整理转录"; case .brief: return "Brief" }
    }
}
public enum MeetingWorkflow {
    public enum Next: Equatable { case transcribe, clean, brief, read }
    public static func cleaned(_ meeting: MeetingRecord) -> Bool {
        !meeting.segments.isEmpty && meeting.segments.allSatisfy {
            !(meeting.cleaned?[$0.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
    public static func next(_ meeting: MeetingRecord) -> Next {
        if meeting.segments.isEmpty { return .transcribe }
        if !cleaned(meeting) { return .clean }
        return meeting.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meeting.briefNeedsUpdate == true ? .brief : .read
    }
}
public enum MeetingTextExport {
    public static func body(_ meeting: MeetingRecord, section: MeetingTextSection, references: Bool) -> String? {
        let text: String
        switch section {
        case .notes: text = meeting.notes
        case .brief: text = MeetingProtocol.briefForDisplay(meeting.brief, references: references)
        case .raw, .cleaned:
            guard !meeting.segments.isEmpty, section != .cleaned || MeetingWorkflow.cleaned(meeting) else { return nil }
            text = meeting.segments.map { row in
                let words = section == .cleaned ? (meeting.cleaned?[row.id] ?? meeting.text(for: row)) : meeting.text(for: row)
                return "[\(MeetingCaptionPolicy.recordingTime(row.start))] \(meeting.name(for: meeting.speaker(for: row)))：\(words)"
            }.joined(separator: "\n\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
    public static func document(_ meeting: MeetingRecord, section: MeetingTextSection, references: Bool) -> String? {
        guard let text = body(meeting, section: section, references: references) else { return nil }
        let date = meeting.created.formatted(date: .abbreviated, time: .shortened)
        return "\(meeting.title)\n\(date) · \(MeetingCaptionPolicy.recordingTime(meeting.seconds))\n\(section.title)\n\n\(text)\n"
    }
    public static func filename(_ meeting: MeetingRecord, section: MeetingTextSection) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        let title = String(meeting.title.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined().prefix(100))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title.isEmpty || title.allSatisfy({ $0 == "." }) ? "会议" : title) + "-" + section.title + ".txt"
    }
}
