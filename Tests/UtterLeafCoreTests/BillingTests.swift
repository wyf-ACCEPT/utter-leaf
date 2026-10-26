import XCTest
@testable import UtterLeafCore
@testable import UtterLeaf

final class BillingTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-23T12:00:00Z")!
    let balanceData = Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"19.12345678","granted_balance":"0.10000000","topped_up_balance":"19.02345678"}]}"#.utf8)
    func payload(instance: String = "fixture", amount: String = "0.1", id: String = "bill", total: Int = 1) -> Data {
        try! JSONSerialization.data(withJSONObject: ["Result": ["Total": total, "List": [["BillDetailId": id, "BillPeriod": "2026-10", "InstanceNo": instance, "Product": "speech", "Currency": "CNY", "PayableAmount": amount, "ExpenseBeginTime": "2026-10-23 18:00:00", "ExpenseEndTime": "2026-10-23 19:00:00"]]]])
    }
    func testBalanceParsesDecimalWithoutPretendingItIsSpend() throws {
        let balance = try BillingPayload.balance(balanceData, fetched: now)
        XCTAssertEqual(balance.balances.first?.total, Decimal(string: "19.12345678"))
        XCTAssertEqual(balance.balances.first?.currency, "CNY")
        XCTAssertThrowsError(try BillingPayload.balance(Data("{}".utf8), fetched: now))
        let corrupt = String(decoding: balanceData, as: UTF8.self).replacingOccurrences(of: "19.12345678", with: "19oops")
        XCTAssertThrowsError(try BillingPayload.balance(Data(corrupt.utf8), fetched: now))
    }
    func testBillParsingRejectsWrongScopeAndMissingMoney() throws {
        var config = BillingConfiguration(); config.instanceID = "fixture"
        let bill = try BillingPayload.bills(payload(), scope: config).rows[0]
        XCTAssertEqual(bill.payable, Decimal(string: "0.1"))
        XCTAssertEqual(bill.start, ISO8601DateFormatter().date(from: "2026-10-23T10:00:00Z"))
        XCTAssertThrowsError(try BillingPayload.bills(payload(instance: "other-project"), scope: config))
        XCTAssertThrowsError(try BillingPayload.bills(payload(amount: "NaN"), scope: config))
        XCTAssertThrowsError(try BillingPayload.bills(payload(), scope: BillingConfiguration()))
    }
    func testMultipleInstanceScopeNormalizationAndLegacyDecoding() throws {
        var config = try JSONDecoder().decode(BillingConfiguration.self,
            from: Data(#"{"enabled":true,"instanceID":"fixture","product":"","exclusiveInstance":false}"#.utf8))
        XCTAssertEqual(config.scopeKey, "fixture")
        config.instanceID = " fixture-b，fixture, fixture-b "
        XCTAssertEqual(config.instanceIDs, ["fixture", "fixture-b"])
        XCTAssertEqual(config.scopeKey, "fixture,fixture-b")
        XCTAssertTrue(config.hasScope)
        XCTAssertEqual(try BillingPayload.bills(payload(instance: "fixture-b"), scope: config).rows.count, 1)
        XCTAssertThrowsError(try BillingPayload.bills(payload(instance: "unselected"), scope: config))
        config.instanceID = "invalid scope"; XCTAssertFalse(config.hasScope)
        config.instanceID = (0..<11).map { "fixture-\($0)" }.joined(separator: ",")
        XCTAssertFalse(config.hasScope)
    }
    @MainActor func testMultipleInstancesQueryIndividuallyAndPreserveLastGoodSnapshotOnFailure() async throws {
        var config = BillingConfiguration(); config.instanceID = "fixture-b,fixture,fixture"
        var queried = Set<String>()
        let service = BillingService(credentials: { _ in "fixture" }, fetch: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let instance = body["InstanceNo"] as! String
            queried.insert(instance)
            if body["BillPeriod"] as? String != "2026-10" { return Data(#"{"Result":{"Total":0,"List":[]}}"#.utf8) }
            return self.payload(instance: instance)
        })
        let bills = try await service.bills(config: config, now: now)
        XCTAssertEqual(queried, ["fixture", "fixture-b"])
        XCTAssertEqual(bills.count, 2)
        XCTAssertEqual(BillComparison(bills: bills + bills, calls: []).official, Decimal(string: "0.2"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root); store.database.preferences.billing = config
        var ledger = BillingLedger(); ledger.bills = bills; ledger.scope = config.scopeKey
        ledger.deepSeek.attempted = now; ledger.doubao.succeeded = now.addingTimeInterval(-60)
        store.database.billingLedger = ledger
        let partial = BillingService(credentials: { _ in "fixture" }, fetch: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            if body["InstanceNo"] as? String == "fixture-b" { throw URLError(.notConnectedToInternet) }
            return Data(#"{"Result":{"Total":0,"List":[]}}"#.utf8)
        })
        await BillingSync(store: store, service: partial).run(force: false, now: now)
        XCTAssertEqual(store.database.billingLedger?.bills, bills)
        XCTAssertEqual(store.database.billingLedger?.doubao.succeeded, ledger.doubao.succeeded)
        XCTAssertEqual(store.database.billingLedger?.doubao.errorCode, "billing_network_-1009")
    }
    func testTwentyMinuteDueAndCrossMonthWindow() {
        XCTAssertFalse(BillingSyncPolicy.isDue(lastAttempt: now.addingTimeInterval(-1199), now: now))
        XCTAssertTrue(BillingSyncPolicy.isDue(lastAttempt: now.addingTimeInterval(-1200), now: now))
        XCTAssertTrue(BillingSyncPolicy.isDue(lastAttempt: nil, now: now))
        XCTAssertTrue(BillingSyncPolicy.isDue(lastAttempt: now.addingTimeInterval(10), now: now))
        XCTAssertEqual(BillingSyncPolicy.months(now: ISO8601DateFormatter().date(from: "2026-03-01T00:00:00Z")!), ["2026-01", "2026-02", "2026-03"])
    }
    func testTerminalAudioEstimateKeepsActualAndFrozenPrice() {
        var call = UsageCall(jobID: UUID(), provider: "Doubao", model: "v2-final", price: .asr(.final))
        call.status = .cancelled; call.seconds = 3.6; call.billedAmount = 0.002
        call.fillLocalEstimate()
        XCTAssertEqual(call.estimatedAmount!, 0.001, accuracy: 0.00000001)
        XCTAssertEqual(call.billedAmount, 0.002); XCTAssertEqual(call.estimateBasis, "sent_audio_duration_v1")
        var file = UsageCall(jobID: UUID(), provider: "Doubao", model: "v2-file", price: .asr(.file))
        file.status = .failed; file.seconds = 100; file.fillLocalEstimate(); XCTAssertNil(file.estimatedAmount)
        file.submittedSeconds = 100; file.fillLocalEstimate(); XCTAssertNotNil(file.estimatedAmount)
        var pending = call; pending.estimatedAmount = nil; pending.status = .pending; pending.fillLocalEstimate(); XCTAssertNil(pending.estimatedAmount)
    }
    func testIntervalComparisonDeduplicatesCallsAndNeverAllocatesBill() throws {
        var config = BillingConfiguration(); config.instanceID = "fixture"
        let bill = try BillingPayload.bills(payload(), scope: config).rows[0]
        var call = UsageCall(jobID: UUID(), provider: "Doubao", model: "v2-final", price: .asr(.final))
        call.started = bill.start.addingTimeInterval(1); call.finished = bill.start.addingTimeInterval(5); call.status = .succeeded; call.estimatedAmount = 0.02
        var pendingTail = call; pendingTail.started = bill.end.addingTimeInterval(1); pendingTail.finished = bill.end.addingTimeInterval(5)
        let comparison = BillComparison(bills: [bill, bill], calls: [call, pendingTail])
        XCTAssertEqual(comparison.matchedCalls, 1); XCTAssertEqual(comparison.localEstimate, 0.02)
        XCTAssertEqual(comparison.official, Decimal(string: "0.1")); XCTAssertNil(call.billedAmount)
    }
    func testV4SignatureMatchesIndependentFixture() {
        let request = VolcBillingSigner.request(body: Data("{}".utf8), accessKey: "fixture-ak", secret: "fixture-sk", date: now)
        XCTAssertEqual(request.url?.host, "open.volcengineapi.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Date"), "20261023T120000Z")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "HMAC-SHA256 Credential=fixture-ak/20261023/cn-north-1/billing/request, SignedHeaders=content-type;host;x-content-sha256;x-date, Signature=883f0a561e400d0cf92d7b66667d22f927a7143905177325107f1354807e66f8")
        XCTAssertNil(request.value(forHTTPHeaderField: "SecretKey"))
    }
    @MainActor func testSchedulerIndependentProvidersFailurePreservesPreviousDataAndNoAutoRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root)
        var old = BillingLedger(); old.balances = [try BillingPayload.balance(balanceData, fetched: now.addingTimeInterval(-1800))]
        store.database.billingLedger = old
        var fetchCount = 0
        let service = BillingService(credentials: { _ in "fixture" }, fetch: { _ in fetchCount += 1; throw URLError(.notConnectedToInternet) })
        let sync = BillingSync(store: store, service: service)
        await sync.run(force: false, now: now)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.database.billingLedger?.balances.count, 1)
        XCTAssertEqual(store.database.billingLedger?.doubao.errorCode, "billing_scope_missing")
        XCTAssertEqual(store.database.billingLedger?.deepSeek.errorCode, "billing_network_-1009")
        await sync.run(force: false, now: now.addingTimeInterval(100))
        XCTAssertEqual(fetchCount, 1)
        var config = BillingConfiguration(); config.enabled = false; store.database.preferences.billing = config
        await sync.run(force: false, now: now.addingTimeInterval(2000)); XCTAssertEqual(fetchCount, 1)
        await sync.run(force: true, now: now.addingTimeInterval(2000)); XCTAssertEqual(fetchCount, 2)
        XCTAssertFalse(store.billingSyncing)
    }

    @MainActor func testBillingPagesUseScopedSignedRequestsAndCommitOnlyCompleteResults() async throws {
        var config = BillingConfiguration(); config.instanceID = "fixture"; config.product = "speech"
        var pages = 0
        let service = BillingService(credentials: { _ in "fixture" }, fetch: { request in
            XCTAssertEqual(request.url?.host, "open.volcengineapi.com")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "SecretKey"))
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["InstanceNo"] as? String, "fixture")
            XCTAssertEqual(body["Product"] as? [String], ["speech"])
            let month = body["BillPeriod"] as! String
            let offset = body["Offset"] as! Int
            pages += 1
            if month != "2026-10" { return Data(#"{"Result":{"Total":0,"List":[]}}"#.utf8) }
            let count = offset == 0 ? 100 : 1
            let rows = (0..<count).map { index -> [String: Any] in
                ["BillDetailId": "row-\(offset + index)", "BillPeriod": month, "InstanceNo": "fixture", "Product": "speech", "Currency": "CNY", "PayableAmount": "0.001", "ExpenseBeginTime": "2026-10-23 18:00:00", "ExpenseEndTime": "2026-10-23 19:00:00"]
            }
            return try JSONSerialization.data(withJSONObject: ["Result": ["Total": 101, "List": rows]])
        })
        let bills = try await service.bills(config: config, now: now)
        XCTAssertEqual(bills.count, 101); XCTAssertEqual(pages, 3)
        let partial = BillingService(credentials: { _ in "fixture" }, fetch: { _ in Data(#"{"Result":{"Total":5,"List":[]}}"#.utf8) })
        do { _ = try await partial.bills(config: config, now: now); XCTFail("Incomplete data must not become a successful zero bill") }
        catch { XCTAssertTrue(error is BillingPayloadError) }
    }
    @MainActor func testBalanceSyncDoesNotRewriteActualChargesAndLegacyMigrationIsSafe() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root)
        var call = UsageCall(jobID: UUID(), provider: "Doubao", model: "v2-final", price: .asr(.final)); call.status = .cancelled; call.seconds = 5
        store.update(call)
        XCTAssertNotNil(store.database.calls.first?.estimatedAmount)
        let service = BillingService(credentials: { _ in "fixture" }, fetch: { [balanceData] request in
            XCTAssertEqual(request.url?.path, "/user/balance"); return balanceData
        })
        let sync = BillingSync(store: store, service: service); await sync.run(force: true, now: now)
        XCTAssertEqual(store.database.billingLedger?.deepSeek.succeeded, now)
        XCTAssertNil(store.database.calls.first?.billedAmount)
        let restored = LocalStore(root: root)
        XCTAssertEqual(restored.database.billingLedger?.balances.last?.balances.first?.total, Decimal(string: "19.12345678"))
    }
}
