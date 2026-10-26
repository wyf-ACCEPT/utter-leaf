import AppKit
import SwiftUI
import UtterLeafCore

@MainActor final class MeetingCaptionPanel {
    private(set) var panel: RecordingPanel?
    private var interaction: MeetingOverlayInteractionView?
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
        let interaction = MeetingOverlayInteractionView(frame: .zero)
        interaction.onPause = { [weak model] in model?.togglePause() }
        interaction.onCollapse = { [weak model] in model?.captionsCollapsed.toggle() }
        interaction.onHide = { [weak model] in model?.floatingCaptions = false; model?.saveOptions() }
        panel.contentView = MeetingCaptionContentView(rootView: MeetingCaptionView(model: model, store: store), interaction: interaction)
        self.interaction = interaction
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
        let transcript = model.live && !model.paused
        let preferredWidth = transcript ? 660.0 : 360.0
        let width = model.captionsCollapsed ? 260.0 : min(preferredWidth, max(300, (bounds?.width ?? 708) - 48))
        let height = model.captionsCollapsed ? 52.0 : (transcript ? Double(100 + 28 * MeetingCaptionPolicy.lineCount(model.captionLineCount)) : 136.0)
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
        interaction?.update(paused: model.paused, collapsed: model.captionsCollapsed, recording: model.recording)
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

// One native interaction surface covers the entire overlay; controls retain their own hit regions.
final class MeetingOverlayInteractionView: NSView {
    final class Control: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    let pauseButton = Control(), collapseButton = Control(), hideButton = Control()
    var onPause: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onHide: (() -> Void)?
    private var collapsed = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for button in [pauseButton, collapseButton, hideButton] {
            button.isBordered = false; button.imagePosition = .imageOnly
            button.refusesFirstResponder = true; button.focusRingType = .none
            button.contentTintColor = NSColor(LeafTheme.muted)
            button.target = self; addSubview(button)
        }
        pauseButton.action = #selector(togglePause)
        collapseButton.action = #selector(toggleCollapse)
        hideButton.action = #selector(hideOverlay)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        for button in [pauseButton, collapseButton, hideButton] { addCursorRect(button.frame, cursor: .pointingHand) }
    }
    func update(paused: Bool, collapsed: Bool, recording: Bool) {
        self.collapsed = collapsed
        configure(pauseButton, symbol: paused ? "play.fill" : "pause.fill", label: paused ? "继续录音" : "暂停录音", identifier: "meeting-overlay-pause")
        configure(collapseButton, symbol: collapsed ? "arrow.up.left.and.arrow.down.right" : "minus", label: collapsed ? "展开悬浮窗" : "收起悬浮窗", identifier: "meeting-overlay-collapse")
        configure(hideButton, symbol: "xmark", label: "隐藏悬浮窗", identifier: "meeting-overlay-hide")
        pauseButton.isEnabled = recording
        needsLayout = true
    }
    private func configure(_ button: NSButton, symbol: String, label: String, identifier: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.setAccessibilityLabel(label); button.setAccessibilityIdentifier(identifier); button.toolTip = label
    }
    override func layout() {
        super.layout()
        let inset: CGFloat = collapsed ? 16 : 24
        let top: CGFloat = collapsed ? 14 : 16
        for (index, button) in [pauseButton, collapseButton, hideButton].enumerated() {
            button.frame = NSRect(x: max(0, bounds.width - inset - 80) + CGFloat(index) * 28, y: bounds.height - top - 24, width: 24, height: 24)
        }
        window?.invalidateCursorRects(for: self)
    }
    @objc private func togglePause() { onPause?() }
    @objc private func toggleCollapse() { onCollapse?() }
    @objc private func hideOverlay() { onHide?() }
}
final class MeetingCaptionContentView<Content: View>: NSView {
    let interaction: MeetingOverlayInteractionView
    private let host: NSHostingView<Content>
    init(rootView: Content, interaction: MeetingOverlayInteractionView) {
        self.interaction = interaction; host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]; interaction.autoresizingMask = [.width, .height]
        addSubview(host); addSubview(interaction)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout(); host.frame = bounds; interaction.frame = bounds
    }
}

