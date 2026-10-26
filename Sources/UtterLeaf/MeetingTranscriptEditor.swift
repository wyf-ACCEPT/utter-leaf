import SwiftUI
import UtterLeafCore

struct MeetingTranscriptEditor: View {
    let row: MeetingUtterance
    let initial: String
    let save: (String) -> Void
    @State private var text: String
    @State private var discard = false
    @Environment(\.dismiss) private var dismiss
    init(row: MeetingUtterance, text: String, save: @escaping (String) -> Void) {
        self.row = row; initial = text; self.save = save; _text = State(initialValue: text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑这段转录").font(LeafType.headline)
            Text("\(MeetingCaptionPolicy.recordingTime(row.start)) · 修改后需重新整理；原始识别结果和录音仍保留。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            TextEditor(text: $text).frame(height: 220).leafInput().accessibilityLabel("发言文字")
            HStack {
                Button("恢复识别文本") { text = row.text }.buttonStyle(.bordered).handCursor()
                Spacer()
                Button("取消") { cancel() }.handCursor().keyboardShortcut(.cancelAction)
                Button("保存修改") { save(text); dismiss() }.buttonStyle(PrimaryStyle()).handCursor()
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 640).background(LeafTheme.mist).foregroundStyle(LeafTheme.ink)
            .interactiveDismissDisabled(text != initial)
            .confirmationDialog("放弃这段文字的修改？", isPresented: $discard) {
                Button("放弃修改", role: .destructive) { dismiss() }; Button("继续编辑", role: .cancel) {}
            }
    }
    private func cancel() { if text != initial { discard = true } else { dismiss() } }
}
