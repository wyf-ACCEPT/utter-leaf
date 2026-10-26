import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var timer: Timer?
    private var resolverTrace: [String: Any] = [:]
    override func viewDidLoad() {
        super.viewDidLoad()
        hasDictationKey = true
        // Create the optional client before the input destination becomes active.
        KBHostArbiterHook.activeArbiterCheck()
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
        KBHostArbiterHook.activeArbiterCheck()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.refresh() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); timer?.invalidate(); timer = nil
        KBHostArbiterHook.invalidateCache(); model.host = nil
    }
    fileprivate func prepare() async -> URL? {
        guard hasFullAccess, !model.launching else { return nil }
        model.launching = true
        defer { model.launching = false }
        let originalDocument = textDocumentProxy.documentIdentifier
        let record: [String: Any] = ["requestID": model.nextID, "document": textDocumentProxy.documentIdentifier.uuidString,
            "before": String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(80)),
            "after": String((textDocumentProxy.documentContextAfterInput ?? "").prefix(80)), "created": Date().timeIntervalSince1970]
        // Target context is local to this extension and never sent to an API or the main app.
        UserDefaults.standard.set(record, forKey: "pendingTarget")
        model.host = await resolveHostForCurrentTap()
        guard viewIfLoaded?.window != nil, textDocumentProxy.documentIdentifier == originalDocument else { return nil }
        var ticket: [String: Any] = ["requestID": model.nextID, "created": Date().timeIntervalSince1970]
        if let host = model.host { ticket["host"] = host }
        do { try DictationExchange.write(ticket, to: "handoff") }
        catch { model.status = "无法共享录音请求，请重新允许完全访问。"; return nil }
        var trace = resolverTrace
        trace["hostResolved"] = model.host != nil
        trace["hostKind"] = model.host == "com.tencent.xin" ? "wechat" : model.host == nil ? "missing" : "other"
        trace["os"] = UIDevice.current.systemVersion; trace["updated"] = Date().timeIntervalSince1970
        try? DictationExchange.write(trace, to: "keyboard-navigation")
        var parts = URLComponents(); parts.scheme = "utterleaf"; parts.host = "dictate"
        parts.queryItems = [URLQueryItem(name: "request", value: model.nextID)]
        return parts.url
    }
    fileprivate func command(_ action: String) {
        let state = DictationExchange.read("state")
        try? DictationExchange.write(["id": UUID().uuidString, "requestID": state["requestID"] ?? "", "action": action], to: "command")
    }
    fileprivate func insert(manual: Bool) {
        let state = DictationExchange.read("state")
        guard state["phase"] as? String == "ready", let id = state["requestID"] as? String,
              let text = state["text"] as? String, !text.isEmpty,
              let updated = state["updated"] as? Double,
              KeyboardDelivery.hasFreshResult(request: id, consumed: UserDefaults.standard.string(forKey: "consumedRequest"), text: text, updated: updated, now: Date().timeIntervalSince1970) else { return }
        if !manual {
            guard let target = UserDefaults.standard.dictionary(forKey: "pendingTarget"),
                  KeyboardDelivery.matchesTarget(request: id, expectedRequest: target["requestID"] as? String,
                    document: textDocumentProxy.documentIdentifier.uuidString, expectedDocument: target["document"] as? String,
                    before: String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(80)), expectedBefore: target["before"] as? String,
                    after: String((textDocumentProxy.documentContextAfterInput ?? "").prefix(80)), expectedAfter: target["after"] as? String) else { return }
        }
        // Claim before insertion so a recreated extension cannot paste the same result twice.
        UserDefaults.standard.set(id, forKey: "consumedRequest")
        textDocumentProxy.insertText(text)
        model.status = "已放入输入框"; model.phase = "inserted"; model.nextID = UUID().uuidString
    }
    private func refresh() {
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
        case "ready": model.status = "文字已就绪，点按插入"; insert(manual: false)
        case "error": model.status = state["error"] as? String ?? "请返回言叶重试"
        default: model.status = "让想法，自然落成文字。"
        }
    }
    private func freshHost() -> String? {
        // Optional selectors disappear on some iOS versions. Never reuse a cached source app.
        for object: NSObject in [self, parent, extensionContext].compactMap({ $0 }) {
            for name in ["_hostApplicationBundleIdentifier", "_hostBundleID"] {
                let selector = NSSelectorFromString(name)
                if object.responds(to: selector), let id = object.perform(selector)?.takeUnretainedValue() as? String,
                   id != "network.utterleaf.personal.mobile", id.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil { return id }
            }
        }
        return nil
    }
    private func resolveHostForCurrentTap() async -> String? {
        guard viewIfLoaded?.window != nil else { return nil }
        if #available(iOS 26.4, *) {
            let generation = KBHostArbiterHook.captureGeneration()
            resolverTrace = ["before": generation, "arbiter": NSClassFromString("_UIKeyboardArbiterClient") != nil,
                "destination": NSClassFromString("_UIKeyboardArbiterClientInputDestination") != nil]
            resolverTrace["hook"] = KBHostArbiterHook.diagnostics()
            KBHostArbiterHook.activeArbiterCheck()
            for _ in 0..<20 {
                guard viewIfLoaded?.window != nil, !Task.isCancelled else { return nil }
                if let host = KBHostArbiterHook.hostBundleId(capturedAfter: generation) { resolverTrace["after"] = KBHostArbiterHook.captureGeneration(); return host }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            resolverTrace["after"] = KBHostArbiterHook.captureGeneration(); return nil
        }
        return freshHost()
    }
}

private final class KeyboardModel: ObservableObject {
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
    var body: some View {
        VStack(spacing: 18) {
            HStack { Label("言叶", systemImage: "leaf").font(.headline); Spacer(); if ["starting", "recording", "processing"].contains(model.phase) { Button("取消") { controller.command("cancel") }.font(.caption) } else { Text("个人语音输入").font(.caption).opacity(0.65) } }
            Text(model.status).font(.subheadline).multilineTextAlignment(.center).lineLimit(2).frame(minHeight: 36).accessibilityAddTraits(.updatesFrequently)
            Group {
                if model.phase == "recording" {
                    Button { controller.command("stop") } label: { Label("结束并整理", systemImage: "stop.fill") }
                } else if model.phase == "ready" {
                    Button { controller.insert(manual: true) } label: { Label("插入文字", systemImage: "text.badge.plus") }
                } else if ["starting", "processing"].contains(model.phase) {
                    ProgressView().tint(leaf).frame(height: 48)
                } else {
                    Button {
                        Task { if let url = await controller.prepare() { openURL(url) } }
                    } label: {
                        Label("开始说话", systemImage: "mic.fill")
                    }.disabled(!model.fullAccess || model.launching)
                }
            }.font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                .background(leaf.opacity(0.16), in: Capsule()).foregroundStyle(leaf)
            HStack(spacing: 28) {
                if model.showSwitcher {
                    Button { controller.advanceToNextInputMode() } label: { Image(systemName: "globe") }.accessibilityLabel("切换输入法")
                }
                Button("空格") { controller.textDocumentProxy.insertText(" ") }.frame(maxWidth: .infinity)
                Button { controller.textDocumentProxy.deleteBackward() } label: { Image(systemName: "delete.left") }.accessibilityLabel("删除")
            }.font(.title3).frame(height: 40)
        }.padding(18).foregroundStyle(.primary)
    }
}
