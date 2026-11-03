import XCTest
import UtterLeafCore
@testable import UtterLeaf

@MainActor private final class FileTestTransport: MinutesFileTransport {
    var remaining = 150.0
    var uploads = 0
    var resumes = 0
    var failUpload = false
    var actions: [String] = []
    func load() async throws {}
    func run(_ action: String, key: UUID, arguments: [String: Any]) async throws -> [String: Any] {
        actions.append(action)
        switch action {
        case "quota": return ["remaining": remaining]
        case "status": return ["status": [["objectStatus": 2]]]
        case "result": return ["segments": [["id": "s1", "start": 0.0, "end": 1.0, "text": "Synthetic transcript", "speaker": "unknown"]]]
        default: throw AppFailure("Synthetic failure", code: "test")
        }
    }
    func upload(audio: URL, seconds: Double, key: UUID, resume: Bool, prepared: (String) throws -> Void, progress: (Int) -> Void) async throws -> String {
        if resume { resumes += 1 } else { uploads += 1 }
        try prepared("syntheticobject")
        if failUpload && !resume { throw AppFailure("Synthetic connection loss", code: "test") }
        return "syntheticobject"
    }
}
final class FileASRRouterTests: XCTestCase {
    @MainActor func testAvailableQuotaAlwaysUsesMinutesAndCachesCompleteResult() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = MinutesAccountStore(root: root, networkEnabled: false), transport = FileTestTransport(), id = UUID()
        let router = FileASRRouter(root: root, accounts: accounts, makeSession: { _ in transport })
        guard case .transcript(let rows) = try await router.transcribe(audio: root, seconds: 2400, id: id) else { return XCTFail("Available Minutes quota must not use Doubao") }
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(transport.uploads, 1)
        _ = try await router.transcribe(audio: root, seconds: 2400, id: id)
        XCTAssertEqual(transport.uploads, 1)
    }
    @MainActor func testInsufficientQuotaFallsBackBeforeAnyMinutesSubmission() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = MinutesAccountStore(root: root, networkEnabled: false), transport = FileTestTransport(), id = UUID()
        transport.remaining = 30
        let router = FileASRRouter(root: root, accounts: accounts, makeSession: { _ in transport })
        guard case .useDoubao = try await router.transcribe(audio: root, seconds: 2400, id: id) else { return XCTFail("Confirmed insufficient quota should allow Doubao") }
        XCTAssertEqual(transport.uploads, 0); XCTAssertFalse(router.hasReceipt(id))
    }
    @MainActor func testUncertainUploadResumesOriginalObjectWithoutSecondSubmission() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = MinutesAccountStore(root: root, networkEnabled: false), transport = FileTestTransport(), id = UUID()
        transport.failUpload = true
        let router = FileASRRouter(root: root, accounts: accounts, makeSession: { _ in transport })
        do { _ = try await router.transcribe(audio: root, seconds: 20, id: id); XCTFail("Must preserve the uncertain result") } catch {}
        XCTAssertTrue(router.hasReceipt(id))
        let resumed = FileASRRouter(root: root, accounts: accounts, makeSession: { _ in transport })
        _ = try await resumed.transcribe(audio: root, seconds: 20, id: id)
        XCTAssertEqual(transport.uploads, 1); XCTAssertEqual(transport.resumes, 1)
    }
    func testIncompleteStatusAndMalformedTranscriptAreNotSuccess() {
        XCTAssertFalse(MinutesFileResult.isComplete(["status": [["objectStatus": 1]]]))
        XCTAssertFalse(MinutesFileResult.isComplete([:]))
        XCTAssertTrue(MinutesFileResult.isComplete(["status": [["objectStatus": "2"]]]))
        XCTAssertEqual(MinutesFileResult.failure(["status": [["objectStatus": "3"]]]), 3)
        XCTAssertThrowsError(try MinutesFileResult.segments(["pending": true]))
        XCTAssertThrowsError(try MinutesFileResult.segments(["segments": [["id": "x", "start": -1, "end": 1, "speaker": "0", "text": "x"]]]))
    }
}
