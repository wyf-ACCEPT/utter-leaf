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
    func testWorkflowRequiresCompleteCleanupBeforeAdvancing() {
        XCTAssertEqual(MeetingWorkflow.next(MeetingRecord()), .transcribe)
        var value = meeting()
        XCTAssertEqual(MeetingWorkflow.next(value), .clean)
        value.cleaned = ["u0": "Cleaned statement", "unrelated": "Not a source"]
        XCTAssertFalse(MeetingWorkflow.cleaned(value))
        value.cleaned?["u1"] = "   "
        XCTAssertEqual(MeetingWorkflow.next(value), .clean)
        value.cleaned?["u1"] = "Another cleaned statement"
        XCTAssertEqual(MeetingWorkflow.next(value), .brief)
        value.brief = "A summary [u0]"
        XCTAssertEqual(MeetingWorkflow.next(value), .read)
        value.briefNeedsUpdate = true
        XCTAssertEqual(MeetingWorkflow.next(value), .brief)
        XCTAssertEqual(value.brief, "A summary [u0]")
        value.cleaned = nil
        XCTAssertEqual(MeetingWorkflow.next(value), .clean)
    }
    func testExportUsesSelectedVersionSpeakerCorrectionsAndReferencePreference() throws {
        var value = meeting()
        value.speakerNames["3"] = "Alice"; value.speakerOverrides = ["u0": "3"]
        XCTAssertNil(MeetingTextExport.body(value, section: .cleaned, references: false))
        value.cleaned = ["u0": "Cleaned statement", "u1": "Another cleaned statement"]
        let raw = try XCTUnwrap(MeetingTextExport.body(value, section: .raw, references: false))
        let clean = try XCTUnwrap(MeetingTextExport.body(value, section: .cleaned, references: false))
        XCTAssertTrue(raw.contains("[00:00] Alice：Raw statement"))
        XCTAssertTrue(clean.contains("[01:01] 说话人 2：Another cleaned statement"))
        XCTAssertFalse(clean.contains("Raw statement"))
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
    func testBriefCanUseCleanedTextWithoutChangingOriginalOrSourceIDs() throws {
        var value = meeting(); value.cleaned = ["u0": "Cleaned statement", "u1": "Another cleaned statement"]
        let raw = try MeetingProtocol.envelope(value)
        let cleaned = try MeetingProtocol.envelope(value, preferCleaned: true)
        XCTAssertTrue(raw.contains("Raw statement")); XCTAssertFalse(cleaned.contains("Raw statement"))
        XCTAssertTrue(cleaned.contains("u0")); XCTAssertTrue(cleaned.contains("u1"))
        XCTAssertEqual(value.segments[0].text, "Raw statement")
    }
}
