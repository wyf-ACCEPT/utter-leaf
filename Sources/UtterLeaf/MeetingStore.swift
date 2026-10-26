import Foundation
import UtterLeafCore

@MainActor final class MeetingStore: ObservableObject {
    struct Index: Codable { var meetings: [MeetingRecord] = []; var voices: [VoiceIdentity] = []; var voiceMutationUncertain: Bool?; var systemAudio: Bool?; var liveCaptions: Bool?; var floatingCaptions: Bool?; var captionOpacity: Double?; var captionLineCount: Int?; var briefReferences: Bool? }
    @Published private(set) var index = Index()
    @Published var error: String?
    let root: URL
    private var writable = true
    init(root: URL) {
        self.root = root.appendingPathComponent("meetings", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = self.root.appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: file.path) {
                index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: file))
                for i in index.meetings.indices where ["recording", "paused", "preparing", "saving", "transcribing", "summarizing"].contains(index.meetings[i].state) {
                    index.meetings[i].state = "interrupted"
                }
            }
        } catch { writable = false; self.error = "会议记录无法读取，已停止写入以保护现有资料。" }
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func audio(_ id: UUID) -> URL { folder(id).appendingPathComponent("meeting.wav") }
    func prepare(_ id: UUID) throws {
        guard writable else { throw AppFailure(error ?? "会议存储不可用。", code: "meeting_storage") }
        try FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func save(_ value: MeetingRecord) throws {
        if let i = index.meetings.firstIndex(where: { $0.id == value.id }) { index.meetings[i] = value }
        else { index.meetings.insert(value, at: 0) }
        try persist()
    }
    func saveOptions(systemAudio: Bool, live: Bool, floating: Bool = true, captionOpacity: Double = 0.75, captionLineCount: Int = 3, briefReferences: Bool = false) throws {
        index.systemAudio = systemAudio; index.liveCaptions = live; index.floatingCaptions = floating
        index.captionOpacity = MeetingCaptionPolicy.opacity(captionOpacity)
        index.captionLineCount = MeetingCaptionPolicy.lineCount(captionLineCount)
        index.briefReferences = briefReferences
        try persist()
    }
    func markVoiceMutation(_ uncertain: Bool) throws { index.voiceMutationUncertain = uncertain; try persist() }
    func saveVoices(_ voices: [VoiceIdentity]) throws { index.voices = voices; try persist() }
    private func persist() throws {
        guard writable else { throw AppFailure(error ?? "会议存储不可用。", code: "meeting_storage") }
        do {
            let data = try JSONEncoder().encode(index)
            let path = root.appendingPathComponent("index.json")
            try data.write(to: path, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var folder = root; try folder.setResourceValues(values)
            error = nil
        } catch { self.error = "会议保存失败，请先复制笔记并检查磁盘空间。"; throw error }
    }
    func delete(_ id: UUID) throws {
        guard writable else { throw AppFailure("会议存储不可用。", code: "meeting_storage") }
        if FileManager.default.fileExists(atPath: folder(id).path) { try FileManager.default.removeItem(at: folder(id)) }
        index.meetings.removeAll { $0.id == id }; try persist()
    }
    func deleteAudio(_ id: UUID) throws {
        let folder = folder(id)
        for name in ["meeting.wav", "microphone.pcm", "system.pcm", "request.json"] {
            let file = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
}
