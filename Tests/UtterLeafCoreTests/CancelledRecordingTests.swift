import XCTest
import UtterLeafCore
@testable import UtterLeaf

final class CancelledRecordingTests: XCTestCase {
    @MainActor func testLocalAudioSurvivesRestartAndTranscribesOnlyOnRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root), job = HistoryJob(pipeline: .final)
        let audio = Data(repeating: 1, count: 32000)
        try store.saveCancelledAudio(audio, job: job)
        let restored = LocalStore(root: root)
        XCTAssertEqual(restored.historyJobs.first?.status, "audio_saved")
        XCTAssertEqual(try restored.loadCancelledAudio(job.id), audio)
        XCTAssertEqual(restored.database.calls.count, 0)
        restored.database.preferences.cleanup = false
        var requests = 0
        let model = AppModel(store: restored, fileTranscriber: { data, id in
            requests += 1; XCTAssertEqual(data, audio); XCTAssertEqual(id, job.id)
            return "Synthetic deferred transcript"
        })
        XCTAssertEqual(requests, 0)
        model.transcribeSavedRecording(restored.historyJobs[0])
        for _ in 0..<30 where model.busy { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(requests, 1); XCTAssertEqual(model.draft, "Synthetic deferred transcript")
        XCTAssertEqual(model.phase, .preview); XCTAssertFalse(model.showsPillRecovery)
        XCTAssertTrue(restored.hasCancelledAudio(job.id))
        try restored.deleteCancelledAudio(job.id)
        XCTAssertFalse(restored.hasCancelledAudio(job.id))
        XCTAssertEqual(restored.historyJobs.first?.finalText, "Synthetic deferred transcript")
    }
    @MainActor func testIndexWriteFailureDoesNotReportSuccessfulSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root), job = HistoryJob(pipeline: .file)
        let file = root.appendingPathComponent("ledger.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let audio = Data(repeating: 1, count: 3200)
        XCTAssertThrowsError(try store.saveCancelledAudio(audio, job: job))
        XCTAssertEqual(try store.loadCancelledAudio(job.id), audio)
        try FileManager.default.removeItem(at: file)
        try store.saveCancelledAudio(audio, job: job)
        XCTAssertEqual(LocalStore(root: root).historyJobs.first?.status, "audio_saved")
    }
    @MainActor func testStagedFileDictationCanBeRecoveredAndDoesNotDeleteCancelledRecording() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root), job = HistoryJob(pipeline: .file)
        let audio = Data(repeating: 1, count: 3200)
        _ = try store.stageFileAudio(audio, id: job.id)
        XCTAssertTrue(store.hasCancelledAudio(job.id))
        XCTAssertEqual(try LocalStore(root: root).loadCancelledAudio(job.id), audio)
        store.removeStagedFileAudio(job.id)
        XCTAssertFalse(store.hasCancelledAudio(job.id))
        try store.saveCancelledAudio(audio, job: job)
        _ = try store.stageFileAudio(audio, id: job.id)
        store.removeStagedFileAudio(job.id)
        XCTAssertEqual(try store.loadCancelledAudio(job.id), audio)
    }
    @MainActor func testInvalidAudioCannotReplaceSavedRecording() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root), job = HistoryJob(pipeline: .file)
        let audio = Data(repeating: 1, count: 3200)
        try store.saveCancelledAudio(audio, job: job)
        XCTAssertThrowsError(try store.saveCancelledAudio(Data(), job: job))
        XCTAssertThrowsError(try store.saveCancelledAudio(Data([1]), job: job))
        XCTAssertEqual(try store.loadCancelledAudio(job.id), audio)
        let file = root.appendingPathComponent("cancelled-recordings/" + job.id.uuidString.lowercased() + ".wav")
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data("invalid".utf8).write(to: file)
        XCTAssertThrowsError(try store.loadCancelledAudio(job.id))
    }
}
