import Foundation

public struct MinutesAccountProfile: Codable, Equatable, Identifiable {
    public static let originalID = UUID(uuidString: "B19683D3-4195-4B82-8620-6D3E45048CC2")!
    public var id: UUID
    public var name: String
    public var host: String?
    public init(id: UUID = UUID(), name: String, host: String? = nil) { self.id = id; self.name = name; self.host = host }
    public static func validHost(_ host: String) -> Bool {
        host.count <= 253 && (host == "feishu.cn" || host.hasSuffix(".feishu.cn"))
            && host.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.").contains($0) }
            && host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0.count <= 63 }
    }
    public var valid: Bool {
        !name.isEmpty && name.count <= 60 && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && name.rangeOfCharacter(from: .controlCharacters) == nil && (host.map(Self.validHost) ?? true)
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
