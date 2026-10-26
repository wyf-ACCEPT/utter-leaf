import AVFoundation
import Flutter
import UIKit

@MainActor final class DictationCoordinator: NSObject {
    static let shared = DictationCoordinator()
    private let provider = MobileProvider()
    private var engine: AVAudioEngine?
    private var timer: Timer?
    private var work: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var buffer = Data()
    private var generation = UUID()
    private var started: Date?
    private var requestID = UUID().uuidString
    private var fromKeyboard = false
    private var host: String?
    private var returnStatus = ""
    private var lastCommand = ""
    private var background: UIBackgroundTaskIdentifier = .invalid
    private(set) var phase = "idle"
    private var text = "", raw = "", error = ""
    private var level = 0.0
    private var elapsed = 0
    private var prompt: String {
        guard let url = Bundle.main.url(forResource: "cleanup", withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    override init() {
        super.init()
        #if UTTERLEAF_NAVIGATION_TEST
        error = "当前为跳转测试版：不录音、不调用 API。请从原 App 的言叶键盘点击开始。"
        #endif
        PersonalKeys.importPersonalBundle()
        // A terminated recorder never leaves a live command that can restart the microphone.
        let old = DictationExchange.read("state")
        if ["starting", "recording", "processing"].contains(old["phase"] as? String ?? "") {
            try? DictationExchange.write(["phase": "error", "error": "上次录音已中断，请重新开始。", "requestID": old["requestID"] ?? "", "updated": Date().timeIntervalSince1970], to: "state")
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
    }
    func attach(_ messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "network.utterleaf/dictation", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return }
            switch call.method {
            case "snapshot": result(self.snapshot)
            case "start": self.start(); result(nil)
            case "stop": self.stop(); result(nil)
            case "cancel": self.cancel(); result(nil)
            case "retry": self.retry(); result(nil)
            case "return":
                Task { let sent = await KeyboardReturn.attempt(host: self.host); self.returnStatus = sent ? "requested" : "manual"; result(sent) }
            case "saveKeys":
                guard !["starting", "recording", "processing"].contains(self.phase) else { result(FlutterError(code: "busy", message: "请先结束录音。", details: nil)); return }
                do {
                    let args = call.arguments as? [String: String] ?? [:]
                    for key in PersonalKeys.allowed { if let value = args[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try PersonalKeys.save(key, value: value.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                    result(nil)
                } catch { result(FlutterError(code: "keychain", message: "凭证保存失败。", details: nil)) }
            case "settings": UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!); result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }
    var snapshot: [String: Any] {
        ["phase": phase, "text": text, "raw": raw, "error": error, "level": level, "seconds": elapsed,
         "fromKeyboard": fromKeyboard, "returnStatus": returnStatus, "doubaoConfigured": PersonalKeys.get("DOUBAO_API_KEY")?.isEmpty == false,
         "deepseekConfigured": PersonalKeys.get("DEEPSEEK_API_KEY")?.isEmpty == false]
    }
    private func publish() {
        try? DictationExchange.write(["requestID": requestID, "phase": phase, "text": text, "error": error,
            "seconds": elapsed, "updated": Date().timeIntervalSince1970], to: "state")
    }
    func open(_ url: URL) {
        guard url.scheme == "utterleaf", url.host == "dictate", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = parts.queryItems?.first(where: { $0.name == "request" })?.value, UUID(uuidString: id) != nil else { return }
        guard !["starting", "recording", "processing"].contains(phase) else { return }
        let ticket = DictationExchange.read("handoff")
        guard ticket["requestID"] as? String == id, let created = ticket["created"] as? Double,
              Date().timeIntervalSince1970 >= created, Date().timeIntervalSince1970 - created < 30,
              UserDefaults.standard.string(forKey: "claimedHandoff") != id else {
            error = "输入法请求已过期，请返回原输入框重新点击开始说话。"; return
        }
        UserDefaults.standard.set(id, forKey: "claimedHandoff")
        host = ticket["host"] as? String
        #if targetEnvironment(simulator) || UTTERLEAF_NAVIGATION_TEST
        // Exercise real extension/host navigation in the simulator without recording or API calls.
        #if UTTERLEAF_NAVIGATION_TEST
        let navigationOnly = true
        #else
        let navigationOnly = ProcessInfo.processInfo.arguments.contains("--navigation-smoke")
        #endif
        if navigationOnly {
            Task {
                var target = host
                var fixedFixture = false
                #if targetEnvironment(simulator)
                if target == nil, ProcessInfo.processInfo.arguments.contains("--navigation-fixture") {
                    target = "network.utterleaf.navigation.fixture"; fixedFixture = true
                }
                #endif
                let returned = await KeyboardReturn.attempt(host: target)
                try? DictationExchange.write(["simulation": true, "returned": returned, "hostResolved": host != nil,
                    "fixedFixture": fixedFixture], to: "navigation-smoke")
            }
            return
        }
        #endif
        start(id: id, keyboard: true)
    }
    func start(id: String = UUID().uuidString, keyboard: Bool = false) {
        #if UTTERLEAF_NAVIGATION_TEST
        error = "跳转测试版不会录音。请从原 App 的言叶键盘开始测试。"; return
        #endif
        guard !["starting", "recording", "processing"].contains(phase) else { return }
        requestID = id; fromKeyboard = keyboard; generation = UUID()
        returnStatus = ""; if !keyboard { host = nil }
        lastCommand = DictationExchange.read("command")["id"] as? String ?? ""
        let token = generation
        phase = "starting"; text = ""; raw = ""; error = ""; elapsed = 0; buffer.removeAll(); publish()
        work = Task {
            do {
                guard !prompt.isEmpty else { throw MobileFailure.message("整理规则未打包，请重新构建。") }
                let granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
                }
                guard generation == token else { return }
                guard granted else { throw MobileFailure.message("需要麦克风权限，请在系统设置中开启。") }
                try await provider.start()
                try Task.checkCancellation(); guard generation == token else { return }
                try beginAudio(token: token)
                started = Date(); phase = "recording"; publish()
                timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
                sender = Task {
                    do {
                        while !Task.isCancelled, generation == token, phase == "recording" {
                            try await Task.sleep(nanoseconds: 200_000_000)
                            try Task.checkCancellation()
                            let chunk = buffer; buffer.removeAll(keepingCapacity: true)
                            if !chunk.isEmpty { try await provider.send(chunk) }
                        }
                    } catch { if generation == token, phase == "recording", !Task.isCancelled { fail(error) } }
                }
                if fromKeyboard {
                    // Wait for a real running audio engine before leaving the foreground.
                    try await Task.sleep(nanoseconds: 220_000_000)
                    try Task.checkCancellation()
                    if generation == token, phase == "recording" {
                        let sent = await KeyboardReturn.attempt(host: host)
                        returnStatus = sent ? "requested" : "manual"
                    }
                }
            } catch { if generation == token, !Task.isCancelled { fail(error) } }
        }
    }
    private func beginAudio(token: UUID) throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setActive(true)
        let engine = AVAudioEngine(), input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: source, to: target) else { throw MobileFailure.message("当前麦克风不可用。") }
        input.installTap(onBus: 0, bufferSize: 4096, format: source) { [weak self] block, _ in
            let capacity = AVAudioFrameCount(Double(block.frameLength) * 16000 / source.sampleRate) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false, conversionError: NSError?
            converter.convert(to: output, error: &conversionError) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return block
            }
            guard conversionError == nil, let samples = output.int16ChannelData?.pointee, output.frameLength > 0 else { return }
            let count = Int(output.frameLength)
            let data = Data(bytes: samples, count: count * 2)
            var sum = 0.0
            for n in 0..<count { let v = Double(samples[n]) / 32768; sum += v * v }
            let rms = sqrt(sum / Double(count))
            Task { @MainActor in
                guard let self, self.generation == token, self.phase == "recording" else { return }
                self.buffer.append(data); self.level = min(1, max(0, (20 * log10(max(rms, 0.00001)) + 50) / 42))
                if self.buffer.count > 32000 * 8 { self.fail(MobileFailure.message("网络过慢，录音已停止，请重试。")) }
            }
        }
        self.engine = engine
        engine.prepare(); try engine.start()
    }
    private func tick() {
        guard ["recording", "processing"].contains(phase) else { return }
        let command = DictationExchange.read("command")
        if command["requestID"] as? String == requestID, let id = command["id"] as? String, id != lastCommand {
            lastCommand = id
            if command["action"] as? String == "stop", phase == "recording" { stop(); return }
            else if command["action"] as? String == "cancel" { cancel(); return }
        }
        guard phase == "recording" else { return }
        elapsed = Int(Date().timeIntervalSince(started ?? Date())); publish()
        if elapsed >= 300 { stop() }
    }
    func stop() {
        guard phase == "recording" else { return }
        phase = "processing"; stopAudio(); publish()
        let pendingSender = sender, token = generation
        beginBackground()
        work = Task {
            do {
                await pendingSender?.value
                try Task.checkCancellation(); guard generation == token else { return }
                let chunk = buffer; buffer.removeAll()
                try await provider.send(chunk, final: true)
                let recognized = try await provider.finish()
                guard generation == token else { return }
                raw = recognized
                text = try await provider.clean(recognized, prompt: prompt)
                try Task.checkCancellation(); guard generation == token else { return }
                phase = "ready"; publish(); endBackground()
            } catch { if generation == token, !Task.isCancelled { fail(error) } }
        }
    }
    func retry() {
        guard phase == "error", !raw.isEmpty else { return }
        phase = "processing"; error = ""; publish(); let token = generation; beginBackground()
        work = Task {
            do { let result = try await provider.clean(raw, prompt: prompt); guard generation == token else { return }; text = result; phase = "ready"; publish(); endBackground() }
            catch { if generation == token, !Task.isCancelled { fail(error) } }
        }
    }
    func cancel() {
        generation = UUID(); work?.cancel(); sender?.cancel(); provider.cancel(); stopAudio(); buffer.removeAll()
        phase = "cancelled"; text = ""; raw = ""; error = ""; publish(); endBackground()
    }
    private func fail(_ failure: Error) {
        sender?.cancel(); provider.cancel(); stopAudio(); buffer.removeAll(); phase = "error"
        error = (failure as? MobileFailure)?.localizedDescription ?? "连接或录音中断，请检查网络和个人 API Key 后重试。"
        publish(); endBackground()
    }
    private func stopAudio() {
        timer?.invalidate(); timer = nil; engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil; level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func beginBackground() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        }
        background = UIApplication.shared.beginBackgroundTask(withName: "Finish dictation") { [weak self] in
            Task { @MainActor in self?.work?.cancel(); self?.fail(MobileFailure.message("系统暂停了后台整理，请回到言叶重试；原始文字已保留。")) }
        }
    }
    private func endBackground() {
        timer?.invalidate(); timer = nil
        if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
    }
    @objc private func interrupted(_ note: Notification) {
        if ["starting", "recording", "processing"].contains(phase) { work?.cancel(); fail(MobileFailure.message("录音被来电或音频设备打断，请重新开始。")) }
    }
}
