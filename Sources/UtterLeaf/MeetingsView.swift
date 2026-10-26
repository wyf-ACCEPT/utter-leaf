import SwiftUI
import UniformTypeIdentifiers
import UtterLeafCore

struct MeetingsView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var meetings: MeetingStore
    @State private var tab = "笔记"
    @State private var exporting = false
    @State private var exportFile = MeetingTextFile(text: "")
    @State private var exportName = "会议.txt"
    @State private var search = ""
    @State private var showVoices = false
    @State private var confirmMeetingDeletion = false
    @State private var confirmAudioDeletion = false
    @State private var editingSegment: MeetingUtterance?
    @State private var correcting: MeetingUtterance?
    @State private var focusedSegment: String?
    init(model: MeetingModel, meetings: MeetingStore, initialTab: String = "笔记") {
        self.model = model; self.meetings = meetings; _tab = State(initialValue: initialTab)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "把讨论，留成共识。", subtitle: "本机录音 · 区分说话人 · 你的笔记与原文一起整理")
            HStack {
                Button { showVoices = true } label: { Label("说话人声纹", systemImage: "person.wave.2") }.buttonStyle(.bordered).handCursor()
                Spacer()
                if model.recording {
                    Button(model.floatingCaptions ? "隐藏悬浮窗" : "显示悬浮窗") {
                        model.floatingCaptions.toggle(); model.saveOptions()
                    }.buttonStyle(.bordered).handCursor()
                    Text(clock(model.elapsed)).monospacedDigit().foregroundStyle(LeafTheme.leaf)
                    Button(model.paused ? "继续" : "暂停", action: model.togglePause).buttonStyle(.bordered).handCursor()
                    Button("结束会议", action: model.stop).buttonStyle(PrimaryStyle()).handCursor()
                } else {
                    Button("新会议") { model.create(systemAudio: model.systemAudio) }.buttonStyle(PrimaryStyle()).handCursor().disabled(model.busy)
                }
            }
            if !model.recording {
                if model.current == nil {
                    Toggle("同时采集系统声音（线上会议）", isOn: $model.systemAudio).disabled(model.busy)
                    Toggle("会中实时字幕（另计流式调用费，会后仍做整场识别）", isOn: $model.live).disabled(model.busy)
                    Text("系统声音会包含其他应用播放的音频，请关闭无关音源；线下会议关闭系统声音。单场最长 3 小时，录音保存在本机，可回听或手动删除。音频与文字会发送至个人 API。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                } else {
                    DisclosureGroup("下次会议的录音选项") {
                        Toggle("同时采集系统声音（线上会议）", isOn: $model.systemAudio).disabled(model.busy)
                        Toggle("会中实时字幕（另计流式调用费，会后仍做整场识别）", isOn: $model.live).disabled(model.busy)
                        Text("系统声音会包含其他应用播放的音频，请关闭无关音源；线下会议关闭系统声音。单场最长 3 小时，录音保存在本机，可回听或手动删除。音频与文字会发送至个人 API。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    }.font(LeafType.caption)
                }
            }
            if let error = meetings.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            if !model.message.isEmpty { Label(model.message, systemImage: "info.circle").font(LeafType.caption).foregroundStyle(LeafTheme.muted).textSelection(.enabled) }
            if model.busy {
                MeetingProcessingView(work: model.progress ?? MeetingWorkProgress(.preparing), canStop: model.canStopWaiting, stop: model.stopWaiting)
            }
            if let value = model.current {
                detail(value)
            } else {
                Surface {
                    Image(systemName: "text.bubble").font(.system(size: 28)).foregroundStyle(LeafTheme.leaf)
                    Text("听会议，也记下你的判断。").font(LeafType.headline)
                    Text("开始后可以随手记笔记。结束录音会生成带说话人的转录，再由你选择生成 brief。").foregroundStyle(LeafTheme.muted)
                }
            }
            if !meetings.index.meetings.isEmpty {
                Surface(title: "会议记录") {
                    TextField("搜索会议标题与内容", text: $search).leafInput().accessibilityLabel("搜索会议")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(meetings.index.meetings.filter { meeting in search.isEmpty || meeting.title.localizedCaseInsensitiveContains(search) || meeting.notes.localizedCaseInsensitiveContains(search) || meeting.segments.contains { meeting.text(for: $0).localizedCaseInsensitiveContains(search) } }) { value in
                                Button { model.select(value.id) } label: {
                                    HStack {
                                        Image(systemName: value.id == model.current?.id ? "circle.inset.filled" : "waveform")
                                        VStack(alignment: .leading) {
                                            Text(value.title).font(LeafType.headline)
                                            Text(value.created.formatted(date: .abbreviated, time: .shortened) + " · " + clock(value.seconds) + " · " + status(value.state)).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                                        }
                                        Spacer(); Image(systemName: "chevron.right")
                                    }.padding(8).contentShape(Rectangle())
                                }.buttonStyle(.plain).handCursor().disabled(model.blocksDictation)
                            }
                        }
                    }.frame(height: 320).scrollIndicators(.visible).accessibilityLabel("会议记录，可滚动")

                }
            }
        }
        .onChange(of: model.systemAudio) { _, _ in model.saveOptions() }
        .onChange(of: model.live) { _, _ in model.saveOptions() }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .plainText, defaultFilename: exportName) { result in
            switch result {
            case .success: model.message = "TXT 已导出。"
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { model.message = "TXT 导出失败，请检查保存位置后重试。" }
            }
        }
        .sheet(isPresented: $showVoices) { VoiceprintView(model: model, store: meetings) }
        .sheet(item: $editingSegment) { row in
            MeetingTranscriptEditor(row: row, text: model.current?.text(for: row) ?? row.text) { text in
                model.edit { $0.setTranscriptText(id: row.id, text: text) }
            }
        }
        .sheet(item: $correcting) { row in
            MeetingSpeakerEditor(row: row, initial: model.current?.speaker(for: row) ?? row.speaker) { speaker in
                model.edit { if $0.speakerOverrides == nil { $0.speakerOverrides = [:] }; $0.speakerOverrides?[row.id] = speaker }
            }
        }
        .confirmationDialog("删除这场会议的全部本机音频、转录、笔记与 Brief？此操作无法撤销；API 用量与声纹库仍保留。", isPresented: $confirmMeetingDeletion) {
            Button("删除本机会议", role: .destructive, action: model.deleteMeeting)
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除本场会议的本机录音？转录、笔记与用量仍保留。删除后无法回听或重新识别。", isPresented: $confirmAudioDeletion) {
            Button("删除本机音频", role: .destructive, action: model.deleteAudio)
            Button("取消", role: .cancel) {}
        }
    }
    @ViewBuilder private func detail(_ value: MeetingRecord) -> some View {
        Surface {
            TextField("会议标题", text: Binding(get: { model.current?.title ?? "" }, set: { text in model.editText { $0.title = text } })).font(LeafType.headline).leafInput().accessibilityLabel("会议标题")
            HStack {
                Text(status(value.state) + " · " + clock(value.seconds)).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                Spacer()
                Button("回听") { model.playback() }.disabled(model.recording).handCursor()
                Button("停止播放", action: model.stopPlayback).handCursor()
                Button(model.audioExporting ? "导出中…" : "导出 M4A", action: model.exportAudio).handCursor().disabled(model.recording || model.audioExporting || value.state == "saving")
            }
            if !model.recording {
                if !value.segments.isEmpty { MeetingNamingView(model: model, meeting: value) }
                workflow(value)
            }
            LeafSegments(title: "会议内容", selection: $tab, items: [LeafSegment("笔记", "我的笔记"), LeafSegment("转录", "原始转录"), LeafSegment("整理稿", "整理转录"), LeafSegment("Brief", "Brief")])
            if !model.recording {
                HStack {
                    Text(section.title).font(LeafType.headline)
                    Spacer()
                    Button {
                        if let text = MeetingTextExport.body(value, section: section, references: model.briefReferences) {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                            model.message = "已复制\(section.title)。"
                        }
                    } label: { Label("复制", systemImage: "doc.on.doc") }.handCursor()
                    Button {
                        guard let text = MeetingTextExport.document(value, section: section, references: model.briefReferences) else { return }
                        exportFile = MeetingTextFile(text: text); exportName = MeetingTextExport.filename(value, section: section); exporting = true
                    } label: { Label("导出 TXT", systemImage: "square.and.arrow.up") }
                        .handCursor().help("导出当前的\(section.title)，使用 UTF-8 编码")
                }.buttonStyle(.bordered)
                    .disabled(MeetingTextExport.body(value, section: section, references: model.briefReferences) == nil)
            }
            switch tab {
            case "笔记":
                Text("你记下的要点会和转录一起整理；输入自动保存在本机。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                TextEditor(text: Binding(get: { model.current?.notes ?? "" }, set: { text in model.editText { $0.notes = text } })).frame(minHeight: 250).leafInput().accessibilityLabel("会议随手笔记")
            case "转录", "整理稿":
                if tab == "整理稿", !MeetingWorkflow.cleaned(value) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "text.badge.checkmark").font(.system(size: 24)).foregroundStyle(LeafTheme.muted)
                        Text(model.busy ? "整理中，完成后在这里显示整理稿。" : "还没有整理转录，点击上方“整理转录”开始。")
                            .foregroundStyle(LeafTheme.muted)
                    }.frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
                } else if value.segments.isEmpty {
                    if model.recording {
                        Text("实时说话人仅为暂定编号；暂停前后、麦克风与系统音轨的编号不能直接视为同一个人。会后完整识别将统一校正。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(model.liveSegments.keys.sorted(), id: \.self) { source in
                                    Text(source == "system" ? "系统音轨 · 暂定" : "麦克风音轨 · 暂定").font(LeafType.headline)
                                    ForEach(model.liveSegments[source] ?? []) { row in
                                        Text("[\(row.start < 0 ? "实时" : clock(row.start))] \(row.speaker == "unknown" ? "说话人待确认" : "说话人 " + row.speaker)：\(row.text)").textSelection(.enabled)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 360).scrollIndicators(.visible).accessibilityLabel("实时原始转录，可滚动")

                    } else { Text("尚无完整转录。结束会议后可提交识别，或核对已有任务。").foregroundStyle(LeafTheme.muted) }
                } else {
                    Text("说话人名称可修改；同名表示你确认属于同一个人。未知身份请保留未知，不靠文本猜人名。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], alignment: .leading, spacing: 12) {
                        ForEach(Array(Set(value.segments.map(\.speaker))).sorted(), id: \.self) { speaker in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("说话人 " + speaker).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                                TextField(value.name(for: speaker), text: Binding(get: { model.current?.speakerNames[speaker] ?? "" }, set: { name in model.editText { $0.speakerNames[speaker] = name } })).leafInput().accessibilityLabel("说话人 \(speaker) 姓名")
                            }
                        }
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(value.segments) { row in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Button { model.playback(at: row.start) } label: { Text(clock(row.start)).monospacedDigit() }.handCursor()
                                            Text(value.name(for: value.speaker(for: row))).font(LeafType.headline)
                                            Spacer(); Text("[\(row.id)]").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                                        }
                                        Text(tab == "整理稿" ? (value.cleaned?[row.id] ?? "") : value.text(for: row)).textSelection(.enabled)
                                        HStack {
                                            if tab == "转录" { Button("编辑文字") { editingSegment = row }.handCursor().disabled(model.blocksDictation) }
                                            Button("纠正说话人") { correcting = row }.handCursor().disabled(model.blocksDictation)
                                        }.font(LeafType.caption)
                                    }.padding(10).background(focusedSegment == row.id ? LeafTheme.leaf.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10)).id(row.id)
                                }
                            }
                        }.frame(height: 420)
                        .task(id: focusedSegment) { await Task.yield(); if let id = focusedSegment { proxy.scrollTo(id, anchor: .top) } }
                    }
                }
            default:
                Toggle("显示溯源编号", isOn: Binding(get: { model.briefReferences }, set: { model.briefReferences = $0; model.saveOptions() }))
                    .help("默认关闭；切换只影响显示与复制，无需重新生成纪要")
                if value.brief.isEmpty { Text("转录完成后，结合你的笔记生成摘要、决定、待办和未决问题。").foregroundStyle(LeafTheme.muted) }
                else if model.briefReferences {
                    TextEditor(text: Binding(get: { model.current?.brief ?? "" }, set: { text in model.editText { $0.brief = text } })).frame(minHeight: 300).leafInput().accessibilityLabel("会议 Brief 原稿")
                    HStack {
                        TextField("原文编号，例如 u12", text: Binding(get: { focusedSegment ?? "" }, set: { focusedSegment = $0 })).leafInput().accessibilityLabel("原文发言编号")
                        Button("查看原文") { tab = "转录" }.handCursor()
                    }
                } else {
                    ScrollView {
                        Text(MeetingProtocol.briefForDisplay(value.brief, references: false))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.frame(height: 360).scrollIndicators(.visible).accessibilityLabel("会议 Brief，无溯源编号")
                    Button("编辑原稿") { model.briefReferences = true; model.saveOptions() }
                        .buttonStyle(.bordered).handCursor().help("展开带溯源编号的原稿进行编辑")
                }
            }
            if !model.recording {
                Text(model.costSummary).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                DisclosureGroup("其他处理选项") {
                    HStack {
                        Button(value.requestID == nil ? "转录整场会议" : "核对转录", action: model.transcribe).disabled(model.busy || !value.segments.isEmpty).handCursor()
                        Button("重新整理转录") { tab = "整理稿"; model.cleanTranscript() }.disabled(model.busy || value.segments.isEmpty).handCursor()
                        Button(value.brief.isEmpty ? "直接生成 Brief" : "更新 Brief") { tab = "Brief"; model.summarize() }.disabled(model.busy || value.segments.isEmpty).handCursor()
                    }.buttonStyle(.bordered)
                }.font(LeafType.caption)

                HStack {
                    Button("恢复中断音频", action: model.recover).handCursor()
                    Spacer(); Button("删除会议…", role: .destructive) { confirmMeetingDeletion = true }.handCursor()
                    Button("删除本机音频…", role: .destructive) { confirmAudioDeletion = true }.handCursor()
                }.disabled(model.busy).font(LeafType.caption)
            }
        }
    }
    private var section: MeetingTextSection {
        switch tab { case "笔记": return .notes; case "转录": return .raw; case "整理稿": return .cleaned; default: return .brief }
    }
    @ViewBuilder private func workflow(_ value: MeetingRecord) -> some View {
        let next = MeetingWorkflow.next(value)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                step("原始转录", done: !value.segments.isEmpty, current: next == .transcribe)
                Image(systemName: "chevron.right").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                step("整理转录", done: MeetingWorkflow.cleaned(value), current: next == .clean)
                Image(systemName: "chevron.right").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                step("Brief", done: !value.brief.isEmpty && value.briefNeedsUpdate != true, current: next == .brief || next == .read)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { workflowDescription(value); Spacer(minLength: 12); nextAction(value) }
                VStack(alignment: .leading, spacing: 12) { workflowDescription(value); nextAction(value) }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LeafTheme.leaf.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(LeafTheme.leaf.opacity(0.22)))
    }
    private func step(_ title: String, done: Bool, current: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : (current ? "circle.inset.filled" : "circle"))
            .font(LeafType.caption).foregroundStyle(done || current ? LeafTheme.leaf : LeafTheme.muted)
            .accessibilityLabel(title + (done ? "，已完成" : current ? "，下一步" : "，待完成"))
    }
    private func workflowDescription(_ value: MeetingRecord) -> some View {
        let next = MeetingWorkflow.next(value)
        let heading: String
        let detail: String
        switch next {
        case .transcribe:
            heading = model.busy ? "正在准备原始转录" : "先获得完整的原始转录"
            detail = model.busy ? "音频正在保存、提交或由豆包处理，完成后继续整理。" : "使用整场录音识别文字与说话人，再继续整理表达。"
        case .clean:
            heading = "原始转录已就绪，下一步整理表达"
            detail = "去掉口吃、修正标点与拼写，保留原意和说话人；原始转录始终保留。"
        case .brief:
            heading = value.briefNeedsUpdate == true ? "整理稿已更新，接着更新 Brief" : "整理转录已就绪，接着提炼会议要点"
            detail = "结合转录和你的笔记，生成摘要、决定、待办与未决问题。"
        case .read:
            heading = "会议内容已整理完成"
            detail = "查看 Brief，或切换标签页复制、导出对应内容。"
        }
        return VStack(alignment: .leading, spacing: 5) {
            Text(heading).font(LeafType.headline)
            Text(detail).font(LeafType.caption).foregroundStyle(LeafTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private func nextAction(_ value: MeetingRecord) -> some View {
        let next = MeetingWorkflow.next(value)
        Button {
            switch next {
            case .transcribe: tab = "转录"; model.transcribe()
            case .clean: tab = "整理稿"; model.cleanTranscript()
            case .brief: tab = "Brief"; model.summarize()
            case .read: tab = "Brief"
            }
        } label: {
            HStack(spacing: 8) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.busy ? "处理中…" : (next == .clean ? "整理转录" : next == .brief ? (value.brief.isEmpty ? "生成 Brief" : "更新 Brief") : next == .read ? "查看 Brief" : value.requestID == nil ? "转录整场会议" : "核对转录"))
                if !model.busy { Image(systemName: "arrow.right") }
            }.frame(minWidth: 130)
        }.buttonStyle(PrimaryStyle()).handCursor().disabled(model.busy)
    }
    private func clock(_ seconds: Double) -> String { let n = max(0, Int(seconds)); return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%02d:%02d", n / 60, n % 60) }
    private func status(_ state: String) -> String {
        ["draft": "待开始", "preparing": "准备录音", "recording": "录音中", "paused": "已暂停", "saving": "保存音频", "recorded": "录音已保存", "transcribing": "转录中", "summarizing": "整理中", "transcribed": "转录已完成", "ready": "笔记已完成", "interrupted": "上次中断，可恢复", "pending": "等待服务端结果", "failed": "需要处理" ][state] ?? state
    }
}

struct VoiceprintView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var store: MeetingStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var renaming: VoiceIdentity?
    @State private var deleting: VoiceIdentity?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("记住说话人的声音").font(LeafType.headline); Spacer(); Button("完成") { url = ""; dismiss() }.handCursor() }
            Text("豆包托管声纹，言叶仅保存身份 ID 与姓名；姓名匹配仍可能有误，可在每场会议纠正。启用的身份用于下一场会议，最多 50 人。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            if !model.message.isEmpty { Text(model.message).font(LeafType.caption).textSelection(.enabled) }
            HStack { Button("刷新豆包名单", action: model.refreshVoices).handCursor().disabled(model.voiceBusy); if model.voiceBusy { ProgressView().controlSize(.small) }; Spacer() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.index.voices.isEmpty { Text("还没有声纹。可以先使用会议内说话人编号，或从临时签名音频注册身份。").foregroundStyle(LeafTheme.muted) }
                    ForEach(store.index.voices) { voice in
                        HStack {
                            Toggle(voice.name, isOn: Binding(get: { voice.enabled }, set: { _ in model.toggleVoice(voice) }))
                            Spacer()
                            Button("改名") { renaming = voice }.handCursor()
                            Button("移除…", role: .destructive) { deleting = voice }.handCursor()
                        }
                    }
                    Divider()
                    Text("注册跨会议身份").font(LeafType.headline)
                    TextField("姓名", text: $name).leafInput().accessibilityLabel("声纹姓名")
                    SecureField("HTTPS 音频签名 URL", text: $url).leafInput().accessibilityLabel("声纹音频签名 URL")
                    Text("仅使用你有权处理的清晰单人语音，5–30 秒，wav / pcm / mp3。豆包会读取此 URL 并保存音频与声纹。URL 仅本次使用，不写入历史；不要使用公开永久链接。当前不会自动上传本机录音。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    Button("提交音频 URL 并注册") { model.registerVoice(name: name, url: url); url = "" }.buttonStyle(PrimaryStyle()).handCursor().disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || url.isEmpty)
                }
            }.frame(maxHeight: 430).disabled(model.voiceBusy)
            Text("移除使用供应商软删除：停止后续识别，不承诺物理清除。注册结果不明确时请先刷新，避免重复注册。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }.padding(26).frame(width: 640).background(LeafTheme.mist)
            .sheet(item: $renaming) { voice in VoiceNameEditor(voice: voice) { model.updateVoice($0) } }
            .confirmationDialog("从豆包可用声纹中移除这位说话人？这是软删除，不代表物理清除。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("移除声纹", role: .destructive) { if let deleting { model.updateVoice(deleting, delete: true) }; deleting = nil }
                Button("取消", role: .cancel) { deleting = nil }
            }
    }
}

