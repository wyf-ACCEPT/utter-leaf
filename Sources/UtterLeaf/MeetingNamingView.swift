import SwiftUI
import UtterLeafCore

struct MeetingNamingView: View {
    @ObservedObject var model: MeetingModel
    let meeting: MeetingRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("会议命名").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                Spacer()
                if model.namingMeetingID == meeting.id { ProgressView().controlSize(.small); Text("正在生成 3 个候选…").font(LeafType.caption) }
                else { Button(meeting.nameCandidates == nil ? "生成 3 个候选名称" : "重新生成候选") { model.suggestNames() }.handCursor().disabled(model.busy || model.namingMeetingID != nil) }
            }
            if let names = meeting.nameCandidates, !names.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(names, id: \.self) { name in
                        Button { model.applyName(name) } label: {
                            HStack { Text(name).lineLimit(2); if meeting.fileStem == name { Image(systemName: "checkmark") } }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered).handCursor().disabled(model.busy)
                    }
                }
            }
            Text("导出文件名：\(MeetingNaming.stem(meeting)).txt / .m4a")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted).textSelection(.enabled)
        }
    }
}
