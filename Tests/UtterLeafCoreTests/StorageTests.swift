import XCTest
@testable import UtterLeaf
import UtterLeafCore

final class StorageTests: XCTestCase {
    func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("utterleaf-tests-" + UUID().uuidString) }
    func testHistoryRetentionAndClearKeepUsageAndCounts() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        try await MainActor.run {
            let store = LocalStore(root: root)
            var job = HistoryJob(pipeline: .realtime)
            job.rawText = "原始转写"; job.finalText = "最终稿"; job.rawCharacters = 4; job.finalCharacters = 3
            store.update(job)
            let call = UsageCall(jobID: job.id, provider: "Doubao", model: "v2-realtime", price: .asr(.realtime))
            store.update(call)
            XCTAssertEqual(store.database.jobs.first?.rawText, "原始转写")
            store.clearText()
            XCTAssertNil(store.database.jobs.first?.rawText); XCTAssertNil(store.database.jobs.first?.finalText)
            XCTAssertEqual(store.database.jobs.first?.finalCharacters, 3)
            XCTAssertEqual(store.database.calls.count, 1)
            let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("ledger.json").path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }
    func testRetentionNoneNeverSerializesTranscript() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        try await MainActor.run {
            let store = LocalStore(root: root); store.database.preferences.retention = "none"
            var job = HistoryJob(pipeline: .file); job.rawText = "PRIVATE_RAW_SENTINEL"; job.finalText = "PRIVATE_FINAL_SENTINEL"
            store.update(job)
            let data = try String(contentsOf: root.appendingPathComponent("ledger.json"), encoding: .utf8)
            XCTAssertFalse(data.contains("PRIVATE_RAW_SENTINEL")); XCTAssertFalse(data.contains("PRIVATE_FINAL_SENTINEL"))
        }
    }
    func testInterruptedPendingCallsAreUnknownRatherThanFree() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        await MainActor.run {
            let store = LocalStore(root: root)
            let call = UsageCall(jobID: UUID(), provider: "DeepSeek", model: "deepseek-flash", price: .flash)
            store.update(call)
            let restored = LocalStore(root: root)
            XCTAssertEqual(restored.database.calls.first?.status, .interrupted)
            XCTAssertNil(restored.database.calls.first?.estimatedAmount)
        }
    }
    func testCorruptStoreIsPreservedAndWritesFailClosed() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("ledger.json"); try Data("invalid-json-sentinel".utf8).write(to: file)
        try await MainActor.run {
            let store = LocalStore(root: root); XCTAssertNotNil(store.storageError)
            store.save()
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "invalid-json-sentinel")
        }
    }
    func testTwoDecimalCNYDisplayAndPrices() async {
        await MainActor.run {
            XCTAssertEqual(money(0.123456, "CNY"), "¥0.12")
            XCTAssertEqual(money(1, "CNY"), "¥1.00")
            XCTAssertEqual(PriceSnapshot.flash.currency, "CNY")
            XCTAssertEqual(PriceSnapshot.flash.inputPerMillion, 2)
            XCTAssertNil(LeafTheme.scheme("system"))
            XCTAssertEqual(LeafTheme.scheme(nil), .dark)
        }
    }
    @MainActor func testBriefEmptyAudioIsQuietButLongAudioAndRealErrorsRemainVisible() {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: LocalStore(root: root), captureTarget: { nil })
        var opened = 0; model.showWindow = { opened += 1 }
        for code in ["asr_empty", "silent_audio"] {
            model.elapsed = 3; model.phase = .transcribing
            model.fail(AppFailure("No speech", code: code))
            XCTAssertEqual(model.phase, .idle); XCTAssertTrue(model.message.isEmpty); XCTAssertEqual(opened, 0)
        }
        model.elapsed = 3.001; model.phase = .transcribing
        model.fail(AppFailure("No speech", code: "asr_empty"))
        XCTAssertEqual(model.phase, .error); XCTAssertEqual(opened, 1)
        model.elapsed = 1; model.phase = .starting
        model.fail(AppFailure("Permission denied", code: "microphone_denied"))
        XCTAssertEqual(model.phase, .error); XCTAssertEqual(model.message, "Permission denied"); XCTAssertEqual(opened, 2)
    }

    @MainActor func testSoundChoicePersistsAndLegacyDefaultsToSoftTheme() {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root)
        XCTAssertEqual((store.database.preferences.sound ?? SoundPreferences()).theme, .soft)
        var sound = SoundPreferences(); sound.theme = .wood; sound.enabled = false; sound.volume = 0.4
        store.database.preferences.sound = sound; store.save()
        let restored = LocalStore(root: root)
        XCTAssertEqual(restored.database.preferences.sound?.theme, .wood)
        XCTAssertEqual(restored.database.preferences.sound?.enabled, false)
        XCTAssertEqual(restored.database.preferences.sound?.volume, 0.4)
        sound.volume = .nan; XCTAssertEqual(sound.playbackVolume, 0.7)
        sound.volume = 2; XCTAssertEqual(sound.playbackVolume, 1)
    }

}
