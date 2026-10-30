import SwiftUI
import UIKit
import KeyboardKitHostPlugin

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var timer: Timer?
    private var resolverFailure: [String: Any] = [:]
    override func viewDidLoad() {
        super.viewDidLoad()
        hasDictationKey = true
        // The keyboard-style UIInputView paints the same system background as the bottom dock.
        // Do not cover it with the main app's botanical surface.
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: KeyboardSurface(model: model, controller: self))
        addChild(host); host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(host.view)
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), view.heightAnchor.constraint(equalToConstant: 260)])
        host.didMove(toParent: self)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.refresh() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); timer?.invalidate(); timer = nil
        model.host = nil
    }
    override func textDidChange(_ textInput: UITextInput?) { super.textDidChange(textInput); refresh() }
    override func selectionDidChange(_ textInput: UITextInput?) { super.selectionDidChange(textInput); refresh() }
    fileprivate func performReturn() {
        guard model.canReturn else { return }
        // Recheck shared state so a tap cannot race the keyboard's polling interval.
        let phase = DictationExchange.read("state")["phase"] as? String ?? "idle"
        guard !["starting", "recording", "processing"].contains(phase) else { refresh(); return }
        textDocumentProxy.insertText("\n")
    }
    private var returnTitle: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .search, .google, .yahoo: return "搜索"
        case .send: return "发送"
        case .go: return "前往"
        case .next: return "下一项"
        case .done: return "完成"
        case .join: return "加入"
        case .route: return "路线"
        case .emergencyCall: return "呼叫"
        case .continue: return "继续"
        default: return "换行"
        }
    }
    fileprivate func prepare() async -> URL? {
        guard hasFullAccess, !model.launching else { return nil }
        model.launching = true
        defer { model.launching = false }
        model.nextID = UUID().uuidString
        let originalDocument = textDocumentProxy.documentIdentifier
        captureTarget(requestID: model.nextID)
        model.host = await resolveHostForCurrentTap()
        guard viewIfLoaded?.window != nil, textDocumentProxy.documentIdentifier == originalDocument else { return nil }
        var ticket: [String: Any] = ["requestID": model.nextID, "created": Date().timeIntervalSince1970]
        if let host = model.host { ticket["host"] = host }
        do { try DictationExchange.write(ticket, to: "handoff") }
        catch { model.status = "无法共享录音请求，请重新允许完全访问。"; return nil }
        var trace: [String: Any] = ["resolver": "KeyboardKitHostPlugin-11.0.0"]
        trace.merge(resolverFailure) { _, new in new }
        trace["hostResolved"] = model.host != nil
        trace["hostKind"] = model.host == "com.tencent.xin" ? "wechat" : model.host == nil ? "missing" : "other"
        #if targetEnvironment(simulator)
        trace["fixtureMatched"] = model.host == "network.utterleaf.navigation.fixture"
        #endif
        trace["os"] = UIDevice.current.systemVersion; trace["updated"] = Date().timeIntervalSince1970
        try? DictationExchange.write(trace, to: "keyboard-navigation")
        var parts = URLComponents(); parts.scheme = DictationExchange.urlScheme; parts.host = "dictate"
        parts.queryItems = [URLQueryItem(name: "request", value: model.nextID)]
        return parts.url
    }
    fileprivate func command(_ action: String) {
        let state = DictationExchange.read("state")
        if action == "stop", state["phase"] as? String == "recording", let id = state["requestID"] as? String {
            // Returning from the containing app can recreate the document proxy. The user's Stop
            // gesture selects this current input field as the delivery destination for this request.
            captureTarget(requestID: id)
        }
        try? DictationExchange.write(["id": UUID().uuidString, "requestID": state["requestID"] ?? "", "action": action], to: "command")
    }
    private func captureTarget(requestID: String, proxy supplied: UITextDocumentProxy? = nil) {
        // Context stays in extension-local preferences, never in the App Group or provider requests.
        let proxy = supplied ?? textDocumentProxy
        UserDefaults.standard.set(["requestID": requestID, "document": proxy.documentIdentifier.uuidString,
            "before": String((proxy.documentContextBeforeInput ?? "").suffix(80)),
            "after": String((proxy.documentContextAfterInput ?? "").prefix(80)),
            "created": Date().timeIntervalSince1970], forKey: "pendingTarget")
    }
    fileprivate func insertIntoCurrentField() { insert(explicit: true) }
    private func insert(explicit: Bool = false) {
        guard hasFullAccess, viewIfLoaded?.window != nil else { return }
        let state = DictationExchange.read("state")
        guard state["phase"] as? String == "ready", let id = state["requestID"] as? String,
              let text = state["text"] as? String, !text.isEmpty,
              let updated = state["updated"] as? Double,
              KeyboardDelivery.hasFreshResult(request: id, consumed: UserDefaults.standard.string(forKey: "consumedRequest"), text: text, updated: updated, now: Date().timeIntervalSince1970) else { return }
        // A deliberate tap chooses the currently focused field. Automatic delivery never rebinds.
        let proxy = textDocumentProxy
        if explicit { captureTarget(requestID: id, proxy: proxy) }
        let target = UserDefaults.standard.dictionary(forKey: "pendingTarget") ?? [:]
        if let reason = KeyboardDelivery.mismatch(request: id, expectedRequest: target["requestID"] as? String,
                    document: proxy.documentIdentifier.uuidString, expectedDocument: target["document"] as? String,
                    before: String((proxy.documentContextBeforeInput ?? "").suffix(80)), expectedBefore: target["before"] as? String,
                    after: String((proxy.documentContextAfterInput ?? "").prefix(80)), expectedAfter: target["after"] as? String) {
            model.status = "输入位置有变化，点按放入当前输入框"
            traceDelivery(reason: reason, explicit: explicit)
            return
        }
        // Claim before insertion so a recreated extension cannot paste the same result twice.
        UserDefaults.standard.set(id, forKey: "consumedRequest")
        proxy.insertText(text)
        traceDelivery(reason: "insert_requested", explicit: explicit)
        model.status = "已放入输入框"; model.phase = "inserted"; model.nextID = UUID().uuidString
    }
    private var lastDeliveryTrace = ""
    private func traceDelivery(reason: String, explicit: Bool) {
        let key = reason + (explicit ? ".explicit" : ".automatic")
        guard key != lastDeliveryTrace else { return }; lastDeliveryTrace = key
        try? DictationExchange.write(["reason": reason, "explicit": explicit, "updated": Date().timeIntervalSince1970], to: "keyboard-delivery")
    }
    private func refresh() {
        model.returnTitle = returnTitle
        model.fullAccess = hasFullAccess
        switch textDocumentProxy.keyboardAppearance {
        case .dark: overrideUserInterfaceStyle = .dark
        case .light: overrideUserInterfaceStyle = .light
        default: overrideUserInterfaceStyle = .unspecified
        }
        model.showSwitcher = needsInputModeSwitchKey
        guard hasFullAccess else { model.status = "请为言叶键盘允许完全访问"; return }
        let state = DictationExchange.read("state"), phase = state["phase"] as? String ?? "idle"
        if let updated = state["updated"] as? Double, Date().timeIntervalSince1970 - updated >= 900 {
            model.phase = "idle"; model.status = "上次结果已过期，请重新录音。"; return
        }
        if let id = state["requestID"] as? String, UserDefaults.standard.string(forKey: "consumedRequest") == id {
            model.phase = "inserted"; model.status = "已放入输入框"; return
        }
        model.phase = phase
        model.level = min(1, max(0, state["level"] as? Double ?? 0))
        let seconds = state["seconds"] as? Int ?? 0
        switch phase {
        case "recording": model.status = String(format: "正在录音 · %02d:%02d", seconds / 60, seconds % 60)
        case "starting": model.status = "正在准备麦克风…"
        case "processing": model.status = "正在处理文字…"
        case "ready": model.status = "文字已保留，点按可放入当前输入框"; insert()
        case "error": model.status = state["error"] as? String ?? "请返回言叶重试"
        default: model.status = "让想法，自然落成文字。"
        }
    }
    private func resolveHostForCurrentTap() async -> String? {
        resolverFailure = [:]
        guard viewIfLoaded?.window != nil else { return nil }
        do {
            let result = try await pluginHostApplicationResolver(controller: self, pollingInterval: 0.05, timeout: 1.0)
            guard viewIfLoaded?.window != nil, !Task.isCancelled, let result,
                  !result.hasPrefix("network.utterleaf.personal.mobile"), !result.hasPrefix("network.utterleaf.mobile"),
                  result.range(of: "^[A-Za-z0-9]+[A-Za-z0-9.-]+$", options: .regularExpression) != nil else { return nil }
            return result
        } catch {
            let failure = error as NSError
            resolverFailure = ["errorDomain": failure.domain, "errorCode": failure.code]
            return nil
        }
    }
}

