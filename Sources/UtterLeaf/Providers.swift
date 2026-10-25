import Foundation
import UtterLeafCore

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class Providers {
    private let delegate = NoRedirectDelegate()
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = Double(RecordingLimit.seconds + 120)
        config.urlCache = nil; config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    var socket: URLSessionWebSocketTask?
    var receiver: Task<String, Error>?
    var timeout: Task<Void, Never>?
    var sentBytes = 0
    var sequence: Int32 = 2
    var currentCall: UsageCall?
    var onCall: ((UsageCall) -> Void)?
    var onPartial: ((String) -> Void)?
    func record(_ call: UsageCall) { currentCall = call; onCall?(call) }
    func finishCall(error: Error? = nil) {
        guard var call = currentCall, call.status == .pending else { return }
        call.finished = Date()
        if let error {
            let failure = safeFailure(error)
            call.status = failure.code == "cancelled" ? .cancelled : .failed
            call.errorCode = failure.code
            // Estimate only from acknowledged sent audio or returned token usage.
        } else {
            call.status = .succeeded
            call.estimatedAmount = call.price.estimate(seconds: call.seconds, input: call.inputTokens, cached: call.cachedTokens, output: call.outputTokens)
        }
        call.fillLocalEstimate(); record(call)
    }
    func startStream(pipeline: ASRPipeline, job: UUID, price: PriceSnapshot) async throws {
        let secret = try Credentials.load("DOUBAO_API_KEY")
        let call = UsageCall(jobID: job, provider: "Doubao", model: pipeline.rawValue, price: price)
        record(call); sentBytes = 0; sequence = 2
        var request = URLRequest(url: URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/" + pipeline.route)!)
        request.setValue(secret, forHTTPHeaderField: "X-Api-Key")
        request.setValue(pipeline.resource, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(call.requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(call.requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        let ws = session.webSocketTask(with: request); ws.maximumMessageSize = 8 * 1024 * 1024
        socket = ws; ws.resume()
        let config: [String: Any] = ["user": ["uid": "utterleaf-personal"],
            "audio": ["format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1],
            "request": ["model_name": "bigmodel", "enable_itn": true, "enable_punc": true, "enable_ddc": false, "show_utterances": true]]
        do {
            try await ws.send(.data(DoubaoWire.encode(kind: 1, sequence: 1, payload: JSONSerialization.data(withJSONObject: config))))
            try Task.checkCancellation()
            receiver = Task { [weak self] in
                var latest = ""
                for _ in 0..<5000 {
                    try Task.checkCancellation()
                    let message = try await ws.receive()
                    guard case .data(let data) = message else { throw AppFailure("ASR 返回了不支持的数据。", code: "ws_text_frame") }
                    let response = try DoubaoWire.decode(data)
                    if response.code != 0 { throw AppFailure("ASR 返回错误 \(response.code)。请检查语音资源权限。", code: "asr_\(response.code)") }
                    if let text = (response.body["result"] as? [String: Any])?["text"] as? String {
                        latest = text; self?.onPartial?(text)
                    }
                    if response.final { return latest }
                }
                throw AppFailure("ASR 返回包过多。", code: "ws_packet_limit")
            }
        } catch { finishCall(error: error); ws.cancel(with: .goingAway, reason: nil); throw error }
    }
    func send(_ data: Data, final: Bool = false) async throws {
        guard let ws = socket else { throw AppFailure("语音连接已关闭。", code: "ws_closed") }
        try Task.checkCancellation()
        try await ws.send(.data(DoubaoWire.encode(kind: 2, sequence: sequence, payload: data, final: final)))
        sequence += 1; sentBytes += data.count
        if var call = currentCall {
            let before = Int(call.seconds / 5); call.seconds = Double(sentBytes) / 32000; call.submittedSeconds = call.seconds
            currentCall = call
            if final || Int(call.seconds / 5) != before { onCall?(call) }
        }
    }
    func endStream() async throws -> String {
        guard let ws = socket, let receiver else { throw AppFailure("语音连接未建立。", code: "ws_missing") }
        timeout = Task {
            try? await Task.sleep(for: .seconds(35))
            if !Task.isCancelled { ws.cancel(with: .goingAway, reason: nil) }
        }
        defer { timeout?.cancel(); ws.cancel(with: .normalClosure, reason: nil); self.receiver = nil; socket = nil }
        do {
            let text = try await receiver.value
            try Task.checkCancellation()
            if var call = currentCall, let http = ws.response as? HTTPURLResponse {
                call.httpStatus = http.statusCode; call.logID = http.value(forHTTPHeaderField: "X-Tt-Logid"); record(call)
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure("没有识别到文字，请检查麦克风后重试。", code: "asr_empty") }
            finishCall(); return text
        } catch { finishCall(error: error); throw error }
    }
    func cancel() {
        timeout?.cancel(); receiver?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        socket = nil; receiver = nil; finishCall(error: CancellationError())
    }
    private func post(_ url: URL, body: [String: Any], headers: [String: String]) async throws -> ([String: Any], HTTPURLResponse) {
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppFailure("服务未返回 HTTP 状态。", code: "http_missing") }
        if var call = currentCall {
            call.httpStatus = http.statusCode
            call.logID = http.value(forHTTPHeaderField: "X-Tt-Logid")
            call.providerStatus = http.value(forHTTPHeaderField: "X-Api-Status-Code"); record(call)
        }
        guard (200..<300).contains(http.statusCode) else { throw AppFailure("API 请求失败（HTTP \(http.statusCode)）。请检查个人凭证与额度。", code: "http_\(http.statusCode)") }
        guard data.count < 8 * 1024 * 1024, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppFailure("API 返回格式不正确。", code: "invalid_json")
        }
        return (json, http)
    }
    func fileASR(pcm: Data, job: UUID, price: PriceSnapshot) async throws -> String {
        let secret = try Credentials.load("DOUBAO_API_KEY")
        var call = UsageCall(jobID: job, provider: "Doubao", model: ASRPipeline.file.rawValue, price: price)
        call.seconds = Double(pcm.count) / 32000; record(call)
        let headers = ["X-Api-Key": secret, "X-Api-Resource-Id": ASRPipeline.file.resource,
            "X-Api-Request-Id": call.requestID, "X-Api-Sequence": "-1"]
        let base = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/"
        do {
            let body: [String: Any] = ["user": ["uid": "utterleaf-personal"],
                "audio": ["data": DoubaoWire.wav(pcm).base64EncodedString(), "format": "wav"],
                "request": ["model_name": "bigmodel", "enable_itn": true, "enable_punc": true, "enable_ddc": false, "show_utterances": true]]
            let (_, submit) = try await post(URL(string: base + "submit")!, body: body, headers: headers)
            if var submitted = currentCall { submitted.submittedSeconds = call.seconds; record(submitted) }
            guard submit.value(forHTTPHeaderField: "X-Api-Status-Code") == "20000000" else {
                throw AppFailure("文件 ASR 提交失败。audio.data 为已实测接法，官方 schema 主要支持 URL。可切换流式模式。", code: "file_submit_rejected")
            }
            for _ in 0..<90 {
                try await Task.sleep(for: .seconds(1)); try Task.checkCancellation()
                let (json, response) = try await post(URL(string: base + "query")!, body: [:], headers: headers)
                let code = response.value(forHTTPHeaderField: "X-Api-Status-Code") ?? "missing"
                if ["20000001", "20000002"].contains(code) { continue }
                guard code == "20000000" else { throw AppFailure("文件 ASR 返回状态 \(code)。", code: "file_\(code)") }
                let text = (json["result"] as? [String: Any])?["text"] as? String ?? ""
                guard !text.isEmpty else { throw AppFailure("没有识别到文字。", code: "asr_empty") }
                finishCall(); return text
            }
            throw AppFailure("文件识别等待超时；服务端可能仍在处理并计费。", code: "file_timeout")
        } catch { finishCall(error: error); throw error }
    }
    func cleanup(text: String, prompt: String, job: UUID, price: PriceSnapshot, vocabulary: [VocabularyEntry] = []) async throws -> String {
        let secret = try Credentials.load("DEEPSEEK_API_KEY")
        var call = UsageCall(jobID: job, provider: "DeepSeek", model: "deepseek-flash", price: price)
        let effectivePrompt = CleanupPrompt.compose(prompt, entries: vocabulary)
        call.promptHash = TextEnvelope.hash(effectivePrompt); call.vocabularyHash = VocabularyContext.hash(vocabulary); record(call)
        do {
            let body: [String: Any] = ["model": "deepseek-flash", "thinking": ["type": "disabled"], "max_tokens": 8192,
                "messages": [["role": "system", "content": effectivePrompt], ["role": "user", "content": try TextEnvelope.wrap(text, vocabulary: vocabulary)]]]
            let (json, _) = try await post(URL(string: "https://api.deepseek.com/chat/completions")!, body: body,
                                         headers: ["Authorization": "Bearer " + secret])
            if var updated = currentCall {
                let usage = json["usage"] as? [String: Any] ?? [:]
                updated.inputTokens = usage["prompt_tokens"] as? Int
                updated.cachedTokens = usage["prompt_cache_hit_tokens"] as? Int
                    ?? (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int
                updated.outputTokens = usage["completion_tokens"] as? Int
                updated.responseID = json["id"] as? String; updated.returnedModel = json["model"] as? String
                updated.estimatedAmount = price.estimate(seconds: 0, input: updated.inputTokens, cached: updated.cachedTokens, output: updated.outputTokens)
                record(updated)
            }
            guard let choice = (json["choices"] as? [[String: Any]])?.first,
                  choice["finish_reason"] as? String == "stop",
                  let result = (choice["message"] as? [String: Any])?["content"] as? String else {
                throw AppFailure("整理稿未完整返回。原始转写已保留，可重试整理。", code: "cleanup_incomplete")
            }
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppFailure("整理稿为空。可保留原始转写或重试整理。", code: "cleanup_empty")
            }
            try Task.checkCancellation(); finishCall(); return result
        } catch { finishCall(error: error); throw error }
    }
}
