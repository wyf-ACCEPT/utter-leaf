import Foundation

/// Display metadata only. No account IDs, email, phone or session fields.
public struct MinutesAccountIdentity: Codable, Equatable {
    public let userName: String?
    public let organization: String?
    public init?(userName: String?, organization: String?) {
        self.userName = Self.clean(userName); self.organization = Self.clean(organization)
        if self.userName == nil && self.organization == nil { return nil }
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
    }
    public var displayName: String {
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
            && (identity?.valid ?? true)
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
            && Set(profiles.map(\.id)).count == profiles.count && profiles.contains { $0.id == selected }
    }
}
