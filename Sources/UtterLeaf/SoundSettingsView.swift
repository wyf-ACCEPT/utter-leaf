import SwiftUI
import UtterLeafCore

struct SoundSettingsView: View {
    @ObservedObject var store: LocalStore
    @ObservedObject var sounds: SoundFeedback
    @State private var volume = 0.7
    private var preferences: SoundPreferences { store.database.preferences.sound ?? SoundPreferences() }
    private func update(_ change: (inout SoundPreferences) -> Void) {
        var value = preferences; change(&value); store.database.preferences.sound = value; store.save()
    }
    var body: some View {
        Surface(title: "提示音") {
            Toggle("播放操作提示音", isOn: Binding(get: { preferences.enabled }, set: { enabled in
                if !enabled { sounds.stop() }; update { $0.enabled = enabled }
            }))
            LeafSegments(title: "声音方案", selection: Binding(get: { preferences.theme }, set: { theme in
                sounds.stop(); update { $0.theme = theme }
            }), items: SoundTheme.allCases.map { LeafSegment($0, $0.title) })
            HStack(spacing: 16) {
                Text("音量").font(LeafType.caption)
                Slider(value: $volume, in: 0...1, onEditingChanged: { editing in
                    if !editing { update { $0.volume = volume } }
                }).accessibilityLabel("提示音音量")
                Text("\(Int((volume * 100).rounded()))%").font(LeafType.caption).monospacedDigit().frame(width: 44)
                Button(sounds.previewing ? "停止试听" : "试听") {
                    if sounds.previewing { sounds.stop() }
                    else { var value = preferences; value.volume = volume; sounds.preview(preferences: value) }
                }.buttonStyle(.bordered).handCursor().frame(width: 100)
            }.disabled(!preferences.enabled)
            Text("默认 A · 轻触。试听顺序：开始录音 → 结束录音 → 确认回填完成。开始提示音结束后开启采音，减少混入转写；取消或回填未确认时不播放完成音。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            if let error = sounds.error { Text(error).font(LeafType.caption).foregroundStyle(.orange) }
        }.onAppear { volume = preferences.volume.isFinite ? min(max(preferences.volume, 0), 1) : 0.7 }
            .onDisappear { sounds.stop() }
    }
}
