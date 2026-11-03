import XCTest
import UtterLeafCore

final class TerminalReturnTests: XCTestCase {
    func testTerminalTextCannotContainExecutionControls() {
        XCTAssertTrue(TerminalReturnPolicy.acceptsText("合成输入 Synthetic text"))
        for text in ["", "one\ntwo", "one\rtwo", "\u{1b}[A", "one\ttwo"] { XCTAssertFalse(TerminalReturnPolicy.acceptsText(text)) }
    }
    func testOnlyUnchangedOriginalTerminalCanReceivePaste() {
        XCTAssertTrue(TerminalReturnPolicy.allows(inputChanged: false, sameWindow: true, sameElement: true, foregroundMatches: true))
        for values in [(true, true, true, true), (false, false, true, true), (false, true, false, true), (false, true, true, false)] {
            XCTAssertFalse(TerminalReturnPolicy.allows(inputChanged: values.0, sameWindow: values.1, sameElement: values.2, foregroundMatches: values.3))
        }
    }
}
