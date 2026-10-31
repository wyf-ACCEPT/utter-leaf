import Foundation
import Combine
import UtterLeafCore

/// Profiles select isolated WebKit stores and quota caches, never a shared Cookie jar.
@MainActor final class MinutesAccountStore: ObservableObject {
    @Published private(set) var manifest: MinutesAccountsManifest
    @Published private(set) var active: MinutesQuotaStore
    @Published private(set) var error: String?
    @Published private(set) var duplicateProfileID: UUID?
    private var duplicateCandidate: MinutesQuotaStore?
    private let root: URL
    private let networkEnabled: Bool
    private var writable = true
    var canRefresh: () -> Bool = { true } { didSet { configure(active) } }
    var selected: UUID { manifest.selected }
    var profiles: [MinutesAccountProfile] { manifest.profiles.filter { $0.duplicateOf == nil } }
    var profile: MinutesAccountProfile { profiles.first { $0.id == selected }! }
    private var file: URL { root.appendingPathComponent("minutes-accounts-v1.json") }
    init(root: URL, networkEnabled: Bool = true) {
        self.root = root; self.networkEnabled = networkEnabled
        let path = root.appendingPathComponent("minutes-accounts-v1.json")
        var value = MinutesAccountsManifest(), loadFailed = false
        if FileManager.default.fileExists(atPath: path.path) {
            do {
                let data = try Data(contentsOf: path)
                guard data.count <= 1_048_576 else { throw Failure.storage }
                value = try JSONDecoder().decode(MinutesAccountsManifest.self, from: data)
                guard value.valid else { throw Failure.storage }
            } catch { value = MinutesAccountsManifest(); loadFailed = true }
        }
        manifest = value; writable = !loadFailed
        let profile = value.profiles.first { $0.id == value.selected }!
        active = MinutesQuotaStore(file: Self.cacheFile(root: root, id: profile.id), networkEnabled: networkEnabled && !loadFailed,
                                   sessionIdentifier: profile.id, preferredHost: profile.host)
        if loadFailed { error = "账号配置无法读取，已停止修改以保护原有数据。" }
        configure(active)
        if profile.id != MinutesAccountProfile.originalID && profile.identity == nil && active.snapshot == nil { active.prepareIdentitySelection() }
    }
    static func cacheFile(root: URL, id: UUID) -> URL {
        root.appendingPathComponent(id == MinutesAccountProfile.originalID ? "minutes-quota-v1.json" : "minutes-quota-\(id.uuidString.lowercased()).json")
    }
    private func configure(_ store: MinutesQuotaStore) {
        store.canRefresh = { [weak self] in guard let self else { return false }; return writable && canRefresh() }
        store.onAuthenticatedHost = { [weak self, weak store] host in
            guard let self, let store, store === active,
                  let index = manifest.profiles.firstIndex(where: { $0.id == store.sessionIdentifier }),
                  manifest.profiles[index].host != host, MinutesAccountProfile.validHost(host) else { return }
            var next = manifest; next.profiles[index].host = host
            do { try persist(next); manifest = next } catch { self.error = "账号登录已完成，但本机配置保存失败。" }
        }
        store.onIdentity = { [weak self, weak store] identity in
            guard let self, let store else { return .accepted }
            return acceptIdentity(identity, from: store)
        }
    }
    private func makeStore(_ profile: MinutesAccountProfile) -> MinutesQuotaStore {
        let store = MinutesQuotaStore(file: Self.cacheFile(root: root, id: profile.id), networkEnabled: networkEnabled,
                                     sessionIdentifier: profile.id, preferredHost: profile.host)
        configure(store)
        if profile.id != MinutesAccountProfile.originalID && profile.identity == nil && store.snapshot == nil { store.prepareIdentitySelection() }
        return store
    }
    private func acceptIdentity(_ identity: MinutesAccountIdentity, from store: MinutesQuotaStore) -> MinutesQuotaStore.IdentityDecision {
        guard (store === active || store === duplicateCandidate), identity.valid,
              let index = manifest.profiles.firstIndex(where: { $0.id == store.sessionIdentifier }) else { return .accepted }
        guard identity.subjectKey != nil else { return .unverifiable }
        var next = manifest; next.profiles[index].identity = identity; next.profiles[index].duplicateOf = nil
        if store === duplicateCandidate { next.selected = store.sessionIdentifier }
        let merged = next.mergeVerifiedDuplicates()
        if next != manifest {
            do { try persist(next) } catch { self.error = "身份校验已完成，但账号配置无法保存。"; return .unverifiable }
        }
        let newlyArchived = next.profiles.first { entry in
            merged[entry.id] != nil && manifest.profiles.first(where: { $0.id == entry.id })?.duplicateOf == nil
        }
        manifest = next
        if let removed = newlyArchived { duplicateProfileID = removed.id }
        if merged[store.sessionIdentifier] != nil {
            duplicateCandidate = store; store.suspend()
            if active === store { active = makeStore(profile) }
            error = nil; return .duplicate
        }
        if store === duplicateCandidate {
            active.suspend(); active = store; duplicateCandidate = nil; duplicateProfileID = nil
        }
        error = nil; return .accepted
    }
    func duplicateLoginContext() -> (MinutesAccountProfile, MinutesQuotaStore)? {
        guard let id = duplicateProfileID, let profile = manifest.profiles.first(where: { $0.id == id }) else { return nil }
        if duplicateCandidate?.sessionIdentifier != id { duplicateCandidate = makeStore(profile) }
        guard let store = duplicateCandidate else { return nil }
        return (profile, store)
    }
    func dismissDuplicateNotice() { duplicateProfileID = nil; duplicateCandidate?.suspend(); duplicateCandidate = nil }
    func select(_ id: UUID) throws {
        guard id != selected else { return }
        guard let profile = profiles.first(where: { $0.id == id }) else { throw Failure.storage }
        var next = manifest; next.selected = id
        try persist(next)
        active.suspend()
        let store = makeStore(profile)
        manifest = next; active = store; error = nil
    }
    @discardableResult func add(name: String) throws -> UUID {
        let name = try validated(name)
        var next = manifest; var profile = MinutesAccountProfile(name: name)
        profile.automaticName = MinutesAccountProfile.isPlaceholder(name)
        next.profiles.append(profile); next.selected = profile.id
        try persist(next)
        active.suspend()
        let store = MinutesQuotaStore(file: Self.cacheFile(root: root, id: profile.id), networkEnabled: networkEnabled,
                                     sessionIdentifier: profile.id, preferredHost: nil)
        configure(store); store.prepareIdentitySelection(); manifest = next; active = store; error = nil
        return profile.id
    }
    func rename(_ id: UUID, name: String) throws {
        let name = try validated(name, excluding: id)
        guard let index = manifest.profiles.firstIndex(where: { $0.id == id && $0.duplicateOf == nil }) else { throw Failure.storage }
        var next = manifest; next.profiles[index].name = name
        next.profiles[index].automaticName = false
        try persist(next); manifest = next; error = nil
    }
    func useAutomaticName(_ id: UUID) throws {
        guard let index = manifest.profiles.firstIndex(where: { $0.id == id && $0.duplicateOf == nil }) else { throw Failure.storage }
        var next = manifest; next.profiles[index].automaticName = true
        try persist(next); manifest = next; error = nil
    }
    private func validated(_ name: String, excluding id: UUID? = nil) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MinutesAccountProfile(name: value).valid else { throw Failure.name }
        guard !profiles.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { throw Failure.duplicate }
        return value
    }
    private func persist(_ value: MinutesAccountsManifest) throws {
        guard writable, value.valid else { throw Failure.storage }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(value)
            guard data.count <= 1_048_576 else { throw Failure.storage }
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { throw Failure.storage }
    }
    enum Failure: LocalizedError {
        case name, duplicate, storage
        var errorDescription: String? {
            switch self {
            case .name: return "请输入 1–60 个字符的账号名称，不要包含换行。"
            case .duplicate: return "已有同名账号，请换一个名称。"
            case .storage: return "账号配置无法保存，原有账号与登录状态已保留。"
            }
        }
    }
}
