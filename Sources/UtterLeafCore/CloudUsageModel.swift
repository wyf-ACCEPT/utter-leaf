import Foundation

/// A strict metadata envelope. No transcript, audio, credentials, app targets or free-form notes.
public struct CloudUsageRow: Codable, Equatable {
    public var id: String
    public var kind: String
    public var source: String
    public var device: String
    public var updated: Double = 0
    public var job: String?
    public var started: Double?
    public var purpose: String?
    public var provider: String?
    public var model: String?
    public var status: String?
    public var currency: String?
    public var amount: Double?
    public var actual: Double?
    public var seconds: Double?
    public var input: Int?
    public var cached: Int?
    public var output: Int?
    public var characters: Int?
    public var weekly: Double?
    public var monthly: Double?
    public init(id: String, kind: String, source: String, device: String) {
        self.id = id; self.kind = kind; self.source = source; self.device = device
    }
    public var valid: Bool {
        guard UUID(uuidString: source) != nil, ["Mac", "iPhone"].contains(device), updated.isFinite, updated >= 0 else { return false }
        if kind == "budget" { return id == "budget.v1" && [weekly, monthly].allSatisfy { $0.map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } == true } }
        guard ["call", "job"].contains(kind), id.hasPrefix(kind + "."), UUID(uuidString: String(id.dropFirst(kind.count + 1)))?.uuidString.lowercased() == String(id.dropFirst(kind.count + 1)),
              let started, started.isFinite, started >= 0, ["dictation", "meeting"].contains(purpose),
              [amount, actual, seconds].allSatisfy({ $0.map { $0.isFinite && $0 >= 0 && $0 <= 100_000_000 } ?? true }),
              [input, cached, output, characters].allSatisfy({ $0.map { $0 >= 0 && $0 <= 1_000_000_000 } ?? true }) else { return false }
        if kind == "job" { return true }
        guard UUID(uuidString: job ?? "") != nil, ["Doubao", "DeepSeek"].contains(provider),
              ["pending", "succeeded", "failed", "cancelled", "interrupted"].contains(status),
              let model, !model.isEmpty, model.count <= 96, model.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil,
              let currency, currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { return false }
        return true
    }
    public var data: Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
    public func wins(over other: Self) -> Bool {
        if updated != other.updated { return updated > other.updated }
        return other.data.lexicographicallyPrecedes(data)
    }
}

public struct CloudUsageCache: Codable {
    public var source = UUID().uuidString
    public var accountHash: String?
    public var rows: [String: CloudUsageRow] = [:]
    public var lastSync: Double?
    public var serverTag: String?
    public var ownedDigest: String?
    public init() {}
    @discardableResult public mutating func merge(_ incoming: CloudUsageRow) -> Bool {
        guard incoming.valid else { return false }
        if let old = rows[incoming.id], !incoming.wins(over: old) { return false }
        rows[incoming.id] = incoming; return true
    }
    /// Only original records from this installation can be uploaded. Cached remote rows never migrate accounts.
    public var owned: [CloudUsageRow] { rows.values.filter { $0.source == source && $0.valid } }
    public var week: Double { rows["budget.v1"]?.weekly ?? 5 }
    public var month: Double { rows["budget.v1"]?.monthly ?? 20 }
    public func window(days: Int, now: Double = Date().timeIntervalSince1970) -> [String: Any] {
        let cutoff = now - Double(days) * 86400
        let calls = rows.values.filter { $0.kind == "call" && $0.currency == "CNY" && ($0.started ?? 0) >= cutoff && ($0.started ?? 0) <= now }
        let jobs = rows.values.filter { $0.kind == "job" && ($0.started ?? 0) >= cutoff && ($0.started ?? 0) <= now }
        let spent = calls.compactMap(\.amount).reduce(0, +), limit = days == 7 ? week : month
        let dictation = calls.filter { $0.purpose == "dictation" }.compactMap(\.amount).reduce(0, +)
        let meeting = spent - dictation
        let written = jobs.filter { $0.purpose == "dictation" }.compactMap(\.characters).reduce(0, +)
        var matchedCost = 0.0, matchedCharacters = 0
        for job in rows.values where job.kind == "job" && job.purpose == "dictation" && (job.characters ?? 0) > 0 {
            let id = String(job.id.dropFirst(4))
            let related = calls.filter { $0.job?.lowercased() == id.lowercased() }
            if !related.isEmpty && related.allSatisfy({ $0.amount != nil && $0.status == "succeeded" }) && related.contains(where: { $0.provider == "Doubao" }) {
                matchedCharacters += job.characters ?? 0; matchedCost += related.compactMap(\.amount).reduce(0, +)
            }
        }
        var result: [String: Any] = ["days": days, "spent": spent, "budget": limit, "remaining": max(0, limit - spent),
            "remainingFraction": max(0, 1 - spent / limit), "dictationFraction": dictation / max(limit, spent),
            "meetingFraction": meeting / max(limit, spent), "written": written,
            "unknown": calls.filter { $0.amount == nil }.count, "calls": calls.count,
            "mac": calls.filter { $0.device == "Mac" }.compactMap(\.amount).reduce(0, +),
            "phone": calls.filter { $0.device == "iPhone" }.compactMap(\.amount).reduce(0, +),
            "dictation": dictation, "meeting": meeting]
        if matchedCost > 0 && matchedCharacters > 0 {
            result["remainingCharacters"] = max(0, limit - spent) * Double(matchedCharacters) / matchedCost
            result["perThousand"] = matchedCost / Double(matchedCharacters) * 1000
        }
        let meetingSeconds = jobs.filter { $0.purpose == "meeting" }.compactMap(\.seconds).reduce(0, +)
        if meetingSeconds > 0 { result["meetingPerHour"] = meeting / meetingSeconds * 3600 }
        return result
    }
}
