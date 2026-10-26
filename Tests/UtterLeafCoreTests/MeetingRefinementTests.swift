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
}
