import Foundation
import Security
import LocalAuthentication
import UtterLeafCore

struct Preferences: Codable {
    var appearance: String?
    var sound: SoundPreferences?
    var pricingCurrency: String?
    var pipeline: ASRPipeline?
    var insertionMode: String?
    var weeklyBudget: Double?
    var monthlyBudget: Double?
    var billing: BillingConfiguration?
    var vocabulary: [VocabularyEntry]?
    var cleanup = true
    var retention = "both"
    var streamPrice = 1.0
    var filePrice = 0.8
    var flashInput = 2.0
    var flashCached = 0.04
    var flashOutput = 8.0
    var customPrompt: String?
    var promptVersions: [String] = []
}
struct LocalDatabase: Codable {
    var version = 1
    var preferences = Preferences()
    var jobs: [HistoryJob] = []
    var calls: [UsageCall] = []
    var billingLedger: BillingLedger?
}

@MainActor final class LocalStore: ObservableObject {
    @Published var database = LocalDatabase()
    @Published var storageError: String?
    @Published var billingSyncing = false
    lazy var billingSync = BillingSync(store: self)
    lazy var minutesAccounts = MinutesAccountStore(root: root)
    lazy var vocabularyCloud: CloudVocabularySync = {
        let cloud = CloudVocabularySync(file: root.appendingPathComponent("vocabulary-cloud-v1.json"))
        cloud.seed(database.preferences.vocabulary ?? [.typeless])
        cloud.onChange = { [weak self] in self?.objectWillChange.send() }
        return cloud
    }()
    lazy var historyCloud: CloudHistorySync = {
        let cloud = CloudHistorySync(file: root.appendingPathComponent("history-cloud-v1.json"), device: "Mac")
        cloud.onChange = { [weak self] in self?.objectWillChange.send() }
        cloud.onRemoteChange = { [weak self] in self?.applyHistoryRedactions() }
        return cloud
    }()
    lazy var usageCloud: CloudUsageSync = {
        let control = ProcessInfo.processInfo.arguments.contains("--cloud-container-control")
        // Keep the previous container's account-bound cache intact in its original file.
        let cloud = CloudUsageSync(file: root.appendingPathComponent(control ? "usage-cloud-control.json" : "usage-cloud-v1.json"), device: "Mac")
        cloud.onChange = { [weak self] in self?.objectWillChange.send() }
        cloud.onRemoteBudget = { [weak self] week, month in
            guard let self else { return }
            database.preferences.weeklyBudget = week; database.preferences.monthlyBudget = month; save()
        }
        if cloud.cache.rows["budget.v1"] != nil {
            database.preferences.weeklyBudget = cloud.cache.week
            database.preferences.monthlyBudget = cloud.cache.month
        }
        return cloud
    }()
    let root: URL
    private var writable = true
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UtterLeaf", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.root.path)
            let file = self.root.appendingPathComponent("ledger.json")
            if FileManager.default.fileExists(atPath: file.path) {
                database = try JSONDecoder().decode(LocalDatabase.self, from: Data(contentsOf: file))
                if database.preferences.pricingCurrency == nil {
                    database.preferences.flashInput = 2; database.preferences.flashCached = 0.04; database.preferences.flashOutput = 8
                    database.preferences.pricingCurrency = "CNY"
                }
                for i in database.calls.indices where database.calls[i].status == .pending {
                    database.calls[i].status = .interrupted
                    database.calls[i].errorCode = "app_interrupted_billing_unknown"
                    database.calls[i].finished = Date()
                }
                for i in database.calls.indices { database.calls[i].fillLocalEstimate() }
                for i in database.jobs.indices where ["recording", "processing", "inserting"].contains(database.jobs[i].status) {
                    database.jobs[i].status = "interrupted"
                }
            }
        } catch { writable = false; storageError = "本地记录无法读取，已停止写入以保护现有资料。请检查 Application Support/UtterLeaf。" }
    }
    func save() {
        guard writable else { return }
        do {
            let file = root.appendingPathComponent("ledger.json")
            let data = try JSONEncoder().encode(database)
            try data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            var resource = URLResourceValues(); resource.isExcludedFromBackup = true
            var folder = root; try folder.setResourceValues(resource)
        } catch { storageError = "本地记录保存失败。当前文字仍在预览中，请先复制。" }
        captureCloudUsage()
        captureCloudHistory()
    }
    func captureCloudHistory() {
        for job in database.jobs where job.kind != "meeting" {
            let id = job.id.uuidString.lowercased()
            if job.rawText == nil && job.finalText == nil {
                if historyCloud.cache.rows[id] != nil { historyCloud.erase(id) }
            } else {
                historyCloud.upsert(id: id, created: job.created.timeIntervalSince1970, seconds: job.seconds,
                    raw: job.rawText, final: job.finalText, rawRemoved: job.rawText == nil)
            }
        }
    }
    private func applyHistoryRedactions() {
        var changed = false
        for i in database.jobs.indices where database.jobs[i].kind != "meeting" {
            guard let row = historyCloud.cache.rows[database.jobs[i].id.uuidString.lowercased()] else { continue }
            if (row.erased || row.rawRemoved) && database.jobs[i].rawText != nil { database.jobs[i].rawText = nil; changed = true }
            if row.erased && database.jobs[i].finalText != nil { database.jobs[i].finalText = nil; changed = true }
        }
        if changed { save() }
    }
    var historyJobs: [HistoryJob] {
        var jobs = Dictionary(database.jobs.filter { $0.kind != "meeting" }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for row in historyCloud.cache.visible {
            guard let id = UUID(uuidString: row.id), jobs[id] == nil else { continue }
            var job = HistoryJob(id: id, pipeline: .final)
            job.created = Date(timeIntervalSince1970: row.created); job.seconds = row.seconds
            job.rawText = row.raw; job.finalText = row.final; job.finalCharacters = (row.final ?? row.raw ?? "").unicodeScalars.count
            job.status = "已同步"; jobs[id] = job
        }
        return jobs.values.sorted { $0.created > $1.created }
    }
    func captureCloudUsage() {
        for call in database.calls {
            var row = usageCloud.row(id: "call." + call.id.uuidString.lowercased(), kind: "call")
            row.job = call.jobID.uuidString.lowercased(); row.started = call.started.timeIntervalSince1970
            row.purpose = UsagePurpose.isMeeting(call, jobs: database.jobs) ? "meeting" : "dictation"
            row.provider = call.provider; row.model = call.model; row.status = call.status.rawValue
            row.currency = call.price.currency; row.amount = call.estimatedAmount; row.actual = call.billedAmount
            row.seconds = max(0, call.seconds); row.input = call.inputTokens; row.cached = call.cachedTokens; row.output = call.outputTokens
            usageCloud.ingest(row)
        }
        for job in database.jobs {
            var row = usageCloud.row(id: "job." + job.id.uuidString.lowercased(), kind: "job")
            row.started = job.created.timeIntervalSince1970; row.purpose = job.kind == "meeting" ? "meeting" : "dictation"
            row.seconds = max(0, job.seconds); row.characters = max(0, job.finalCharacters)
            usageCloud.ingest(row)
        }
        usageCloud.setBudget(week: database.preferences.weeklyBudget ?? 5, month: database.preferences.monthlyBudget ?? 20,
            initial: usageCloud.cache.rows["budget.v1"] == nil)
    }
    var combinedCalls: [UsageCall] {
        var rows = Dictionary(database.calls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in usageCloud.cache.rows.values where value.kind == "call" {
            guard let id = UUID(uuidString: String(value.id.dropFirst(5))), rows[id] == nil, let job = UUID(uuidString: value.job ?? "") else { continue }
            var call = UsageCall(jobID: job, provider: value.provider ?? "", model: value.model ?? "", requestID: "Not synchronized", price: .init(version: "icloud-metadata-v1", currency: value.currency ?? "CNY", note: "跨设备用量估算"))
            call.id = id; call.started = Date(timeIntervalSince1970: value.started ?? 0); call.status = CallStatus(rawValue: value.status ?? "") ?? .interrupted
            call.seconds = value.seconds ?? 0; call.estimatedAmount = value.amount; call.billedAmount = value.actual
            call.inputTokens = value.input; call.cachedTokens = value.cached; call.outputTokens = value.output
            rows[id] = call
        }
        return Array(rows.values)
    }
    var combinedJobs: [HistoryJob] {
        var rows = Dictionary(database.jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in usageCloud.cache.rows.values where value.kind == "job" {
            guard let id = UUID(uuidString: String(value.id.dropFirst(4))), rows[id] == nil else { continue }
            var job = HistoryJob(id: id, pipeline: .final); job.created = Date(timeIntervalSince1970: value.started ?? 0)
            job.kind = value.purpose == "meeting" ? "meeting" : nil; job.seconds = value.seconds ?? 0; job.finalCharacters = value.characters ?? 0
            rows[id] = job
        }
        return Array(rows.values)
    }
    func update(_ job: HistoryJob) {
        var value = job
        if database.preferences.retention == "final" { value.rawText = nil }
        if database.preferences.retention == "none" { value.rawText = nil; value.finalText = nil }
        if let i = database.jobs.firstIndex(where: { $0.id == value.id }) { database.jobs[i] = value }
        else { database.jobs.insert(value, at: 0) }
        save()
    }
    func update(_ original: UsageCall) {
        var call = original; call.fillLocalEstimate()
        if let i = database.calls.firstIndex(where: { $0.id == call.id }) { database.calls[i] = call }
        else { database.calls.insert(call, at: 0) }
        save()
    }
    var vocabulary: [VocabularyEntry] { vocabularyCloud.entries }
    func saveVocabulary(_ entry: VocabularyEntry) throws {
        if let error = VocabularyContext.validationError(entry, existing: vocabulary) { throw AppFailure(error, code: "vocabulary_validation") }
        try vocabularyCloud.upsert(entry)
        database.preferences.vocabulary = vocabularyCloud.entries; save()
    }
    func deleteVocabulary(_ id: UUID) throws {
        try vocabularyCloud.delete(id)
        database.preferences.vocabulary = vocabularyCloud.entries; save()
    }
    func clearText() {
        historyCloud.eraseAll()
        for i in database.jobs.indices where database.jobs[i].kind != "meeting" { database.jobs[i].rawText = nil; database.jobs[i].finalText = nil }
        save()
    }
}

enum Credentials {
    static let allowed = ["DOUBAO_API_KEY", "DEEPSEEK_API_KEY", "UTTERLEAF_VOLC_ACCESS_KEY_ID", "UTTERLEAF_VOLC_SECRET_ACCESS_KEY"]
    static func load(_ name: String) throws -> String {
        guard allowed.contains(name) else { throw AppFailure("凭证名称不受支持。", code: "credential_not_allowed") }
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "network.utterleaf.personal", kSecAttrAccount as String: name,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty { return value }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".llm.env")
        let mode = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard mode & 0o077 == 0 else { throw AppFailure("请将 ~/.llm.env 权限设为 600 后重试。", code: "credential_file_permissions") }
        let source = try String(contentsOf: file, encoding: .utf8)
        // Parse only the allowlisted variable. Never execute or source the file.
        let pattern = "(?m)^\\s*(?:export\\s+)?" + name + "\\s*=\\s*(.*)$"
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: source) else {
            throw AppFailure("本机缺少 \(name)，请在个人凭证文件中配置。", code: "credential_missing")
        }
        var value = String(source[range]).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") || value.hasPrefix("'") {
            let quote = value.removeFirst()
            guard let end = value.firstIndex(of: quote) else { throw AppFailure("凭证格式不正确。", code: "credential_format") }
            value = String(value[..<end])
        } else { value = String(value.prefix { !$0.isWhitespace && $0 != "#" }) }
        guard !value.isEmpty, !value.contains("\n") else { throw AppFailure("凭证为空。", code: "credential_empty") }
        return value
    }
    static func available(_ name: String) -> Bool { (try? load(name)) != nil }
}

struct AppFailure: LocalizedError {
    let message: String
    let code: String
    init(_ message: String, code: String) { self.message = message; self.code = code }
    var errorDescription: String? { message }
}
func safeFailure(_ error: Error) -> AppFailure {
    if let e = error as? AppFailure { return e }
    if error is CancellationError || (error as? URLError)?.code == .cancelled { return AppFailure("已取消；已发送的调用可能产生费用。", code: "cancelled") }
    if let e = error as? URLError { return AppFailure("网络连接失败（\(e.errorCode)）。请检查网络与 Clash 后重试。", code: "network_\(e.errorCode)") }
    return AppFailure("处理未完成。请重试；原始文字会保留在当前预览中。", code: "processing_failed")
}
