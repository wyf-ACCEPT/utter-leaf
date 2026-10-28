import Foundation
import CloudKit
import Combine
import CryptoKit

/// Dictation text only. Meeting content, audio, targets and credentials are excluded.
public struct CloudHistoryRow: Codable, Equatable {
    public var id: String
    public var source: String
    public var device: String
    public var created: Double
    public var updated: Double
    public var seconds: Double
    public var raw: String?
    public var final: String?
    public var erased = false
    public var rawRemoved = false
    public init(id: String, source: String, device: String, created: Double, seconds: Double, raw: String?, final: String?) {
        self.id = id; self.source = source; self.device = device; self.created = created
        self.updated = Date().timeIntervalSince1970; self.seconds = seconds; self.raw = raw; self.final = final
    }
    public var valid: Bool {
        UUID(uuidString: id)?.uuidString.lowercased() == id && UUID(uuidString: source) != nil &&
        ["Mac", "iPhone"].contains(device) && created.isFinite && created >= 0 && updated.isFinite && updated >= 0 &&
        seconds.isFinite && seconds >= 0 && seconds <= 86400 && [raw, final].allSatisfy { ($0?.utf8.count ?? 0) <= 2_000_000 }
    }
}
public struct CloudHistoryCache: Codable {
    public var source = UUID().uuidString
    public var accountHash: String?
    public var rows: [String: CloudHistoryRow] = [:]
    public var enabled = true
    public var lastSync: Double?
    public var serverTag: String?
    public var ownedDigest: String?
    public init() {}
    /// Redaction is monotonic, so an offline device cannot restore cleared text.
    public mutating func merge(_ incoming: CloudHistoryRow) {
        guard incoming.valid else { return }
        var value = incoming
        if let old = rows[incoming.id] {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let oldData = (try? encoder.encode(old)) ?? Data(), newData = (try? encoder.encode(incoming)) ?? Data()
            if old.updated > incoming.updated || (old.updated == incoming.updated && newData.lexicographicallyPrecedes(oldData)) { value = old }
            value.erased = old.erased || incoming.erased
            value.rawRemoved = old.rawRemoved || incoming.rawRemoved
        }
        if value.erased { value.raw = nil; value.final = nil }
        if value.rawRemoved { value.raw = nil }
        rows[value.id] = value
    }
    public var owned: [CloudHistoryRow] { rows.values.filter { $0.source == source && $0.valid } }
    public var visible: [CloudHistoryRow] { rows.values.filter { !$0.erased && ($0.raw != nil || $0.final != nil) }.sorted { $0.created > $1.created } }
}

