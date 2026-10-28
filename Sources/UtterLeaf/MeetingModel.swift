import AppKit
import AVFoundation
import UniformTypeIdentifiers
import UtterLeafCore

@MainActor final class MeetingModel: ObservableObject {
    let store: MeetingStore
    private let ledger: LocalStore
    private let api: MeetingAPI
    private let recorder = MeetingRecorder()
    @Published var selected: UUID?
    @Published var active: MeetingRecord?
    @Published var message = ""
    @Published var elapsed = 0.0
    @Published var audioExporting = false
    private var exportTask: Task<Void, Never>?
    @Published var namingMeetingID: UUID?
    private var namingTask: Task<Void, Never>?
    @Published var progress: MeetingWorkProgress?
    @Published var busy = false { didSet { if !busy { progress = nil } } }
    @Published var recording = false { didSet { onCaptionUpdate?() } }
    @Published var paused = false { didSet { onCaptionUpdate?() } }
    @Published var live = true { didSet { onCaptionUpdate?() } }
    @Published var systemAudio = true
    @Published var floatingCaptions = true { didSet { onCaptionUpdate?() } }
    @Published var briefReferences = false
    @Published var captionOpacity = 0.75
    @Published var captionLineCount = 3 { didSet { onCaptionUpdate?() } }
    @Published var captionsCollapsed = false { didSet { onCaptionUpdate?() } }
    @Published var captionLines: [MeetingCaptionLine] = [] { didSet { if oldValue != captionLines { onCaptionUpdate?() } } }
    @Published var captionStatus = "等待发言"
    var onCaptionUpdate: (() -> Void)?
    private var captionRound = UUID()
    @Published var liveSegments: [String: [MeetingUtterance]] = [:]
    @Published var voiceBusy = false
    private var draftSave: Task<Void, Never>?
    private var tick: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var liveSessions: [String: MeetingLive] = [:]
    private var generation = UUID()
    private var player: AVAudioPlayer?
    var onCaptureState: ((Bool, Double, Bool) -> Void)?
    var usesMicrophone: Bool { recording || ["preparing", "saving"].contains(current?.state ?? "") }
    var dictationBusy: (() -> Bool)?
    var canStopWaiting: Bool { ["importing", "transcribing", "summarizing"].contains(current?.state ?? "") }
    var blocksDictation: Bool { recording || busy }
    var current: MeetingRecord? { active ?? store.index.meetings.first { $0.id == selected } }
    init(ledger: LocalStore, api: MeetingAPI? = nil) {
        self.api = api ?? MeetingAPI()
        self.ledger = ledger; store = MeetingStore(root: ledger.root)
        self.api.onCall = { [weak ledger] in ledger?.update($0) }
        floatingCaptions = store.index.floatingCaptions ?? true
        briefReferences = store.index.briefReferences ?? false
        captionOpacity = MeetingCaptionPolicy.opacity(store.index.captionOpacity)
        captionLineCount = MeetingCaptionPolicy.lineCount(store.index.captionLineCount)
        live = store.index.liveCaptions ?? true; systemAudio = store.index.systemAudio ?? true
        for value in store.index.meetings { syncUsage(value) }
        recorder.onFailure = { [weak self] in
            guard let self, recording else { return }
            message = "音频设备或系统采集已断开，正在保留已录内容。"; stop()
        }
    }
    func select(_ id: UUID) { guard !recording, !busy else { return }; flushDraft(); stopPlayback(); selected = id; active = nil; liveSegments = [:]; message = "" }
    private func syncUsage(_ value: MeetingRecord) {
        var metadata = ledger.database.jobs.first { $0.id == value.id } ?? HistoryJob(id: value.id, pipeline: .file)
        metadata.kind = "meeting"; metadata.created = value.created; metadata.seconds = value.seconds
        metadata.rawCharacters = value.segments.reduce(0) { $0 + TextEnvelope.characters($1.text) }
        metadata.finalCharacters = value.segments.reduce(0) { $0 + TextEnvelope.characters(value.cleaned?[$1.id] ?? $1.text) }
        metadata.status = value.state; metadata.rawText = nil; metadata.finalText = nil
        ledger.update(metadata)
    }
    private func flushDraft() {
        draftSave?.cancel(); draftSave = nil
        if let active { do { try store.save(active) } catch { message = store.error ?? "会议保存失败。" } }
    }
    func editText(_ change: (inout MeetingRecord) -> Void) {
        guard var value = current else { return }; change(&value); active = value
        draftSave?.cancel()
        draftSave = Task {
            do { try await Task.sleep(for: .milliseconds(500)); try store.save(value) }
            catch is CancellationError {} catch { message = store.error ?? "会议保存失败。" }
        }
    }
    func edit(_ change: (inout MeetingRecord) -> Void) {
        draftSave?.cancel(); draftSave = nil
        guard var value = current else { return }; change(&value)
        if active != nil { active = value }
        do { try store.save(value); syncUsage(value) } catch { message = store.error ?? "会议保存失败。" }
    }
    func saveOptions() { do { try store.saveOptions(systemAudio: systemAudio, live: live, floating: floatingCaptions, captionOpacity: captionOpacity, captionLineCount: captionLineCount, briefReferences: briefReferences) } catch { message = store.error ?? "会议设置保存失败。" } }
    private func presentationWindow() -> NSWindow? {
        let window = NSApp.keyWindow?.sheetParent ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.canBecomeMain && $0.isVisible }
        guard let window, window.attachedSheet == nil else { return nil }
        return window
    }
    func chooseRecordingFile() {
        guard !blocksDictation, dictationBusy?() != true, let window = presentationWindow() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false; panel.message = "选择手表或录音设备导出的音频。文件会保存在本机，并提交豆包整场转录。"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let source = panel.url else { return }
            self.importRecording(source)
        }
    }
    func importRecording(_ source: URL) {
        guard !blocksDictation, dictationBusy?() != true, store.error == nil, ledger.storageError == nil else { return }
        flushDraft(); stopPlayback()
        var value = MeetingRecord(); value.title = source.deletingPathExtension().lastPathComponent
        value.state = "importing"; value.importedOriginalName = source.lastPathComponent
        value.importedAudioFile = MeetingAudioImport.sourceName(source); value.systemAudio = false
        selected = value.id; active = value; busy = true; progress = MeetingWorkProgress(.importing, total: 100)
        do { try store.prepare(value.id); try store.save(value) } catch { busy = false; fail(error); return }
        operation = Task {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await MeetingAudioImport.convert(source: source, folder: store.folder(value.id)) { [weak self] percent in
                    Task { @MainActor in if self?.progress?.stage == .importing { self?.progress?.completed = percent } }
                }
                try Task.checkCancellation()
                edit { $0.seconds = result.seconds; $0.importedAudioFile = result.sourceFile; $0.state = "recorded" }
                active = nil; busy = false; message = "录音已导入本机，正在提交整场转录。"; transcribe()
            } catch {
                busy = false
                if error is CancellationError { edit { $0.state = "interrupted" }; message = "已取消导入，原文件未改动。" }
                else { fail(error); if !(error is AppFailure) { message = "录音导入或转换失败。原文件未改动，请尝试 M4A、MP3 或 WAV。" } }
            }
        }
    }
    func create(systemAudio: Bool) {
        guard !blocksDictation, dictationBusy?() != true, store.error == nil, ledger.storageError == nil else { message = "请先结束当前听写或会议，并检查本地存储。"; return }
        guard store.index.voices.filter(\.enabled).count <= 50 else { message = "一次会议最多启用 50 位声纹身份。"; return }
        flushDraft(); stopPlayback()
        var value = MeetingRecord(); value.state = "preparing"; value.systemAudio = systemAudio
        value.voiceprints = store.index.voices.filter(\.enabled)
        value.title = Date.now.formatted(date: .abbreviated, time: .shortened) + " 会议"
        selected = value.id; active = value; busy = true; liveSegments = [:]; elapsed = 0; message = "准备采集；系统声音会触发系统授权。"
        let token = UUID(); generation = token
        operation = Task {
            do {
                _ = try Credentials.load("DOUBAO_API_KEY")
                try store.prepare(value.id); try store.save(value)
                try await recorder.start(folder: store.folder(value.id), systemAudio: systemAudio)
                guard generation == token, !Task.isCancelled else { recorder.shutdown(); return }
                recording = true; busy = false; onCaptureState?(true, 0, false); edit { $0.state = "recording" }
                message = systemAudio ? "正在记录麦克风与系统声音。建议使用耳机，减少回声。" : "正在记录麦克风。"
                recorder.onChunk = { [weak self] data, source in self?.liveSessions[source]?.append(data) }
                if live { await startLive(token: token) }
                tick = Task {
                    while recording && !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1)); guard !Task.isCancelled else { return }
                        elapsed = recorder.elapsed; onCaptureState?(true, elapsed, paused)
                        if Int(elapsed) % 5 == 0 {
                            do { _ = try await recorder.checkpoint(); edit { $0.seconds = elapsed } }
                            catch { message = "音频写入失败，已停止录音并保留已写入内容。"; stop(); return }
                        }
                        if elapsed >= 3 * 3600 { message = "已达到本轮 3 小时会议上限，正在保存。"; stop(); return }
                    }
                }
            } catch { fail(error); recorder.shutdown(); busy = false }
        }
    }
    private func startLive(token: UUID) async {
        guard let meeting = current else { return }
        let round = UUID(); captionRound = round; captionLines = []; liveSegments = [:]; captionStatus = "等待发言"
        for source in meeting.systemAudio ? ["microphone", "system"] : ["microphone"] {
            let session = MeetingLive()
            session.onFailure = { [weak self] in
                guard let self, captionRound == round, recording, !paused else { return }
                captionStatus = "部分字幕连接中断，录音继续"; message = "实时字幕连接中断；本机录音继续，会后可完整转录。"
            }
            do {
                try await session.start(job: meeting.id, price: .asr(.realtime, stream: ledger.database.preferences.streamPrice), onCall: { [weak ledger] in ledger?.update($0) }) { [weak self] rows in
                    guard let self, generation == token, captionRound == round, recording, !paused else { return }
                    liveSegments[source] = rows
                    if let row = rows.last { captionLines = MeetingCaptionPolicy.updating(captionLines, source: source, row: row) }
                    if !captionStatus.contains("中断") { captionStatus = "实时转录 · 说话人暂定" }
                }
                guard recording, !paused, generation == token, captionRound == round else { session.cancel(); return }
                liveSessions[source] = session
            } catch { if captionRound == round { captionStatus = "字幕暂不可用，录音继续"; message = "实时字幕暂不可用；本机录音继续，会后可完整转录。" } }
        }
    }
    func togglePause() {
        guard recording else { return }
        elapsed = recorder.elapsed
        if paused {
            recorder.resume(); paused = false; edit { $0.state = "recording"; $0.seconds = elapsed }
            let token = generation; if live { operation = Task { await startLive(token: token) } }
        } else {
            recorder.pause(); paused = true; edit { $0.state = "paused"; $0.seconds = elapsed }; finishLive()
        }
        onCaptureState?(true, elapsed, paused)
    }
    private func finishLive() { captionRound = UUID(); liveSessions.values.forEach { $0.finish() }; liveSessions.removeAll() }
    func stop() {
        guard recording else { return }
        recording = false; paused = false; onCaptureState?(false, elapsed, false); busy = true; tick?.cancel(); elapsed = recorder.elapsed
        progress = MeetingWorkProgress(.saving)
        finishLive(); edit { $0.seconds = elapsed; $0.state = "saving" }
        operation = Task {
            do {
                let audio = try await recorder.stop()
                let bytes = try audio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 44
                let seconds = Double(max(0, bytes - 44)) / 32000
                edit { $0.state = "recorded"; $0.seconds = seconds }; active = nil; busy = false
                guard seconds >= 1 else { message = "未采集到足够音频，请检查麦克风与系统声音权限。文件已保留。"; return }
                transcribe()
            }
            catch { busy = false; fail(error) }
        }
    }
    func recover() {
        guard let value = current, !blocksDictation else { return }
        if let name = value.importedAudioFile, name.hasPrefix("imported-audio."), !name.contains("/"), !name.contains("\\") {
            let source = store.folder(value.id).appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { message = "本机导入副本已删除，请重新选择录音文件。"; return }
            busy = true; progress = MeetingWorkProgress(.importing, total: 100)
            operation = Task {
                do {
                    let audio = try await MeetingAudioImport.convert(source: source, folder: store.folder(value.id)) { [weak self] percent in
                        Task { @MainActor in if self?.progress?.stage == .importing { self?.progress?.completed = percent } }
                    }
                    try Task.checkCancellation(); edit { $0.seconds = audio.seconds; $0.state = "recorded" }; busy = false; message = "导入录音已恢复，可提交整场转录。"
                } catch { busy = false; fail(error) }
            }
            return
        }
        guard FileManager.default.fileExists(atPath: store.folder(value.id).appendingPathComponent("microphone.pcm").path) else { message = "本机原始音轨不存在，不能恢复。"; return }
        busy = true
        operation = Task {
            do {
                let files = try MeetingAudioFiles(folder: store.folder(value.id), recovering: true)
                let seconds = try await files.checkpoint(); _ = try await files.finish()
                edit { $0.seconds = seconds; $0.state = "recorded" }; busy = false; message = "已恢复本机音频，可开始转录。"
            } catch { busy = false; fail(error) }
        }
    }
    func transcribe() {
        guard let value = current, !blocksDictation else { return }
        guard ledger.storageError == nil else { message = "用量账本不可写，已停止发送会议音频。"; return }
        guard value.seconds >= 1 else { message = "会议音频太短，请保留至少一秒有效录音。"; return }
        busy = true; edit { $0.state = "transcribing" }; message = value.requestID == nil ? "准备完整会议转录与说话人识别…" : "核对上次提交的会议任务，不重复提交。"
        progress = MeetingWorkProgress(.preparing)
        operation = Task {
            api.onRecognitionStatus = { [weak self] code in
                guard let self, busy else { return }
                let stage: MeetingWorkProgress.Stage = code == "20000002" ? .queued : .recognizing
                if ["20000001", "20000002"].contains(code), progress?.stage != stage { progress = MeetingWorkProgress(stage) }
            }
            api.onRawResult = { [store] data in
                let path = store.folder(value.id).appendingPathComponent("provider-result.json")
                try data.write(to: path, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            }
            defer { api.onRawResult = nil; api.onRecognitionStatus = nil }
            do {
                let call: UsageCall
                if let id = value.requestID {
                    guard let existing = ledger.database.calls.first(where: { $0.requestID == id }) else { throw AppFailure("原转录请求回执缺失，已停止自动重新提交。", code: "meeting_receipt_missing") }
                    call = existing; progress = MeetingWorkProgress(.recognizing)
                } else {
                    let upload = store.folder(value.id).appendingPathComponent("request.json")
                    try await MeetingAPI.buildUpload(audio: store.audio(value.id), destination: upload, voices: value.voiceprints, seconds: value.seconds)
                    try Task.checkCancellation()
                    var pending = UsageCall(jobID: value.id, provider: "Doubao", model: value.seconds < 180 ? "meeting-ssd200" : "meeting-ssd300", price: .asr(.file, file: ledger.database.preferences.filePrice))
                    pending.seconds = value.seconds
                    ledger.update(pending)
                    guard ledger.storageError == nil else { throw AppFailure("用量回执保存失败，未发送会议音频。", code: "meeting_usage_storage") }
                    edit { $0.requestID = pending.requestID; $0.submission = "uncertain" }
                    if store.error != nil { throw AppFailure("请求 ID 保存失败，已停止发送。", code: "meeting_storage") }
                    try Task.checkCancellation()
                    progress = MeetingWorkProgress(.uploading, total: 100)
                    call = try await api.submit(upload: upload, call: pending) { [weak self] percent in
                        guard let self, progress?.stage == .uploading else { return }
                        progress?.completed = percent
                    }
                    progress = MeetingWorkProgress(.queued)
                    edit { $0.submission = "accepted" }
                    try? FileManager.default.removeItem(at: upload)
                }
                for attempt in 0..<600 {
                    try Task.checkCancellation()
                    if let result = try await api.query(call: call) {
                        let path = store.folder(value.id).appendingPathComponent("provider-result.json")
                        try result.data.write(to: path, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                        edit { $0.segments = result.segments; $0.rawResultHash = TextEnvelope.hash(String(decoding: result.data, as: UTF8.self)); $0.state = "transcribed"; $0.failureCode = nil }
                        message = "整场转录已完成，说话人编号仅属于本场会议；已注册声纹会参与匹配。"
                        busy = false
                        if current?.nameCandidates == nil { suggestNames() }
                        return
                    }
                    if attempt % 10 == 0 { message = "豆包仍在处理完整会议，原请求已保留，可停止等待后再核对。" }
                    try await Task.sleep(for: .seconds(3))
                }
                edit { $0.state = "pending" }; message = "服务端仍在处理，稍后点“核对转录”继续查询。"; busy = false
            } catch {
                busy = false
                if error is CancellationError { edit { $0.state = "pending" }; message = "已停止本地等待，服务端可能继续处理；下次只查询原请求。" }
                else { fail(error) }
            }
        }
    }
    func cleanTranscript() {
        guard let value = current, !value.segments.isEmpty, !blocksDictation else { return }
        busy = true; progress = MeetingWorkProgress(.cleaning, total: value.segments.count); edit { $0.state = "summarizing" }
        operation = Task {
            do {
                let prefs = ledger.database.preferences
                let price = PriceSnapshot(version: "meeting-configured-v1", currency: "CNY", inputPerMillion: prefs.flashInput, cachedPerMillion: prefs.flashCached, outputPerMillion: prefs.flashOutput, note: "会议逐句整理")
                var output = value.cleaned ?? [:]
                for offset in stride(from: 0, to: value.segments.count, by: 60) {
                    try Task.checkCancellation()
                    let rows = Array(value.segments[offset..<min(offset + 60, value.segments.count)])
                    message = "逐句整理会议转录 \(offset + 1) / \(value.segments.count)…"
                    let response = try await api.brief(content: MeetingProtocol.envelope(value, segments: rows), meeting: value.id, price: price, system: MeetingProtocol.cleanupPrompt)
                    let cleaned = try MeetingProtocol.cleaned(response, expected: rows)
                    progress?.completed += rows.count
                    output.merge(cleaned) { _, new in new }; edit { $0.cleaned = output; if !$0.brief.isEmpty { $0.briefNeedsUpdate = true } }
                }
                edit { $0.state = "transcribed" }; busy = false; message = "逐句整理稿已保存，原始转录与说话人归属保持独立。"
            } catch { busy = false; fail(error) }
        }
    }
    func summarize() {
        guard let value = current, !value.segments.isEmpty, !blocksDictation else { return }
        busy = true; edit { $0.state = "summarizing"; $0.briefNeedsUpdate = true }; message = "根据你的笔记和带说话人的原文整理…"
        operation = Task {
            do {
                let prefs = ledger.database.preferences
                let price = PriceSnapshot(version: "meeting-configured-v1", currency: "CNY", inputPerMillion: prefs.flashInput, cachedPerMillion: prefs.flashCached, outputPerMillion: prefs.flashOutput, note: "当前个人设置的整理费率")
                var chunks: [[MeetingUtterance]] = []; var chunk: [MeetingUtterance] = []; var size = 0
                for row in value.segments {
                    if size + row.text.count > 18000, !chunk.isEmpty { chunks.append(chunk); chunk = []; size = 0 }
                    chunk.append(row); size += row.text.count
                }
                if !chunk.isEmpty { chunks.append(chunk) }
                progress = MeetingWorkProgress(.briefing, total: chunks.count)
                var parts: [String] = []
                for (i, rows) in chunks.enumerated() {
                    try Task.checkCancellation(); message = "整理会议片段 \(i + 1) / \(chunks.count)…"
                    let result = try await api.brief(content: MeetingProtocol.envelope(value, segments: rows, preferCleaned: true), meeting: value.id, price: price)
                    guard MeetingProtocol.hasValidReferences(result, segments: rows) else { throw AppFailure("笔记原文引用缺失或不正确，已保留原始转录。可重试整理。", code: "meeting_brief_references") }
                    parts.append(result); progress?.completed = parts.count
                    edit { $0.brief = parts.joined(separator: "\n\n---\n\n") }
                }
                if parts.count > 1 {
                    let joined = parts.joined(separator: "\n\n")
                    if joined.count <= 60000 {
                        let data = try JSONSerialization.data(withJSONObject: ["partial_notes": parts, "user_notes": value.notes])
                        progress = MeetingWorkProgress(.merging)
                        let merged = try await api.brief(content: "以下 JSON 为分段笔记数据，请合并，保留原文 [uN] 引用：\n" + String(decoding: data, as: UTF8.self), meeting: value.id, price: price)
                        guard MeetingProtocol.hasValidReferences(merged, segments: value.segments) else { throw AppFailure("合并笔记的引用校验未通过，分段笔记仍保留。", code: "meeting_brief_references") }
                        edit { $0.brief = merged }
                    }
                }
                edit { $0.state = "ready"; $0.briefNeedsUpdate = false }; busy = false; message = "会议笔记已保存。可复制；开启溯源编号后可编辑原稿并核对原文。"
            } catch { busy = false; fail(error) }
        }
    }
    func suggestNames() {
        guard let value = current, !value.segments.isEmpty, namingMeetingID == nil else { return }
        namingMeetingID = value.id
        namingTask = Task {
            defer { namingMeetingID = nil }
            do {
                let prefs = ledger.database.preferences
                let price = PriceSnapshot(version: "meeting-naming-v1", currency: "CNY", inputPerMillion: prefs.flashInput, cachedPerMillion: prefs.flashCached, outputPerMillion: prefs.flashOutput, note: "会议命名候选")
                let result = try await api.brief(content: MeetingNaming.envelope(value), meeting: value.id, price: price, system: MeetingNaming.prompt, usageModel: "deepseek-flash-meeting-naming", maxTokens: 512)
                try Task.checkCancellation()
                let names = try MeetingNaming.candidates(result, created: value.created)
                guard var latest = store.index.meetings.first(where: { $0.id == value.id }) else { return }
                latest.nameCandidates = names; try store.save(latest)
                if active?.id == latest.id { active = latest }
                if current?.id == value.id { message = "已生成 3 个候选名称，点选后用于标题及导出文件名。" }
            } catch { if current?.id == value.id, !(error is CancellationError) { message = "候选名称生成失败，可稍后重试；原会议内容保留。" } }
        }
    }
    func applyName(_ name: String) {
        guard let value = current, value.nameCandidates?.contains(name) == true else { return }
        let used = Set(store.index.meetings.filter { $0.id != value.id }.compactMap(\.fileStem))
        var stem = name, suffix = 2
        while used.contains(stem) { stem = name + "-\(suffix)"; suffix += 1 }
        edit { $0.title = stem; $0.fileStem = stem }
    }
    func exportAudio() {
        guard let value = current, !recording, !audioExporting, FileManager.default.fileExists(atPath: store.audio(value.id).path) else { message = "请等待录音保存完成后再导出音频。"; return }
        let save = NSSavePanel(); save.allowedContentTypes = [.mpeg4Audio]
        save.nameFieldStringValue = MeetingNaming.stem(value) + ".m4a"; save.canCreateDirectories = true
        guard let window = presentationWindow() else { message = "请在主窗口中导出。"; return }
        audioExporting = true
        save.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .OK, let destination = save.url else { audioExporting = false; return }
            exportTask = Task {
                defer { self.audioExporting = false }
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("utterleaf-export-" + UUID().uuidString + ".m4a")
                let staged = destination.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".m4a")
                defer { try? FileManager.default.removeItem(at: temporary); try? FileManager.default.removeItem(at: staged) }
                do {
                    try await MeetingAudioExport.convert(source: self.store.originalAudio(value.id) ?? self.store.audio(value.id), destination: temporary)
                    try Task.checkCancellation()
                    try FileManager.default.copyItem(at: temporary, to: staged)
                    if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged) }
                    else { try FileManager.default.moveItem(at: staged, to: destination) }
                    self.message = "M4A 已导出，原始录音保留。"
                } catch { self.message = "M4A 导出失败，原始录音与目标文件已保留。" }
            }
        }
    }
    func stopWaiting() { guard !recording, canStopWaiting else { return }; operation?.cancel() }
    private func fail(_ error: Error) {
        let failure = safeFailure(error); message = failure.message
        recording = false; onCaptureState?(false, elapsed, false); tick?.cancel(); finishLive()
        edit { $0.state = "failed"; $0.failureCode = failure.code }
    }
    func refreshVoices() {
        guard !voiceBusy else { return }; voiceBusy = true
        Task {
            defer { voiceBusy = false }
            do {
                var values = try await api.listVoices()
                for i in values.indices { values[i].enabled = store.index.voices.first { $0.id == values[i].id }?.enabled ?? true }
                try store.saveVoices(values); try store.markVoiceMutation(false); message = "声纹名单已核对；特征向量不下载到本机。"
            } catch { message = safeFailure(error).message }
        }
    }
    func registerVoice(name: String, url: String) {
        guard store.index.voiceMutationUncertain != true else { message = "上次声纹注册结果不明确，请先刷新名单核对。"; return }
        guard !voiceBusy, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let audioURL: String
        do { audioURL = try MeetingProtocol.signedAudioURL(url).absoluteString }
        catch { message = "请提供 HTTPS 音频签名 URL，音频应为 5–30 秒清晰单人语音。"; return }
        voiceBusy = true
        Task {
            defer { voiceBusy = false }
            do {
                try store.markVoiceMutation(true)
                let result = try await api.voiceprint(action: "UpdateVoiceprint", body: ["Action": 0, "AudioUrl": audioURL, "SpeakerName": name.trimmingCharacters(in: .whitespacesAndNewlines)])
                guard let id = result["SpeakId"] as? String, !id.isEmpty else { throw AppFailure("声纹注册结果不明确，请刷新列表核对，避免重复注册。", code: "voiceprint_registration_unknown") }
                var voices = store.index.voices; voices.append(.init(id: id, name: name)); try store.saveVoices(voices); try store.markVoiceMutation(false)
                message = "声纹注册成功，下一次会议会带上此身份。"
            } catch { message = "声纹注册未确认。请先刷新列表核对，不要直接重复注册。" }
        }
    }
    func updateVoice(_ value: VoiceIdentity, delete: Bool = false) {
        guard !voiceBusy else { return }; voiceBusy = true
        Task {
            defer { voiceBusy = false }
            do {
                var body: [String: Any] = ["Action": delete ? 2 : 1, "SpeakId": value.id]
                if !delete { body["SpeakerName"] = value.name }
                _ = try await api.voiceprint(action: "UpdateVoiceprint", body: body)
                var values = store.index.voices.filter { $0.id != value.id }; if !delete { values.append(value) }
                try store.saveVoices(values); message = delete ? "已从可用声纹中移除；供应商为软删除，不代表物理清除。" : "声纹姓名已更新。"
            } catch { message = safeFailure(error).message }
        }
    }
    func toggleVoice(_ voice: VoiceIdentity) {
        var values = store.index.voices
        if let i = values.firstIndex(where: { $0.id == voice.id }) { values[i].enabled.toggle() }
        do { try store.saveVoices(values) } catch { message = store.error ?? "名单保存失败。" }
    }
    func playback(at seconds: Double = 0) {
        guard let value = current, !recording else { return }
        do { player = try AVAudioPlayer(contentsOf: store.originalAudio(value.id) ?? store.audio(value.id)); player?.currentTime = seconds; player?.play() }
        catch { message = "无法回听，请先恢复录音，或检查音频是否已删除。" }
    }
    func stopPlayback() { player?.stop(); player = nil }
    var costSummary: String {
        guard let value = current else { return "" }
        let calls = ledger.database.calls.filter { $0.jobID == value.id }
        let cost = calls.compactMap(\.estimatedAmount).reduce(0, +)
        let unknown = calls.filter { $0.estimatedAmount == nil }.count
        return String(format: "本场已知估算 ¥%.2f · %d 次 API 调用", cost, calls.count) + (unknown > 0 ? " · \(unknown) 次金额待定" : "")
    }
    func deleteMeeting() {
        guard let value = current, !blocksDictation else { return }
        do { stopPlayback(); draftSave?.cancel(); try store.delete(value.id); active = nil; selected = nil; message = "已删除本机会议内容，API 用量仍保留。声纹库不受影响。" }
        catch { message = "会议未完整删除，请检查本机存储后重试。" }
    }
    func deleteAudio() {
        guard let value = current, !blocksDictation else { return }
        do { stopPlayback(); try store.deleteAudio(value.id); message = "本机音频已删除，文字记录仍保留。" }
        catch { message = "音频未完整删除，请检查本机文件权限。" }
    }
    func shutdown() { exportTask?.cancel(); namingTask?.cancel(); flushDraft(); if recording { edit { $0.state = "interrupted"; $0.seconds = elapsed } }; tick?.cancel(); operation?.cancel(); liveSessions.values.forEach { $0.cancel() }; recorder.shutdown(); stopPlayback() }
}
