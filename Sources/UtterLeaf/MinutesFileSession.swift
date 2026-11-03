import Foundation
import WebKit
import UtterLeafCore

@MainActor protocol MinutesFileTransport {
    func load() async throws
    func run(_ action: String, key: UUID, arguments: [String: Any]) async throws -> [String: Any]
    func upload(audio: URL, seconds: Double, key: UUID, resume: Bool, prepared: (String) throws -> Void, progress: (Int) -> Void) async throws -> String
}

/// An account-scoped file transport. Session secrets remain inside its private WebKit store.
@MainActor final class MinutesFileSession: NSObject, WKNavigationDelegate, WKUIDelegate, MinutesFileTransport {
    private let browser: WKWebView
    private let home: URL
    private var loaded = false
    private let expectedSubject: String?
    init(profile: MinutesAccountProfile) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile.id)
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        expectedSubject = profile.identity?.subjectKey
        browser = WKWebView(frame: .zero, configuration: configuration)
        home = URL(string: "https://\(profile.host ?? "meetings.feishu.cn")/minutes/home")!
        super.init(); browser.navigationDelegate = self; browser.uiDelegate = self
    }
    func load() async throws {
        browser.load(URLRequest(url: home))
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(200))
            if loaded {
                if let expectedSubject {
                    let identity = try await run("identity", key: UUID())
                    guard identity["subject"] as? String == expectedSubject else { throw AppFailure("飞书登录身份已变化，请重新选择账号。", code: "minutes_identity_changed") }
                }
                return
            }
        }
        throw AppFailure("飞书登录或页面加载失败，请在用量页重新登录。", code: "minutes_login")
    }
    func upload(audio: URL, seconds: Double, key: UUID, resume: Bool = false, prepared: (String) throws -> Void, progress: (Int) -> Void) async throws -> String {
        if !resume {
            let quota = try await run("quota", key: key)
            guard let remaining = quota["remaining"] as? Double else { throw AppFailure("无法确认飞书额度，未发送音频。", code: "minutes_quota_unknown") }
            guard remaining >= ceil(seconds / 60) else { throw AppFailure("飞书额度不足以转录此录音。", code: "minutes_quota_exhausted") }
        }
        let size = try audio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 44, size < 2_000_000_000 else { throw AppFailure("音频大小无效。", code: "minutes_file_size") }
        let file = try FileHandle(forReadingFrom: audio); defer { try? file.close() }
        let header = try file.read(upToCount: 512) ?? Data(); try file.seek(toOffset: 0)
        let result = try await run(resume ? "resume" : "prepare", key: key, arguments: ["size": size, "name": "utterleaf-" + key.uuidString.lowercased() + ".wav", "header": header.base64EncodedString()])
        if resume, let stage = result["stage"] as? String, ["minutes_finishing", "finished"].contains(stage), let object = result["objectToken"] as? String { return object }
        guard let object = result["objectToken"] as? String, let blockSize = result["blockSize"] as? Int,
              let blocks = result["blocks"] as? Int, blockSize > 0, blockSize <= 16_777_216,
              blocks == Int(ceil(Double(size) / Double(blockSize))) else { throw AppFailure("飞书上传参数无效，未重复提交。", code: "minutes_prepare_response") }
        try prepared(object)
        let next = result["nextSequence"] as? Int ?? 0
        guard next >= 0, next <= blocks else { throw AppFailure("飞书续传参数无效。", code: "minutes_upload_state") }
        try file.seek(toOffset: UInt64(next * blockSize))
        for index in next..<blocks {
            try Task.checkCancellation()
            let data = try file.read(upToCount: blockSize) ?? Data()
            _ = try await run("block", key: key, arguments: ["body": data.base64EncodedString(), "sequence": index])
            progress((index + 1) * 100 / blocks)
        }
        let finished = try await run("finish", key: key)
        guard let token = finished["objectToken"] as? String else { throw AppFailure("飞书提交状态待核对。", code: "minutes_finish_uncertain") }
        return token
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = webView.url?.path == "/minutes/home" && webView.url?.host?.hasSuffix(".feishu.cn") == true
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) { completionHandler(nil) }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
    func run(_ action: String, key: UUID, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard let path = Bundle.main.url(forResource: "MinutesFileBridge", withExtension: "js") else { throw AppFailure("飞书转录组件未打包。", code: "minutes_resource") }
        let body = try String(contentsOf: path, encoding: .utf8)
        let script = "return JSON.stringify(await (async () => {\n" + body + "\n})());"
        var args = arguments; args["action"] = action; args["key"] = key.uuidString.lowercased()
        // WKWebView requires all named parameters referenced by a script to be defined.
        for name in ["size", "name", "header", "body", "sequence", "objectToken"] where args[name] == nil { args[name] = NSNull() }
        let result: Any
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                browser.callAsyncJavaScript(script, arguments: args, in: nil, in: .page) { result in
                    continuation.resume(with: result)
                }
            }
        } catch {
            throw AppFailure("飞书登录或网页接口暂不可用，请在用量页检查账号；未自动改用豆包。", code: "minutes_client_unavailable")
        }
        try Task.checkCancellation()
        guard let string = result as? String, let data = string.data(using: .utf8),
              let output = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppFailure("飞书返回格式不兼容。", code: "minutes_response") }
        if let error = output["error"] as? String { throw AppFailure("飞书文件转录未完成（\(error)）；未自动改用豆包。", code: error) }
        return output
    }
}
