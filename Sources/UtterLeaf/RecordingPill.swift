import SwiftUI
import UtterLeafCore

struct RecordingPill: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: LocalStore
    @ObservedObject var presentation: PillPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var stage: PillPresentation.Stage { presentation.stage }
    private var limitWarning: String? { stage == .recording ? RecordingLimit.warning(at: model.elapsed) : nil }
    private var detail: String { limitWarning ?? presentation.detail }
    private var swap: AnyTransition { reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)) }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if stage == .recording {
                    LiveWaveform(meter: model.waveform, active: model.phase == .recording, compact: true).equatable()
                        .transition(swap)
                } else if stage == .preparing || stage == .processing {
                    ProgressView().controlSize(.small).frame(width: 28, height: 32)
                        .accessibilityLabel(stage.title).transition(swap)
                } else {
                    Image(systemName: stage.icon).font(.system(size: 20, weight: .medium))
                        .frame(width: 28, height: 32).transition(swap)
                }
            }.frame(width: stage == .recording ? 82 : 28, height: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(stage.title).font(.system(size: LeafType.scaled(13), weight: .medium))
                    .id(stage).transition(.opacity)
                if !stage.isTerminal {
                    Text(detail).monospacedDigit().font(.system(size: LeafType.scaled(10)))
                        .foregroundStyle(limitWarning == nil ? LeafTheme.muted : .orange)
                        .accessibilityLabel(limitWarning == nil ? detail : "录音即将达到 5 分钟上限，" + detail)
                }
            }.fixedSize(horizontal: true, vertical: true)
            if !stage.isTerminal {
                Spacer(minLength: 0)
                if stage == .recording {
                    Button(action: model.stop) { Image(systemName: "stop.circle.fill").font(.system(size: 26, weight: .medium)) }
                        .buttonStyle(.plain).handCursor().help("结束录音").accessibilityLabel("结束录音").transition(swap)
                }
                Button { model.abort() } label: { Image(systemName: "xmark.circle").font(.system(size: 23)) }
                    .buttonStyle(.plain).handCursor().help("取消录音").accessibilityLabel("取消录音").disabled(model.inserting)
            }
        }.padding(.horizontal, 18)
            .frame(width: presentation.revealed || reduceMotion ? stage.width : 96, height: 76)
            .foregroundStyle(LeafTheme.leaf).background(LeafTheme.mist, in: Capsule())
            .overlay(Capsule().stroke(LeafTheme.line)).clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            .scaleEffect(x: reduceMotion || presentation.revealed ? 1 : 0.86, y: reduceMotion || presentation.revealed ? 1 : 0.76, anchor: .bottom)
            .offset(y: reduceMotion || presentation.revealed ? 0 : 12)
            .opacity(presentation.revealed ? 1 : 0)
            .allowsHitTesting(!stage.isTerminal && presentation.revealed)
            .frame(width: 420, height: 120)
            .preferredColorScheme(LeafTheme.scheme(store.database.preferences.appearance))
    }
}
