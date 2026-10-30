import Foundation
import Combine
import UtterLeafCore

/// Profiles select isolated WebKit stores and quota caches, never a shared Cookie jar.
@MainActor final class MinutesAccountStore: ObservableObject {
    @Published private(set) var manifest: MinutesAccountsManifest
    @Published private(set) var active: MinutesQuotaStore
    @Published private(set) var error: String?
    private let root: URL
    private let networkEnabled: Bool
    private var writable = true
    var canRefresh: () -> Bool = { true } { didSet { configure(active) } }
    var selected: UUID { manifest.selected }
    var profiles: [MinutesAccountProfile] { manifest.profiles }
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
    }
    func select(_ id: UUID) throws {
        guard id != selected else { return }
        guard let profile = profiles.first(where: { $0.id == id }) else { throw Failure.storage }
        var next = manifest; next.selected = id
        try persist(next)
        active.suspend()
        let store = MinutesQuotaStore(file: Self.cacheFile(root: root, id: id), networkEnabled: networkEnabled,
                                     sessionIdentifier: id, preferredHost: profile.host)
        configure(store); manifest = next; active = store; error = nil
    }
    @discardableResult func add(name: String) throws -> UUID {
        let name = try validated(name)
        var next = manifest; let profile = MinutesAccountProfile(name: name)
        next.profiles.append(profile); next.selected = profile.id
        try persist(next)
        active.suspend()
        let store = MinutesQuotaStore(file: Self.cacheFile(root: root, id: profile.id), networkEnabled: networkEnabled,
                                     sessionIdentifier: profile.id, preferredHost: nil)
        configure(store); manifest = next; active = store; error = nil
        return profile.id
    }
    func rename(_ id: UUID, name: String) throws {
        let name = try validated(name, excluding: id)
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw Failure.storage }
        var next = manifest; next.profiles[index].name = name
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
