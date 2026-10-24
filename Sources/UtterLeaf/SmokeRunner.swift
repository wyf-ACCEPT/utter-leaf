import Foundation
@preconcurrency import AVFoundation
import UtterLeafCore

@MainActor enum SmokeRunner {
    static func run(model: AppModel) async {
        // Synthetic fixture only. Never read historical recordings or write to the user's ledger.
        let api = Providers()
        var receipts: [UsageCall] = []
        api.onCall = { call in
            if let i = receipts.firstIndex(where: { $0.id == call.id }) { receipts[i] = call } else { receipts.append(call) }
        }
        var outcomes: [String: String] = [:]
        var syntheticOutputs: [String: String] = [:]
        do {
            let cleaned = try await api.cleanup(text: "这个 session 命名为 tap on 杠 31。", prompt: model.prompt(), job: UUID(), price: .flash)
            outcomes["cleanup"] = cleaned.contains("tap on-31") ? "passed" : "symbol_output_mismatch"
        } catch { outcomes["cleanup"] = safeFailure(error).code }
        if ProcessInfo.processInfo.arguments.contains("--vocabulary-smoke") {
            do {
                let positive = try await api.cleanup(text: "这个语音输入工具叫 Typeface，我正在测试它的录音功能。", prompt: model.prompt(), job: UUID(), price: .flash, vocabulary: [.typeless])
                syntheticOutputs["vocabulary_typeless"] = positive
                outcomes["vocabulary_typeless"] = positive.contains("Typeless") && !positive.contains("Typeface") ? "passed" : "term_mismatch"
                let negative = try await api.cleanup(text: "这里讨论字体，typeface 是字体的英文，不是在说语音输入软件。", prompt: model.prompt(), job: UUID(), price: .flash, vocabulary: [.typeless])
                syntheticOutputs["vocabulary_context"] = negative
                outcomes["vocabulary_context"] = !negative.contains("Typeless") ? "passed" : "overcorrection"
            } catch { outcomes["vocabulary"] = safeFailure(error).code }
        }
        // Audio smoke fixtures must be explicitly provided, and are not discovered automatically.
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--synthetic-wav"), index + 1 < ProcessInfo.processInfo.arguments.count {
            do {
                let file = try AVAudioFile(forReading: URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1]))
                let source = file.processingFormat
                let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
                guard file.length <= AVAudioFramePosition(source.sampleRate * 12), let converter = AVAudioConverter(from: source, to: target),
                      let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)),
                      let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(16000 * 13)) else { throw AppFailure("Synthetic fixture too long.", code: "fixture_limit") }
                try file.read(into: input); var fed = false; var error: NSError?
                converter.convert(to: output, error: &error) { _, status in
                    if fed { status.pointee = .endOfStream; return nil }; fed = true; status.pointee = .haveData; return input
                }
                guard error == nil, let samples = output.int16ChannelData?[0] else { throw AppFailure("Fixture conversion failed.", code: "fixture_conversion") }
                let pcm = Data(bytes: samples, count: Int(output.frameLength) * 2)
                for pipeline in ASRPipeline.allCases {
                    do {
                        let text: String
                        if pipeline == .file { text = try await api.fileASR(pcm: pcm, job: UUID(), price: .asr(pipeline)) }
                        else {
                            try await api.startStream(pipeline: pipeline, job: UUID(), price: .asr(pipeline))
                            for offset in stride(from: 0, to: pcm.count, by: 6400) {
                                let end = min(offset + 6400, pcm.count)
                                try await api.send(Data(pcm[offset..<end]), final: end == pcm.count)
                                if end != pcm.count { try await Task.sleep(for: .milliseconds(200)) }
                            }
                            text = try await api.endStream()
                        }
                        outcomes[pipeline.rawValue] = text.isEmpty ? "empty" : "passed_nonempty_transcript"
                    } catch { outcomes[pipeline.rawValue] = safeFailure(error).code; api.cancel() }
                }
            } catch { outcomes["fixture"] = safeFailure(error).code }
        }
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UTTERLEAF_SMOKE_OUTPUT"] ?? "/private/tmp/utterleaf-smoke", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipts).write(to: root.appendingPathComponent("calls.json"), options: .atomic)
            try encoder.encode(outcomes).write(to: root.appendingPathComponent("outcomes.json"), options: .atomic)
            if !syntheticOutputs.isEmpty { try encoder.encode(syntheticOutputs).write(to: root.appendingPathComponent("synthetic-outputs.json"), options: .atomic) }
            print("Provider smoke complete. Outcomes: " + outcomes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        } catch { print("Provider smoke receipt write failed.") }
    }
}
