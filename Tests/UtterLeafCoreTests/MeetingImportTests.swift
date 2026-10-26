import XCTest
import AVFoundation
import UtterLeafCore
@testable import UtterLeaf

final class MeetingImportTests: XCTestCase {
    private func writeAudio(_ url: URL, rate: Double = 44100, channels: AVAudioChannelCount = 2, seconds: Double = 1) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for index in 0..<Int(frames) { buffer.floatChannelData![channel][index] = Float(sin(Double(index) * 440 * 2 * .pi / rate) * 0.05) }
        }
        try file!.write(from: buffer); file = nil
    }
    func testStereoImportResamplesAndPreservesOriginalAndPrivateCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("watch.wav"), folder = root.appendingPathComponent("meeting")
        try writeAudio(source); let original = try Data(contentsOf: source)
        let result = try await MeetingAudioImport.convert(source: source, folder: folder)
        XCTAssertEqual(result.seconds, 1, accuracy: 0.02)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(result.sourceFile)), original)
        let wav = try Data(contentsOf: folder.appendingPathComponent("meeting.wav"))
        XCTAssertEqual(Array(wav[22..<24]), [1,0]); XCTAssertEqual(Array(wav[24..<28]), [128,62,0,0])
        XCTAssertEqual(Array(wav[34..<36]), [16,0])
        let attrs = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(result.sourceFile).path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testCancellingConversionLeavesSourceUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("watch.wav"); try writeAudio(source, seconds: 2)
        let original = try Data(contentsOf: source)
        let task = Task { try await MeetingAudioImport.convert(source: source, folder: root.appendingPathComponent("cancelled")) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must stop conversion") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
    @MainActor func testM4AImportIsReadableAndAudioDeletionIncludesRetainedCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.wav"), m4a = root.appendingPathComponent("watch.m4a")
        try writeAudio(source, rate: 16000, channels: 1, seconds: 2)
        try await MeetingAudioExport.convert(source: source, destination: m4a)
        let store = MeetingStore(root: root); var meeting = MeetingRecord()
        let result = try await MeetingAudioImport.convert(source: m4a, folder: store.folder(meeting.id))
        meeting.importedAudioFile = result.sourceFile; try store.save(meeting)
        let sourceCopy = try XCTUnwrap(store.originalAudio(meeting.id))
        let exported = root.appendingPathComponent("lossless-copy.m4a")
        try await MeetingAudioExport.convert(source: sourceCopy, destination: exported)
        XCTAssertEqual(try Data(contentsOf: exported), try Data(contentsOf: m4a))
        XCTAssertEqual(result.seconds, 2, accuracy: 0.15)
        try store.deleteAudio(meeting.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.audio(meeting.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(meeting.id).appendingPathComponent(result.sourceFile).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: m4a.path))
    }
    @MainActor func testImportFlowUsesFileASRWithoutStartingMicrophoneOrLiveStreams() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("external.wav"); try writeAudio(source, rate: 16000, channels: 1, seconds: 2)
        let ledger = LocalStore(root: root)
        var routes: [String] = []
        let api = MeetingAPI(credentials: { _ in "synthetic" }) { request in
            routes.append(request.url!.path)
            let body: [String: Any]
            if request.url?.host == "api.deepseek.com" {
                body = ["choices": [["finish_reason": "stop", "message": ["content": #"{"candidates":["audio-review","watch-review","meeting-review"]}"#]]], "usage": ["prompt_tokens": 10, "completion_tokens": 10]]
            } else if request.url!.path.hasSuffix("query") {
                body = ["result": ["utterances": [["text": "Synthetic imported speech", "start_time": 0, "end_time": 1500, "additions": ["speaker": "1"]]]]]
            } else { body = [:] }
            return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["X-Api-Status-Code": "20000000"])!)
        }
        let model = MeetingModel(ledger: ledger, api: api); model.importRecording(source)
        for _ in 0..<400 {
            if !model.busy && model.namingMeetingID == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.recording); XCTAssertFalse(model.usesMicrophone)
        XCTAssertEqual(model.current?.state, "transcribed"); XCTAssertEqual(model.current?.nameCandidates?.count, 3)
        XCTAssertEqual(routes.filter { $0.hasSuffix("submit") }.count, 1)
        XCTAssertEqual(routes.filter { $0.hasSuffix("query") }.count, 1)
        XCTAssertFalse(ledger.database.calls.contains { $0.model.contains("live") || $0.model == "v2-realtime" })
    }
}
