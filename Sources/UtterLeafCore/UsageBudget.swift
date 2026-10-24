import Foundation

/// Local rolling-budget guidance. It never enforces an API limit or represents a balance.
public struct UsageBudget {
    public let limit: Double
    public let spent: Double
    public let unknown: Int
    public let doubaoEstimated: Double
    public let deepSeekEstimated: Double
    public var providerTotal: Double { doubaoEstimated + deepSeekEstimated }
    public var doubaoFraction: Double? { providerTotal > 0 ? doubaoEstimated / providerTotal : nil }
    public var deepSeekFraction: Double? { providerTotal > 0 ? deepSeekEstimated / providerTotal : nil }
    public var doubaoToDeepSeek: Double? { deepSeekEstimated > 0 ? doubaoEstimated / deepSeekEstimated : nil }
    public let costPerCharacter: Double?
    public var remaining: Double { max(0, limit - spent) }
    public var remainingFraction: Double { limit > 0 ? min(1, remaining / limit) : 0 }
    public var allowanceCharacters: Double? { costPerCharacter.map { limit / $0 } }
    public var remainingCharacters: Double? { costPerCharacter.map { remaining / $0 } }
    public init(calls: [UsageCall], jobs: [HistoryJob], days: Int, limit: Double, now: Date = Date()) {
        self.limit = limit.isFinite && limit > 0 ? limit : 5
        let rows = calls.filter { $0.price.currency == "CNY" && $0.started >= now.addingTimeInterval(-Double(days) * 86400) && $0.started <= now }
        spent = rows.compactMap(\.estimatedAmount).reduce(0, +)
        doubaoEstimated = rows.filter { $0.provider == "Doubao" }.compactMap(\.estimatedAmount).reduce(0, +)
        deepSeekEstimated = rows.filter { $0.provider == "DeepSeek" }.compactMap(\.estimatedAmount).reduce(0, +)
        unknown = rows.filter { $0.estimatedAmount == nil }.count
        let grouped = Dictionary(grouping: rows, by: \.jobID)
        var characters = 0
        var matchedCost = 0.0
        for job in jobs where job.finalCharacters > 0 {
            guard let items = grouped[job.id], !items.isEmpty,
                  items.allSatisfy({ $0.estimatedAmount != nil && $0.status == .succeeded }),
                  items.contains(where: { $0.provider == "Doubao" }) else { continue }
            characters += job.finalCharacters
            matchedCost += items.compactMap(\.estimatedAmount).reduce(0, +)
        }
        costPerCharacter = characters > 0 && matchedCost > 0 ? matchedCost / Double(characters) : nil
    }
}
