import XCTest
import UtterLeafCore

final class RecordingLimitTests: XCTestCase {
    func testFormerTwoMinuteBoundaryDoesNotLimitRecording() {
        XCTAssertGreaterThan(RecordingLimit.acceptedBytes(buffered: 120 * 32_000, incoming: 6400), 0)
        XCTAssertNil(RecordingLimit.warning(at: 120))
    }
    func testCountdownBeginsOnlyInLastThirtySeconds() {
        XCTAssertNil(RecordingLimit.warning(at: 269.999))
        XCTAssertEqual(RecordingLimit.warning(at: 270), "剩余 30 秒")
        XCTAssertEqual(RecordingLimit.warning(at: 299.1), "剩余 1 秒")
        XCTAssertEqual(RecordingLimit.warning(at: 300), "剩余 0 秒")
        XCTAssertEqual(RecordingLimit.remaining(at: 301), 0)
    }
    func testAudioBufferStopsExactlyAtFiveMinutes() {
        XCTAssertEqual(RecordingLimit.maximumPCMBytes, 9_600_000)
        XCTAssertEqual(RecordingLimit.acceptedBytes(buffered: 9_599_000, incoming: 6400), 1000)
        XCTAssertEqual(RecordingLimit.acceptedBytes(buffered: 9_600_000, incoming: 6400), 0)
    }
}
