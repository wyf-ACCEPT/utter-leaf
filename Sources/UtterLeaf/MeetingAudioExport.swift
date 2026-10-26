import AVFoundation
import Foundation

@MainActor enum MeetingAudioExport {
    static func convert(source: URL, destination: URL) async throws {
        if source.pathExtension.lowercased() == "m4a" {
            let file = try FileHandle(forReadingFrom: source)
            let header = try file.read(upToCount: 8) ?? Data(); try file.close()
            if header.count == 8, header[4..<8] == Data("ftyp".utf8) {
                try FileManager.default.copyItem(at: source, to: destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                return
            }
        }
        guard let exporter = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else {
            throw AppFailure("当前音频无法导出为 M4A。", code: "meeting_export_format")
        }
        exporter.outputFileType = .m4a; exporter.outputURL = destination
        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in exporter.exportAsynchronously { continuation.resume() } }
            guard exporter.status == .completed else { throw exporter.error ?? AppFailure("M4A 转换未完成。", code: "meeting_export_audio") }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } onCancel: { exporter.cancelExport() }
    }
}
