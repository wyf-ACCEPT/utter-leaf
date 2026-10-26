import Foundation
import UtterLeafCore

@MainActor final class MeetingAPI {
    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)
    private let credentials: (String) throws -> String
    private let fetch: Fetch?
    init(credentials: @escaping (String) throws -> String = Credentials.load, fetch: Fetch? = nil) {
        self.credentials = credentials; self.fetch = fetch
    }
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let fetch { return try await fetch(request) }
        return try await session.data(for: request)
    }
    private let delegate = NoRedirectDelegate()
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 900
        config.urlCache = nil; config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    var onRecognitionStatus: ((String) -> Void)?
    var onRawResult: ((Data) throws -> Void)?
    var onCall: ((UsageCall) -> Void)?
    private func request(_ url: String, key: String, resource: String? = nil, requestID: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!); request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let resource { request.setValue(resource, forHTTPHeaderField: "X-Api-Resource-Id") }
        if let requestID { request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id"); request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence") }
        return request
    }
    private func decode(_ data: Data, _ response: URLResponse) throws -> ([String: Any], HTTPURLResponse) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppFailure("会议 API 请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)），请检查个人凭证、权限和网络。", code: "meeting_http_\((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard data.count <= 32 * 1024 * 1024, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppFailure("会议 API 返回格式不正确。音频仍在本机。", code: "meeting_response")
        }
        return (json, http)
    }
    func voiceprint(action: String, body: [String: Any]) async throws -> [String: Any] {
        var call = UsageCall(jobID: UUID(), provider: "Doubao", model: "voiceprint-" + action,
            price: PriceSnapshot(version: "voiceprint-unpriced-v1", currency: "CNY", note: "声纹接口尚无可核实的逐次费率，金额未知"))
        onCall?(call)
        do {
            var req = request("https://openspeech.bytedance.com/api/proxy/invoke/?Action=" + action, key: try credentials("DOUBAO_API_KEY"))
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await perform(req)
            call.httpStatus = (response as? HTTPURLResponse)?.statusCode
            let (json, http) = try decode(data, response)
            call.httpStatus = http.statusCode
            let metadata = json["ResponseMetadata"] as? [String: Any]
            call.responseID = metadata?["RequestId"] as? String
            guard metadata?["Error"] == nil, let result = json["Result"] as? [String: Any], result["Code"] as? Int == 1000 else {
                throw AppFailure("豆包声纹操作未确认成功，请刷新核对权限和结果；不要反复注册。", code: "voiceprint_rejected")
            }
            call.status = .succeeded; call.finished = Date(); onCall?(call); return result
        } catch {
            call.status = .failed; call.errorCode = safeFailure(error).code; call.finished = Date(); onCall?(call); throw error
        }
    }
    func listVoices() async throws -> [VoiceIdentity] {
        var voices: [VoiceIdentity] = []
        for page in 0..<100 {
            let result = try await voiceprint(action: "ListVoiceprint", body: ["Limit": 50, "Offset": page])
            guard let rows = result["AudioEmbedding"] as? [[String: Any]], let total = result["TotalCount"] as? Int else { throw AppFailure("声纹列表不完整，已保留本地名单。", code: "voiceprint_list") }
            for row in rows {
                guard let id = row["SpeakId"] as? String, let name = row["SpeakerName"] as? String, !id.isEmpty, !name.isEmpty else {
                    throw AppFailure("声纹列表字段不完整，已保留本地名单。", code: "voiceprint_list")
                }
                if row["Status"] as? Int == 1 { voices.append(.init(id: id, name: name)) }
            }
            guard total >= 0, rows.count <= 50 else { throw AppFailure("声纹分页异常，已保留本地名单。", code: "voiceprint_pagination") }
            if (page + 1) * 50 >= total {
                guard voices.count == total, Set(voices.map(\.id)).count == voices.count else { throw AppFailure("声纹名单不完整或重复，已保留本地名单。", code: "voiceprint_pagination") }
                return voices
            }
            guard !rows.isEmpty else { break }
        }
        throw AppFailure("声纹列表过大或分页异常，已保留本地名单。", code: "voiceprint_pagination")
    }
    /// Build the experimental audio.data request as a private disk file in bounded memory.
    static func buildUpload(audio: URL, destination: URL, voices: [VoiceIdentity], seconds: Double? = nil) async throws {
        try await Task.detached(priority: .utility) {
            let source = try FileHandle(forReadingFrom: audio); defer { try? source.close() }
            FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
            try output.truncate(atOffset: 0)
            try output.write(contentsOf: Data("{\"user\":{\"uid\":\"utterleaf-personal\"},\"audio\":{\"format\":\"wav\",\"data\":\"".utf8))
            while let chunk = try source.read(upToCount: 49152), !chunk.isEmpty {
                try Task.checkCancellation(); try output.write(contentsOf: Data(chunk.base64EncodedString().utf8))
            }
            try output.write(contentsOf: Data("\"},\"request\":".utf8))
            let bytes = try audio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 44
            try output.write(contentsOf: JSONSerialization.data(withJSONObject: MeetingProtocol.request(voices: voices, seconds: seconds ?? Double(max(0, bytes - 44)) / 32000)))
            try output.write(contentsOf: Data("}".utf8)); try output.synchronize()
        }.value
    }
    func submit(upload: URL, call: UsageCall, progress: (@MainActor (Int) -> Void)? = nil) async throws -> UsageCall {
        var call = call; onCall?(call)
        let req = request("https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit", key: try credentials("DOUBAO_API_KEY"), resource: ASRPipeline.file.resource, requestID: call.requestID)
        let delegate = MeetingUploadProgress { percent in Task { @MainActor in progress?(percent) } }
        let data: Data, response: URLResponse
        if let fetch {
            var synthetic = req; synthetic.httpBody = try Data(contentsOf: upload)
            (data, response) = try await fetch(synthetic)
        } else { (data, response) = try await session.upload(for: req, fromFile: upload, delegate: delegate) }
        let (_, http) = try decode(data, response)
        call.httpStatus = http.statusCode; call.providerStatus = http.value(forHTTPHeaderField: "X-Api-Status-Code")
        call.logID = http.value(forHTTPHeaderField: "X-Tt-Logid")
        guard call.providerStatus == "20000000" else {
            call.status = .failed; call.finished = Date(); call.errorCode = "meeting_submit_rejected"; onCall?(call)
            throw AppFailure("会议文件提交被拒绝。audio.data 接法为实验兼容路径，音频仍在本机；请检查文件接口权限。", code: "meeting_submit_rejected")
        }
        call.submittedSeconds = call.seconds; onCall?(call); return call
    }
    func query(call: UsageCall) async throws -> (segments: [MeetingUtterance], data: Data)? {
        var call = call
        var req = request("https://openspeech.bytedance.com/api/v3/auc/bigmodel/query", key: try credentials("DOUBAO_API_KEY"), resource: ASRPipeline.file.resource, requestID: call.requestID)
        req.httpBody = Data("{}".utf8)
        let (data, response) = try await perform(req)
        let (json, http) = try decode(data, response)
        let code = http.value(forHTTPHeaderField: "X-Api-Status-Code") ?? "missing"
        call.providerStatus = code; call.httpStatus = http.statusCode
        onRecognitionStatus?(code)
        if ["20000001", "20000002"].contains(code) { return nil }
        guard code == "20000000" else {
            call.status = .failed; call.finished = Date(); call.errorCode = "meeting_query_" + code; onCall?(call)
            throw AppFailure("会议转录查询状态 \(code)。请求已保留，重新提交前需核对原任务。", code: "meeting_query_" + code)
        }
        call.status = .succeeded; call.finished = Date(); call.estimatedAmount = call.price.estimate(seconds: call.seconds, input: nil, cached: nil, output: nil); onCall?(call)
        try onRawResult?(data)
        let segments: [MeetingUtterance]
        do { segments = try MeetingProtocol.segments(json) }
        catch { throw AppFailure("豆包未返回有效的带说话人转录，请检查说话人分离权限与配置。音频已保留。", code: "meeting_speakers_missing") }
        call.status = .succeeded; call.finished = Date(); call.estimatedAmount = call.price.estimate(seconds: call.seconds, input: nil, cached: nil, output: nil); onCall?(call)
        return (segments, data)
    }
    func brief(content: String, meeting: UUID, price: PriceSnapshot, system: String = MeetingProtocol.prompt, usageModel: String = "deepseek-flash-meeting", maxTokens: Int = 8192) async throws -> String {
        var call = UsageCall(jobID: meeting, provider: "DeepSeek", model: usageModel, price: price)
        call.promptHash = TextEnvelope.hash(system); onCall?(call)
        do {
            var req = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!); req.httpMethod = "POST"
            req.setValue("Bearer " + (try credentials("DEEPSEEK_API_KEY")), forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["model": "deepseek-flash", "thinking": ["type": "disabled"], "max_tokens": maxTokens,
                "messages": [["role": "system", "content": system], ["role": "user", "content": content]]])
            let (data, response) = try await perform(req)
            let (json, http) = try decode(data, response); call.httpStatus = http.statusCode
            let usage = json["usage"] as? [String: Any] ?? [:]
            call.inputTokens = usage["prompt_tokens"] as? Int; call.outputTokens = usage["completion_tokens"] as? Int
            call.cachedTokens = usage["prompt_cache_hit_tokens"] as? Int
            call.responseID = json["id"] as? String; call.returnedModel = json["model"] as? String
            call.estimatedAmount = price.estimate(seconds: 0, input: call.inputTokens, cached: call.cachedTokens, output: call.outputTokens)
            guard let choice = (json["choices"] as? [[String: Any]])?.first, choice["finish_reason"] as? String == "stop",
                  let result = (choice["message"] as? [String: Any])?["content"] as? String, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppFailure("会议笔记未完整返回，转录和你的笔记仍保留。", code: "meeting_brief_incomplete")
            }
            call.status = .succeeded; call.finished = Date(); onCall?(call); return result
        } catch { call.status = .failed; call.finished = Date(); call.errorCode = safeFailure(error).code; onCall?(call); throw error }
    }
}
