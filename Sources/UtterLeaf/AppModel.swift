import AppKit
import SwiftUI
import UtterLeafCore

@MainActor final class AppModel: ObservableObject {
    enum Phase: String { case idle, starting, recording, transcribing, cleaning, inserting, preview, error }
    @Published var promptEditorDraft: String?
    @Published var phase: Phase = .idle
    @Published var partial = ""
    @Published var draft = ""
    @Published var raw = ""
    @Published var message = ""
    @Published var elapsed: Double = 0
    var level: Float = 0
    @Published var route = "听写"
    @Published var hotkeyRegistered = true
    @Published var inserting = false
    var pillOutcome: PillPresentation.Stage = .cancelled
    lazy var meetings: MeetingModel = {
        let value = MeetingModel(ledger: store)
        value.dictationBusy = { [weak self] in self?.busy ?? false }
        return value
    }()
    let store: LocalStore
    private let captureTarget: (@MainActor () -> (any DictationTarget)?)?
    private var jobAutomatic = true
    private var activeVocabulary: [VocabularyEntry] = []
    let waveform = LiveAudioMeter()
    let sounds = SoundFeedback()
    private var activeSound = SoundPreferences()
    private let mic = Microphone()
    private var api = Providers()
    private var target: (any DictationTarget)?
    private var job: HistoryJob?
    private var pcm = Data()
    private var chunkBuffer = Data()
    private var maxLevel: Float = 0
    private var activeToken = UUID()
    private var continuation: AsyncStream<Data>.Continuation?
    private var upload: Task<Void, Error>?
    private var operation: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    var showWindow: (() -> Void)?
    var onPhase: (() -> Void)?
    var busy: Bool { [.starting, .recording, .transcribing, .cleaning, .inserting].contains(phase) }
    var targetName: String { target?.displayName ?? "未捕获输入框" }
    init(store: LocalStore? = nil, captureTarget: (@MainActor () -> (any DictationTarget)?)? = nil) {
        self.store = store ?? LocalStore()
        self.captureTarget = captureTarget
        api.onCall = { [weak self] in self?.store.update($0) }
        api.onPartial = { [weak self] in self?.partial = $0 }
        mic.onDisconnect = { [weak self] in self?.abort(message: "麦克风设备发生变化，录音已停止。请重新开始。") }
    }
    func prompt() throws -> String {
        if let custom = store.database.preferences.customPrompt { return custom }
        guard let url = Bundle.main.url(forResource: "cleanup-v6-spoken-symbols", withExtension: "txt", subdirectory: "prompts") else {
            throw AppFailure("未找到 v6 prompt，请使用打包后的 UtterLeaf.app。", code: "prompt_missing")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
    func changePhase(_ value: Phase) { phase = value; onPhase?() }
    func toggle() {
        if phase == .recording { stop() }
        else if !busy { start() }
    }
    func start() {
        guard !meetings.usesMicrophone else { message = "会议正在录音，请先结束会议录音。"; return }
        guard !busy, !inserting else { return }
        guard let pipeline = store.database.preferences.pipeline else {
            route = "模型与设置"; message = "先选择这次试用的 ASR 管线。"; showWindow?(); return
        }
        guard store.storageError == nil else { message = store.storageError!; showWindow?(); return }
        preservePendingDraft()
        let pendingCapture = captureTarget == nil ? InputTarget.prepareCapture() : nil
        target = captureTarget?(); jobAutomatic = store.database.preferences.insertionMode != "preview"
        activeVocabulary = VocabularyContext.active(store.vocabulary); waveform.reset(); raw = ""; draft = ""; partial = ""; message = ""
        elapsed = 0; level = 0; maxLevel = 0; pcm = Data(); chunkBuffer = Data()
        activeSound = store.database.preferences.sound ?? SoundPreferences()
        let token = UUID(); activeToken = token
        let api = Providers(); self.api = api
        api.onCall = { [weak self] in self?.store.update($0) }
        api.onPartial = { [weak self] text in if self?.activeToken == token { self?.partial = text } }
        var current = HistoryJob(pipeline: pipeline); current.targetBundleID = target?.diagnosticID ?? pendingCapture?.bundleID; job = current; store.update(current)
        changePhase(.starting)
        operation = Task {
            do {
                if let pendingCapture {
                    self.target = try await pendingCapture.resolve()
                    guard self.activeToken == token else { return }
                    current.targetCaptureErrorCode = pendingCapture.errorCode
                    current.targetCaptureAttempts = pendingCapture.attempts
                    self.job = current; self.store.update(current)
                }
                // Validate local configuration before sending audio or starting the microphone.
                _ = try Credentials.load("DOUBAO_API_KEY")
                if self.store.database.preferences.cleanup { _ = try Credentials.load("DEEPSEEK_API_KEY"); _ = try self.prompt() }
                try await self.mic.ensurePermission(); try Task.checkCancellation()
                if pipeline != .file {
                    let price = PriceSnapshot.asr(pipeline, stream: self.store.database.preferences.streamPrice, file: self.store.database.preferences.filePrice)
                    try await api.startStream(pipeline: pipeline, job: current.id, price: price)
                    var continuation: AsyncStream<Data>.Continuation!
                    let stream = AsyncStream<Data> { continuation = $0 }
                    self.continuation = continuation
                    self.upload = Task {
                        do {
                            let clock = ContinuousClock()
                            var last = clock.now - .seconds(1)
                            for await chunk in stream {
                                try await clock.sleep(until: last + .milliseconds(200))
                                try Task.checkCancellation(); last = clock.now
                                try await api.send(chunk)
                            }
                            try Task.checkCancellation()
                            try await clock.sleep(until: last + .milliseconds(200))
                            try await api.send(self.chunkBuffer, final: true)
                        } catch {
                            api.finishCall(error: error)
                            if self.activeToken == token && self.phase == .recording { self.abort(message: safeFailure(error).message) }
                            throw error
                        }
                    }
                }
                try await self.sounds.beforeMicrophone(preferences: self.activeSound)
                guard self.activeToken == token else { return }
                self.mic.onChunk = { [weak self] data, rms in self?.accept(data, rms: rms, token: token) }
                try self.mic.start(); try Task.checkCancellation()
                guard self.activeToken == token else { self.mic.stop(); return }
                self.changePhase(.recording)
                self.watchdog = Task {
                    for tick in 0..<RecordingLimit.seconds {
                        try? await Task.sleep(for: .seconds(1))
                        if Task.isCancelled { return }
                        if self.phase == .recording {
                            if tick >= 4 && self.elapsed < 0.1 { self.abort(message: "麦克风没有产生音频数据，请检查输入设备后重试。"); return }
                            if self.elapsed >= Double(RecordingLimit.seconds) { self.stop(); return }
                        } else { return }
                    }
                    if self.phase == .recording { self.stop() }
                }
            } catch {
                if self.activeToken == token { api.cancel(); self.fail(error) }
            }
        }
    }
    private func accept(_ data: Data, rms: Float, token: UUID) {
        guard activeToken == token, phase == .recording || phase == .starting else { return }
        let count = RecordingLimit.acceptedBytes(buffered: pcm.count, incoming: data.count)
        let accepted = data.prefix(count)
        pcm.append(accepted)
        let seconds = Double(pcm.count) / 32000
        if Int(seconds) != Int(elapsed) { elapsed = seconds }
        waveform.append(rms: rms)
        level = rms; maxLevel = max(maxLevel, rms)
        if job?.pipeline != .file {
            chunkBuffer.append(accepted)
            while chunkBuffer.count >= 6400 {
                continuation?.yield(Data(chunkBuffer.prefix(6400))); chunkBuffer.removeFirst(6400)
            }
        }
        if pcm.count >= RecordingLimit.maximumPCMBytes { stop() }
    }
    func stop() {
        guard phase == .recording else { return }
        elapsed = Double(pcm.count) / 32000
        mic.stop(); mic.onChunk = nil; watchdog?.cancel(); continuation?.finish()
        sounds.play(.stop, preferences: activeSound)
        let token = activeToken
        let api = self.api
        if var job { job.seconds = elapsed; job.status = "processing"; self.job = job; store.update(job) }
        guard elapsed >= 0.3, maxLevel >= 0.001 else {
            upload?.cancel(); api.cancel(); fail(AppFailure("录音没有有效输入。请检查系统输入设备和音量后重试。", code: "silent_audio")); return
        }
        changePhase(.transcribing)
        operation = Task {
            do {
                guard let current = self.job else { return }
                let text: String
                if current.pipeline == .file {
                    text = try await api.fileASR(pcm: self.pcm, job: current.id,
                        price: .asr(.file, stream: self.store.database.preferences.streamPrice, file: self.store.database.preferences.filePrice))
                } else {
                    try await self.upload?.value
                    text = try await api.endStream()
                }
                try Task.checkCancellation(); guard self.activeToken == token else { return }
                self.pcm = Data(); self.raw = text
                if var job = self.job { job.rawText = text; job.rawCharacters = TextEnvelope.characters(text); self.job = job; self.store.update(job) }
                if self.store.database.preferences.cleanup { try await self.clean(token: token) }
                else { await self.deliver(text, automatic: self.jobAutomatic, token: token) }
            } catch { if self.activeToken == token { self.fail(error) } }
        }
    }
    private func clean(token: UUID, automatic: Bool? = nil) async throws {
        guard let current = job else { return }
        let prompt = try prompt()
        changePhase(.cleaning)
        var price = PriceSnapshot.flash
        let prefs = store.database.preferences
        price.inputPerMillion = prefs.flashInput; price.cachedPerMillion = prefs.flashCached; price.outputPerMillion = prefs.flashOutput
        if prefs.flashInput != 2 || prefs.flashCached != 0.04 || prefs.flashOutput != 8 {
            price.version = "user-" + ISO8601DateFormatter().string(from: Date()); price.note = "用户设置的 CNY / 百万 token 单价"
        }
        if var job { job.promptHash = TextEnvelope.hash(CleanupPrompt.compose(prompt, entries: activeVocabulary)); job.vocabularyHash = VocabularyContext.hash(activeVocabulary); job.promptVersion = (prefs.customPrompt == nil ? "cleanup-v6-spoken-symbols" : "custom-" + String(TextEnvelope.hash(prompt).prefix(12))) + (activeVocabulary.isEmpty ? "" : "+vocabulary-v1") + "+arabic-digits-v1"; self.job = job; store.update(job) }
        let cleaned = try await api.cleanup(text: raw, prompt: prompt, job: current.id, price: price, vocabulary: activeVocabulary)
        try Task.checkCancellation(); guard activeToken == token else { return }
        await deliver(cleaned, automatic: automatic ?? jobAutomatic, token: token)
    }
    func retryCleanup() {
        guard !busy, !raw.isEmpty else { return }
        let token = activeToken; message = ""; activeVocabulary = VocabularyContext.active(store.vocabulary)
        operation = Task { do { try await self.clean(token: token, automatic: false) } catch { if self.activeToken == token { self.fail(error) } } }
    }
    func useRaw() { guard !busy, !raw.isEmpty else { return }; setPreview(raw) }
    private func setPreview(_ text: String) {
        pillOutcome = .retained
        draft = text; persistDraft(status: "preview")
        changePhase(.preview); route = "听写"; showWindow?()
    }
    /// Completes one dictation without opening the app on successful automatic insertion.
    func deliver(_ text: String, automatic: Bool, token: UUID? = nil) async {
        if let token, token != activeToken { return }
        draft = text; persistDraft(status: "ready")
        if automatic { await performInsertion(automatic: true) }
        else { setPreview(text) }
    }
    func fail(_ error: Error) {
        elapsed = max(elapsed, Double(pcm.count) / 32000)
        let failure = safeFailure(error)
        // Brief empty recordings are usually accidental Fn gestures; retain usage without an alert.
        let quiet = elapsed <= 3 && ["asr_empty", "silent_audio"].contains(failure.code)
        if phase == .starting { sounds.stop() }
        pillOutcome = quiet ? .cancelled : .failed
        mic.stop(); mic.onChunk = nil; watchdog?.cancel(); pcm = Data()
        api.finishCall(error: error); api.cancel()
        message = quiet ? "" : failure.message
        if var job { job.status = "failed"; job.seconds = elapsed; self.job = job; store.update(job) }
        changePhase(quiet ? .idle : .error)
        if !quiet { showWindow?() }
    }
    func abort(message: String? = nil) {
        guard !inserting else { return }
        if !busy { if !draft.isEmpty { persistDraft(status: "saved") }; return }
        elapsed = max(elapsed, Double(pcm.count) / 32000)
        sounds.stop()
        activeToken = UUID(); operation?.cancel(); upload?.cancel(); watchdog?.cancel()
        mic.stop(); mic.onChunk = nil; continuation?.finish(); api.cancel(); pcm = Data(); chunkBuffer = Data()
        if var job { job.status = "cancelled"; job.seconds = elapsed; self.job = job; store.update(job) }
        pillOutcome = message == nil ? .cancelled : .failed
        self.message = message ?? "已取消。已发送给供应商的内容可能产生费用。"
        changePhase(message == nil ? .idle : .error)
    }
    func discard() { draft = ""; raw = ""; target = nil; job = nil; message = ""; changePhase(.idle) }
    func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft, forType: .string)
        persistDraft(status: "copied")
        draft = ""; raw = ""; target = nil; job = nil
        message = "已复制到剪贴板，可在原应用粘贴；也可以继续按 Fn 录音。"
        changePhase(.idle)
    }
    func preservePendingDraft() {
        if !draft.isEmpty { persistDraft(status: "saved") }
        draft = ""; raw = ""; target = nil; job = nil
        if phase == .preview || phase == .error { changePhase(.idle) }
    }
    func persistDraft(status: String? = nil) {
        if var job { if let status { job.status = status }; job.finalText = draft; job.finalCharacters = TextEnvelope.characters(draft); self.job = job; store.update(job) }
    }
    func insert() {
        guard !inserting, !busy, !draft.isEmpty else { return }
        operation = Task { await self.performInsertion(automatic: false) }
    }
    private func performInsertion(automatic: Bool) async {
        guard !inserting, !draft.isEmpty else { return }
        guard let target else {
            if var job {
                job.insertionErrorCode = job.targetCaptureErrorCode ?? "capture_missing"
                self.job = job; store.update(job)
            }
            let detail = job?.targetCaptureErrorCode == "capture_utterleaf_foreground"
                ? "开始时焦点在 UtterLeaf；请先点击原应用的输入框。"
                : "开始录音时未能读取原输入框；请点击目标输入框后再试。"
            message = detail + "文字已保留，可复制后粘贴。"
            setPreview(draft); return
        }
        inserting = true; persistDraft(status: "inserting"); changePhase(.inserting)
        defer { inserting = false }
        do {
            let method = try await target.insert(draft, allowActivation: !automatic)
            if var job {
                job.inserted = method != .pasteDispatched
                job.status = method == .pasteDispatched ? "paste_dispatched" : "inserted"
                job.insertionMethod = method.rawValue; store.update(job)
            }
            draft = ""; raw = ""; self.target = nil; job = nil
            if method != .pasteDispatched { sounds.play(.complete, preferences: activeSound) }
            pillOutcome = method == .pasteDispatched ? .pasteRequested : .inserted
            message = method == .pasteDispatched ? "已向 \(target.displayName) 发出粘贴；如未显示，可从听写历史复制。" : "已输入到 \(target.displayName)。"
            changePhase(.idle)
        } catch {
            let failure = safeFailure(error)
            if var job { job.insertionErrorCode = failure.code; self.job = job; store.update(job) }
            message = failure.message
            setPreview(draft)
        }
    }
    func captureDestination() { target = captureTarget?() }
}
