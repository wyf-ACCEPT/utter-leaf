import SwiftUI
import UtterLeafCore

struct MeetingProcessingView: View {
    let work: MeetingWorkProgress
    let canStop: Bool
    let stop: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(work.title).font(LeafType.headline)
                Spacer()
                if let fraction = work.fraction { Text("\(Int(fraction * 100))%").monospacedDigit() }
                if canStop { Button("停止等待", action: stop).buttonStyle(.bordered).handCursor() }
            }
            if let fraction = work.fraction { ProgressView(value: fraction).tint(LeafTheme.leaf) }
            else { ProgressView().progressViewStyle(.linear).tint(LeafTheme.leaf) }
            if work.total > 0, work.stage != .uploading {
                Text("已完成 \(work.completed) / \(work.total) \(work.stage == .cleaning ? "段发言" : "个片段")；仅统计已返回并校验的内容。")
                    .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("已等待 \(MeetingCaptionPolicy.recordingTime(context.date.timeIntervalSince(work.started)))" + (work.stage == .queued || work.stage == .recognizing ? " · 豆包未提供识别百分比" : ""))
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
            }
        }.padding(16).background(LeafTheme.leaf.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain).accessibilityLabel("会议处理进度")
    }
}
