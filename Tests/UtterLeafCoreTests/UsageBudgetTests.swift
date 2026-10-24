import XCTest
@testable import UtterLeafCore

final class UsageBudgetTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func call(_ job: HistoryJob, daysAgo: Double, provider: String = "Doubao", cost: Double?, currency: String = "CNY") -> UsageCall {
        var row = UsageCall(jobID: job.id, provider: provider, model: "test", price: .init(version: "test", currency: currency, note: "test"))
        row.started = now.addingTimeInterval(-daysAgo * 86400); row.status = .succeeded; row.estimatedAmount = cost
        return row
    }
    func testRollingWindowsCurrencyAndDeduplicatedCharacters() {
        var job = HistoryJob(pipeline: .final); job.finalCharacters = 1000
        let rows = [call(job, daysAgo: 1, cost: 0.8), call(job, daysAgo: 1, provider: "DeepSeek", cost: 0.2), call(job, daysAgo: 8, cost: 2), call(job, daysAgo: 1, cost: 9, currency: "USD"), call(job, daysAgo: -1, cost: 9)]
        let week = UsageBudget(calls: rows, jobs: [job], days: 7, limit: 5, now: now)
        XCTAssertEqual(week.doubaoFraction!, 0.8, accuracy: 0.000001)
        XCTAssertEqual(week.deepSeekFraction!, 0.2, accuracy: 0.000001)
        XCTAssertEqual(week.doubaoToDeepSeek!, 4, accuracy: 0.000001)
        XCTAssertEqual(week.spent, 1, accuracy: 0.000001)
        XCTAssertEqual(week.remainingFraction, 0.8, accuracy: 0.000001)
        XCTAssertEqual(week.allowanceCharacters!, 5000, accuracy: 0.000001)
        XCTAssertEqual(UsageBudget(calls: rows, jobs: [job], days: 30, limit: 5, now: now).spent, 3)
    }
    func testUnknownCostsRemainVisibleAndDoNotCreateFalseProjection() {
        var job = HistoryJob(pipeline: .final); job.finalCharacters = 100
        let budget = UsageBudget(calls: [call(job, daysAgo: 1, cost: 0.2), call(job, daysAgo: 1, provider: "DeepSeek", cost: nil)], jobs: [job], days: 7, limit: 5, now: now)
        XCTAssertEqual(budget.unknown, 1); XCTAssertNil(budget.costPerCharacter)
        XCTAssertEqual(budget.spent, 0.2)
    }
    func testSingleProviderHasValidShareWithoutInfiniteRatio() {
        let job = HistoryJob(pipeline: .final)
        let budget = UsageBudget(calls: [call(job, daysAgo: 1, cost: 1), call(job, daysAgo: 1, provider: "DeepSeek", cost: nil)], jobs: [job], days: 7, limit: 5, now: now)
        XCTAssertEqual(budget.doubaoFraction, 1); XCTAssertEqual(budget.deepSeekFraction, 0)
        XCTAssertNil(budget.doubaoToDeepSeek); XCTAssertEqual(budget.unknown, 1)
    }
    func testExceededAndEmptyBudgets() {
        let job = HistoryJob(pipeline: .final)
        let exceeded = UsageBudget(calls: [call(job, daysAgo: 1, cost: 6)], jobs: [job], days: 7, limit: 5, now: now)
        XCTAssertEqual(exceeded.remaining, 0); XCTAssertEqual(exceeded.remainingFraction, 0)
        let empty = UsageBudget(calls: [], jobs: [], days: 7, limit: 5, now: now)
        XCTAssertNil(empty.doubaoFraction); XCTAssertNil(empty.doubaoToDeepSeek)
        XCTAssertEqual(empty.remainingFraction, 1); XCTAssertNil(empty.remainingCharacters)
    }
    func testWrittenCharactersUseDistinctFinalJobsWithinEachWindowRegardlessOfBilling() {
        var recent = HistoryJob(pipeline: .final); recent.created = now.addingTimeInterval(-86400); recent.finalCharacters = 120
        var older = HistoryJob(pipeline: .final); older.created = now.addingTimeInterval(-10 * 86400); older.finalCharacters = 80
        var future = HistoryJob(pipeline: .final); future.created = now.addingTimeInterval(10); future.finalCharacters = 999
        var rawOnly = HistoryJob(pipeline: .final); rawOnly.created = now; rawOnly.rawCharacters = 500
        let jobs = [recent, recent, older, future, rawOnly]
        let rows = [call(recent, daysAgo: 1, cost: 0.1), call(recent, daysAgo: 1, provider: "DeepSeek", cost: nil)]
        let week = UsageBudget(calls: rows, jobs: jobs, days: 7, limit: 5, now: now)
        XCTAssertEqual(week.writtenCharacters, 120)
        XCTAssertEqual(UsageBudget(calls: rows, jobs: jobs, days: 30, limit: 20, now: now).writtenCharacters, 200)
        recent.finalText = nil; recent.rawText = nil
        XCTAssertEqual(UsageBudget(calls: [], jobs: [recent], days: 7, limit: 5, now: now).writtenCharacters, 120)
    }

}
