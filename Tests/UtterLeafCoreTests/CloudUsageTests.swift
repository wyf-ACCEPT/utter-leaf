import XCTest
@testable import UtterLeafCore

final class CloudUsageTests: XCTestCase {
    private let now = 1_800_000_000.0
    private func call(_ id: UUID = UUID(), job: UUID, device: String = "Mac", amount: Double? = 1, purpose: String = "dictation") -> CloudUsageRow {
        var row = CloudUsageRow(id: "call." + id.uuidString.lowercased(), kind: "call", source: UUID().uuidString, device: device)
        row.job = job.uuidString.lowercased(); row.started = now - 60; row.purpose = purpose
        row.provider = "Doubao"; row.model = "v2-final"; row.status = "succeeded"; row.currency = "CNY"; row.amount = amount
        return row
    }
    func testRepeatedAndOutOfOrderDeliveryDoesNotDuplicateSpend() {
        let original = call(job: UUID())
        var changed = original; changed.amount = 2; changed.updated = 20
        var first = CloudUsageCache(), second = CloudUsageCache()
        for row in [original, changed, original, changed] { first.merge(row) }
        for row in [changed, original, original] { second.merge(row) }
        XCTAssertEqual(first.rows, second.rows)
        XCTAssertEqual(first.window(days: 7, now: now)["spent"] as? Double, 2)
        XCTAssertEqual(first.rows.count, 1)
    }
    func testBudgetConflictsResolveIdenticallyRegardlessOfArrivalOrder() {
        var a = CloudUsageRow(id: "budget.v1", kind: "budget", source: UUID().uuidString, device: "Mac")
        a.weekly = 5; a.monthly = 20; a.updated = 10
        var b = a; b.source = UUID().uuidString; b.weekly = 8
        var one = CloudUsageCache(), two = CloudUsageCache()
        [a,b].forEach { one.merge($0) }; [b,a].forEach { two.merge($0) }
        XCTAssertEqual(one.rows, two.rows)
        XCTAssertEqual(one.week, two.week)
    }
    func testRollupCountsJobsOnceSeparatesDevicesUnknownAndCurrencies() {
        let jobID = UUID(); var cache = CloudUsageCache()
        var job = CloudUsageRow(id: "job." + jobID.uuidString.lowercased(), kind: "job", source: UUID().uuidString, device: "Mac")
        job.started = now - 60; job.purpose = "dictation"; job.characters = 1000; job.seconds = 30
        cache.merge(job); cache.merge(job)
        cache.merge(call(job: jobID))
        var cleanup = call(job: jobID, device: "iPhone", amount: 0.2); cleanup.provider = "DeepSeek"; cleanup.model = "deepseek-flash"
        cache.merge(cleanup)
        cache.merge(call(job: UUID(), amount: nil, purpose: "meeting"))
        var usd = call(job: UUID(), amount: 500); usd.currency = "USD"; cache.merge(usd)
        var future = call(job: UUID(), amount: 100); future.started = now + 1; cache.merge(future)
        let summary = cache.window(days: 7, now: now)
        XCTAssertEqual(summary["spent"] as? Double, 1.2)
        XCTAssertEqual(summary["written"] as? Int, 1000)
        XCTAssertEqual(summary["unknown"] as? Int, 1)
        XCTAssertEqual(summary["mac"] as? Double, 1)
        XCTAssertEqual(summary["phone"] as? Double, 0.2)
    }
    func testMalformedRowsNeverEnterCacheOrOutgoingSet() {
        var cache = CloudUsageCache(); var value = call(job: UUID())
        value.model = "private transcript goes here"
        XCTAssertFalse(cache.merge(value))
        value.model = "v2-final"; value.amount = -.infinity
        XCTAssertFalse(cache.merge(value))
        value.amount = 1; value.source = "bad-identity"
        XCTAssertFalse(cache.merge(value))
        let remote = call(job: UUID()); cache.merge(remote)
        XCTAssertTrue(cache.owned.isEmpty)
        XCTAssertEqual(Set((try! JSONSerialization.jsonObject(with: remote.data) as! [String: Any]).keys).intersection(["text", "rawText", "audio", "key", "targetBundleID"]), [])
    }
    @MainActor func testOfflineMetadataAndBudgetSurviveRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("usage.json")
        let first = CloudUsageSync(file: file, device: "Mac")
        var row = first.row(id: "call." + UUID().uuidString.lowercased(), kind: "call")
        row.job = UUID().uuidString; row.started = now; row.purpose = "dictation"; row.provider = "Doubao"; row.model = "v2-final"; row.status = "cancelled"; row.currency = "CNY"; row.amount = 0.1
        first.ingest(row); first.setBudget(week: 7, month: 30)
        let restored = CloudUsageSync(file: file, device: "Mac")
        XCTAssertEqual(restored.cache.source, first.cache.source)
        XCTAssertEqual(restored.cache.rows.count, 2)
        XCTAssertEqual(restored.cache.week, 7)
        XCTAssertEqual(restored.cache.owned.count, 2)
        XCTAssertNil(restored.cache.lastSync)
    }
}
