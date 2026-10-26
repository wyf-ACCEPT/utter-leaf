import AppKit
import SwiftUI
import UtterLeafCore

@MainActor final class MeetingCaptionPanel {
    private(set) var panel: RecordingPanel?
    private weak var model: MeetingModel?
    private var revision = 0
    private var desiredVisible = false
    private var positioned = false
    private var dismissal: Task<Void, Never>?
    func attach(model: MeetingModel, store: LocalStore) {
        self.model = model
        let panel = RecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 184), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.level = .floating; panel.isFloatingPanel = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = false; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = CaptionHostingView(rootView: MeetingCaptionView(model: model, store: store))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        model.onCaptionUpdate = { [weak self] in self?.refresh() }
        refresh()
    }
    private func updateFrame() {
        guard let model, let panel else { return }
        let screen = !positioned ? NSScreen.main : (NSScreen.screens.max { lhs, rhs in
            let a = lhs.visibleFrame.intersection(panel.frame), b = rhs.visibleFrame.intersection(panel.frame)
            return a.width * a.height < b.width * b.height
        } ?? NSScreen.main)
        let bounds = screen?.visibleFrame
        let width = model.captionsCollapsed ? 260.0 : min(660, max(300, (bounds?.width ?? 708) - 48))
        let height = model.captionsCollapsed ? 52.0 : Double(100 + 28 * MeetingCaptionPolicy.lineCount(model.captionLineCount))
        var frame = NSRect(x: positioned ? panel.frame.minX : (bounds ?? panel.frame).midX - width / 2,
                           y: positioned ? panel.frame.maxY - height : (bounds ?? panel.frame).midY - height / 2,
                           width: width, height: height)
        if let bounds {
            frame.origin.x = max(bounds.minX, min(frame.minX, bounds.maxX - width))
            frame.origin.y = max(bounds.minY, min(frame.minY, bounds.maxY - height))
        }
        positioned = true
        guard frame != panel.frame else { return }
        let duration = panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.18 : 0
        panel.setFrame(frame, display: true, animate: duration > 0)
    }
    private func refresh() {
        guard let model, let panel else { return }
        let visible = MeetingCaptionPolicy.shouldShow(recording: model.recording, paused: model.paused, live: model.live, enabled: model.floatingCaptions)
        if visible { updateFrame() }
        guard desiredVisible != visible else { return }
        dismissal?.cancel()
        desiredVisible = visible; revision += 1; let token = revision
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
        if visible {
            if !panel.isVisible { panel.alphaValue = 0; panel.orderFrontRegardless() }
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

// Native dragging preserves the destination application's keyboard focus.
private struct CaptionDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Handle() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class Handle: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
private final class CaptionHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct MeetingCaptionView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var store: LocalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var previous: [MeetingCaptionLine] {
        Array(model.captionLines.dropLast().suffix(max(0, MeetingCaptionPolicy.lineCount(model.captionLineCount) - 2)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                CaptionDragHandle().accessibilityLabel("拖动悬浮字幕")
                HStack(spacing: 7) {
                    Image(systemName: "captions.bubble").allowsHitTesting(false)
                    Text(model.captionsCollapsed ? "会议字幕" : model.captionStatus).lineLimit(1).allowsHitTesting(false)
                    Spacer(minLength: 4)
                    Button {
                        model.captionsCollapsed.toggle()
                    } label: { Image(systemName: model.captionsCollapsed ? "arrow.up.left.and.arrow.down.right" : "minus") }
                        .handCursor().accessibilityLabel(model.captionsCollapsed ? "展开字幕" : "收起字幕").help(model.captionsCollapsed ? "展开字幕" : "收起字幕")
                    Button {
                        model.floatingCaptions = false; model.saveOptions()
                    } label: { Image(systemName: "xmark") }
                        .handCursor().accessibilityLabel("隐藏字幕").help("隐藏字幕，可从会议页重新显示")
                }.buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(LeafTheme.muted)
            }.frame(height: 24)
            if !model.captionsCollapsed {
                ForEach(previous) { line in
                    Text(line.text).font(.system(size: 15)).foregroundStyle(LeafTheme.muted).lineLimit(1).truncationMode(.head)
                }
                if let latest = model.captionLines.last {
                    Text(latest.text).font(.system(size: LeafType.scaled(21), weight: .medium, design: .rounded))
                        .lineLimit(2).truncationMode(.head).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                        .id(latest.id).transition(.opacity)
                    Text((latest.source == "system" ? "系统声音" : "麦克风") + (latest.speaker == "unknown" ? " · 说话人待确认" : " · 说话人 " + latest.speaker + "（暂定）"))
                        .font(.system(size: 12)).foregroundStyle(LeafTheme.muted)
                } else {
                    Text("等待发言…").font(.system(size: LeafType.scaled(21), weight: .medium, design: .rounded)).foregroundStyle(LeafTheme.muted)
                    Text("拖动顶部移动 · 收起或隐藏不影响录音").font(.system(size: 12)).foregroundStyle(LeafTheme.muted)
                }
            }
        }.padding(.horizontal, model.captionsCollapsed ? 16 : 24).padding(.vertical, model.captionsCollapsed ? 14 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(LeafTheme.ink)
            .background { RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).opacity(MeetingCaptionPolicy.opacity(model.captionOpacity)) }
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(LeafTheme.line.opacity(0.6)).allowsHitTesting(false))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.captionLines.last?.id)
            .preferredColorScheme(LeafTheme.scheme(store.database.preferences.appearance))
            .accessibilityElement(children: .contain).accessibilityLabel("会议悬浮字幕")
    }
}

struct MeetingCaptionSettings: View {
    @ObservedObject var model: MeetingModel
    var body: some View {
        Surface(title: "会议字幕") {
            Toggle("会议实时字幕", isOn: Binding(get: { model.live }, set: { model.live = $0; model.saveOptions() })).disabled(model.blocksDictation)
            Toggle("悬浮字幕", isOn: Binding(get: { model.floatingCaptions }, set: { model.floatingCaptions = $0; model.saveOptions() }))
            LeafSegments(title: "字幕行数", selection: Binding(get: { model.captionLineCount }, set: { model.captionLineCount = $0; model.saveOptions() }), items: MeetingCaptionPolicy.lineOptions.map { LeafSegment($0, "\($0) 行") })
            HStack {
                Text("背景透明度")
                Slider(value: Binding(get: { 1 - model.captionOpacity }, set: { model.captionOpacity = 1 - $0 }), in: 0...0.65, onEditingChanged: { editing in if !editing { model.saveOptions() } })
                    .accessibilityLabel("字幕背景透明度")
                Text("\(Int(((1 - model.captionOpacity) * 100).rounded()))%").monospacedDigit().frame(width: 46, alignment: .trailing)
            }
            Text("默认半透明，文字保持清晰。拖动顶部移动；收起后可展开，隐藏后可从会议页重新显示。暂停或结束后自动隐藏。浮层使用现有实时字幕，不增加 API 调用。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }
    }
}
