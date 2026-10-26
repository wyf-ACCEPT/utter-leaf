import Foundation
import AppKit
import UtterLeafCore

@MainActor final class BillingService {
    typealias Fetch = (URLRequest) async throws -> Data
    private let credentials: (String) throws -> String
    private let fetch: Fetch
    private static let delegate = NoRedirectDelegate()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 60
        config.urlCache = nil; config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    init(credentials: @escaping (String) throws -> String = Credentials.load, fetch: Fetch? = nil) {
        self.credentials = credentials
        self.fetch = fetch ?? { request in
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AppFailure("官方查询未返回 HTTP 状态。", code: "billing_http_missing") }
            guard (200..<300).contains(http.statusCode) else { throw AppFailure("官方查询失败（HTTP \(http.statusCode)）。请检查只读凭证与网络。", code: "billing_http_\(http.statusCode)") }
            guard data.count <= 8 * 1024 * 1024 else { throw BillingPayloadError.invalid }
            return data
        }
    }
    func balance(now: Date = Date()) async throws -> BalanceSnapshot {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.setValue("Bearer " + (try credentials("DEEPSEEK_API_KEY")), forHTTPHeaderField: "Authorization")
        return try BillingPayload.balance(await fetch(request), fetched: now)
    }
    func bills(config: BillingConfiguration, now: Date = Date()) async throws -> [RemoteBill] {
        guard config.hasScope else { throw AppFailure("请配置豆包账单实例 ID，避免查询其他项目。", code: "billing_scope_missing") }
        let accessKey = try credentials("UTTERLEAF_VOLC_ACCESS_KEY_ID")
        let secret = try credentials("UTTERLEAF_VOLC_SECRET_ACCESS_KEY")
        var collected: [String: RemoteBill] = [:]
        let deadline = Date().addingTimeInterval(90)
        let cutoff = now.addingTimeInterval(-30 * 86400)
        for instance in config.instanceIDs {
            var singleScope = config; singleScope.instanceID = instance
            for month in BillingSyncPolicy.months(now: now) {
                var complete = false
                var expectedTotal: Int?
                var observed = Set<String>()
                for page in 0..<20 {
                    try Task.checkCancellation()
                    guard Date() < deadline else { throw URLError(.timedOut) }
                    var body: [String: Any] = ["BillPeriod": month, "InstanceNo": instance,
                        "GroupTerm": 0, "GroupPeriod": 2, "NeedRecordNum": 1, "IgnoreZero": 0,
                        "Offset": page * 100, "Limit": 100]
                    if !config.product.isEmpty { body["Product"] = [config.product] }
                    let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
                    let request = VolcBillingSigner.request(body: data, accessKey: accessKey, secret: secret, date: Date())
                    let result = try BillingPayload.bills(await fetch(request), scope: singleScope)
                    guard result.rows.allSatisfy({ $0.id.hasPrefix(month + ":") }) else { throw BillingPayloadError.invalid }
                    if let expectedTotal, expectedTotal != result.total { throw BillingPayloadError.invalid }
                    expectedTotal = result.total
                    guard result.rows.count == min(100, max(0, result.total - page * 100)) else { throw BillingPayloadError.invalid }
                    for bill in result.rows {
                        guard observed.insert(bill.id).inserted else { throw BillingPayloadError.invalid }
                    }
                    for bill in result.rows where bill.start >= cutoff && bill.end <= now { collected[bill.instanceID + ":" + bill.id] = bill }
                    if observed.count == result.total { complete = true; break }
                    guard result.rows.count == 100 else { throw BillingPayloadError.invalid }
                    try await Task.sleep(for: .milliseconds(250))
                }
                guard complete else { throw BillingPayloadError.paginationLimit }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        return collected.values.sorted { $0.start > $1.start }
    }
}

@MainActor final class BillingSync {
    private weak var store: LocalStore?
    private let service: BillingService
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var task: Task<Void, Never>?
    var isDictating: (() -> Bool)?
    init(store: LocalStore, service: BillingService? = nil) { self.store = store; self.service = service ?? BillingService() }
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.request() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.request() }
            })
        }
        request()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        task?.cancel(); task = nil
    }
    func request(force: Bool = false) {
        guard task == nil, let store, store.storageError == nil, !store.billingSyncing else { return }
        let config = store.database.preferences.billing ?? BillingConfiguration()
        guard force || (config.enabled && isDictating?() != true) else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await run(force: force)
            task = nil
        }
    }
    func run(force: Bool, now: Date = Date()) async {
        guard let store, store.storageError == nil, !store.billingSyncing else { return }
        let config = store.database.preferences.billing ?? BillingConfiguration()
        guard force || config.enabled else { return }
        let old = store.database.billingLedger ?? BillingLedger()
        let deepDue = force || BillingSyncPolicy.isDue(lastAttempt: old.deepSeek.attempted, now: now)
        let volcDue = force || BillingSyncPolicy.isDue(lastAttempt: old.doubao.attempted, now: now)
        guard deepDue || volcDue else { return }
        store.billingSyncing = true
        defer { store.billingSyncing = false }
        if deepDue {
            change { $0.deepSeek.attempted = now; $0.deepSeek.errorCode = nil }
            do {
                let snapshot = try await service.balance(now: now)
                try Task.checkCancellation()
                change { ledger in
                    ledger.balances.append(snapshot); ledger.balances = Array(ledger.balances.suffix(2160))
                    ledger.deepSeek.succeeded = now; ledger.deepSeek.errorCode = nil
                }
            } catch { change { $0.deepSeek.errorCode = errorCode(error) } }
        }
        guard !Task.isCancelled else { return }
        if volcDue {
            change { $0.doubao.attempted = now; $0.doubao.errorCode = nil }
            do {
                let bills = try await service.bills(config: config, now: now)
                try Task.checkCancellation()
                guard (store.database.preferences.billing ?? BillingConfiguration()).scopeKey == config.scopeKey,
                      (store.database.preferences.billing ?? BillingConfiguration()).product == config.product else { return }
                change { ledger in
                    ledger.bills = bills; ledger.scope = config.scopeKey
                    ledger.doubao.succeeded = now; ledger.doubao.errorCode = nil
                }
            } catch { change { $0.doubao.errorCode = errorCode(error) } }
        }
    }
    private func change(_ action: (inout BillingLedger) -> Void) {
        guard let store else { return }
        var ledger = store.database.billingLedger ?? BillingLedger(); action(&ledger)
        store.database.billingLedger = ledger; store.save()
    }
    private func errorCode(_ error: Error) -> String {
        if let failure = error as? AppFailure { return failure.code }
        if let remote = error as? BillingPayloadError {
            switch remote { case .scopeMismatch: return "billing_scope_mismatch"; case .remoteError: return "billing_remote_error"; case .paginationLimit: return "billing_page_limit"; case .invalid: return "billing_invalid_response" }
        }
        if error is CancellationError { return "billing_cancelled" }
        if let network = error as? URLError { return "billing_network_\(network.errorCode)" }
        return "billing_query_failed"
    }
}
