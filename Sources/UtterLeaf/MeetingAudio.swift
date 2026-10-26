import AppKit
import AVFoundation
import ScreenCaptureKit
import UtterLeafCore

/// Disk-backed, timestamp-aligned tracks; the mixed WAV is built in bounded chunks.
final class MeetingAudioFiles: @unchecked Sendable {
    private let queue = DispatchQueue(label: "network.utterleaf.meeting-files", qos: .userInitiated)
    let folder: URL
    private var tracks: [String: FileHandle] = [:]
    private var failure: Error?
    private var length = 0
    init(folder: URL, recovering: Bool = false) throws {
        self.folder = folder
        for name in ["microphone", "system"] {
            let file = folder.appendingPathComponent(name + ".pcm")
            if !recovering || !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forUpdating: file); tracks[name] = handle
            length = max(length, Int(try handle.seekToEnd()))
        }
    }
    func append(_ data: Data, source: String, at seconds: Double) {
        queue.async { [self] in
            guard failure == nil, let handle = tracks[source] else { return }
            do {
                let offset = max(0, Int(seconds * 16000) * 2)
                try handle.seek(toOffset: UInt64(offset)); try handle.write(contentsOf: data)
                length = max(length, offset + data.count)
            } catch { failure = error }
        }
    }
    func checkpoint() async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if let failure { throw failure }
                    for handle in tracks.values { try handle.synchronize() }
                    continuation.resume(returning: Double(length) / 32000)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if let failure { throw failure }
                    for handle in tracks.values { try handle.synchronize(); try handle.close() }
                    tracks.removeAll()
                    let mic = try FileHandle(forReadingFrom: folder.appendingPathComponent("microphone.pcm"))
                    let system = try FileHandle(forReadingFrom: folder.appendingPathComponent("system.pcm"))
                    defer { try? mic.close(); try? system.close() }
                    let output = folder.appendingPathComponent("meeting.wav")
                    FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
                    let writer = try FileHandle(forWritingTo: output)
                    defer { try? writer.close() }
                    var header = DoubaoWire.wav(Data())
                    func patch(_ offset: Int, _ value: UInt32) { var n = value.littleEndian; withUnsafeBytes(of: &n) { header.replaceSubrange(offset..<offset + 4, with: $0) } }
                    patch(4, UInt32(length + 36)); patch(40, UInt32(length))
                    try writer.write(contentsOf: header)
                    var position = 0
                    while position < length {
                        let count = min(32000, length - position)
                        let a = [UInt8](try mic.read(upToCount: count) ?? Data())
                        let b = [UInt8](try system.read(upToCount: count) ?? Data())
                        var mixed = Data(count: count)
                        mixed.withUnsafeMutableBytes { raw in
                            let output = raw.bindMemory(to: UInt8.self)
                            for i in stride(from: 0, to: count - 1, by: 2) {
                                let av = i + 1 < a.count ? Int(Int16(bitPattern: UInt16(a[i]) | UInt16(a[i + 1]) << 8)) : 0
                                let bv = i + 1 < b.count ? Int(Int16(bitPattern: UInt16(b[i]) | UInt16(b[i + 1]) << 8)) : 0
                                let bits = UInt16(bitPattern: Int16(clamping: av + bv))
                                output[i] = UInt8(bits & 255); output[i + 1] = UInt8(bits >> 8)
                            }
                        }
                        try writer.write(contentsOf: mixed); position += count
                    }
                    try writer.synchronize(); continuation.resume(returning: output)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    deinit { for handle in tracks.values { try? handle.close() } }
}

private final class SystemMeetingAudio: NSObject, SCStreamOutput, SCStreamDelegate {
    var onPCM: ((Data) -> Void)?
    var onFailure: (() -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "network.utterleaf.system-audio")
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw AppFailure("没有可用的系统音频来源。", code: "meeting_system_unavailable") }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true; config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000; config.channelCount = 2
        config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }
    func stop() async { try? await stream?.stopCapture(); stream = nil }
    func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure?() }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sample.isValid, let desc = sample.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: desc)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.numSamples)),
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else { return }
        buffer.frameLength = AVAudioFrameCount(sample.numSamples)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(sample.numSamples), into: buffer.mutableAudioBufferList) == noErr else { return }
        if inputFormat != format { inputFormat = format; converter = AVAudioConverter(from: format, to: target) }
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / format.sampleRate) + 32)) else { return }
        var consumed = false; var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if consumed { state.pointee = .noDataNow; return nil }
            consumed = true; state.pointee = .haveData; return buffer
        }
        guard status != .error, let samples = output.int16ChannelData?[0], output.frameLength > 0 else { return }
        onPCM?(Data(bytes: samples, count: Int(output.frameLength) * 2))
    }
}

@MainActor final class MeetingRecorder {
    private let microphone = Microphone()
    private var system: SystemMeetingAudio?
    private var files: MeetingAudioFiles?
    private var collecting = false
    private var started = 0.0
    private var pausedAt: Double?
    private var pausedDuration = 0.0
    var onChunk: ((Data, String) -> Void)?
    var onFailure: (() -> Void)?
    var elapsed: Double { max(0, (pausedAt ?? ProcessInfo.processInfo.systemUptime) - started - pausedDuration) }
    var paused: Bool { pausedAt != nil }
    func start(folder: URL, systemAudio: Bool) async throws {
        collecting = false
        try await microphone.ensurePermission()
        files = try MeetingAudioFiles(folder: folder)
        started = ProcessInfo.processInfo.systemUptime; pausedDuration = 0; pausedAt = nil
        microphone.onChunk = { [weak self] data, _ in self?.accept(data, source: "microphone") }
        microphone.onDisconnect = { [weak self] in self?.onFailure?() }
        do {
            try microphone.start()
            if systemAudio {
                let system = SystemMeetingAudio(); self.system = system
                system.onPCM = { [weak self] data in Task { @MainActor in self?.accept(data, source: "system") } }
                system.onFailure = { [weak self] in Task { @MainActor in self?.onFailure?() } }
                do { try await system.start() }
                catch {
                    throw AppFailure("系统声音采集未启动。请在系统设置的“录屏与系统录音”中允许 UtterLeaf，重启本 App 后再试；也可先关闭系统声音，仅使用麦克风。", code: "meeting_system_capture_\((error as NSError).code)")
                }
            }
            started = ProcessInfo.processInfo.systemUptime; collecting = true
        } catch { microphone.stop(); await system?.stop(); system = nil; throw error }
    }
    private func accept(_ data: Data, source: String) {
        guard collecting, pausedAt == nil, let files else { return }
        files.append(data, source: source, at: max(0, elapsed - Double(data.count) / 32000))
        onChunk?(data, source)
    }
    func pause() { guard pausedAt == nil else { return }; pausedAt = ProcessInfo.processInfo.systemUptime }
    func resume() {
        guard let pausedAt else { return }
        pausedDuration += ProcessInfo.processInfo.systemUptime - pausedAt; self.pausedAt = nil
    }
    func checkpoint() async throws -> Double { try await files?.checkpoint() ?? 0 }
    func stop() async throws -> URL {
        collecting = false
        microphone.stop(); microphone.onChunk = nil
        let system = self.system; self.system = nil; await system?.stop()
        guard let files else { throw AppFailure("没有可恢复的会议音频。", code: "meeting_audio_missing") }
        let url = try await files.finish(); self.files = nil; return url
    }
    func shutdown() { collecting = false; microphone.stop(); microphone.onChunk = nil; let system = self.system; self.system = nil; Task { await system?.stop() } }
}
