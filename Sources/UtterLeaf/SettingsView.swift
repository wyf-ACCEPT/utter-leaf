import SwiftUI
import AppKit
import AVFoundation
import UtterLeafCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: LocalStore
    @State private var promptText = ""
    @State private var savedPrompt = ""
    @State private var flashKey = false
    @State private var doubaoKey = false
    @State private var trusted = false
    @State private var microphone = "未检查"
    @State private var confirmClear = false
    @State private var confirmReset = false
    @State private var feedback = ""
    @State private var rollbackVersion = ""
    func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { store.database.preferences[keyPath: path] }, set: { store.database.preferences[keyPath: path] = $0; store.save() })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
        PageHeading(title: "按你的习惯，慢慢调好。", subtitle: "三条 ASR 管线都可试用；选择只影响下一次听写。")
        Surface(title: "外观") {
            LeafSegments(title: "界面主题", selection: Binding(get: { store.database.preferences.appearance ?? "dark" }, set: { store.database.preferences.appearance = $0; store.save() }), items: [LeafSegment("dark", "深色"), LeafSegment("light", "浅色"), LeafSegment("system", "跟随系统")])
            Text("首次打开默认深色；切换后应用于主窗口和录音浮层。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }
        MeetingCaptionSettings(model: model.meetings)
        SoundSettingsView(store: store, sounds: model.sounds).disabled(model.busy || model.inserting)
        Surface(title: "语音识别") {
            LeafSegments(title: "ASR 管线", selection: binding(\.pipeline), items: [LeafSegment(Optional(ASRPipeline.final), "流式 · 结束后返回"), LeafSegment(Optional(ASRPipeline.realtime), "流式 · 实时模式"), LeafSegment(Optional(ASRPipeline.file), "文件标准版")])
            if store.database.preferences.pipeline == nil { Text("请选择本次试用的管线，暂未设置默认值。").font(LeafType.caption).foregroundStyle(LeafTheme.muted) }
            Button("清除试用选择") { store.database.preferences.pipeline = nil; store.save() }.font(LeafType.caption).disabled(store.database.preferences.pipeline == nil)
            Text("前两项使用同一流式 2.0 模型；实时模式会边说边识别。文件版 audio.data 是已实测接法，当前官方接口主要列出 URL，兼容性失败时可切换流式。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            Toggle("使用 DeepSeek Flash 整理文字", isOn: binding(\.cleanup))
            Text("不提供工具调用。口述中的问题和命令始终作为录音数据整理。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }.disabled(model.busy)
        Surface(title: "文字输入") {
            LeafSegments(title: "录音结束后", selection: Binding(get: { store.database.preferences.insertionMode ?? "automatic" }, set: { store.database.preferences.insertionMode = $0; store.save() }), items: [LeafSegment("automatic", "自动输入到原应用"), LeafSegment("preview", "先在 App 内预览")])
            Text("默认自动输入。原应用、输入框与光标保持一致时，整理完成后直接插入；焦点变化或输入失败时保留文字供处理。不会自动发送消息。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }.disabled(model.busy || model.inserting)
        Surface(title: "权限与个人凭证") {
            HStack { Label(doubaoKey ? "豆包个人凭证可读" : "豆包凭证待配置", systemImage: doubaoKey ? "checkmark.circle" : "key"); Spacer(); Label(flashKey ? "DeepSeek 个人凭证可读" : "DeepSeek 凭证待配置", systemImage: flashKey ? "checkmark.circle" : "key") }.font(.system(size: LeafType.scaled(12)))
            Text("仅从本机 Keychain 的 network.utterleaf.personal 服务，或 ~/.llm.env 的 DOUBAO_API_KEY / DEEPSEEK_API_KEY 读取。不读取公司的 OpenRouter Key，不在 App 内展示凭证。").font(LeafType.caption).foregroundStyle(LeafTheme.muted).textSelection(.enabled)
            HStack {
                Text("麦克风：\(microphone) · 辅助功能：\(trusted ? "已授权" : "未授权")").font(LeafType.caption)
                Spacer(); Button("刷新状态", action: refresh)
            }
            HStack {
                Button("打开麦克风设置") { openPrivacy("Privacy_Microphone") }
                Button("打开辅助功能设置") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    trusted = AXIsProcessTrustedWithOptions(options)
                    openPrivacy("Privacy_Accessibility")
                }
            }
            Text(model.hotkeyRegistered ? "全局快捷键：单按 Fn 开始 / 结束 · Fn 组合键不触发录音" : "Fn 监听尚未启用，请检查辅助功能权限；可先用窗口按钮录音。")
                .font(LeafType.caption).foregroundStyle(model.hotkeyRegistered ? LeafTheme.muted : .red)
            Text("单按并松开 Fn 切换录音。仅拦截 Fn 本身的系统动作，不更改系统键盘设置；Fn + 方向键等组合键继续传给原应用。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            Text("先在目标输入框按快捷键开始，结束后会按上面的方式自动输入或预览。不支持辅助功能回填的应用可复制粘贴。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }
        Surface(title: "听写历史与隐私") {
            LeafSegments(title: "正文保留", selection: binding(\.retention), items: [LeafSegment("both", "原始 + 最终稿"), LeafSegment("final", "仅最终稿"), LeafSegment("none", "仅用量")])
            Text("当前设置应用于新记录。已有正文保留至手动清除。音频不落盘，最长录音 5 分钟。用量与听写历史同步到个人私有 iCloud；录音、密钥和会议正文不参与同步。系统和供应商各自的保留政策仍适用。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            Button("清除全部听写正文…", role: .destructive) { confirmClear = true }.disabled(model.busy || model.inserting)
        }
        BillingSyncView(store: store)
        Surface(title: "计价设置") {
            Text("人民币 / 音频小时 · 2026-10-22 历史参考，账户实际套餐尚未核实").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            priceField("流式 2.0", binding(\.streamPrice))
            priceField("文件标准版 2.0", binding(\.filePrice))
            Divider()
            Text("人民币 / 百万 token · 2026-10-23 官方高峰价参考").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            priceField("输入（未缓存）", binding(\.flashInput)); priceField("输入（缓存命中）", binding(\.flashCached)); priceField("输出", binding(\.flashOutput))
            Text("DeepSeek 非高峰参考价为高峰的一半。这里按配置单价估算，不自动推断节假日或免费额度。修改只影响后续调用的计价快照；实际金额需对应供应商账单核对。采用官方人民币报价，不使用美元汇率换算。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            Link("查看 DeepSeek 官方价格", destination: URL(string: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/")!)
        }.disabled(model.busy)
        Surface(title: "文字整理 Prompt") {
            HStack { Text(store.database.preferences.customPrompt == nil ? "cleanup-v6-spoken-symbols · 内置" : "自定义版本 · " + String(TextEnvelope.hash(savedPrompt).prefix(12))).font(LeafType.caption); Spacer(); if promptText != savedPrompt { Text("尚未保存").font(LeafType.caption).foregroundStyle(.orange) } }
            TextEditor(text: $promptText).font(.system(size: LeafType.scaled(12), design: .monospaced)).frame(height: 250).leafInput().accessibilityLabel("文字整理 system prompt")
            HStack {
                Button("保存新版本") {
                    if let old = store.database.preferences.customPrompt, !store.database.preferences.promptVersions.contains(old) { store.database.preferences.promptVersions.append(old) }
                    store.database.preferences.customPrompt = promptText
                    savedPrompt = promptText; store.save(); feedback = "已保存 Prompt 新版本；JSON 数据封装保持启用。"
                }.disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || promptText == savedPrompt)
                Button("撤销未保存修改") { promptText = savedPrompt }.disabled(promptText == savedPrompt)
                Button("恢复内置 v6…") { confirmReset = true }
            }
            if !store.database.preferences.promptVersions.isEmpty {
                HStack {
                    LeafSegments(title: "历史版本", selection: $rollbackVersion, items: [LeafSegment("", "未选择")] + store.database.preferences.promptVersions.map { LeafSegment($0, String(TextEnvelope.hash($0).prefix(8))) })
                    Button("载入到编辑器") { promptText = rollbackVersion }.disabled(rollbackVersion.isEmpty)
                }
            }
            Text("JSON transcript 数据封装与阿拉伯数字偏好由程序固定添加（如 session one → session 1、队名 G two → G2）。每次调用记录实际 Prompt 的 SHA-256；保存新版本会保留上一版供回滚。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }.disabled(model.busy)
        if !feedback.isEmpty { Text(feedback).font(LeafType.caption).foregroundStyle(LeafTheme.leaf) }
        }
        .onAppear {
            refresh(); savedPrompt = (try? model.prompt()) ?? ""; promptText = model.promptEditorDraft ?? savedPrompt
        }
        .onChange(of: promptText) { _, value in model.promptEditorDraft = value }
        .confirmationDialog("清除已载入的全部听写正文，并同步清除到 iCloud 和其他设备？会议记录不受影响。此操作不能撤销，用量记录与当前预览会保留。", isPresented: $confirmClear) {
            Button("清除全部听写正文", role: .destructive) { store.clearText(); feedback = "已清除听写正文，保留用量与字符计数。" }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("恢复内置 v6？当前编辑器中未保存的修改将丢失，已保存的自定义版本仍可回滚。", isPresented: $confirmReset) {
            Button("恢复内置 v6") {
                if let old = store.database.preferences.customPrompt, !store.database.preferences.promptVersions.contains(old) { store.database.preferences.promptVersions.append(old) }
                store.database.preferences.customPrompt = nil; store.save(); savedPrompt = (try? model.prompt()) ?? ""; promptText = savedPrompt
            }
            Button("取消", role: .cancel) {}
        }
    }
    func priceField(_ title: String, _ value: Binding<Double>) -> some View {
        HStack { Text(title).font(.system(size: LeafType.scaled(13))); Spacer(); TextField(title, value: Binding(get: { value.wrappedValue }, set: { if $0.isFinite && $0 >= 0 { value.wrappedValue = $0 } }), format: .number.precision(.fractionLength(0...6))).leafInput().frame(width: 130) }
    }
    func refresh() {
        doubaoKey = Credentials.available("DOUBAO_API_KEY"); flashKey = Credentials.available("DEEPSEEK_API_KEY"); trusted = AXIsProcessTrusted()
        switch AVCaptureDevice.authorizationStatus(for: .audio) { case .authorized: microphone = "已授权"; case .notDetermined: microphone = "首次录音时请求"; default: microphone = "未授权" }
    }
    func openPrivacy(_ anchor: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor)!) }
}
