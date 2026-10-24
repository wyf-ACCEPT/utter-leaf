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
    var vocabulary: [VocabularyEntry] { database.preferences.vocabulary ?? [.typeless] }
    func saveVocabulary(_ entry: VocabularyEntry) throws {
        if let error = VocabularyContext.validationError(entry, existing: vocabulary) { throw AppFailure(error, code: "vocabulary_validation") }
        var entries = vocabulary
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry.normalized() }
        else { entries.append(entry.normalized()) }
        database.preferences.vocabulary = entries; save()
    }
    func deleteVocabulary(_ id: UUID) {
        database.preferences.vocabulary = vocabulary.filter { $0.id != id }; save()
    }
    func clearText() {
        for i in database.jobs.indices { database.jobs[i].rawText = nil; database.jobs[i].finalText = nil }
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
