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
        if arguments.contains("--caption-stream-smoke") { await streaming(audio: audio, receipt: receipt); return }
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
    static func streaming(audio: URL, receipt: URL) async {
        let api = Providers(); var report: [String: Any] = [:]
        var partialCount = 0, speakerCount = 0, packets = 0
        api.onPartial = { text in if !text.isEmpty { partialCount += 1 } }
        api.onSpeakerResult = { rows in if !rows.isEmpty { speakerCount += 1 } }
        api.onStreamResponse = { body in
            packets += 1
            report["bodyKeys"] = body.keys.sorted()
            if let result = body["result"] as? [String: Any] {
                report["resultKeys"] = result.keys.sorted()
                if let rows = result["utterances"] as? [[String: Any]] {
                    report["untimedRows"] = rows.filter { row in
                        guard let start = row["start_time"] as? NSNumber, let end = row["end_time"] as? NSNumber else { return true }
                        return start.doubleValue < 0 || end.doubleValue < start.doubleValue
                    }.count
                    report["speakerValueTypes"] = Array(Set(rows.map { String(describing: type(of: ($0["additions"] as? [String: Any])?["speaker_id"] ?? NSNull())) })).sorted()
                    report["emptySpeakerIDs"] = rows.filter { (($0["additions"] as? [String: Any])?["speaker_id"] as? String ?? "").isEmpty }.count
                    do { _ = try MeetingProtocol.segments(body) } catch { report["strictParseError"] = String(describing: error) }
                }
                if let row = (result["utterances"] as? [[String: Any]])?.last {
                    report["rowKeys"] = row.keys.sorted()
                    report["additionKeys"] = (row["additions"] as? [String: Any])?.keys.sorted() ?? []
                    report["startNonnegative"] = ((row["start_time"] as? NSNumber)?.doubleValue ?? -1) >= 0
                    report["endNonnegative"] = ((row["end_time"] as? NSNumber)?.doubleValue ?? -1) >= 0
                }
            }
        }
        do {
            let wav = try Data(contentsOf: audio)
            guard wav.count >= 44, wav.count <= 32_000 * 40 + 44 else { throw AppFailure("Synthetic fixture size invalid.", code: "meeting_fixture_size") }
            let pcm = Data(wav.dropFirst(44))
            try await api.startStream(pipeline: .realtime, job: UUID(), price: .asr(.realtime), speakerInfo: true)
            for offset in stride(from: 0, to: pcm.count, by: 6400) {
                let end = min(offset + 6400, pcm.count)
                try await api.send(Data(pcm[offset..<end]), final: end == pcm.count)
                if end < pcm.count { try await Task.sleep(for: .milliseconds(200)) }
            }
            let text = try await api.endStream(); report["finalCharacters"] = text.count
        } catch { report["error"] = safeFailure(error).code; api.cancel() }
        report["partialEvents"] = partialCount; report["speakerEvents"] = speakerCount; report["packets"] = packets
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: receipt, options: .atomic)
    }
}
