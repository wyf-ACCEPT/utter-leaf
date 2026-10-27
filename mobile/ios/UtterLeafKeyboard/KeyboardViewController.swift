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
    fileprivate func performReturn() { textDocumentProxy.insertText("\n") }
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
        var parts = URLComponents(); parts.scheme = "utterleaf"; parts.host = "dictate"
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
    private func captureTarget(requestID: String) {
        // Context stays in extension-local preferences, never in the App Group or provider requests.
        UserDefaults.standard.set(["requestID": requestID, "document": textDocumentProxy.documentIdentifier.uuidString,
            "before": String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(80)),
            "after": String((textDocumentProxy.documentContextAfterInput ?? "").prefix(80)),
            "created": Date().timeIntervalSince1970], forKey: "pendingTarget")
    }
    private func insert() {
        let state = DictationExchange.read("state")
        guard state["phase"] as? String == "ready", let id = state["requestID"] as? String,
              let text = state["text"] as? String, !text.isEmpty,
              let updated = state["updated"] as? Double,
              KeyboardDelivery.hasFreshResult(request: id, consumed: UserDefaults.standard.string(forKey: "consumedRequest"), text: text, updated: updated, now: Date().timeIntervalSince1970) else { return }
        guard let target = UserDefaults.standard.dictionary(forKey: "pendingTarget"),
                  KeyboardDelivery.matchesTarget(request: id, expectedRequest: target["requestID"] as? String,
                    document: textDocumentProxy.documentIdentifier.uuidString, expectedDocument: target["document"] as? String,
                    before: String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(80)), expectedBefore: target["before"] as? String,
                    after: String((textDocumentProxy.documentContextAfterInput ?? "").prefix(80)), expectedAfter: target["after"] as? String) else { return }
        // Claim before insertion so a recreated extension cannot paste the same result twice.
        UserDefaults.standard.set(id, forKey: "consumedRequest")
        textDocumentProxy.insertText(text)
        model.status = "已放入输入框"; model.phase = "inserted"; model.nextID = UUID().uuidString
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
        let seconds = state["seconds"] as? Int ?? 0
        switch phase {
        case "recording": model.status = String(format: "正在录音 · %02d:%02d", seconds / 60, seconds % 60)
        case "starting": model.status = "正在准备麦克风…"
        case "processing": model.status = "正在转写与整理…"
        case "ready": model.status = "文字已保留，回到原输入框后自动放入"; insert()
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
                  !result.hasPrefix("network.utterleaf.personal.mobile"),
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
    @Published var returnTitle = "换行"
    @Published var phase = "idle"
    @Published var status = "让想法，自然落成文字。"
    @Published var nextID = UUID().uuidString
    @Published var fullAccess = false
    @Published var showSwitcher = true
    @Published var host: String?
    @Published var launching = false
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
            HStack { Label("言叶", systemImage: "leaf").font(.headline); Spacer(); if ["starting", "recording", "processing"].contains(model.phase) { Button("取消") { controller.command("cancel") }.font(.caption) } else { Text("个人语音输入").font(.caption).opacity(0.65) } }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(2).frame(height: 36)
                .opacity(showsStatus ? 1 : 0).accessibilityHidden(!showsStatus)
                .accessibilityAddTraits(.updatesFrequently)
            Group {
                if model.phase == "recording" {
                    Button { controller.command("stop") } label: { Label("结束并整理", systemImage: "stop.fill") }
                } else if model.phase == "ready" {
                    Label("等待原输入框", systemImage: "text.badge.checkmark")
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
            HStack(spacing: 28) {
                if model.showSwitcher {
                    Button { controller.advanceToNextInputMode() } label: { Image(systemName: "globe").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("切换输入法")
                }
                Spacer(minLength: 0)
                Button { controller.performReturn() } label: {
                    Text(model.returnTitle).font(.system(size: 18, weight: .medium))
                        .frame(width: 112, height: 52)
                        .background(leaf.opacity(0.16), in: Capsule()).contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityLabel(model.returnTitle)
                Spacer(minLength: 0)
                Button { controller.textDocumentProxy.deleteBackward() } label: {
                    Image(systemName: "delete.left").font(.system(size: 28, weight: .medium))
                        .frame(width: 64, height: 52)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("删除")
            }.font(.title3).frame(height: 52)
        }.padding(18).foregroundStyle(.primary)
    }
}
