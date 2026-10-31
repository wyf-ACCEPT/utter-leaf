import SwiftUI

/// Presentation tasks never delay recording, cleanup or insertion work.
@MainActor final class PillPresentation: ObservableObject {
    enum Stage: Equatable {
        case preparing, recording, processing, recovery, inserted, pasteRequested, retained, cancelled, failed
        var width: CGFloat {
            switch self { case .preparing, .processing: return 290; case .recording: return 350; case .recovery: return 380; default: return 230 }
        }
        var title: String {
            switch self {
            case .preparing: return "准备录音"; case .recording: return "正在听你说"; case .processing: return "处理中"
            case .inserted: return "已输入"; case .pasteRequested: return "已请求粘贴"; case .retained, .recovery: return "文字已保留"
            case .cancelled: return "已取消"; case .failed: return "需要处理"
            }
        }
        var icon: String {
            switch self { case .inserted: return "checkmark"; case .pasteRequested: return "arrow.up.doc"; case .retained, .recovery: return "doc.text"; case .cancelled: return "xmark"; case .failed: return "exclamationmark"; default: return "leaf" }
        }
        var isTerminal: Bool { ![.preparing, .recording, .processing].contains(self) }
    }
    @Published private(set) var revealed = false
    @Published private(set) var stage: Stage = .preparing
    @Published private(set) var detail = ""
    private(set) var onScreen = false
    var orderFront: (() -> Void)?
    var orderOut: (() -> Void)?
    private var revision = 0
    private var task: Task<Void, Never>?
    private let dwell: Duration
    private let exitWait: Duration
    init(dwell: Duration = .milliseconds(320), exitWait: Duration = .milliseconds(240)) {
        self.dwell = dwell; self.exitWait = exitWait
    }
    func show(_ stage: Stage, detail: String, reduceMotion: Bool) {
        task?.cancel(); revision += 1
        let token = revision
        if !onScreen { onScreen = true; revealed = false; orderFront?() }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88)) {
            self.stage = stage; self.detail = detail
        }
        guard !revealed else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled, revision == token else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.38, dampingFraction: 0.84)) { self.revealed = true }
        }
    }
    func finish(_ stage: Stage, reduceMotion: Bool) {
        if stage == .recovery { show(stage, detail: "文字已保留", reduceMotion: reduceMotion); return }
        guard onScreen else { return }
        task?.cancel(); revision += 1
        let token = revision
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)) {
            self.stage = stage; detail = ""; revealed = true
        }
        task = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: stage == .cancelled ? .milliseconds(120) : dwell) } catch { return }
            guard !Task.isCancelled, revision == token else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.1 : 0.2)) { self.revealed = false }
            do { try await Task.sleep(for: reduceMotion ? .milliseconds(120) : exitWait) } catch { return }
            guard !Task.isCancelled, revision == token else { return }
            onScreen = false; orderOut?()
        }
    }
    func closeImmediately() {
        task?.cancel(); task = nil; revision += 1
        revealed = false; onScreen = false; orderOut?()
    }
}
