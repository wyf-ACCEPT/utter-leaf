import Foundation
import UtterLeafCore

@MainActor enum MeetingSmokeRunner {
    static func run() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "--synthetic-wav"), arguments.count > i + 1,
              let j = arguments.firstIndex(of: "--meeting-receipt"), arguments.count > j + 1 else { return }
        let receipt = URL(fileURLWithPath: arguments[j + 1])
        let audio = URL(fileURLWithPath: arguments[i + 1])
        let folder = receipt.deletingLastPathComponent()
        let api = MeetingAPI(); var calls: [UsageCall] = []
        api.onCall = { value in if let i = calls.firstIndex(where: { $0.id == value.id }) { calls[i] = value } else { calls.append(value) } }
        var result: [String: Any] = [:]
        do {
            // Only the explicitly supplied short synthetic fixture may leave the device.
            let size = (try audio.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size >= 44, size <= 32_000 * 40 + 44 else { throw AppFailure("Synthetic fixture size invalid.", code: "meeting_fixture_size") }
            let upload = folder.appendingPathComponent("synthetic-request.json")
            try await MeetingAPI.buildUpload(audio: audio, destination: upload, voices: [])
            defer { try? FileManager.default.removeItem(at: upload) }
            var call = UsageCall(jobID: UUID(), provider: "Doubao", model: "meeting-ssd300", price: .asr(.file)); call.seconds = Double(size - 44) / 32000
            call = try await api.submit(upload: upload, call: call)
            for _ in 0..<60 {
                if let response = try await api.query(call: call) {
                    result["fileASR"] = "passed"
                    result["segments"] = response.segments.count
                    result["speakers"] = Set(response.segments.map(\.speaker)).count
                    var meeting = MeetingRecord(); meeting.segments = response.segments; meeting.notes = "Synthetic meeting validation only."
                    let brief = try await api.brief(content: MeetingProtocol.envelope(meeting), meeting: meeting.id, price: .flash)
                    result["brief"] = MeetingProtocol.hasValidReferences(brief, segments: response.segments) ? "passed" : "invalid_references"
                    let cleaned = try await api.brief(content: MeetingProtocol.envelope(meeting), meeting: meeting.id, price: .flash, system: MeetingProtocol.cleanupPrompt)
                    result["cleanedSegments"] = try MeetingProtocol.cleaned(cleaned, expected: response.segments).count
                    result["briefCharacters"] = brief.count
                    break
                }
                try await Task.sleep(for: .seconds(2))
            }
        } catch { result["fileOrBriefError"] = safeFailure(error).code }
        do { result["voiceListCount"] = try await api.listVoices().count; result["voiceList"] = "passed" }
        catch { result["voiceListError"] = safeFailure(error).code }
        let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: receipt, options: .atomic)
        // Receipts contain API usage only; no transcript, voiceprint names, URL, or credential values.
        try? JSONEncoder().encode(calls).write(to: folder.appendingPathComponent("synthetic-calls.json"), options: .atomic)
    }
}
