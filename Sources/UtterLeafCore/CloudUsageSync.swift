import Foundation
import CloudKit
import Combine
import CryptoKit

@MainActor public final class CloudUsageSync: ObservableObject {
    @Published public private(set) var cache = CloudUsageCache()
    @Published public private(set) var status = "等待同步"
    @Published public private(set) var syncing = false
    public private(set) var version = 0
    public var onChange: (() -> Void)?
    public var onRemoteBudget: ((Double, Double) -> Void)?
    public var canSync: () -> Bool = { true }
    private let file: URL
    private let device: String
    private let containerName: String
    private let manifestID = CKRecord.ID(recordName: "usage.metadata.v1")
    private var timer: Timer?
    private var scheduled: Task<Void, Never>?
    private var writable = true
    private var automatic = false
    private var retryAt: Date = .distantPast
    private var step = "idle"
    public init(file: URL, device: String, containerName: String = "iCloud.network.utterleaf.usage") {
        self.file = file; self.device = device; self.containerName = containerName
        if FileManager.default.fileExists(atPath: file.path) {
            do { cache = try JSONDecoder().decode(CloudUsageCache.self, from: Data(contentsOf: file)) }
            catch { writable = false; status = "本地同步记录无法读取，已停止写入" }
        }
        if device == "iPhone" {
            for (id, var row) in cache.rows where row.source == cache.source && row.kind == "call" && row.status == "pending" {
                row.status = "interrupted"; row.updated = Date().timeIntervalSince1970; cache.rows[id] = row
            }
        }
    }
    public func row(id: String, kind: String) -> CloudUsageRow { .init(id: id, kind: kind, source: cache.source, device: device) }
    public func ingest(_ candidate: CloudUsageRow) {
        var next = candidate
        if var old = cache.rows[next.id] {
            old.updated = 0; next.updated = 0
            if old == next { return }
        }
        next.updated = Date().timeIntervalSince1970
        guard next.valid else { return }
        cache.rows[next.id] = next; persist(); changed(); requestSync()
    }
    public func setBudget(week: Double, month: Double, initial: Bool = false) {
        guard week.isFinite, month.isFinite, week > 0, month > 0, week <= 1_000_000, month <= 1_000_000 else { return }
        if cache.rows["budget.v1"] != nil && cache.week == week && cache.month == month { return }
        var value = row(id: "budget.v1", kind: "budget"); value.weekly = week; value.monthly = month
        if initial && cache.rows["budget.v1"] == nil {
            value.updated = 0; cache.rows[value.id] = value; persist(); changed()
        } else { ingest(value) }
    }
    public func start() {
        guard timer == nil else { return }
        automatic = true
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
        requestSync()
    }
    public func stop() { automatic = false; timer?.invalidate(); timer = nil; scheduled?.cancel(); scheduled = nil }
    public func requestSync() {
        guard automatic, scheduled == nil else { return }
        scheduled = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            scheduled = nil; await sync()
        }
    }
    private func changed() { version &+= 1; onChange?() }
    private func persist() {
        guard writable else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: file, options: .atomic)
            #if os(iOS)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            #else
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            #endif
        } catch { writable = false; status = "同步记录保存失败；本机 API 账本不受影响" }
    }
    public func sync() async {
        guard writable, !syncing, canSync(), Date() >= retryAt else { return }
        #if os(macOS)
        guard FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile").path) else {
            status = "Mac 尚未配置 iCloud 签名"; changed(); return
        }
        #elseif targetEnvironment(simulator)
        status = "模拟器未连接 iCloud；显示本地记录"; changed(); return
        #endif
        syncing = true; status = "正在同步用量…"; changed()
        defer { syncing = false; changed() }
        do {
            step = "account"
            let container = CKContainer(identifier: containerName)
            guard try await container.accountStatus() == .available else { status = "请登录 iCloud，离线记录已保留"; return }
            let identity = try await container.userRecordID().recordName
            let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            if let previous = cache.accountHash, previous != hash { status = "iCloud 账户已变更，已暂停同步以保护原账户记录"; return }
            cache.accountHash = hash; persist()
            let database = container.privateCloudDatabase
            step = "header"
            let header = try await readManifest(database, metadataOnly: true)
            let currentOwnedDigest = digest(try encode(cache.owned))
            if let header, header.recordChangeTag == cache.serverTag, currentOwnedDigest == cache.ownedDigest {
                cache.lastSync = Date().timeIntervalSince1970; status = "已同步 · 私有 iCloud"; persist(); return
            }
            step = "download"
            let record = header == nil ? nil : try await readManifest(database, metadataOnly: false)
            var remote = CloudUsageCache()
            if let record {
                guard record.recordType == "LeafUsageSnapshotV1", let asset = record["blob"] as? CKAsset, let url = asset.fileURL,
                      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024 * 1024 else { throw SyncFailure.invalidRecord }
                let data = try Data(contentsOf: url)
                guard record["checksum"] as? String == digest(data) else { throw SyncFailure.invalidRecord }
                let rows = try JSONDecoder().decode([CloudUsageRow].self, from: data)
                for row in rows { guard row.valid else { throw SyncFailure.invalidRecord }; remote.merge(row) }
            }
            let previousBudget = cache.rows["budget.v1"]
            for row in remote.rows.values { cache.merge(row) }
            if cache.rows["budget.v1"] != previousBudget, let budget = cache.rows["budget.v1"], let week = budget.weekly, let month = budget.monthly {
                onRemoteBudget?(week, month)
            }
            persist(); changed()
            // Keep all server rows, merge only this installation's originals, and use the record
            // change tag for atomic conflict detection. No query/index or custom-zone dependency.
            let own = cache.owned
            for row in own { remote.merge(row) }
            let payload = try encode(Array(remote.rows.values))
            let checksum = digest(payload)
            var savedRecord = record
            if record == nil || record?["checksum"] as? String != checksum {
                step = "upload"
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent("utterleaf-usage-" + UUID().uuidString + ".json")
                try payload.write(to: staging, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
                defer { try? FileManager.default.removeItem(at: staging) }
                let value = record ?? CKRecord(recordType: "LeafUsageSnapshotV1", recordID: manifestID)
                value["blob"] = CKAsset(fileURL: staging); value["checksum"] = checksum as NSString
                let response = try await database.modifyRecords(saving: [value], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                guard let result = response.saveResults[manifestID] else { throw SyncFailure.invalidRecord }
                savedRecord = try result.get()
            }
            cache.serverTag = savedRecord?.recordChangeTag
            cache.ownedDigest = digest(try encode(own))
            cache.lastSync = Date().timeIntervalSince1970
            let pending = digest(try encode(cache.owned)) != cache.ownedDigest
            status = pending ? "已同步，新增记录等待补传" : "已同步 · 私有 iCloud"
            persist()
            if pending { requestSync() }
        } catch {
            #if os(macOS)
            if ProcessInfo.processInfo.arguments.contains("--usage-sync-check") {
                print("Cloud metadata sync diagnostic (\(step)): \((error as NSError).domain)/\((error as NSError).code)")
                let info = (error as NSError).userInfo
                if let code = info["CKHTTPStatus"] as? NSNumber { print("Cloud HTTP status: \(code)") }
                if let underlying = info[NSUnderlyingErrorKey] as? NSError {
                    print("Cloud underlying domain/code: \(underlying.domain)/\(underlying.code)")
                }
            }
            #endif
            if let cloud = error as? CKError {
                let delay = (cloud.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue ?? 15
                retryAt = Date().addingTimeInterval(max(5, delay))
                status = cloud.code == .serverRecordChanged ? "有并发更新，将自动合并重试" : "iCloud 暂时不可用，本地记录已保留（\(cloud.errorCode)）"
            } else { status = "同步未完成，本地记录已保留"; retryAt = Date().addingTimeInterval(15) }
        }
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func encode(_ rows: [CloudUsageRow]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(rows.sorted { $0.id < $1.id })
    }
    private func readManifest(_ database: CKDatabase, metadataOnly: Bool) async throws -> CKRecord? {
        do {
            let records = try await database.records(for: [manifestID], desiredKeys: metadataOnly ? ["checksum"] : nil)
            guard let result = records[manifestID] else { throw SyncFailure.invalidRecord }
            return try result.get()
        } catch let error as CKError where error.code == .unknownItem { return nil }
    }
    public var snapshot: [String: Any] {
        let recent = cache.rows.values.filter { $0.kind == "call" }.sorted { ($0.started ?? 0) > ($1.started ?? 0) }.prefix(50)
        return ["status": status, "syncing": syncing, "lastSync": cache.lastSync ?? 0,
            "week": cache.window(days: 7), "month": cache.window(days: 30),
            "macCalls": cache.rows.values.filter { $0.kind == "call" && $0.device == "Mac" }.count,
            "phoneCalls": cache.rows.values.filter { $0.kind == "call" && $0.device == "iPhone" }.count,
            "calls": recent.map { row -> [String: Any] in
                var value: [String: Any] = ["id": row.id, "device": row.device, "provider": row.provider ?? "", "model": row.model ?? "", "status": row.status ?? "", "started": row.started ?? 0, "currency": row.currency ?? "CNY"]
                if let amount = row.amount { value["amount"] = amount }; return value
            }]
    }
}
private enum SyncFailure: Error { case invalidRecord }
