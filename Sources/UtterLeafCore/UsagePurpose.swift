import Foundation

public enum UsagePurpose: String, CaseIterable {
    case all, dictation, meeting
    public static func isMeeting(_ call: UsageCall, jobs: [HistoryJob]) -> Bool {
        jobs.contains { $0.id == call.jobID && $0.kind == "meeting" } || call.model.hasPrefix("meeting-") || call.model.hasPrefix("voiceprint-") || call.model.hasSuffix("-meeting")
    }
    public func matches(_ call: UsageCall, jobs: [HistoryJob]) -> Bool {
        self == .all || (Self.isMeeting(call, jobs: jobs) ? self == .meeting : self == .dictation)
    }
}
