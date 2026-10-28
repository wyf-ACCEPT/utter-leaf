import Foundation

enum MobileFailure: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor final class MobileProvider {
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<String, Error>?
    private var sequence: Int32 = 2
    private var usageCall: CloudUsageRow?
    private var usageJob: CloudUsageRow?
    private var sentSeconds = 0.0
    private var checkpointSeconds = 0.0
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 40
        config.timeoutIntervalForResource = 420
        config.urlCache = nil; config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: MobileNoRedirect(), delegateQueue: nil)
    }()
    func start(jobID: String) async throws {
        guard let key = PersonalKeys.get("DOUBAO_API_KEY"), !key.isEmpty else { throw MobileFailure.message("请先配置个人豆包 Key。") }
        guard PersonalKeys.get("DEEPSEEK_API_KEY")?.isEmpty == false else { throw MobileFailure.message("请先配置个人 DeepSeek Key。") }
        sentSeconds = 0; checkpointSeconds = 0
        let ledger = MobileUsage.store
        var job = ledger.row(id: "job." + jobID.lowercased(), kind: "job")
        job.started = Date().timeIntervalSince1970; job.purpose = "dictation"; job.characters = 0; job.seconds = 0
        usageJob = job; ledger.ingest(job)
        var call = ledger.row(id: "call." + UUID().uuidString.lowercased(), kind: "call")
        call.job = jobID.lowercased(); call.started = job.started; call.purpose = "dictation"
        call.provider = "Doubao"; call.model = "v2-final"; call.currency = "CNY"; call.status = "pending"
        usageCall = call; ledger.ingest(call)
        var request = URLRequest(url: URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")!)
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.setValue("volc.seedasr.sauc.duration", forHTTPHeaderField: "X-Api-Resource-Id")
        let id = UUID().uuidString
        request.setValue(id, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(id, forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        let ws = session.webSocketTask(with: request); ws.maximumMessageSize = 8 * 1024 * 1024
        socket = ws; sequence = 2; ws.resume()
        let config: [String: Any] = ["user": ["uid": "utterleaf-ios-personal"],
            "audio": ["format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1],
            "request": ["model_name": "bigmodel", "enable_itn": true, "enable_punc": true, "enable_ddc": false]]
        try await ws.send(.data(DoubaoWire.encode(kind: 1, sequence: 1, payload: JSONSerialization.data(withJSONObject: config))))
        guard usageCall?.id == call.id else { ws.cancel(with: .goingAway, reason: nil); throw CancellationError() }
        receiver = Task {
            var text = ""
            for _ in 0..<5000 {
                try Task.checkCancellation()
                guard case .data(let data) = try await ws.receive() else { throw MobileFailure.message("语音服务返回格式不正确。") }
                let response = try DoubaoWire.decode(data)
                guard response.code == 0 else { throw MobileFailure.message("豆包识别失败（\(response.code)）。") }
                if let next = (response.body["result"] as? [String: Any])?["text"] as? String { text = next }
                if response.final { return text }
            }
            throw MobileFailure.message("语音服务返回过多数据，请重试。")
        }
    }
    private func checkpoint(status: String) {
        guard var call = usageCall, call.status == "pending" else { return }
        call.seconds = sentSeconds; call.amount = sentSeconds > 0 ? sentSeconds / 3600 : nil
        call.status = status; usageCall = call; MobileUsage.store.ingest(call)
        if var job = usageJob { job.seconds = sentSeconds; usageJob = job; MobileUsage.store.ingest(job) }
    }
    func send(_ pcm: Data, final: Bool = false) async throws {
        guard let socket else { throw MobileFailure.message("语音连接已关闭。") }
        let callID = usageCall?.id
        do {
            try await socket.send(.data(DoubaoWire.encode(kind: 2, sequence: sequence, payload: pcm, final: final)))
            guard usageCall?.id == callID else { return }
            sequence += 1; sentSeconds += Double(pcm.count) / 32000
            if final || sentSeconds - checkpointSeconds >= 1 {
                checkpointSeconds = sentSeconds; checkpoint(status: "pending")
            }
        } catch { if usageCall?.id == callID { checkpoint(status: "failed") }; throw error }
    }
    func finish() async throws -> String {
        guard let receiver, let socket else { throw MobileFailure.message("语音连接未建立。") }
        let callID = usageCall?.id
        let timeout = Task { try? await Task.sleep(nanoseconds: 40_000_000_000); if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) } }
        defer { timeout.cancel(); socket.cancel(with: .normalClosure, reason: nil); if usageCall?.id == callID { self.receiver = nil; self.socket = nil } }
        do {
            let text = try await receiver.value
            if usageCall?.id == callID { checkpoint(status: "succeeded") }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MobileFailure.message("没有识别到文字。") }
            return text
        } catch { if usageCall?.id == callID { checkpoint(status: "failed") }; throw error }
    }
    func clean(_ text: String, prompt: String) async throws -> String {
        guard let key = PersonalKeys.get("DEEPSEEK_API_KEY") else { throw MobileFailure.message("缺少 DeepSeek Key。") }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let envelope = String(data: try JSONSerialization.data(withJSONObject: ["transcript": text]), encoding: .utf8)!
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "deepseek-flash", "thinking": ["type": "disabled"], "max_tokens": 8192,
            "messages": [["role": "system", "content": prompt], ["role": "user", "content": envelope]]])
        let ledger = MobileUsage.store
        let targetJob = usageJob
        var call = ledger.row(id: "call." + UUID().uuidString.lowercased(), kind: "call")
        call.job = targetJob.map { String($0.id.dropFirst(4)) } ?? UUID().uuidString.lowercased()
        call.started = Date().timeIntervalSince1970; call.purpose = "dictation"; call.provider = "DeepSeek"
        call.model = "deepseek-flash"; call.status = "pending"; call.currency = "CNY"; ledger.ingest(call)
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 8 * 1024 * 1024,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MobileFailure.message("整理未完成，原始文字已保留，可复制或重试。")
            }
            if let usage = json["usage"] as? [String: Any], let input = usage["prompt_tokens"] as? Int, input >= 0,
               let output = usage["completion_tokens"] as? Int, output >= 0 {
                let cached = min(input, max(0, usage["prompt_cache_hit_tokens"] as? Int ?? 0))
                call.input = input; call.cached = cached; call.output = output
                // Dated CNY reference configuration, matching the desktop default; not an actual bill.
                call.amount = (Double(input - cached) * 2 + Double(cached) * 0.04 + Double(output) * 8) / 1_000_000
            }
            guard let choice = (json["choices"] as? [[String: Any]])?.first, choice["finish_reason"] as? String == "stop",
                  let result = (choice["message"] as? [String: Any])?["content"] as? String, !result.isEmpty else {
                throw MobileFailure.message("整理未完成，原始文字已保留，可复制或重试。")
            }
            call.status = "succeeded"; ledger.ingest(call)
            if var job = targetJob { job.characters = result.unicodeScalars.count; if usageJob?.id == job.id { usageJob = job }; ledger.ingest(job) }
            return result
        } catch { call.status = Task.isCancelled ? "cancelled" : "failed"; ledger.ingest(call); throw error }
    }

    func cancel(failed: Bool = false) { checkpoint(status: failed ? "failed" : "cancelled"); receiver?.cancel(); socket?.cancel(with: .goingAway, reason: nil); socket = nil; receiver = nil }
}

private final class MobileNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
