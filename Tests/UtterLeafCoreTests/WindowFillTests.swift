import XCTest
import CoreGraphics
@testable import UtterLeafCore

final class WindowFillTests: XCTestCase {
    let screen = CGRect(x: 0, y: 80, width: 1512, height: 870)
    let original = CGRect(x: 180, y: 100, width: 1100, height: 780)
    func testFillRestoresExactPositionAndDimensionsAcrossRepeatedCycles() {
        var state = WindowFillState()
        for _ in 0..<3 {
            XCTAssertEqual(state.destination(current: original, visibleFrame: screen), screen)
            XCTAssertEqual(state.destination(current: screen, visibleFrame: screen), original)
            XCTAssertNil(state.restoreFrame)
        }
    }
    func testUserResizeEstablishesNewRestoreFrame() {
        var state = WindowFillState()
        _ = state.destination(current: original, visibleFrame: screen)
        let changed = CGRect(x: 50, y: 110, width: 1000, height: 700)
        XCTAssertEqual(state.destination(current: changed, visibleFrame: screen), screen)
        XCTAssertEqual(state.destination(current: screen, visibleFrame: screen), changed)
    }
    func testPersistedFilledWindowRestoresAfterRelaunchAndScreenChangeClampsSafely() {
        var state = WindowFillState(restoreFrame: original, filledFrame: screen)
        XCTAssertEqual(state.destination(current: screen, visibleFrame: screen), original)
        state = WindowFillState(restoreFrame: CGRect(x: 2200, y: 200, width: 1400, height: 900), filledFrame: screen)
        let restored = state.destination(current: screen, visibleFrame: screen)
        XCTAssertTrue(screen.contains(restored)); XCTAssertEqual(restored.height, 870)
    }
}
