import Foundation

public enum SoundTheme: String, Codable, CaseIterable, Identifiable {
    case soft = "a", wood = "b", chime = "c"
    public var id: String { rawValue }
    public var title: String {
        switch self { case .soft: return "A · 轻触"; case .wood: return "B · 木滴"; case .chime: return "C · 清铃" }
    }
}
public struct SoundPreferences: Codable {
    public var enabled = true
    public var theme: SoundTheme = .soft
    public var volume: Double = 0.7
    public init() {}
    public var playbackVolume: Float { Float(volume.isFinite ? min(max(volume, 0), 1) : 0.7) }
}
