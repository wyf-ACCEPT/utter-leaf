import XCTest
import UtterLeafCore
@testable import UtterLeaf

final class MinutesAccountTests: XCTestCase {
    func testIdentityDisplayUsesOnlyValidatedNameAndOrganization() throws {
        let identity = try XCTUnwrap(MinutesAccountIdentity(userName: " Alex ", organization: "Example Studio"))
        XCTAssertEqual(identity.displayName, "Alex · Example Studio")
        XCTAssertTrue(identity.valid)
        XCTAssertEqual(MinutesAccountIdentity(userName: "Alex", organization: nil)?.displayName, "Alex")
        XCTAssertEqual(MinutesAccountIdentity(userName: nil, organization: "Example Studio")?.displayName, "Example Studio")
        XCTAssertEqual(MinutesAccountIdentity(userName: "Alex", organization: "alex")?.displayName, "Alex")
        XCTAssertNil(MinutesAccountIdentity(userName: "\n", organization: nil))
        XCTAssertNil(MinutesAccountIdentity(userName: String(repeating: "x", count: 121), organization: nil))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(identity)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["userName", "organization"])
        var first = MinutesAccountProfile(name: "默认账号"); first.identity = identity
        var second = MinutesAccountProfile(name: "账号 2"); second.identity = identity
        XCTAssertEqual(first.displayName, identity.displayName)
        XCTAssertEqual(second.displayName, identity.displayName)
        XCTAssertNotEqual(first.menuName(in: [first, second]), second.menuName(in: [first, second]))
    }
    @MainActor func testAutomaticNamesRespectManualAliasesAndIgnoreInactiveCallbacks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = MinutesAccountStore(root: root, networkEnabled: false)
        let original = accounts.active
        let identity = try XCTUnwrap(MinutesAccountIdentity(userName: "Alex", organization: "Example Studio"))
        original.onIdentity?(identity)
        XCTAssertEqual(accounts.profile.displayName, "Alex · Example Studio")
        try accounts.rename(accounts.selected, name: "我的工作账号")
        original.onIdentity?(MinutesAccountIdentity(userName: "Alex", organization: "Other Studio")!)
        XCTAssertEqual(accounts.profile.displayName, "我的工作账号")
        try accounts.useAutomaticName(accounts.selected)
        XCTAssertEqual(accounts.profile.displayName, "Alex · Other Studio")
        let second = try accounts.add(name: "账号 2")
        XCTAssertTrue(accounts.profile.usesAutomaticName)
        original.onIdentity?(MinutesAccountIdentity(userName: "Wrong", organization: "Wrong")!)
        XCTAssertNil(accounts.profile.identity)
        accounts.active.onIdentity?(MinutesAccountIdentity(userName: "Sam", organization: "Personal")!)
        let restored = MinutesAccountStore(root: root, networkEnabled: false)
        XCTAssertEqual(restored.selected, second)
        XCTAssertEqual(restored.profile.displayName, "Sam · Personal")
        try restored.select(MinutesAccountProfile.originalID)
        XCTAssertEqual(restored.profile.displayName, "Alex · Other Studio")
    }
    private func snapshot(_ minutes: Int) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": ["display_quota": ["remaining_asr_quota": minutes]]])
        return try JSONEncoder().encode(MinutesQuotaSnapshot.parse(data))
    }
    @MainActor func testLegacyLoginIdentityAndIndependentCachesSurviveSwitchingAndRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let originalCache = root.appendingPathComponent("minutes-quota-v1.json")
        try snapshot(148).write(to: originalCache)
        let accounts = MinutesAccountStore(root: root, networkEnabled: false)
        let original = accounts.active
        XCTAssertEqual(accounts.selected, MinutesAccountProfile.originalID)
        XCTAssertEqual(original.sessionIdentifier, MinutesAccountProfile.originalID)
        XCTAssertEqual(original.snapshot?.remainingMinutes, 148)
        let second = try accounts.add(name: "第二账号")
        XCTAssertNotEqual(second, original.sessionIdentifier)
        XCTAssertNil(accounts.active.snapshot)
        XCTAssertEqual(accounts.active.sessionIdentifier, second)
        XCTAssertFalse(original === accounts.active)
        XCTAssertEqual(accounts.active.authentication, .unverified)
        try snapshot(30).write(to: MinutesAccountStore.cacheFile(root: root, id: second))
        try accounts.select(MinutesAccountProfile.originalID)
        XCTAssertEqual(accounts.active.snapshot?.remainingMinutes, 148)
        try accounts.select(second)
        XCTAssertEqual(accounts.active.snapshot?.remainingMinutes, 30)
        try accounts.rename(second, name: "工作账号")
        let restored = MinutesAccountStore(root: root, networkEnabled: false)
        XCTAssertEqual(restored.selected, second)
        XCTAssertEqual(restored.profile.name, "工作账号")
        XCTAssertEqual(restored.active.snapshot?.remainingMinutes, 30)
        XCTAssertEqual(try JSONDecoder().decode(MinutesQuotaSnapshot.self, from: Data(contentsOf: originalCache)).remainingMinutes, 148)
        let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("minutes-accounts-v1.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    @MainActor func testInvalidNameAndFailedSavePreserveSelectedAccount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = MinutesAccountStore(root: root, networkEnabled: false)
        for name in [" ", "Line\nBreak", String(repeating: "x", count: 61), "默认账号"] {
            XCTAssertThrowsError(try accounts.add(name: name))
            XCTAssertEqual(accounts.profiles.count, 1)
            XCTAssertEqual(accounts.selected, MinutesAccountProfile.originalID)
        }
        try Data("not a directory".utf8).write(to: root)
        XCTAssertThrowsError(try accounts.add(name: "第二账号"))
        XCTAssertEqual(accounts.profiles.count, 1)
    }
    @MainActor func testMalformedRegistryIsNotOverwrittenAndForeignHostsAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("minutes-accounts-v1.json"), bytes = Data("{broken".utf8)
        try bytes.write(to: file)
        let accounts = MinutesAccountStore(root: root, networkEnabled: false)
        XCTAssertNotNil(accounts.error)
        XCTAssertThrowsError(try accounts.add(name: "第二账号"))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        for host in ["feishu.cn.evil.test", "accounts.feishu.cn@evil.test", "../feishu.cn", "a..feishu.cn"] {
            XCTAssertFalse(MinutesAccountProfile.validHost(host))
        }
        XCTAssertTrue(MinutesAccountProfile.validHost("meetings.feishu.cn"))
        XCTAssertTrue(MinutesAccountProfile.validHost("other-tenant.feishu.cn"))
    }
}
