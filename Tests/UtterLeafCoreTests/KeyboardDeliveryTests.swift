import XCTest
@testable import UtterLeafCore

final class KeyboardDeliveryTests: XCTestCase {
    func testReturnActionsStayDisabledThroughoutCaptureAndDelivery() {
        for phase in ["starting", "recording", "processing", "ready"] {
            XCTAssertFalse(KeyboardDelivery.canPerformReturn(phase: phase, launching: false, fullAccess: true), phase)
        }
        for phase in ["idle", "inserted", "error"] {
            XCTAssertTrue(KeyboardDelivery.canPerformReturn(phase: phase, launching: false, fullAccess: true), phase)
        }
        XCTAssertFalse(KeyboardDelivery.canPerformReturn(phase: "idle", launching: true, fullAccess: true))
        XCTAssertFalse(KeyboardDelivery.canPerformReturn(phase: "inserted", launching: false, fullAccess: false))
    }
    func testExpiredDuplicateEmptyAndFutureResultsNeverInsert() {
        let id = UUID().uuidString
        XCTAssertTrue(KeyboardDelivery.hasFreshResult(request: id, consumed: nil, text: "Synthetic text", updated: 1000, now: 1010))
        XCTAssertFalse(KeyboardDelivery.hasFreshResult(request: id, consumed: id, text: "Synthetic text", updated: 1000, now: 1010))
        XCTAssertFalse(KeyboardDelivery.hasFreshResult(request: id, consumed: nil, text: "Synthetic text", updated: 1000, now: 1900))
        XCTAssertFalse(KeyboardDelivery.hasFreshResult(request: id, consumed: nil, text: "Synthetic text", updated: 1100, now: 1000))
        XCTAssertFalse(KeyboardDelivery.hasFreshResult(request: id, consumed: nil, text: " \n", updated: 1000, now: 1010))
        XCTAssertFalse(KeyboardDelivery.hasFreshResult(request: "invalid", consumed: nil, text: "Synthetic text", updated: 1000, now: 1010))
        XCTAssertFalse(KeyboardDelivery.hasFreshResult(request: id, consumed: nil, text: "Synthetic text", updated: .nan, now: 1010))
    }
    func testCrossDocumentOrChangedCaretRequiresExplicitInsertion() {
        let id = UUID().uuidString
        XCTAssertTrue(KeyboardDelivery.matchesTarget(request: id, expectedRequest: id, document: "doc1", expectedDocument: "doc1", before: "prefix", expectedBefore: "prefix", after: "suffix", expectedAfter: "suffix"))
        XCTAssertFalse(KeyboardDelivery.matchesTarget(request: id, expectedRequest: id, document: "doc2", expectedDocument: "doc1", before: "prefix", expectedBefore: "prefix", after: "suffix", expectedAfter: "suffix"))
        XCTAssertFalse(KeyboardDelivery.matchesTarget(request: id, expectedRequest: id, document: "doc1", expectedDocument: "doc1", before: "changed", expectedBefore: "prefix", after: "suffix", expectedAfter: "suffix"))
        XCTAssertFalse(KeyboardDelivery.matchesTarget(request: id, expectedRequest: UUID().uuidString, document: "doc1", expectedDocument: "doc1", before: "prefix", expectedBefore: "prefix", after: "suffix", expectedAfter: "suffix"))
        XCTAssertEqual(KeyboardDelivery.mismatch(request: id, expectedRequest: id, document: "doc2", expectedDocument: "doc1", before: "prefix", expectedBefore: "prefix", after: "suffix", expectedAfter: "suffix"), "document_changed")
        XCTAssertEqual(KeyboardDelivery.mismatch(request: id, expectedRequest: id, document: "doc1", expectedDocument: "doc1", before: "changed", expectedBefore: "prefix", after: "suffix", expectedAfter: "suffix"), "context_changed")
    }
}
