import Foundation
import CoreFoundation

/// Provider quota only; never mixed with the user's CNY reminder budgets.
public struct MinutesQuotaSnapshot: Codable, Equatable {
    public struct Source: Codable, Equatable, Identifiable {
        public let id: Int
        public let title: String
        public let remaining: Double
        public let amount: Double?
        public let refresh: Date?
    }
    public let fetched: Date
    public let remainingMinutes: Double
    public let totalMinutes: Double?
    public let summaryRemaining: Double?
    public let sources: [Source]
    public var nextRefresh: Date? { sources.compactMap(\.refresh).min() }

    public enum Failure: Error { case authentication, invalidResponse }
    public static func parse(_ data: Data, fetched: Date = Date()) throws -> Self {
        guard data.count <= 1_048_576,
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidResponse }
        guard number(envelope["code"]) == 0 else {
            if [99991641.0, 99991663.0].contains(number(envelope["code"]) ?? -1) { throw Failure.authentication }
            throw Failure.invalidResponse
        }
        guard let body = envelope["data"] as? [String: Any], let display = body["display_quota"] as? [String: Any] else { throw Failure.invalidResponse }
        let entries = display["display_quota_list"] as? [[String: Any]] ?? []
        let asr = entries.first { $0["AuthKey"] as? String == "vc_asr_function_prem" && $0["IsVisible"] as? Bool == true }
        if let unit = asr?["QuotaUnit"] as? NSNumber, unit.intValue != 0 { throw Failure.invalidResponse }
        guard let remaining = number(display["remaining_asr_quota"] ?? asr?["Remaining"]) else { throw Failure.invalidResponse }
        let total = number(asr?["Amount"])
        if let total, total < remaining { throw Failure.invalidResponse }
        var sources: [Source] = []
        for (index, item) in (asr?["SourceList"] as? [[String: Any]] ?? []).enumerated() where item["IsVisible"] as? Bool == true {
            guard let title = item["DisplayText"] as? String, !title.isEmpty, title.count <= 120,
                  let value = number(item["Remaining"]) else { throw Failure.invalidResponse }
            let amount = number(item["Amount"])
            if let amount, amount < value { throw Failure.invalidResponse }
            let stamp = number(item["RefreshTime"], maximum: 100_000_000_000)
            sources.append(Source(id: index, title: title, remaining: value, amount: amount,
                                  refresh: stamp.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }))
        }
        return Self(fetched: fetched, remainingMinutes: remaining, totalMinutes: total,
                    summaryRemaining: number(display["remaining_ai_quota"]), sources: sources)
    }

    private static func number(_ value: Any?, maximum: Double = 1_000_000_000) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let result = value.doubleValue
        return result.isFinite && result >= 0 && result <= maximum ? result : nil
    }
}
