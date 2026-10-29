import Foundation
import CloudKit
import Combine
import CryptoKit

public struct CloudVocabularyRow: Codable, Equatable {
    public var id: String
    public var source: String
    public var updated: Double
    public var entry: VocabularyEntry?
    public var deleted: Bool
    public init(entry: VocabularyEntry, source: String, updated: Double = Date().timeIntervalSince1970) {
        self.id = entry.id.uuidString.lowercased(); self.source = source; self.updated = updated
        self.entry = entry.normalized(); self.deleted = false
    }
    public var valid: Bool {
        guard UUID(uuidString: id)?.uuidString.lowercased() == id, UUID(uuidString: source) != nil, updated.isFinite, updated >= 0 else { return false }
        if deleted { return entry == nil }
        guard let entry, entry.id.uuidString.lowercased() == id, entry == entry.normalized() else { return false }
        return VocabularyContext.validationError(entry, existing: []) == nil
    }
}
public struct CloudVocabularyCache: Codable {
    public var source = UUID().uuidString
    public var accountHash: String?
    public var seeded = false
    public var rows: [String: CloudVocabularyRow] = [:]
    public var lastSync: Double?
    public var serverTag: String?
    public var ownedDigest: String?
    public init() {}
    public mutating func merge(_ incoming: CloudVocabularyRow) {
        guard incoming.valid else { return }
        var value = incoming
        if let old = rows[incoming.id] {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let a = (try? encoder.encode(old)) ?? Data(), b = (try? encoder.encode(incoming)) ?? Data()
            if old.updated > value.updated || (old.updated == value.updated && b.lexicographicallyPrecedes(a)) { value = old }
            if old.deleted || incoming.deleted { value.deleted = true; value.entry = nil }
        }
        rows[value.id] = value
    }
    public var owned: [CloudVocabularyRow] { rows.values.filter { $0.source == source && $0.valid } }
    public var entries: [VocabularyEntry] {
        var seen = Set<String>(), result: [VocabularyEntry] = []
        // Concurrent offline additions of the same spelling resolve consistently without duplicates.
        for row in rows.values.sorted(by: { $0.updated == $1.updated ? $0.id < $1.id : $0.updated > $1.updated }) {
            if !row.deleted, let entry = row.entry, seen.insert(entry.term.lowercased()).inserted { result.append(entry) }
            if result.count == 200 { break }
        }
        return result.sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
    }
}
@MainActor public final class CloudVocabularySync: ObservableObject {
    @Published public private(set) var cache = CloudVocabularyCache()
    @Published public private(set) var status = "等待同步"
    @Published public private(set) var syncing = false
    public private(set) var version = 0
    public var onChange: (() -> Void)?
    public var canSync: () -> Bool = { true }
    private let file: URL
    private let recordID = CKRecord.ID(recordName: "vocabulary.snapshot.v1")
    private var timer: Timer?
    private var scheduled: Task<Void, Never>?
    private var writable = true
    private var retryAt: Date = .distantPast
    public init(file: URL) {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            do { cache = try JSONDecoder().decode(CloudVocabularyCache.self, from: Data(contentsOf: file)) }
            catch { writable = false; status = "词汇表缓存无法读取，已停止写入" }
        }
    }
    public var entries: [VocabularyEntry] { cache.entries }
    public func seed(_ entries: [VocabularyEntry]) {
        guard writable, !cache.seeded else { return }
        for entry in entries { cache.merge(.init(entry: entry, source: cache.source, updated: 0)) }
        cache.seeded = true; persist()
    }
    public func upsert(_ entry: VocabularyEntry) throws {
        guard writable else { throw VocabularySyncFailure.invalid("词汇表无法保存，请检查本机存储。") }
        let normalized = entry.normalized(), id = entry.id.uuidString.lowercased()
        if cache.rows[id]?.deleted == true { throw VocabularySyncFailure.invalid("此词条已删除，请重新添加。") }
        if let error = VocabularyContext.validationError(normalized, existing: entries) { throw VocabularySyncFailure.invalid(error) }
        if cache.rows[id]?.entry == normalized { return }
        cache.merge(.init(entry: normalized, source: cache.source)); persist(); changed(); requestSync()
        if !writable { throw VocabularySyncFailure.invalid("词汇表未能写入本机，请重试。") }
    }
    public func delete(_ id: UUID) throws {
        guard writable else { throw VocabularySyncFailure.invalid("词汇表无法保存，请检查本机存储。") }
        guard var value = cache.rows[id.uuidString.lowercased()], !value.deleted else { return }
        value.entry = nil; value.deleted = true; value.source = cache.source; value.updated = Date().timeIntervalSince1970
        cache.merge(value); persist(); changed(); requestSync()
        if !writable { throw VocabularySyncFailure.invalid("删除未能写入本机，请重试。") }
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
        } catch { writable = false; status = "词汇表保存失败，已停止同步" }
    }
    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
        requestSync()
    }
    public func stop() { timer?.invalidate(); timer = nil; scheduled?.cancel(); scheduled = nil }
    public func requestSync() {
        guard timer != nil, scheduled == nil else { return }
        scheduled = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }; scheduled = nil; await sync()
        }
    }
    public func sync() async {
        guard writable, !syncing, canSync(), Date() >= retryAt else { return }
        #if os(macOS)
        guard FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile").path) else {
            status = "Mac 尚未配置 iCloud 签名"; changed(); return
        }
        #elseif targetEnvironment(simulator)
        status = "模拟器未连接 iCloud；显示本机词汇表"; changed(); return
        #endif
        syncing = true; status = "正在同步词汇表…"; changed()
        defer { syncing = false; changed() }
        do {
            let container = CKContainer(identifier: "iCloud.network.utterleaf.usage")
            guard try await container.accountStatus() == .available else { status = "请登录 iCloud；词汇已保存在本机"; return }
            let account = digest(Data(try await container.userRecordID().recordName.utf8))
            if let old = cache.accountHash, old != account { status = "iCloud 账户已变更，已暂停词汇同步"; return }
            cache.accountHash = account; persist()
            guard writable else { return }
            let db = container.privateCloudDatabase
            let header = try await read(db, metadataOnly: true)
            if let header, cache.serverTag == header.recordChangeTag, cache.ownedDigest == digest(try encode(cache.owned)) {
                cache.lastSync = Date().timeIntervalSince1970; status = "已同步 · 私有 iCloud"; persist(); return
            }
            let record = header == nil ? nil : try await read(db, metadataOnly: false)
            var remote = CloudVocabularyCache()
            if let record {
                guard record.recordType == "LeafVocabularySnapshotV1", let asset = record["blob"] as? CKAsset, let url = asset.fileURL,
                      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024 else { throw VocabularySyncFailure.invalid("词汇表数据异常") }
                let data = try Data(contentsOf: url)
                guard record["checksum"] as? String == digest(data) else { throw VocabularySyncFailure.invalid("词汇表校验失败") }
                for row in try JSONDecoder().decode([CloudVocabularyRow].self, from: data) {
                    guard row.valid else { throw VocabularySyncFailure.invalid("词汇表格式异常") }; remote.merge(row)
                }
            }
            for row in remote.rows.values { cache.merge(row) }
            persist(); changed()
            guard writable else { return }
            let own = cache.owned
            for row in own { remote.merge(row) }
            let payload = try encode(Array(remote.rows.values)), checksum = digest(payload)
            guard payload.count <= 8 * 1024 * 1024 else { throw VocabularySyncFailure.invalid("词汇表同步空间已满") }
            var saved = record
            if record == nil || record?["checksum"] as? String != checksum {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("utterleaf-vocabulary-" + UUID().uuidString)
                try payload.write(to: temp, options: .atomic)
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temp.path)
                #else
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
                #endif
                defer { try? FileManager.default.removeItem(at: temp) }
                let value = record ?? CKRecord(recordType: "LeafVocabularySnapshotV1", recordID: recordID)
                value["blob"] = CKAsset(fileURL: temp); value["checksum"] = checksum as NSString
                let response = try await db.modifyRecords(saving: [value], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                guard let result = response.saveResults[recordID] else { throw VocabularySyncFailure.invalid("未收到同步回执") }
                saved = try result.get()
            }
            cache.serverTag = saved?.recordChangeTag; cache.ownedDigest = digest(try encode(own)); cache.lastSync = Date().timeIntervalSince1970
            status = "已同步 · 私有 iCloud"; persist()
            if cache.ownedDigest != digest(try encode(cache.owned)) { requestSync() }
        } catch { retryAt = Date().addingTimeInterval(max(5, ((error as NSError).userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue ?? 15)); status = "词汇同步未完成，本机记录已保留" }
    }
    private func read(_ db: CKDatabase, metadataOnly: Bool) async throws -> CKRecord? {
        do {
            let values = try await db.records(for: [recordID], desiredKeys: metadataOnly ? ["checksum"] : nil)
            guard let result = values[recordID] else { throw VocabularySyncFailure.invalid("缺少同步回执") }; return try result.get()
        } catch let error as CKError where error.code == .unknownItem { return nil }
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func encode(_ rows: [CloudVocabularyRow]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(rows.sorted { $0.id < $1.id })
    }
    public var snapshot: [String: Any] {
        ["status": status, "syncing": syncing, "lastSync": cache.lastSync ?? 0,
         "entries": entries.map { ["id": $0.id.uuidString.lowercased(), "term": $0.term, "aliases": $0.aliases, "note": $0.note, "enabled": $0.enabled] as [String: Any] }]
    }
    public var diagnostic: [String: Any] { ["status": status, "lastSync": cache.lastSync ?? 0, "count": entries.count, "enabled": entries.filter(\.enabled).count] }
}
private enum VocabularySyncFailure: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let value) = self { return value }; return nil }
}
