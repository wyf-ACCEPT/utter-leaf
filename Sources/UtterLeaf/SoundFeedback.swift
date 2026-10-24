import AVFoundation
import Combine
import UtterLeafCore

@MainActor final class SoundFeedback: ObservableObject {
    enum Cue: String, CaseIterable { case start, stop, complete }
    @Published private(set) var previewing = false
    @Published private(set) var error: String?
    private var player: AVAudioPlayer?
    private var previewRevision = 0
    private var previewTask: Task<Void, Never>?
    @discardableResult func play(_ cue: Cue, preferences: SoundPreferences) -> TimeInterval? {
        guard preferences.enabled, preferences.playbackVolume > 0 else { return nil }
        player?.stop()
        guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sounds/" + preferences.theme.rawValue),
              let sound = try? AVAudioPlayer(contentsOf: url) else {
            error = "提示音文件无法读取，听写仍可正常使用。"; return nil
        }
        sound.volume = preferences.playbackVolume; sound.prepareToPlay(); player = sound
        guard sound.play() else { error = "提示音无法播放，请检查音频输出设备。"; return nil }
        error = nil
        return sound.duration
    }
    func beforeMicrophone(preferences: SoundPreferences) async throws {
        stop()
        // Keep the cue and a short speaker tail outside the microphone capture window.
        if let duration = play(.start, preferences: preferences) {
            try await Task.sleep(for: .seconds(duration + 0.03))
        }
        try Task.checkCancellation()
    }
    func preview(preferences: SoundPreferences) {
        stop(); previewing = true
        let revision = previewRevision
        previewTask = Task { [weak self] in
            guard let self else { return }
            defer { if previewRevision == revision { previewing = false } }
            for cue in Cue.allCases {
                guard !Task.isCancelled else { return }
                play(cue, preferences: preferences)
                do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            }
        }
    }
    func stop() { previewRevision += 1; previewTask?.cancel(); previewTask = nil; player?.stop(); player = nil; previewing = false }
}
