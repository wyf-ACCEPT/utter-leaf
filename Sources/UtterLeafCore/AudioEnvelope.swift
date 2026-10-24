import Foundation

/// A bounded, time-based amplitude history. It stores no audio or speech content.
public struct AudioEnvelope {
    private struct Point { var time: TimeInterval; var level: Float }
    private var points: [Point] = []
    private var smoothed: Float = 0
    public init() {}
    public mutating func reset() { points.removeAll(keepingCapacity: true); smoothed = 0 }
    public mutating func append(rms: Float, at time: TimeInterval) {
        guard rms.isFinite, time.isFinite else { return }
        if let last = points.last, time < last.time { reset() }
        let db = 20 * log10(max(Double(rms), 0.000001))
        // Ignore the near-silence noise floor before visual gain is applied.
        let target = Float(pow(min(max((db + 50) / 44, 0), 1), 1.25))
        let dt = min(max(time - (points.last?.time ?? (time - 0.04)), 0.001), 0.25)
        let tau = target > smoothed ? 0.035 : 0.16
        smoothed += (target - smoothed) * Float(1 - exp(-dt / tau))
        points.append(Point(time: time, level: smoothed))
        points.removeAll { $0.time < time - 1.6 }
        if points.count > 128 { points.removeFirst(points.count - 128) }
    }
    public func amplitudes(at time: TimeInterval, count: Int = 64, window: TimeInterval = 0.9) -> [Float] {
        guard count > 0 else { return [] }
        guard let first = points.first, let last = points.last else { return Array(repeating: 0, count: count) }
        var cursor = 0
        // A small presentation delay lets rendering interpolate between actual samples.
        let end = time - 0.075
        return (0..<count).map { index in
            let moment = end - window + (count == 1 ? 1 : Double(index) / Double(count - 1)) * window
            guard moment + 0.000000001 >= first.time else { return 0 }
            if moment >= last.time {
                return last.level * Float(exp(-max(moment - last.time, 0) / 0.16))
            }
            while cursor + 1 < points.count && points[cursor + 1].time < moment { cursor += 1 }
            let next = min(cursor + 1, points.count - 1)
            let a = points[cursor], b = points[next]
            let weight = Float(min(max((moment - a.time) / max(b.time - a.time, 0.001), 0), 1))
            return min(max(a.level + (b.level - a.level) * weight, 0), 1)
        }
    }
}
