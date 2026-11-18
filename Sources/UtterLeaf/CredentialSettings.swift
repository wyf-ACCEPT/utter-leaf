import SwiftUI

/// One API key: shows where the app currently reads it from, and lets the person paste a new value
/// into the Keychain. The saved value is never read back into the UI.
struct CredentialField: View {
    let name: String
    let title: String
    var placeholder = "粘贴新的 Key"
    var onChange: () -> Void = {}
    @State private var draft = ""
    @State private var status: Credentials.Status = .missing
    @State private var message = ""
    @State private var failed = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: LeafType.scaled(13), weight: .medium))
                Spacer()
                Label(statusText, systemImage: statusIcon)
                    .font(LeafType.caption)
                    .foregroundStyle(status == .missing || status == .locked ? Color.orange : LeafTheme.leaf)
            }
            HStack(spacing: 8) {
                SecureField(placeholder, text: $draft)
                    .leafInput()
                    .onSubmit(save)
                    .accessibilityLabel("\(title) 新值")
                Button("保存", action: save)
                    .buttonStyle(.bordered).handCursor()
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if status == .locked {
                    Button("授权读取") {
                        if Credentials.unlock(name) { show("已授权，本机版本可读取 Keychain 中的 Key。") } else { show("未能读取，可直接粘贴新值覆盖。", failed: true) }
                        refresh()
                    }.buttonStyle(.bordered).handCursor()
                }
                if status == .keychain || status == .locked {
                    Button("移除…") { confirmRemove = true }.buttonStyle(.bordered).handCursor()
                }
            }
            if !message.isEmpty {
                Text(message).font(LeafType.caption).foregroundStyle(failed ? Color.orange : LeafTheme.leaf)
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog("从 Keychain 移除\(title)？如果 ~/.llm.env 里有同名变量，之后会改用它。", isPresented: $confirmRemove) {
            Button("移除", role: .destructive) {
                do { try Credentials.remove(name); show("已从 Keychain 移除。") } catch { show(safeFailure(error).message, failed: true) }
                refresh()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var statusText: String {
        switch status {
        case .keychain: return "已保存在 Keychain"
        case .file: return "读取自 ~/.llm.env"
        case .locked: return "Keychain 需要授权"
        case .missing: return "未配置"
        }
    }
    private var statusIcon: String {
        switch status {
        case .keychain, .file: return "checkmark.circle"
        case .locked: return "lock"
        case .missing: return "key"
        }
    }
    private func save() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try Credentials.save(name, value: draft)
            draft = ""
            show("已保存到 Keychain，下一次调用生效。")
        } catch { show(safeFailure(error).message, failed: true) }
        refresh()
    }
    private func show(_ text: String, failed: Bool = false) { message = text; self.failed = failed }
    private func refresh() { status = Credentials.status(name); onChange() }
}

/// The two keys dictation needs. Shown at the top of Models & Settings so a fresh install starts here.
struct APICredentialsSurface: View {
    var onChange: () -> Void = {}
    var body: some View {
        Surface(title: "API 凭证") {
            Text("UtterLeaf 不内置任何 Key，用你自己的账号直连服务商。豆包负责语音转写，DeepSeek 负责可选的文字整理。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            CredentialField(name: "DOUBAO_API_KEY", title: "豆包语音 API Key", onChange: onChange)
            Link("打开火山引擎「豆包语音」控制台", destination: URL(string: "https://console.volcengine.com/speech/app")!)
                .font(LeafType.caption)
            Divider()
            CredentialField(name: "DEEPSEEK_API_KEY", title: "DeepSeek API Key", onChange: onChange)
            Link("在 DeepSeek 开放平台创建 API Key", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                .font(LeafType.caption)
            Text("Key 保存在本机 Keychain（服务名 network.utterleaf.personal），不会进入听写历史、iCloud 同步或日志，也不会再显示出来。Keychain 里没有时，会读取 ~/.llm.env 中的同名变量（文件权限需为 600）。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted).textSelection(.enabled)
        }
    }
}
