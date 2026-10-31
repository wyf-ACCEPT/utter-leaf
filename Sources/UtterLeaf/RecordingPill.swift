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
        Group {
            if stage == .recovery { recoveryContent }
            else { activeContent }
        }.padding(.horizontal, 18)
            .frame(width: stage == .recovery || presentation.revealed || reduceMotion ? stage.width : 96, height: 76)
            .animation(nil, value: stage == .recovery)
            .foregroundStyle(LeafTheme.leaf).background(LeafTheme.mist, in: Capsule())
            .overlay(Capsule().stroke(LeafTheme.line)).clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            .scaleEffect(x: reduceMotion || presentation.revealed ? 1 : 0.86, y: reduceMotion || presentation.revealed ? 1 : 0.76, anchor: .bottom)
            .offset(y: reduceMotion || presentation.revealed ? 0 : 12)
            .opacity(presentation.revealed ? 1 : 0)
            .allowsHitTesting((!stage.isTerminal || stage == .recovery) && presentation.revealed)
            .frame(width: 420, height: 120)
            .preferredColorScheme(LeafTheme.scheme(store.database.preferences.appearance))
    }
    private var recoveryContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.pillRecoveryPreview).font(.system(size: LeafType.scaled(13), weight: .medium))
                    .foregroundStyle(LeafTheme.ink).lineLimit(1).truncationMode(.tail)
                Text(model.copyFailed ? "复制未完成，请重试" : model.draftWasCopied ? "已复制，可回原应用粘贴" : "未能自动输入，文字已保留")
                    .font(.system(size: LeafType.scaled(10))).foregroundStyle(model.copyFailed ? .orange : LeafTheme.muted).lineLimit(1)
            }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button(action: model.copy) {
                Text(model.draftWasCopied ? "已复制" : "复制").font(.system(size: 13, weight: .semibold))
                    .frame(width: 60, height: 32).background(LeafTheme.leaf.opacity(0.14), in: Capsule())
            }.buttonStyle(.plain).handCursor().help("复制整段文字")
                .accessibilityLabel(model.draftWasCopied ? "已复制完整文字，可再次复制" : "复制完整转录文字")
            Button(action: model.dismissPillRecovery) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(width: 24, height: 32)
            }.buttonStyle(.plain).handCursor().help("关闭胶囊，保留待输入文字")
                .accessibilityLabel("关闭文字预览胶囊")
        }
    }
    private var activeContent: some View {
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
        }
    }
}
