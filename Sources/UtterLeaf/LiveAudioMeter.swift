import Foundation
import UtterLeafCore

/// Audio callbacks update this buffer on the main actor; only the waveform's clock redraws it.
@MainActor final class LiveAudioMeter {
    var history = AudioEnvelope()
    func reset() { history.reset() }
    func append(rms: Float) { history.append(rms: rms, at: ProcessInfo.processInfo.systemUptime) }
}