private final class KeyboardModel: ObservableObject {
    @Published var level = 0.0
    @Published var returnTitle = "换行"
    @Published var phase = "idle"
    @Published var status = "让想法，自然落成文字。"
    @Published var nextID = UUID().uuidString
    @Published var fullAccess = false
    @Published var showSwitcher = true
    @Published var host: String?
    @Published var launching = false
    var canReturn: Bool { KeyboardDelivery.canPerformReturn(phase: phase, launching: launching, fullAccess: fullAccess) }
}

private struct KeyboardSurface: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: KeyboardModel
    unowned var controller: KeyboardViewController
    private let leaf = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 159/255, green: 214/255, blue: 181/255, alpha: 1)
        : UIColor(red: 45/255, green: 94/255, blue: 70/255, alpha: 1) })
    private var showsStatus: Bool {
        !model.fullAccess || ["starting", "recording", "processing", "ready", "error"].contains(model.phase)
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("言叶", systemImage: "leaf").font(.headline); Spacer()
                if ["starting", "recording", "processing"].contains(model.phase) { Button("取消") { controller.command("cancel") }.font(.caption) }
                else if model.phase == "ready" { Button("重新录音") { Task { if let url = await controller.prepare() { openURL(url) } } }.font(.caption).disabled(!model.fullAccess || model.launching) }
                else { Text("个人语音输入").font(.caption).opacity(0.65) }
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(2).frame(height: 36)
                .opacity(showsStatus ? 1 : 0).accessibilityHidden(!showsStatus)
                .accessibilityAddTraits(.updatesFrequently)
            Group {
                if model.phase == "recording" {
                    Button { controller.command("stop") } label: {
                        VStack(spacing: 5) {
                            KeyboardWave(level: model.level).frame(width: 150, height: 34)
                            Text("结束录音").font(.caption.weight(.semibold))
                        }
                    }.accessibilityLabel("结束录音")
                } else if model.phase == "ready" {
                    Button { controller.insertIntoCurrentField() } label: { Label("放入当前输入框", systemImage: "text.badge.plus") }
                        .disabled(!model.fullAccess || model.launching)
                } else if ["starting", "processing"].contains(model.phase) {
                    ProgressView().tint(leaf).frame(height: 48)
                } else {
                    Button {
                        Task { if let url = await controller.prepare() { openURL(url) } }
                    } label: {
                        Label("开始说话", systemImage: "mic.fill")
                    }.disabled(!model.fullAccess || model.launching)
                }
            }.font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75).frame(width: 200, height: 80)
                .background(leaf.opacity(0.16), in: Capsule()).foregroundStyle(leaf)
            ZStack {
                Button { controller.performReturn() } label: {
                    Text(model.returnTitle).font(.system(size: 18, weight: .medium))
                        .frame(width: 112, height: 52)
                        .background(leaf.opacity(0.16), in: Capsule()).contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityLabel(model.returnTitle).disabled(!model.canReturn)
                    .opacity(model.canReturn ? 1 : 0.35)
                    .accessibilityHint(model.canReturn ? "" : model.phase == "ready" ? "先放入文字后再执行此操作" : "录音和文字处理完成后可用")
                HStack {
                    if model.showSwitcher {
                        Button { controller.advanceToNextInputMode() } label: { Image(systemName: "globe").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("切换输入法")
                    }
                    Spacer(minLength: 0)
                    Button { controller.textDocumentProxy.deleteBackward() } label: {
                        Image(systemName: "delete.left").font(.system(size: 28, weight: .medium))
                            .frame(width: 64, height: 52)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("删除")
                }
            }.font(.title3).frame(height: 52)

        }.padding(18).foregroundStyle(.primary)
    }
}

private struct KeyboardWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var level: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            WaveTrace(level: level, phase: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 2)
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .animation(.easeOut(duration: 0.22), value: level)
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
private struct WaveTrace: Shape {
    var level: Double
    var phase: Double
    var animatableData: Double { get { level } set { level = newValue } }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let amplitude = 0.5 + min(1, max(0, level) * 1.5) * rect.height * 0.46
        for x in stride(from: 0.0, through: rect.width, by: 1) {
            let unit = x / max(1, rect.width)
            let y = rect.midY + sin(unit * .pi * 6 + phase) * pow(sin(unit * .pi), 2) * amplitude
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
