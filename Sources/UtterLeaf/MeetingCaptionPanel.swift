import AppKit
import SwiftUI
import UtterLeafCore

@MainActor final class MeetingCaptionPanel {
    private(set) var panel: RecordingPanel?
    private weak var model: MeetingModel?
    private var revision = 0
    private var desiredVisible = false
    private var dismissal: Task<Void, Never>?
    func attach(model: MeetingModel, store: LocalStore) {
        self.model = model
        let panel = RecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 184), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.level = .floating; panel.isFloatingPanel = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: MeetingCaptionView(model: model, store: store))
        self.panel = panel
        model.onCaptionUpdate = { [weak self] in self?.refresh() }
        refresh()
    }
    private func refresh() {
        guard let model, let panel else { return }
        let visible = MeetingCaptionPolicy.shouldShow(recording: model.recording, paused: model.paused, live: model.live, enabled: model.floatingCaptions)
        guard desiredVisible != visible else { return }
        dismissal?.cancel()
        desiredVisible = visible; revision += 1; let token = revision
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
        if visible {
            if !panel.isVisible {
                if let screen = NSScreen.main {
                    let bounds = screen.visibleFrame
                    let width = min(660, max(300, bounds.width - 48))
                    panel.setFrame(NSRect(x: bounds.midX - width / 2, y: bounds.midY - 92, width: width, height: 184), display: false)
                }
                panel.alphaValue = 0; panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { context in context.duration = duration; panel.animator().alphaValue = 1 }
        } else if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in context.duration = duration; panel.animator().alphaValue = 0 }
            dismissal = Task { [weak self, weak panel] in
                do { try await Task.sleep(for: .milliseconds(Int(duration * 1000) + 20)) } catch { return }
                guard let self, !Task.isCancelled, self.revision == token else { return }; panel?.orderOut(nil)
            }
        }
    }
    func close() { dismissal?.cancel(); desiredVisible = false; revision += 1; panel?.orderOut(nil) }
}

private struct MeetingCaptionView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var store: LocalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "captions.bubble")
                Text(model.captionStatus).lineLimit(1)
                Spacer()
                Text("言叶 · 会议").font(.system(size: 12, weight: .medium))
            }.font(.system(size: 12)).foregroundStyle(LeafTheme.muted)
            if model.captionLines.count > 1 {
                Text(model.captionLines[model.captionLines.count - 2].text).font(.system(size: 15)).foregroundStyle(LeafTheme.muted).lineLimit(1).truncationMode(.head)
            }
            if let latest = model.captionLines.last {
                Text(latest.text).font(.system(size: LeafType.scaled(21), weight: .medium, design: .rounded))
                    .lineLimit(2).truncationMode(.head).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                    .id(latest.id).transition(.opacity)
                Text((latest.source == "system" ? "系统声音" : "麦克风") + (latest.speaker == "unknown" ? " · 说话人待确认" : " · 说话人 " + latest.speaker + "（暂定）"))
                    .font(.system(size: 12)).foregroundStyle(LeafTheme.muted)
            } else {
                Text("等待发言…").font(.system(size: LeafType.scaled(21), weight: .medium, design: .rounded)).foregroundStyle(LeafTheme.muted)
                Text("暂停或结束时自动隐藏，可在设置中关闭").font(.system(size: 12)).foregroundStyle(LeafTheme.muted)
            }
        }.padding(.horizontal, 24).padding(.vertical, 18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(LeafTheme.ink)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(LeafTheme.line.opacity(0.8)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.captionLines.last?.id)
            .preferredColorScheme(LeafTheme.scheme(store.database.preferences.appearance))
            .accessibilityElement(children: .combine).accessibilityLabel("会议悬浮字幕")
    }
}

struct MeetingCaptionSettings: View {
    @ObservedObject var model: MeetingModel
    var body: some View {
        Surface(title: "会议字幕") {
            Toggle("会议实时字幕", isOn: Binding(get: { model.live }, set: { model.live = $0; model.saveOptions() })).disabled(model.blocksDictation)
            Toggle("屏幕中央悬浮字幕", isOn: Binding(get: { model.floatingCaptions }, set: { model.floatingCaptions = $0; model.saveOptions() }))
            Text("默认开启。实时字幕开始后像悬浮歌词一样显示，不抢输入焦点、鼠标可穿透；暂停或结束后隐藏。关闭悬浮只隐藏浮层，不关闭会议内字幕，也不增加 API 调用。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }
    }
}
