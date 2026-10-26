import AVFoundation
import Foundation
import UtterLeafCore

struct ImportedMeetingAudio { let seconds: Double; let sourceFile: String }

enum MeetingAudioImport {
    static func sourceName(_ source: URL) -> String {
        let ext = source.pathExtension.lowercased()
        let suffix = ext.range(of: #"^[a-z0-9]{1,8}$"#, options: .regularExpression) != nil ? ext : "audio"
        return "imported-audio." + suffix
    }
    static func convert(source: URL, folder: URL, progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> ImportedMeetingAudio {
        let work = Task.detached(priority: .utility) {
            var input = try AVAudioFile(forReading: source)
            let duration = Double(input.length) / input.processingFormat.sampleRate
            guard duration.isFinite, duration >= 1 else { throw AppFailure("音频不足一秒或无法读取。", code: "meeting_import_short") }
            guard duration <= 10800 else { throw AppFailure("当前会议导入支持最长 3 小时的音频。", code: "meeting_import_long") }
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 512 * 1024 * 1024 else { throw AppFailure("录音文件超过 512 MB，请先压缩或分段。", code: "meeting_import_size") }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let retainedName = MeetingAudioImport.sourceName(source)
            let copy = folder.appendingPathComponent(retainedName)
            if source.standardizedFileURL != copy.standardizedFileURL {
                if FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.removeItem(at: copy) }
                try FileManager.default.copyItem(at: source, to: copy)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
            input = try AVAudioFile(forReading: copy)
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: input.processingFormat, to: target),
                  let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 8192) else {
                throw AppFailure("此音频无法转换，请尝试导出 M4A、MP3 或 WAV。", code: "meeting_import_format")
            }
            let wav = folder.appendingPathComponent("meeting.wav")
            FileManager.default.createFile(atPath: wav.path, contents: DoubaoWire.wav(Data()), attributes: [.posixPermissions: 0o600])
            let writer = try FileHandle(forWritingTo: wav); defer { try? writer.close() }
            try writer.truncate(atOffset: 44); try writer.seekToEnd()
            var frames = 0, lastPercent = -1
            while true {
                try Task.checkCancellation()
                var conversionError: NSError?
                var readError: Error?
                let status = converter.convert(to: output, error: &conversionError) { requested, state in
                    guard input.framePosition < input.length,
                          let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: max(1, min(requested, 8192))) else { state.pointee = .endOfStream; return nil }
                    do {
                        try input.read(into: buffer)
                        state.pointee = buffer.frameLength > 0 ? .haveData : .endOfStream
                        return buffer.frameLength > 0 ? buffer : nil
                    } catch { readError = error; state.pointee = .endOfStream; return nil }
                }
                if let readError { throw readError }
                if let conversionError { throw conversionError }
                guard status != .error else { throw AppFailure("音频转换失败，原文件未改动。", code: "meeting_import_conversion") }
                if output.frameLength > 0, let channel = output.floatChannelData?[0] {
                    var pcm = Data(capacity: Int(output.frameLength) * 2)
                    for index in 0..<Int(output.frameLength) {
                        let sample = channel[index].isFinite ? max(-1, min(1, channel[index])) : 0
                        var value = Int16((sample * 32767).rounded()).littleEndian
                        withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
                    }
                    try writer.write(contentsOf: pcm); frames += Int(output.frameLength)
                }
                let percent = min(100, Int(Double(input.framePosition) / Double(max(1, input.length)) * 100))
                if percent > lastPercent { progress(percent); lastPercent = percent }
                if status == .endOfStream { break }
            }
            guard frames >= 16000 else { throw AppFailure("转换后的音频不足一秒。", code: "meeting_import_short") }
            var header = DoubaoWire.wav(Data())
            func patch(_ offset: Int, _ number: UInt32) { var value = number.littleEndian; withUnsafeBytes(of: &value) { header.replaceSubrange(offset..<offset + 4, with: $0) } }
            patch(4, UInt32(frames * 2 + 36)); patch(40, UInt32(frames * 2))
            try writer.seek(toOffset: 0); try writer.write(contentsOf: header); try writer.synchronize()
            return ImportedMeetingAudio(seconds: Double(frames) / 16000, sourceFile: retainedName)
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}
