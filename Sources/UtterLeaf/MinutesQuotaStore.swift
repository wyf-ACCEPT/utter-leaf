import AppKit
import WebKit
import UtterLeafCore

/// Owns a dedicated website session; browser Cookies never leave WebKit.
@MainActor final class MinutesQuotaStore: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum Authentication { case unverified, authenticated, required }
    static let tenant = "ucnaknhwgwdu.feishu.cn"
    static let home = URL(string: "https://\(tenant)/minutes/home")!
    @Published private(set) var snapshot: MinutesQuotaSnapshot?
    @Published private(set) var checking = false
    @Published private(set) var errorCode: String?
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var authentication: Authentication = .unverified
    var canRefresh: () -> Bool = { true }
    private let file: URL
    private let networkEnabled: Bool
    private var generation = UUID()
    private var deadline: Task<Void, Never>?
    private var loginVisible = false
    private var browser: WKWebView?
    var webView: WKWebView {
        if let browser { return browser }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "B19683D3-4195-4B82-8620-6D3E45048CC2")!)
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self; browser.uiDelegate = self
        self.browser = browser
        return browser
    }
    init(file: URL, networkEnabled: Bool = true) {
        self.file = file; self.networkEnabled = networkEnabled
        if let data = try? Data(contentsOf: file), data.count <= 1_048_576 {
            snapshot = try? JSONDecoder().decode(MinutesQuotaSnapshot.self, from: data)
        }
        super.init()
    }
    var needsLogin: Bool { authentication == .required }
    var refreshDue: Bool {
        guard let lastAttempt else { return true }
        return Date().timeIntervalSince(lastAttempt) >= 300
            || (snapshot?.nextRefresh.map { $0 > lastAttempt && $0 <= Date() } ?? false)
    }
    func refresh(force: Bool = false) {
        guard networkEnabled, !checking, force || (refreshDue && !needsLogin) else { return }
        guard canRefresh() else { if force { errorCode = "busy" }; return }
        checking = true; errorCode = nil; lastAttempt = Date(); generation = UUID()
        let token = generation
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, checking, generation == token else { return }
            browser?.stopLoading(); fail("timeout")
        }
        if webView.url?.host == Self.tenant && webView.url?.path == "/minutes/home" && !webView.isLoading { readQuota(token: token) }
        else { webView.load(URLRequest(url: Self.home, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)) }
    }
    func beginLogin() {
        loginVisible = true
        if webView.url == nil { refresh(force: true) }
    }
    func endLogin() { loginVisible = false }
    private func readQuota(token: UUID) {
        guard checking, token == generation, webView.url?.host == Self.tenant else { return }
        let path = "/minutes/api/quota_data?benefit_type_list[]=1&benefit_type_list[]=3&benefit_type_list[]=4&function_scene_list[]=minutes_list&function_scene_list[]=upload_notice&function_scene_list[]=upload_popup&function_scene_list[]=asr_function_popup_mainpage&function_scene_list[]=asr_function_popup_upload&function_scene_list[]=minutes_recording_transcript_page&language=zh_cn"
        // The only evaluated operation is a same-origin, read-only quota request.
        let script = """
        const response = await fetch(path, {credentials: 'include', cache: 'no-store'});
        if (response.status === 401 || response.status === 403 || response.redirected) return {login: true};
        if (!response.ok) return {failed: true};
        return {body: await response.text()};
        """
        webView.callAsyncJavaScript(script, arguments: ["path": path], in: nil, in: .page) { [weak self] result in
            guard let self, checking, generation == token else { return }
            guard case let .success(value) = result, let envelope = value as? [String: Any] else { fail("network"); return }
            if envelope["login"] as? Bool == true { fail("login"); return }
            guard let text = envelope["body"] as? String else { fail("network"); return }
            do {
                let value = try MinutesQuotaSnapshot.parse(Data(text.utf8))
                snapshot = value; authentication = .authenticated; checking = false; errorCode = nil; deadline?.cancel()
                do {
                    try JSONEncoder().encode(value).write(to: file, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                } catch { errorCode = "storage" }
            } catch MinutesQuotaSnapshot.Failure.authentication { fail("login") }
            catch { fail(text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") ? "login" : "response") }
        }
    }
    private func fail(_ code: String) {
        if code == "login" { authentication = .required }
        checking = false; errorCode = code; deadline?.cancel(); generation = UUID()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.host == Self.tenant, webView.url?.path == "/minutes/home" else {
            if checking { fail("login") }; return
        }
        if checking { readQuota(token: generation) }
        else if loginVisible { refresh(force: true) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if checking && (error as NSError).code != NSURLErrorCancelled { fail("network") }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if checking && (error as NSError).code != NSURLErrorCancelled { fail("network") }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if checking { fail("network") } }
    private func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        guard host == "feishu.cn" || host.hasSuffix(".feishu.cn") else { return false }
        if host == Self.tenant && url.path.hasPrefix("/minutes/") { return url.path == "/minutes/home" }
        return true
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        decisionHandler(allowed(url) || url.absoluteString == "about:blank" ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, allowed(url) { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        completionHandler(nil)
    }
}
