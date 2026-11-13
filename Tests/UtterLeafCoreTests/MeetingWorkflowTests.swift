import XCTest
import UtterLeafCore
@testable import UtterLeaf

final class MeetingWorkflowTests: XCTestCase {
    private func meeting() -> MeetingRecord {
        var meeting = MeetingRecord(); meeting.title = "Synthetic meeting"; meeting.seconds = 65
        meeting.segments = [
            .init(id: "u0", start: 0, end: 3, speaker: "1", text: "Raw statement"),
            .init(id: "u1", start: 61, end: 65, speaker: "2", text: "Another raw statement")
        ]
        return meeting
    }
    func testWorkflowGoesFromRawTranscriptToOptionalBrief() {
        XCTAssertEqual(MeetingWorkflow.next(MeetingRecord()), .transcribe)
        var value = meeting()
        XCTAssertEqual(MeetingWorkflow.next(value), .brief)
        value.brief = "A summary [u0]"
        XCTAssertEqual(MeetingWorkflow.next(value), .read)
        value.briefNeedsUpdate = true
        XCTAssertEqual(MeetingWorkflow.next(value), .brief)
        XCTAssertEqual(value.brief, "A summary [u0]")
        XCTAssertEqual(MeetingTextSection.allCases, [.notes, .raw, .brief])
    }
    func testExportUsesSelectedVersionSpeakerCorrectionsAndReferencePreference() throws {
        var value = meeting()
        value.speakerNames["3"] = "Alice"; value.speakerOverrides = ["u0": "3"]
        let raw = try XCTUnwrap(MeetingTextExport.body(value, section: .raw, references: false))
        XCTAssertTrue(raw.contains("[00:00] Alice：Raw statement"))
        XCTAssertTrue(raw.contains("[01:01] 说话人 2：Another raw statement"))
        value.brief = "Decision [u0]。"
        XCTAssertEqual(MeetingTextExport.body(value, section: .brief, references: false), "Decision。")
        XCTAssertEqual(MeetingTextExport.body(value, section: .brief, references: true), value.brief)
        value.notes = "UTF-8 中文 notes"
        let document = try XCTUnwrap(MeetingTextExport.document(value, section: .notes, references: false))
        XCTAssertTrue(document.contains("我的笔记")); XCTAssertTrue(document.contains(value.notes))
        XCTAssertEqual(String(data: Data(document.utf8), encoding: .utf8), document)
        XCTAssertNil(MeetingTextExport.body(MeetingRecord(), section: .raw, references: false))
        XCTAssertNil(MeetingTextExport.body(MeetingRecord(), section: .brief, references: false))
    }
    func testExportFilenameIsASingleSafeComponent() {
        var value = meeting(); value.title = "../A:B\\C\n会议"
        let filename = MeetingTextExport.filename(value, section: .raw)
        XCTAssertFalse(filename.contains("/")); XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("\\")); XCTAssertFalse(filename.contains("\n"))
        XCTAssertTrue(filename.hasSuffix(".txt")); XCTAssertTrue(filename.contains("-meeting-"))
        value.title = "   "
        XCTAssertEqual(MeetingTextExport.filename(value, section: .brief), MeetingNaming.stem(value) + ".txt")
    }
    func testBriefEnvelopeUsesRawTranscriptWithSourceIDs() throws {
        var value = meeting(); value.setTranscriptText(id: "u1", text: "Corrected raw statement")
        let envelope = try MeetingProtocol.envelope(value)
        XCTAssertTrue(envelope.contains("Raw statement")); XCTAssertTrue(envelope.contains("Corrected raw statement"))
        XCTAssertTrue(envelope.contains("u0")); XCTAssertTrue(envelope.contains("u1"))
    }
}
