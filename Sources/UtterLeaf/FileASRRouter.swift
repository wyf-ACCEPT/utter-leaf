import Foundation
import UtterLeafCore

struct FileASRReceipt: Codable {
    var account: MinutesAccountProfile
    var state: String
    var objectToken: String?
    var usage: UsageCall?
}

@MainActor final class FileASRRouter {
    enum Result { case transcript([MeetingUtterance]), useDoubao }
    private let root: URL
    private let accounts: MinutesAccountStore
    private let onCall: ((UsageCall) -> Void)?
    private let makeSession: @MainActor (MinutesAccountProfile) -> any MinutesFileTransport
    init(root: URL, accounts: MinutesAccountStore, makeSession: (@MainActor (MinutesAccountProfile) -> any MinutesFileTransport)? = nil, onCall: ((UsageCall) -> Void)? = nil) {
        self.root = root.appendingPathComponent("file-transcriptions"); self.accounts = accounts; self.makeSession = makeSession ?? { MinutesFileSession(profile: $0) }; self.onCall = onCall
    }
    private func path(_ id: UUID, _ name: String) -> URL { root.appendingPathComponent(id.uuidString.lowercased()).appendingPathComponent(name) }
    func hasReceipt(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: path(id, "receipt.json").path) }
    private func save(_ receipt: FileASRReceipt, id: UUID) throws {
        let file = path(id, "receipt.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(receipt).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func transcribe(audio: URL, seconds: Double, id: UUID, accountSelected: (MinutesAccountProfile) -> Void = { _ in }, progress: (String, Int?) -> Void = { _, _ in }) async throws -> Result {
        guard seconds.isFinite, seconds > 0 else { throw AppFailure("录音时长无效，未发送文件。", code: "minutes_file_duration") }
        var receipt: FileASRReceipt?
        if hasReceipt(id) { receipt = try JSONDecoder().decode(FileASRReceipt.self, from: Data(contentsOf: path(id, "receipt.json"))) }
        let profile = receipt?.account ?? accounts.profile
        accountSelected(profile)
        let cached = path(id, "transcript.json")
        if FileManager.default.fileExists(atPath: cached.path) {
            return .transcript(try JSONDecoder().decode([MeetingUtterance].self, from: Data(contentsOf: cached)))
        }
        let session = makeSession(profile)
        progress("正在连接飞书妙记…", nil)
        try await session.load()
        let token: String
        if let existing = receipt {
            if ["preparing", "uploading"].contains(existing.state) {
                token = try await session.upload(audio: audio, seconds: seconds, key: id, resume: true, prepared: { object in
                    if let original = existing.objectToken, original != object { throw AppFailure("飞书续传对象不一致。", code: "minutes_upload_state") }
                    receipt?.objectToken = object; receipt?.state = "uploading"; try self.save(receipt!, id: id)
                }, progress: { percent in progress("继续上传至飞书妙记…", percent) })
                receipt?.objectToken = token; receipt?.state = "submitted"; try save(receipt!, id: id)
            } else {
                guard let object = existing.objectToken else { throw AppFailure("上次飞书任务状态未确认，未自动重新提交。", code: "minutes_upload_uncertain") }
                token = object
            }
        } else {
            let quota = try await session.run("quota", key: id, arguments: [:])
            guard let remaining = quota["remaining"] as? Double else { throw AppFailure("飞书额度暂时无法确认，未发送录音。", code: "minutes_quota_unknown") }
            guard remaining >= ceil(seconds / 60) else { return .useDoubao }
            var call = UsageCall(jobID: id, provider: "Feishu", model: "minutes-file", price: PriceSnapshot(version: "feishu-entitlement-v1", currency: "CNY", note: "消耗飞书转录额度，不折算为本地 CNY 支出"))
            call.seconds = seconds; call.estimatedAmount = 0; call.estimateBasis = "provider_entitlement"
            receipt = FileASRReceipt(account: profile, state: "preparing", usage: call)
            try save(receipt!, id: id); onCall?(call)
            progress("正在上传至飞书妙记…", 0)
            token = try await session.upload(audio: audio, seconds: seconds, key: id, resume: false, prepared: { object in
                receipt?.objectToken = object; receipt?.state = "uploading"
                try self.save(receipt!, id: id)
            }, progress: { percent in progress("正在上传至飞书妙记…", percent) })
            receipt?.objectToken = token; receipt?.state = "submitted"; try save(receipt!, id: id)
        }
        progress("飞书妙记转录中…", nil)
        for _ in 0..<720 {
            try Task.checkCancellation()
            let status = try await session.run("status", key: id, arguments: ["objectToken": token])
            if let failure = MinutesFileResult.failure(status) {
                receipt?.state = "failed"; receipt?.usage?.status = .failed
                try save(receipt!, id: id)
                if let call = receipt?.usage { onCall?(call) }
                throw AppFailure("飞书返回转录失败（\(failure)），未自动向豆包重复提交。", code: "minutes_transcription_failed")
            }
            if MinutesFileResult.isComplete(status) {
                let result = try await session.run("result", key: id, arguments: ["objectToken": token])
                let segments = try MinutesFileResult.segments(result)
                try JSONEncoder().encode(segments).write(to: cached, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cached.path)
                receipt?.state = "completed"; receipt?.usage?.status = .succeeded
                receipt?.usage?.submittedSeconds = seconds
                try save(receipt!, id: id)
                if let call = receipt?.usage { onCall?(call) }
                return .transcript(segments)
            }
            try await Task.sleep(for: .seconds(5))
        }
        throw AppFailure("飞书仍在处理，音频和请求已保留；下次继续核对原任务。", code: "minutes_pending")
    }
}

enum MinutesFileResult {
    static func isComplete(_ value: [String: Any]) -> Bool {
        guard let rows = value["status"] as? [[String: Any]], rows.count == 1 else { return false }
        return statusCode(rows[0]) == 2
    }
    private static func statusCode(_ row: [String: Any]) -> Int? {
        let value = row["objectStatus"] ?? row["object_status"] ?? row["status"]
        if let number = value as? Int { return number }
        if let string = value as? String { return Int(string) }
        return nil
    }
    static func failure(_ value: [String: Any]) -> Int? {
        guard let rows = value["status"] as? [[String: Any]], rows.count == 1,
              let status = statusCode(rows[0]),
              [-2, -1, 3, 31].contains(status) else { return nil }
        return status
    }
    static func segments(_ value: [String: Any]) throws -> [MeetingUtterance] {
        guard let rows = value["segments"] as? [[String: Any]], !rows.isEmpty else { throw AppFailure("飞书完整转录尚未返回。", code: "minutes_pending") }
        let data = try JSONSerialization.data(withJSONObject: rows)
        let output = try JSONDecoder().decode([MeetingUtterance].self, from: data)
        guard Set(output.map(\.id)).count == output.count, output.allSatisfy({ !$0.text.isEmpty && $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start }) else {
            throw AppFailure("飞书转录数据不完整，请稍后核对。", code: "minutes_result_invalid")
        }
        return output
    }
}