@MainActor public final class CloudHistorySync: ObservableObject {
    @Published public private(set) var cache = CloudHistoryCache()
    @Published public private(set) var status = "等待同步"
    @Published public private(set) var syncing = false
    public private(set) var version = 0
    public var canSync: () -> Bool = { true }
    public var onChange: (() -> Void)?
    public var onRemoteChange: (() -> Void)?
    private let file: URL
    private let device: String
    private let recordID = CKRecord.ID(recordName: "history.snapshot.v1")
    private var writable = true
    private var timer: Timer?
    private var scheduled: Task<Void, Never>?
    private var retryAt: Date = .distantPast
    public init(file: URL, device: String) {
        self.file = file; self.device = device
        if FileManager.default.fileExists(atPath: file.path) {
            do { cache = try JSONDecoder().decode(CloudHistoryCache.self, from: Data(contentsOf: file)) }
            catch { writable = false; status = "历史记录无法读取，已停止写入" }
        }
    }
    public func setEnabled(_ value: Bool) {
        cache.enabled = value; status = value ? "等待同步" : "此设备已关闭历史同步"; persist(); changed()
        if value { requestSync() }
    }
    public func upsert(id: String, created: Double, seconds: Double, raw: String?, final: String?, rawRemoved: Bool = false) {
        guard raw != nil || final != nil || cache.rows[id] != nil else { return }
        var value = CloudHistoryRow(id: id.lowercased(), source: cache.source, device: device, created: created, seconds: seconds, raw: raw, final: final)
        value.rawRemoved = rawRemoved
        if let old = cache.rows[value.id] {
            if old.erased { return }
            value.rawRemoved = old.rawRemoved || rawRemoved
            if value.rawRemoved { value.raw = nil }
            if old.raw == value.raw && old.final == final && old.rawRemoved == value.rawRemoved && old.seconds == seconds { return }
        }
        guard value.valid else { return }
        cache.merge(value); persist(); changed(); requestSync()
    }
    public func erase(_ id: String) {
        guard var value = cache.rows[id], !value.erased else { return }
        value.source = cache.source; value.updated = Date().timeIntervalSince1970
        value.erased = true; value.raw = nil; value.final = nil
        cache.merge(value); persist(); changed(); requestSync()
    }
    public func eraseAll() { for id in Array(cache.rows.keys) { erase(id) } }
    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
        requestSync()
    }
    public func stop() { timer?.invalidate(); timer = nil; scheduled?.cancel(); scheduled = nil }
    public func requestSync() {
        guard timer != nil, scheduled == nil, cache.enabled else { return }
        scheduled = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }; scheduled = nil; await sync()
        }
    }
    private func changed() { version &+= 1; onChange?() }
    private func persist() {
        guard writable else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: file, options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            #else
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            #endif
        } catch { writable = false; status = "历史保存失败，已停止写入" }
    }
    public func sync() async {
        guard writable, !syncing, canSync(), Date() >= retryAt else { return }
        guard cache.enabled else { status = "此设备已关闭历史同步"; changed(); return }
        #if os(macOS)
        guard FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile").path) else {
            status = "Mac 尚未配置 iCloud 签名"; changed(); return
        }
        #endif
        #if targetEnvironment(simulator)
        status = "模拟器未连接 iCloud；显示本地历史"; changed(); return
        #endif
        syncing = true; status = "正在同步历史…"; changed()
        defer { syncing = false; changed() }
        do {
            let container = CKContainer(identifier: "iCloud.network.utterleaf.usage")
            guard try await container.accountStatus() == .available else { status = "请登录 iCloud；历史已保留在本机"; return }
            let account = digest(Data(try await container.userRecordID().recordName.utf8))
            if let previous = cache.accountHash, previous != account { status = "iCloud 账户已变更，已暂停历史同步"; return }
            cache.accountHash = account; persist()
            let database = container.privateCloudDatabase
            let header = try await read(database, metadataOnly: true)
            let ownedDigest = digest(try encode(cache.owned))
            if let header, header.recordChangeTag == cache.serverTag, ownedDigest == cache.ownedDigest {
                cache.lastSync = Date().timeIntervalSince1970; status = "已同步 · 私有 iCloud"; persist(); return
            }
            let record = header == nil ? nil : try await read(database, metadataOnly: false)
            var remote = CloudHistoryCache()
            if let record {
                guard record.recordType == "LeafHistorySnapshotV1", let asset = record["blob"] as? CKAsset, let url = asset.fileURL,
                      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024 * 1024 else { throw HistoryFailure.invalid }
                let data = try Data(contentsOf: url)
                guard record["checksum"] as? String == digest(data) else { throw HistoryFailure.invalid }
                for row in try JSONDecoder().decode([CloudHistoryRow].self, from: data) {
                    guard row.valid else { throw HistoryFailure.invalid }; remote.merge(row)
                }
            }
            for row in remote.rows.values { cache.merge(row) }
            persist(); onRemoteChange?(); changed()
            let own = cache.owned
            for row in own { remote.merge(row) }
            let payload = try encode(Array(remote.rows.values)), checksum = digest(payload)
            guard payload.count <= 64 * 1024 * 1024 else { throw HistoryFailure.invalid }
            var saved = record
            if record == nil || record?["checksum"] as? String != checksum {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("utterleaf-history-" + UUID().uuidString)
                try payload.write(to: temp, options: .atomic)
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temp.path)
                #else
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
                #endif
                defer { try? FileManager.default.removeItem(at: temp) }
                let value = record ?? CKRecord(recordType: "LeafHistorySnapshotV1", recordID: recordID)
                value["blob"] = CKAsset(fileURL: temp); value["checksum"] = checksum as NSString
                let response = try await database.modifyRecords(saving: [value], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                guard let result = response.saveResults[recordID] else { throw HistoryFailure.invalid }
                saved = try result.get()
            }
            cache.serverTag = saved?.recordChangeTag; cache.ownedDigest = digest(try encode(own))
            cache.lastSync = Date().timeIntervalSince1970; status = "已同步 · 私有 iCloud"; persist()
            if digest(try encode(cache.owned)) != cache.ownedDigest { requestSync() }
        } catch {
            let delay = ((error as NSError).userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue ?? 15
            retryAt = Date().addingTimeInterval(max(5, delay))
            status = "历史同步暂未完成，本机记录已保留"
        }
    }
    private func read(_ database: CKDatabase, metadataOnly: Bool) async throws -> CKRecord? {
        do {
            let result = try await database.records(for: [recordID], desiredKeys: metadataOnly ? ["checksum"] : nil)
            guard let item = result[recordID] else { throw HistoryFailure.invalid }; return try item.get()
        } catch let error as CKError where error.code == .unknownItem { return nil }
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func encode(_ rows: [CloudHistoryRow]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(rows.sorted { $0.id < $1.id })
    }
    public var snapshot: [String: Any] {
        ["status": status, "syncing": syncing, "enabled": cache.enabled, "lastSync": cache.lastSync ?? 0,
         "rows": cache.visible.map { ["id": $0.id, "device": $0.device, "created": $0.created, "seconds": $0.seconds, "raw": $0.raw ?? "", "final": $0.final ?? ""] as [String: Any] }]
    }
    public var diagnostic: [String: Any] {
        ["status": status, "lastSync": cache.lastSync ?? 0, "count": cache.visible.count,
         "mac": cache.visible.filter { $0.device == "Mac" }.count, "phone": cache.visible.filter { $0.device == "iPhone" }.count]
    }
}
private enum HistoryFailure: Error { case invalid }