struct MeetingCaptionView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var store: LocalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var timer: String { MeetingCaptionPolicy.recordingTime(model.elapsed) }
    private var recordingStatus: String { model.paused ? "已暂停" : "正在录制" }
    private var previous: [MeetingCaptionLine] {
        Array(model.captionLines.dropLast().suffix(max(0, MeetingCaptionPolicy.lineCount(model.captionLineCount) - 2)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: model.live && !model.paused ? "captions.bubble" : (model.paused ? "pause.circle" : "record.circle"))
                    .foregroundStyle(model.paused ? LeafTheme.muted : LeafTheme.leaf)
                Text(model.captionsCollapsed ? timer + " " + (model.paused ? "已暂停" : "录制中") : (model.live && !model.paused ? model.captionStatus : recordingStatus))
                    .monospacedDigit().lineLimit(1)
                Spacer(minLength: 4)
                Color.clear.frame(width: 80, height: 24)
            }.font(.system(size: 12)).foregroundStyle(LeafTheme.muted).frame(height: 24)
            if !model.captionsCollapsed, !model.live || model.paused {
                Text(timer).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
                    .accessibilityLabel("会议录音时长").accessibilityValue(timer)
                Text(model.paused ? "录音已暂停，计时暂停" : "仅录音 · 结束后自动转录")
                    .font(.system(size: 12)).foregroundStyle(LeafTheme.muted)
            } else if !model.captionsCollapsed {
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
                    Text("拖动窗口移动 · 收起或隐藏不影响录音").font(.system(size: 12)).foregroundStyle(LeafTheme.muted)
                }
            }
        }.padding(.horizontal, model.captionsCollapsed ? 16 : 24).padding(.vertical, model.captionsCollapsed ? 14 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(LeafTheme.ink)
            .background { RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).opacity(MeetingCaptionPolicy.opacity(model.captionOpacity)) }
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(LeafTheme.line.opacity(0.6)).allowsHitTesting(false))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.captionLines.last?.id)
            .preferredColorScheme(LeafTheme.scheme(store.database.preferences.appearance))
            .accessibilityElement(children: .contain).accessibilityLabel("会议录制悬浮窗")
    }
}

struct MeetingCaptionSettings: View {
    @ObservedObject var model: MeetingModel
    var body: some View {
        Surface(title: "会议字幕与录制状态") {
            Toggle("会议实时字幕", isOn: Binding(get: { model.live }, set: { model.live = $0; model.saveOptions() })).disabled(model.blocksDictation)
            Toggle("会议悬浮窗", isOn: Binding(get: { model.floatingCaptions }, set: { model.floatingCaptions = $0; model.saveOptions() }))
            LeafSegments(title: "字幕行数", selection: Binding(get: { model.captionLineCount }, set: { model.captionLineCount = $0; model.saveOptions() }), items: MeetingCaptionPolicy.lineOptions.map { LeafSegment($0, "\($0) 行") })
            HStack {
                Text("背景透明度")
                Slider(value: Binding(get: { 1 - model.captionOpacity }, set: { model.captionOpacity = 1 - $0 }), in: 0...0.65, onEditingChanged: { editing in if !editing { model.saveOptions() } })
                    .accessibilityLabel("字幕背景透明度")
                Text("\(Int(((1 - model.captionOpacity) * 100).rounded()))%").monospacedDigit().frame(width: 46, alignment: .trailing)
            }
            Text("默认半透明，文字保持清晰。拖动文字或空白处移动；按钮可暂停、继续，收起后可展开，隐藏后可从会议页重新显示。关闭实时字幕时显示录音状态和计时；暂停时显示已暂停，结束后隐藏。浮层不增加 API 调用。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }
    }
}
