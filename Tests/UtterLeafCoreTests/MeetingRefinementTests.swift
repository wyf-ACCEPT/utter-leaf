import XCTest
import Foundation
import UtterLeafCore
@testable import UtterLeaf

final class MeetingRefinementTests: XCTestCase {
    func testRawEditsPreserveProviderTextAndInvalidateOnlyAffectedCleanup() throws {
        var value = MeetingRecord()
        value.segments = [.init(id: "u0", start: 0, end: 3, speaker: "1", text: "Raw"), .init(id: "u1", start: 3, end: 5, speaker: "2", text: "Keep")]
        value.cleaned = ["u0": "Cleaned", "u1": "Cleaned keep"]; value.brief = "Summary [u0]"
        value.setTranscriptText(id: "u0", text: "Corrected")
        XCTAssertEqual(value.segments[0].text, "Raw"); XCTAssertEqual(value.text(for: value.segments[0]), "Corrected")
        XCTAssertNil(value.cleaned?["u0"]); XCTAssertEqual(value.cleaned?["u1"], "Cleaned keep")
        XCTAssertTrue(value.briefNeedsUpdate == true); XCTAssertFalse(MeetingWorkflow.cleaned(value))
        XCTAssertTrue(try MeetingProtocol.envelope(value).contains("Corrected"))
        XCTAssertTrue(MeetingTextExport.body(value, section: .raw, references: false)!.contains("Corrected"))
        value.setTranscriptText(id: "u0", text: "Raw"); XCTAssertNil(value.rawTextEdits?["u0"])
    }
    func testProgressUsesValidatedCountsAndUnknownRecognitionDoesNotInventPercentage() {
        XCTAssertNil(MeetingWorkProgress(.queued).fraction)
        XCTAssertNil(MeetingWorkProgress(.recognizing).fraction)
        XCTAssertEqual(MeetingWorkProgress(.cleaning, completed: 60, total: 804).fraction!, 60.0 / 804, accuracy: 0.00001)
        XCTAssertEqual(MeetingWorkProgress(.uploading, completed: 40, total: 100).fraction!, 0.4)
        XCTAssertEqual(MeetingWorkProgress(.cleaning, completed: 900, total: 804).fraction!, 1)
    }
    func testDatePrefixedNamesAndExtensionShareAValidatedStem() throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-26T08:00:00Z")!
        XCTAssertEqual(MeetingNaming.prefix(date), "6x26")
        XCTAssertEqual(MeetingNaming.prefix(ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!), "7a01")
        let names = try MeetingNaming.candidates(#"{"candidates":["isocution-3","api-review","audit-design"]}"#, created: date)
        XCTAssertEqual(names[0], "6x26-isocution-3")
        XCTAssertThrowsError(try MeetingNaming.candidates(#"{"candidates":["../bad","same","same"]}"#, created: date))
        var value = MeetingRecord(); value.created = date; value.fileStem = names[0]
        XCTAssertEqual(MeetingTextExport.filename(value, section: .brief), "6x26-isocution-3.txt")
        XCTAssertEqual(MeetingNaming.stem(value) + ".m4a", "6x26-isocution-3.m4a")
    }
    @MainActor func testM4AExportReallyConvertsContainerAndRetainsWAV() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input.wav"), output = root.appendingPathComponent("output.m4a")
        let original = DoubaoWire.wav(Data(count: 32000)); try original.write(to: input)
        try await MeetingAudioExport.convert(source: input, destination: output)
        XCTAssertEqual(try Data(contentsOf: input), original)
        let data = try Data(contentsOf: output)
        XCTAssertTrue(String(decoding: data.prefix(100), as: UTF8.self).contains("ftyp"))
        XCTAssertGreaterThan(data.count, 100)
    }
    @MainActor func testNamingUsesPersonalModelReceiptsAndDoesNotChangeTitleUntilSelected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = LocalStore(root: root)
        let api = MeetingAPI(credentials: { _ in "synthetic" }) { request in
            XCTAssertEqual(request.url?.host, "api.deepseek.com")
            let result: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": #"{"candidates":["api-review","core-design","runtime-review"]}"#]]], "usage": ["prompt_tokens": 20, "completion_tokens": 10]]
            return (try JSONSerialization.data(withJSONObject: result), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = MeetingModel(ledger: ledger, api: api)
        var record = MeetingRecord(); record.title = "Original"; record.state = "transcribed"
        record.segments = [.init(id: "u0", start: 0, end: 3, speaker: "1", text: "Synthetic API review")]
        try model.store.save(record); model.select(record.id); model.suggestNames()
        for _ in 0..<100 { if model.namingMeetingID == nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.current?.nameCandidates?.count, 3); XCTAssertEqual(model.current?.title, "Original")
        model.applyName(model.current!.nameCandidates![0]); XCTAssertEqual(model.current?.title, model.current?.fileStem)
        XCTAssertEqual(ledger.database.calls.count, 1); XCTAssertEqual(ledger.database.calls.first?.model, "deepseek-flash-meeting-naming")
    }
}