private struct MeetingSpeakerEditor: View {
    let row: MeetingUtterance
    @State var speaker: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    init(row: MeetingUtterance, initial: String, save: @escaping (String) -> Void) {
        self.row = row; _speaker = State(initialValue: initial); self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("纠正这句话的说话人").font(LeafType.headline)
            Text(row.text).lineLimit(5).textSelection(.enabled)
            Text("填写本场说话人标识，例如 1、2 或 unknown。原始识别仍保留。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            TextField("说话人标识", text: $speaker).leafInput().accessibilityLabel("纠正后的说话人标识")
            HStack {
                Button("取消") { dismiss() }.handCursor(); Spacer()
                Button("保存") { save(speaker.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }.buttonStyle(PrimaryStyle()).handCursor().disabled(speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 520).background(LeafTheme.mist)
    }
}

private struct VoiceNameEditor: View {
    var voice: VoiceIdentity
    var save: (VoiceIdentity) -> Void
    @State private var name: String
    @Environment(\.dismiss) private var dismiss
    init(voice: VoiceIdentity, save: @escaping (VoiceIdentity) -> Void) { self.voice = voice; self.save = save; _name = State(initialValue: voice.name) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("修改声纹姓名").font(LeafType.headline)
            TextField("姓名", text: $name).leafInput().accessibilityLabel("新的声纹姓名")
            Text("将更新豆包声纹姓名；已保存会议的人名快照保持原样。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            HStack { Button("取消") { dismiss() }.handCursor(); Spacer(); Button("保存") { var value = voice; value.name = name.trimmingCharacters(in: .whitespacesAndNewlines); save(value); dismiss() }.buttonStyle(PrimaryStyle()).handCursor().disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(26).frame(width: 480).background(LeafTheme.mist)
    }
}
