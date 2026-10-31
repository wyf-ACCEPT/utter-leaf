import Foundation

/// Display metadata and a one-way identity fingerprint, never raw IDs or credentials.
public struct MinutesAccountIdentity: Codable, Equatable {
    public let userName: String?
    public let organization: String?
    public let subjectKey: String?
    public let kind: String?
    public init?(userName: String?, organization: String?, subjectKey: String? = nil, kind: String? = nil) {
        self.userName = Self.clean(userName); self.organization = Self.clean(organization)
        self.subjectKey = subjectKey.flatMap { Self.validKey($0) ? $0.lowercased() : nil }
        self.kind = kind.flatMap { ["personal", "organization"].contains($0) ? $0 : nil }
        if self.userName == nil && self.organization == nil { return nil }
    }
    private static func validKey(_ value: String) -> Bool {
        value.count == 64 && value.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil
    }
    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= 120 && text.rangeOfCharacter(from: .controlCharacters) == nil ? text : nil
    }
    public var valid: Bool {
        (userName != nil || organization != nil)
            && (userName.map { Self.clean($0) == $0 } ?? true)
            && (organization.map { Self.clean($0) == $0 } ?? true)
            && (subjectKey.map(Self.validKey) ?? true)
            && (kind.map { ["personal", "organization"].contains($0) } ?? true)
    }
    public var displayName: String {
        if kind == "personal" { return userName.map { $0 + " · 个人账号" } ?? "个人账号" }
        if let userName, let organization, userName.caseInsensitiveCompare(organization) != .orderedSame { return userName + " · " + organization }
        return userName ?? organization ?? ""
    }
}

public struct MinutesAccountProfile: Codable, Equatable, Identifiable {
    public static let originalID = UUID(uuidString: "B19683D3-4195-4B82-8620-6D3E45048CC2")!
    public var id: UUID
    public var name: String
    public var host: String?
    public var identity: MinutesAccountIdentity?
    public var automaticName: Bool?
    public var duplicateOf: UUID?
    public init(id: UUID = UUID(), name: String, host: String? = nil) { self.id = id; self.name = name; self.host = host }
    public static func isPlaceholder(_ value: String) -> Bool {
        value == "默认账号" || value.range(of: "^账号\\s*[0-9]+$", options: .regularExpression) != nil
    }
    public var usesAutomaticName: Bool { automaticName ?? Self.isPlaceholder(name) }
    public var displayName: String { usesAutomaticName ? identity?.displayName ?? name : name }
    public func menuName(in profiles: [Self]) -> String {
        guard profiles.filter({ $0.displayName == displayName }).count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return displayName }
        return displayName + "（\(index + 1)）"
    }
    public static func validHost(_ host: String) -> Bool {
        host.count <= 253 && (host == "feishu.cn" || host.hasSuffix(".feishu.cn"))
            && host.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.").contains($0) }
            && host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0.count <= 63 }
    }
    public var valid: Bool {
        !name.isEmpty && name.count <= 60 && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && name.rangeOfCharacter(from: .controlCharacters) == nil && (host.map(Self.validHost) ?? true)
            && (identity?.valid ?? true) && duplicateOf != id
    }
}

public struct MinutesAccountsManifest: Codable, Equatable {
    public var version = 1
    public var profiles: [MinutesAccountProfile]
    public var selected: UUID
    public init() {
        let profile = MinutesAccountProfile(id: MinutesAccountProfile.originalID, name: "默认账号", host: "ucnaknhwgwdu.feishu.cn")
        profiles = [profile]; selected = profile.id
    }
    public var valid: Bool {
        version == 1 && !profiles.isEmpty && profiles.allSatisfy(\.valid)
            && Set(profiles.map(\.id)).count == profiles.count && profiles.contains { $0.id == selected && $0.duplicateOf == nil }
            && profiles.allSatisfy { profile in profile.duplicateOf.map { parent in profiles.contains { $0.id == parent && $0.duplicateOf == nil } } ?? true }
    }
    /// Archive only verified identical identities. Cookie stores and quota files are untouched.
    @discardableResult public mutating func mergeVerifiedDuplicates() -> [UUID: UUID] {
        var owners: [String: UUID] = [:], merged: [UUID: UUID] = [:]
        for index in profiles.indices {
            profiles[index].duplicateOf = nil
            guard let key = profiles[index].identity?.subjectKey else { continue }
            if let owner = owners[key] {
                profiles[index].duplicateOf = owner; merged[profiles[index].id] = owner
            } else { owners[key] = profiles[index].id }
        }
        if let owner = merged[selected] { selected = owner }
        return merged
    }
}
