import Foundation

public struct MeetingWorkProgress: Equatable {
    public enum Stage: String { case saving, preparing, uploading, queued, recognizing, cleaning, briefing, merging }
    public var stage: Stage
    public var completed: Int
    public var total: Int
    public var started: Date
    public init(_ stage: Stage, completed: Int = 0, total: Int = 0, started: Date = Date()) {
        self.stage = stage; self.completed = completed; self.total = total; self.started = started
    }
    public var fraction: Double? { total > 0 ? min(1, max(0, Double(completed) / Double(total))) : nil }
    public var title: String {
        switch stage {
        case .saving: return "保存会议音频"
        case .preparing: return "准备音频文件"
        case .uploading: return "上传会议音频"
        case .queued: return "豆包排队中"
        case .recognizing: return "豆包转录中"
        case .cleaning: return "整理转录"
        case .briefing: return "生成 Brief"
        case .merging: return "合并 Brief"
        }
    }
}
