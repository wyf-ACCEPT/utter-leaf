import XCTest
@testable import UtterLeafCore

final class FnKeyGestureTests: XCTestCase {
    func testStandaloneFnFiresOnceOnRelease() {
        var gesture = FnKeyGesture()
        XCTAssertFalse(gesture.fnChanged(isDown: true, hasOtherModifiers: false))
        XCTAssertTrue(gesture.fnChanged(isDown: false, hasOtherModifiers: false))
        XCTAssertFalse(gesture.fnChanged(isDown: false, hasOtherModifiers: false))
    }
    func testDuplicateDownDoesNotDoubleFire() {
        var gesture = FnKeyGesture()
        XCTAssertFalse(gesture.fnChanged(isDown: true, hasOtherModifiers: false))
        XCTAssertFalse(gesture.fnChanged(isDown: true, hasOtherModifiers: false))
        XCTAssertTrue(gesture.fnChanged(isDown: false, hasOtherModifiers: false))
    }
    func testFnArrowOrFunctionKeyChordDoesNotToggle() {
        var gesture = FnKeyGesture()
        _ = gesture.fnChanged(isDown: true, hasOtherModifiers: false)
        gesture.otherKey()
        XCTAssertFalse(gesture.fnChanged(isDown: false, hasOtherModifiers: false))
    }
    func testModifierAlreadyHeldSuppressesFnTap() {
        var gesture = FnKeyGesture()
        _ = gesture.fnChanged(isDown: true, hasOtherModifiers: true)
        XCTAssertFalse(gesture.fnChanged(isDown: false, hasOtherModifiers: false))
    }
    func testModifierPressedThenReleasedDuringFnIsStillAChord() {
        var gesture = FnKeyGesture()
        _ = gesture.fnChanged(isDown: true, hasOtherModifiers: false)
        gesture.otherModifiersChanged(hasOtherModifiers: true)
        gesture.otherModifiersChanged(hasOtherModifiers: false)
        XCTAssertFalse(gesture.fnChanged(isDown: false, hasOtherModifiers: false))
    }
    func testResetAfterSleepOrTapInterruptionDoesNotCreatePhantomToggle() {
        var gesture = FnKeyGesture()
        _ = gesture.fnChanged(isDown: true, hasOtherModifiers: false)
        gesture.reset()
        XCTAssertFalse(gesture.fnChanged(isDown: false, hasOtherModifiers: false))
        XCTAssertFalse(gesture.isPressed)
    }
    func testTwoStandaloneTapsToggleTwiceAndOrdinaryTypingIsIgnored() {
        var gesture = FnKeyGesture()
        gesture.otherKey()
        for _ in 0..<2 {
            XCTAssertFalse(gesture.fnChanged(isDown: true, hasOtherModifiers: false))
            XCTAssertTrue(gesture.fnChanged(isDown: false, hasOtherModifiers: false))
        }
    }
}
