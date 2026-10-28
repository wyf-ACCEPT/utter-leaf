import XCTest
@testable import UtterLeafCore

final class CloudHistoryTests: XCTestCase {
    private func row(_ id: String = UUID().uuidString.lowercased()) -> CloudHistoryRow {
        CloudHistoryRow(id: id, source: UUID().uuidString, device: "Mac", created: 100, seconds: 20, raw: "Synthetic raw transcript", final: "Synthetic final transcript")
    }
    func testClearedTextCannotReturnFromAnOfflineDevice() {
        let original = row(); var deletion = original; deletion.erased = true; deletion.updated += 10
        var stale = original; stale.updated += 100
        var one = CloudHistoryCache(), two = CloudHistoryCache()
        [original, deletion, stale].forEach { one.merge($0) }
        [stale, deletion, original].forEach { two.merge($0) }
        XCTAssertTrue(one.rows[original.id]!.erased)
        XCTAssertTrue(two.rows[original.id]!.erased)
        XCTAssertNil(one.rows[original.id]!.raw)
        XCTAssertNil(one.rows[original.id]!.final)
        XCTAssertTrue(one.visible.isEmpty)
    }
    func testRawRedactionKeepsFinalAndDuplicateDeliveryStaysSingle() {
        let original = row(); var redacted = original; redacted.rawRemoved = true; redacted.raw = nil; redacted.updated += 10
        var cache = CloudHistoryCache()
        [redacted, original, redacted].forEach { cache.merge($0) }
        XCTAssertEqual(cache.visible.count, 1)
        XCTAssertNil(cache.visible.first?.raw)
        XCTAssertEqual(cache.visible.first?.final, original.final)
        var invalid = original; invalid.id = "not-a-job"; cache.merge(invalid)
        XCTAssertEqual(cache.rows.count, 1)
    }
    @MainActor func testOfflineHistoryAndSyncPreferencePersistWithoutTextInDiagnostics() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.json"), id = UUID().uuidString.lowercased()
        let sync = CloudHistorySync(file: file, device: "iPhone")
        sync.upsert(id: id, created: 100, seconds: 5, raw: "Synthetic private text", final: "Synthetic final")
        sync.setEnabled(false)
        let restored = CloudHistorySync(file: file, device: "iPhone")
        XCTAssertFalse(restored.cache.enabled)
        XCTAssertEqual(restored.cache.visible.count, 1)
        let report = String(data: try JSONSerialization.data(withJSONObject: restored.diagnostic), encoding: .utf8)!
        XCTAssertFalse(report.contains("Synthetic"))
        restored.erase(id)
        restored.upsert(id: id, created: 100, seconds: 5, raw: "Synthetic private text", final: "Synthetic final")
        XCTAssertTrue(restored.cache.visible.isEmpty)
    }
}
