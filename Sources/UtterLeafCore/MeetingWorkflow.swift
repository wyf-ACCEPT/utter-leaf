import Foundation

public enum MeetingTextSection: String, CaseIterable, Identifiable {
    case notes, raw, brief
    public var id: String { rawValue }
    public var title: String {
        switch self { case .notes: return "我的笔记"; case .raw: return "原始转录"; case .brief: return "Brief" }
    }
}
public enum MeetingWorkflow {
    /// Notes, then the raw transcript, then an optional Brief generated straight from the raw transcript.
    public enum Next: Equatable { case transcribe, brief, read }
    public static func next(_ meeting: MeetingRecord) -> Next {
        if meeting.segments.isEmpty { return .transcribe }
        return meeting.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meeting.briefNeedsUpdate == true ? .brief : .read
    }
}
public enum MeetingTextExport {
    public static func body(_ meeting: MeetingRecord, section: MeetingTextSection, references: Bool) -> String? {
        let text: String
        switch section {
        case .notes: text = meeting.notes
        case .brief: text = MeetingProtocol.briefForDisplay(meeting.brief, references: references)
        case .raw:
            guard !meeting.segments.isEmpty else { return nil }
            text = meeting.segments.map { row in
                "[\(MeetingCaptionPolicy.recordingTime(row.start))] \(meeting.name(for: meeting.speaker(for: row)))：\(meeting.text(for: row))"
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
        MeetingNaming.stem(meeting) + ".txt"
    }
}
