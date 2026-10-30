import XCTest
@testable import UtterLeafCore

final class UsageWindowTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testWeekUsesMondayMidnightUTCRegardlessOfLocalDayOrYear() {
        let friday = UsageWindow(days: 7, now: date("2026-10-30T06:34:36Z"))
        XCTAssertEqual(friday.start, date("2026-10-26T00:00:00Z"))
        XCTAssertEqual(friday.end, date("2026-11-02T00:00:00Z"))
        let localMondayButStillSundayUTC = UsageWindow(days: 7, now: date("2026-11-01T23:59:59Z"))
        XCTAssertEqual(localMondayButStillSundayUTC, friday)
        let next = UsageWindow(days: 7, now: friday.end)
        XCTAssertEqual(next.start, friday.end)
        XCTAssertEqual(next.end, date("2026-11-09T00:00:00Z"))
        XCTAssertEqual(UsageWindow(days: 7, now: date("2027-01-01T12:00:00Z")).start, date("2026-12-28T00:00:00Z"))
    }

    func testMonthlyRangeRemainsExactlyThirtyDaysAndIncludesCurrentInstant() {
        let now = date("2026-10-30T06:34:36Z"), month = UsageWindow(days: 30, now: date("2026-10-30T06:34:36Z"))
        XCTAssertEqual(month.start, date("2026-09-30T06:34:36Z"))
        XCTAssertEqual(month.end, now)
        XCTAssertTrue(month.contains(now, asOf: now))
        XCTAssertTrue(month.contains(month.start, asOf: now))
        XCTAssertFalse(month.contains(month.start.addingTimeInterval(-0.001), asOf: now))
        XCTAssertFalse(month.contains(now.addingTimeInterval(1), asOf: now))
    }

    func testWeeklyResetPreservesHistoryAndMacPhoneAggregatesAgree() {
        let monday = date("2026-11-02T00:00:00Z")
        var before = HistoryJob(pipeline: .final); before.created = monday.addingTimeInterval(-1); before.finalCharacters = 100
        var after = HistoryJob(pipeline: .final); after.created = monday; after.finalCharacters = 25
        var oldCall = UsageCall(jobID: before.id, provider: "Doubao", model: "test", price: .init(version: "test", currency: "CNY", note: "test"))
        oldCall.started = before.created; oldCall.status = .succeeded; oldCall.estimatedAmount = 2
        var newCall = oldCall; newCall.id = UUID(); newCall.jobID = after.id; newCall.started = monday; newCall.estimatedAmount = 0.5
        var future = oldCall; future.id = UUID(); future.started = monday.addingTimeInterval(1); future.estimatedAmount = 100
        let calls = [oldCall, newCall, future], jobs = [before, after]
        let prior = UsageBudget(calls: calls, jobs: jobs, days: 7, limit: 5, now: monday.addingTimeInterval(-0.5))
        let current = UsageBudget(calls: calls, jobs: jobs, days: 7, limit: 5, now: monday)
        XCTAssertEqual(prior.spent, 2); XCTAssertEqual(current.spent, 0.5)
        XCTAssertEqual(current.writtenCharacters, 25)
        XCTAssertEqual(UsageBudget(calls: calls, jobs: jobs, days: 30, limit: 20, now: monday).spent, 2.5)

        var cache = CloudUsageCache()
        for item in calls {
            var row = CloudUsageRow(id: "call." + item.id.uuidString.lowercased(), kind: "call", source: cache.source, device: "Mac")
            row.job = item.jobID.uuidString; row.started = item.started.timeIntervalSince1970; row.purpose = "dictation"
            row.provider = "Doubao"; row.model = "test"; row.status = "succeeded"; row.currency = "CNY"; row.amount = item.estimatedAmount
            XCTAssertTrue(cache.merge(row))
        }
        for job in jobs {
            var row = CloudUsageRow(id: "job." + job.id.uuidString.lowercased(), kind: "job", source: cache.source, device: "Mac")
            row.started = job.created.timeIntervalSince1970; row.purpose = "dictation"; row.characters = job.finalCharacters
            XCTAssertTrue(cache.merge(row))
        }
        let phone = cache.window(days: 7, now: monday.timeIntervalSince1970)
        XCTAssertEqual(phone["spent"] as? Double, current.spent)
        XCTAssertEqual(phone["written"] as? Int, current.writtenCharacters)
        XCTAssertEqual(phone["periodStart"] as? Double, monday.timeIntervalSince1970)
        XCTAssertEqual(cache.rows.count, 5)
    }
}
