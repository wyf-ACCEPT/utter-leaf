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
        let identity = try XCTUnwrap(MinutesAccountIdentity(userName: "Alex", organization: "Example Studio", subjectKey: String(repeating: "a", count: 64)))
        _ = original.onIdentity?(identity)
        XCTAssertEqual(accounts.profile.displayName, "Alex · Example Studio")
        try accounts.rename(accounts.selected, name: "我的工作账号")
        _ = original.onIdentity?(MinutesAccountIdentity(userName: "Alex", organization: "Other Studio", subjectKey: String(repeating: "a", count: 64))!)
        XCTAssertEqual(accounts.profile.displayName, "我的工作账号")
        try accounts.useAutomaticName(accounts.selected)
        XCTAssertEqual(accounts.profile.displayName, "Alex · Other Studio")
        let second = try accounts.add(name: "账号 2")
        XCTAssertTrue(accounts.profile.usesAutomaticName)
        _ = original.onIdentity?(MinutesAccountIdentity(userName: "Wrong", organization: "Wrong")!)
        XCTAssertNil(accounts.profile.identity)
        _ = accounts.active.onIdentity?(MinutesAccountIdentity(userName: "Sam", organization: "Personal", subjectKey: String(repeating: "b", count: 64))!)
        let restored = MinutesAccountStore(root: root, networkEnabled: false)
        XCTAssertEqual(restored.selected, second)
        XCTAssertEqual(restored.profile.displayName, "Sam · Personal")
        try restored.select(MinutesAccountProfile.originalID)
        XCTAssertEqual(restored.profile.displayName, "Alex · Other Studio")
    }
    private func identity(_ key: String?, kind: String = "organization") -> MinutesAccountIdentity {
        MinutesAccountIdentity(userName: "Alex", organization: "Example Studio", subjectKey: key.map { String(repeating: $0, count: 64) }, kind: kind)!
    }
    func testDuplicateMergeRequiresFingerprintAndNeverUsesDisplayName() {
        var value = MinutesAccountsManifest()
        value.profiles[0].identity = identity(nil)
        var second = MinutesAccountProfile(name: "账号 2"); second.identity = identity(nil)
        value.profiles.append(second); value.selected = second.id
        XCTAssertTrue(value.mergeVerifiedDuplicates().isEmpty)
        value.profiles[0].identity = identity("a"); value.profiles[1].identity = identity("b")
        XCTAssertTrue(value.mergeVerifiedDuplicates().isEmpty)
        value.profiles[1].identity = identity("a")
        XCTAssertEqual(value.mergeVerifiedDuplicates()[second.id], value.profiles[0].id)
        XCTAssertEqual(value.selected, value.profiles[0].id)
        XCTAssertTrue(value.valid)
        XCTAssertEqual(value.profiles.count, 2)
    }
    func testPersonalIdentityAndInvalidFingerprints() {
        XCTAssertEqual(identity("a", kind: "personal").displayName, "Alex · 个人账号")
        XCTAssertNil(MinutesAccountIdentity(userName: "Alex", organization: nil, subjectKey: "invalid")?.subjectKey)
        var value = MinutesAccountsManifest()
        value.profiles[0].identity = identity("a")
        var second = MinutesAccountProfile(name: "账号 2"); second.identity = identity("b", kind: "personal")
        value.profiles.append(second)
        XCTAssertTrue(value.mergeVerifiedDuplicates().isEmpty)
    }
    @MainActor func testDuplicateLoginIsArchivedAndCanBecomePersonalWithoutLosingCaches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = MinutesAccountStore(root: root, networkEnabled: false)
        XCTAssertEqual(accounts.active.onIdentity?(identity("a")), .accepted)
        let duplicate = try accounts.add(name: "账号 2")
        let candidate = accounts.active
        XCTAssertTrue(candidate.choosingIdentity)
        let cache = MinutesAccountStore.cacheFile(root: root, id: duplicate)
        let bytes = try snapshot(30); try bytes.write(to: cache)
        XCTAssertEqual(candidate.onIdentity?(identity("a")), .duplicate)
        XCTAssertEqual(accounts.profiles.count, 1)
        XCTAssertEqual(accounts.manifest.profiles.count, 2)
        XCTAssertEqual(accounts.selected, MinutesAccountProfile.originalID)
        XCTAssertEqual(accounts.duplicateProfileID, duplicate)
        XCTAssertEqual(try Data(contentsOf: cache), bytes)
        let (_, retry) = try XCTUnwrap(accounts.duplicateLoginContext())
        XCTAssertTrue(retry === candidate)
        XCTAssertEqual(retry.onIdentity?(identity("a")), .duplicate)
        XCTAssertEqual(accounts.profiles.count, 1)
        XCTAssertEqual(retry.onIdentity?(identity("b", kind: "personal")), .accepted)
        XCTAssertEqual(accounts.profiles.count, 2)
        XCTAssertEqual(accounts.selected, duplicate)
        XCTAssertNil(accounts.duplicateProfileID)
        XCTAssertEqual(accounts.profile.displayName, "Alex · 个人账号")
        XCTAssertTrue(accounts.active === retry)
        let restored = MinutesAccountStore(root: root, networkEnabled: false)
        XCTAssertEqual(restored.profiles.count, 2)
        XCTAssertEqual(restored.profile.displayName, "Alex · 个人账号")
        try restored.rename(duplicate, name: "个人")
        XCTAssertEqual(restored.profile.displayName, "个人")
    }
    @MainActor func testArchivedProfileDoesNotShiftRenameIndexAndUnverifiedIdentityCannotReplaceKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = MinutesAccountStore(root: root, networkEnabled: false)
        _ = accounts.active.onIdentity?(identity("a"))
        _ = try accounts.add(name: "账号 2")
        _ = accounts.active.onIdentity?(identity("a"))
        accounts.dismissDuplicateNotice()
        let unique = try accounts.add(name: "账号 3")
        _ = accounts.active.onIdentity?(identity("c"))
        XCTAssertEqual(accounts.active.onIdentity?(identity(nil)), .unverifiable)
        XCTAssertEqual(accounts.profile.identity?.subjectKey, String(repeating: "c", count: 64))
        try accounts.rename(unique, name: "独立账号")
        XCTAssertEqual(accounts.profile.name, "独立账号")
        XCTAssertTrue(accounts.manifest.valid)
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
