import XCTest
@testable import UtterLeafCore

final class InsertionVerificationTests: XCTestCase {
    func testCodexAndBrowserComposersUseKeyboardPaste() {
        XCTAssertTrue(InsertionVerification.prefersKeyboardPaste(bundleID: "com.openai.codex"))
        XCTAssertTrue(InsertionVerification.prefersKeyboardPaste(bundleID: "com.openai.chat"))
        XCTAssertTrue(InsertionVerification.prefersKeyboardPaste(bundleID: "com.google.Chrome"))
        XCTAssertFalse(InsertionVerification.prefersKeyboardPaste(bundleID: "com.apple.TextEdit"))
    }
    func testAXSuccessWithoutChangedTextOrCaretIsNotConfirmation() {
        XCTAssertFalse(InsertionVerification.confirms(before: "", originalRange: NSRange(location: 0, length: 0), inserted: "test", after: "", currentRange: NSRange(location: 0, length: 0), insertedSubstring: nil))
    }
    func testInsertedTextAndCaretConfirmRealInput() {
        XCTAssertTrue(InsertionVerification.confirms(before: "prefix ", originalRange: NSRange(location: 7, length: 0), inserted: "test", after: "prefix test", currentRange: NSRange(location: 11, length: 0), insertedSubstring: "test"))
    }
    func testChangedValueWithUnchangedCaretIsNotEnough() {
        XCTAssertFalse(InsertionVerification.confirms(before: "", originalRange: NSRange(location: 0, length: 0), inserted: "test", after: "test", currentRange: NSRange(location: 0, length: 0), insertedSubstring: "test"))
    }
    func testUTF16SelectionReplacementAndRangeBounds() {
        XCTAssertEqual(InsertionVerification.expectedText(before: "a😀b", range: NSRange(location: 1, length: 2), inserted: "中"), "a中b")
        XCTAssertNil(InsertionVerification.expectedText(before: "a", range: NSRange(location: 9, length: 1), inserted: "x"))
        XCTAssertNil(InsertionVerification.expectedText(before: nil, range: nil, inserted: "x"))
    }
    func testReadbackCanConfirmWithoutFullFieldValue() {
        XCTAssertTrue(InsertionVerification.confirms(before: nil, originalRange: NSRange(location: 3, length: 0), inserted: "x", after: nil, currentRange: NSRange(location: 4, length: 0), insertedSubstring: "x"))
    }
    func testSpeechCurvesAreBoundedAndRespondToRealAmplitude() {
        let silent = SpeechWaveCurve.points(amplitudes: [0,0,0], phase: 1, layer: 0)
        XCTAssertTrue(silent.allSatisfy { $0 == 0 })
        let loud = SpeechWaveCurve.points(amplitudes: [1,1,1], phase: 1, layer: 0)
        XCTAssertTrue(loud.allSatisfy { $0.isFinite && abs($0) <= 1 })
        XCTAssertEqual(loud.first, 0); XCTAssertEqual(loud.last, 0)
        XCTAssertNotEqual(loud, SpeechWaveCurve.points(amplitudes: [1,1,1], phase: 2, layer: 0))
    }
}
