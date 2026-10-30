import XCTest
@testable import UtterLeafCore

final class MinutesQuotaTests: XCTestCase {
    private func response(remaining: Any = 148, refresh: Any = 1_793_289_600, unit: Int = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 0, "data": ["display_quota": [
            "remaining_asr_quota": remaining, "remaining_ai_quota": 0,
            "display_quota_list": [["AuthKey": "vc_asr_function_prem", "IsVisible": true, "QuotaUnit": unit,
                "Amount": 150, "Remaining": remaining,
                "SourceList": [["IsVisible": true, "DisplayText": "每日体验额度", "Remaining": 28, "Amount": 30, "RefreshTime": refresh]]]]]]])
    }
    func testOfficialQuotaKeepsServerRefreshAndZeroSummaryIndependentOfMoney() throws {
        let now = Date(timeIntervalSince1970: 1_793_280_000)
        let snapshot = try MinutesQuotaSnapshot.parse(response(), fetched: now)
        XCTAssertEqual(snapshot.remainingMinutes, 148); XCTAssertEqual(snapshot.totalMinutes, 150)
        XCTAssertEqual(snapshot.summaryRemaining, 0); XCTAssertEqual(snapshot.fetched, now)
        XCTAssertEqual(snapshot.nextRefresh, Date(timeIntervalSince1970: 1_793_289_600))
        XCTAssertEqual(snapshot.sources.first?.remaining, 28)
        let cache = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(MinutesQuotaSnapshot.self, from: cache), snapshot)
        XCTAssertFalse(String(decoding: cache, as: UTF8.self).contains("AuthKey"))
    }
    func testMissingOrInvalidQuotaIsNeverDisplayedAsFreeAllowance() throws {
        for value: Any in [NSNull(), -1, true, "148", 151] {
            XCTAssertThrowsError(try MinutesQuotaSnapshot.parse(response(remaining: value)))
        }
        XCTAssertThrowsError(try MinutesQuotaSnapshot.parse(response(unit: 1)))
        XCTAssertThrowsError(try MinutesQuotaSnapshot.parse(Data("{\"code\":99991641}".utf8))) { error in
            guard case MinutesQuotaSnapshot.Failure.authentication = error else { return XCTFail("Expected authentication failure") }
        }
    }
    func testProviderZeroIsValidAndMissingRefreshIsNotInvented() throws {
        let zero = try MinutesQuotaSnapshot.parse(response(remaining: 0, refresh: NSNull()))
        XCTAssertEqual(zero.remainingMinutes, 0); XCTAssertNil(zero.nextRefresh)
        let expired = try MinutesQuotaSnapshot.parse(response(refresh: 100))
        XCTAssertEqual(expired.nextRefresh, Date(timeIntervalSince1970: 100))
    }
}
