import Foundation

public struct BillingConfiguration: Codable, Equatable {
    public var enabled = true
    public var instanceID = ""
    public var product = ""
    public var exclusiveInstance = false
    public init() {}
    // Keep the persisted string compatible with existing single-instance settings.
    public var instanceIDs: [String] {
        Array(Set(instanceID.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
    public var scopeKey: String { instanceIDs.joined(separator: ",") }
    public var validScope: Bool {
        instanceIDs.count <= 10 && instanceIDs.allSatisfy { id in
            id.count <= 256 && id.range(of: #"^[A-Za-z0-9_.:-]+$"#, options: .regularExpression) != nil
        }
    }
    public var hasScope: Bool { validScope && !instanceIDs.isEmpty }
}
public struct BillingSyncStatus: Codable {
    public var attempted: Date?
    public var succeeded: Date?
    public var errorCode: String?
    public init() {}
}
public struct AccountBalance: Codable, Equatable {
    public let currency: String
    public let total: Decimal
    public let granted: Decimal
    public let toppedUp: Decimal
}
public struct BalanceSnapshot: Codable {
    public let fetched: Date
    public let available: Bool
    public let balances: [AccountBalance]
}
public struct RemoteBill: Codable, Identifiable, Equatable {
    public let id: String
    public let instanceID: String
    public let product: String
    public let start: Date
    public let end: Date
    public let payable: Decimal
    public let currency: String
}
public struct BillingLedger: Codable {
    public var deepSeek = BillingSyncStatus()
    public var doubao = BillingSyncStatus()
    public var balances: [BalanceSnapshot] = []
    public var bills: [RemoteBill] = []
    public var scope: String?
    public init() {}
}
public enum BillingSyncPolicy {
    public static let interval: TimeInterval = 20 * 60
    public static func isDue(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval || now < lastAttempt
    }
    public static func months(now: Date) -> [String] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = calendar.date(byAdding: .day, value: -30, to: now)!
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start))!
        var months: [String] = []
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = calendar.timeZone; format.dateFormat = "yyyy-MM"
        while cursor <= now { months.append(format.string(from: cursor)); cursor = calendar.date(byAdding: .month, value: 1, to: cursor)! }
        return months
    }
}
public enum BillingPayloadError: Error { case invalid, scopeMismatch, remoteError, paginationLimit }
public enum BillingPayload {
    static func decimal(_ value: Any?) -> Decimal? {
        let string = (value as? String) ?? (value as? NSNumber)?.stringValue
        guard let string, string.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil, let number = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")), !number.isNaN else { return nil }
        return number
    }
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.isLenient = false
        return f.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
    public static func balance(_ data: Data, fetched: Date) throws -> BalanceSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let available = json["is_available"] as? Bool, let rows = json["balance_infos"] as? [[String: Any]], !rows.isEmpty else { throw BillingPayloadError.invalid }
        let balances = try rows.map { row -> AccountBalance in
            guard let currency = row["currency"] as? String, ["CNY", "USD"].contains(currency),
                  let total = decimal(row["total_balance"]), let granted = decimal(row["granted_balance"]), let top = decimal(row["topped_up_balance"]) else { throw BillingPayloadError.invalid }
            return AccountBalance(currency: currency, total: total, granted: granted, toppedUp: top)
        }
        guard Set(balances.map(\.currency)).count == balances.count else { throw BillingPayloadError.invalid }
        return BalanceSnapshot(fetched: fetched, available: available, balances: balances)
    }
    public static func bills(_ data: Data, scope: BillingConfiguration) throws -> (rows: [RemoteBill], total: Int) {
        guard scope.hasScope else { throw BillingPayloadError.scopeMismatch }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BillingPayloadError.invalid }
        if (json["ResponseMetadata"] as? [String: Any])?["Error"] != nil { throw BillingPayloadError.remoteError }
        guard let result = json["Result"] as? [String: Any], let rows = result["List"] as? [[String: Any]],
              let total = result["Total"] as? Int, total >= 0, (result["Warning"] as? String ?? "").isEmpty else { throw BillingPayloadError.invalid }
        let parsed = try rows.map { row -> RemoteBill in
            guard let instance = row["InstanceNo"] as? String, scope.instanceIDs.contains(instance),
                  let product = row["Product"] as? String, scope.product.isEmpty || product == scope.product else { throw BillingPayloadError.scopeMismatch }
            guard let id = row["BillDetailId"] as? String, !id.isEmpty,
                  let period = row["BillPeriod"] as? String, let start = date(row["ExpenseBeginTime"]), let end = date(row["ExpenseEndTime"]), start < end,
                  let payable = decimal(row["PayableAmount"]), let currency = row["Currency"] as? String, currency == "CNY" else { throw BillingPayloadError.invalid }
            return RemoteBill(id: period + ":" + id, instanceID: instance, product: product, start: start, end: end, payable: payable, currency: currency)
        }
        return (parsed, total)
    }
}
public struct BillComparison {
    public let official: Decimal
    public let localEstimate: Double
    public let matchedCalls: Int
    public let unknownCalls: Int
    public var difference: Double { NSDecimalNumber(decimal: official).doubleValue - localEstimate }
    public init(bills: [RemoteBill], calls: [UsageCall]) {
        // Multiple charge items can share an interval; count each local request only once.
        let unique = Dictionary(bills.map { ($0.instanceID + ":" + $0.id, $0) }, uniquingKeysWith: { _, new in new }).values
        official = unique.reduce(Decimal.zero) { $0 + $1.payable }
        let matching = calls.filter { call in
            call.provider == "Doubao" && call.price.currency == "CNY" && call.status != .pending &&
                unique.contains { call.started >= $0.start && (call.finished ?? call.started) <= $0.end }
        }
        matchedCalls = matching.count; unknownCalls = matching.filter { $0.estimatedAmount == nil }.count
        localEstimate = matching.compactMap(\.estimatedAmount).reduce(0, +)
    }
}
