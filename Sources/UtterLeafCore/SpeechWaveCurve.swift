import Foundation

/// Small bounded polylines inspired by the MIT SpeechWaveAnimation sine/envelope design.
/// Microphone amplitude controls the height; only phase motion is decorative.
public enum SpeechWaveCurve {
    public static func points(amplitudes: [Float], phase: Double, layer: Int, count: Int = 80) -> [Double] {
        guard count >= 2 else { return [] }
        let frequency = [1.6, 2.15, 2.7][min(max(layer, 0), 2)]
        let strength = [0.95, 0.57, 0.33][min(max(layer, 0), 2)]
        return (0..<count).map { index in
            let x = Double(index) / Double(count - 1)
            let samplePosition = x * Double(max(amplitudes.count - 1, 0))
            let low = min(Int(samplePosition), max(amplitudes.count - 1, 0))
            let high = min(low + 1, max(amplitudes.count - 1, 0))
            let a = amplitudes.isEmpty ? 0 : Double(amplitudes[low])
            let b = amplitudes.isEmpty ? 0 : Double(amplitudes[high])
            let amplitude = min(max((a + (b - a) * (samplePosition - Double(low))) * 1.7, 0), 1)
            let envelope = max(0, 1 - pow(2 * x - 1, 2))
            return envelope * amplitude * strength * sin(2 * .pi * frequency * x + phase)
        }
    }
}
