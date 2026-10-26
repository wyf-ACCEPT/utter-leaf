import XCTest
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UtterLeafCore
@testable import UtterLeaf

final class MeetingPresentationTests: XCTestCase {
    func testTXTFileDocumentWritesUTF8ToDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = "会议记录\n[01:23] Alice：支持中文、English 与 emoji 🌿。\n"
        let file = MeetingTextFile(text: text)
        let wrapper = file.utf8File
        let url = root.appendingPathComponent("Synthetic meeting.txt")
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
    }
    @MainActor func testNativeMeetingWorkflowPresentationWithSyntheticData() async throws {
        guard ProcessInfo.processInfo.environment["UTTERLEAF_NATIVE_PANEL_TEST"] == "1" else { throw XCTSkip("Requires an interactive macOS desktop") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = MeetingModel(ledger: LocalStore(root: root))
        var record = MeetingRecord(); record.title = "产品评审 · 合成会议"; record.state = "transcribed"; record.seconds = 125
        record.segments = [.init(id: "u0", start: 0, end: 30, speaker: "1", text: "嗯，那个，我们周三先完成设计稿。"), .init(id: "u1", start: 30, end: 65, speaker: "2", text: "好的，然后周五一起确认。")]
        for number in 3...5 {
            let start = Double(number) * 10
            record.segments.append(MeetingUtterance(id: "u\(number)", start: start, end: start + 5, speaker: String(number), text: "合成发言 \(number)"))
        }
        record.speakerNames = ["1": "Alice", "2": "Bob", "3": "Carol", "4": "Dave", "5": "Eve"]
        record.notes = "先确认方案与交付时间。"
        for stage in ["raw", "cleaned", "brief"] {
            if stage != "raw" { record.cleaned = Dictionary(uniqueKeysWithValues: record.segments.map { ($0.id, "整理后的合成发言：" + $0.text) }) }
            if stage == "brief" { record.brief = "# 会议纪要\n\n周三完成设计稿，周五一起确认。[u0][u1]"; record.state = "ready" }
            try model.store.save(record); model.selected = record.id
            let view = NSHostingView(rootView: ScrollView { MeetingsView(model: model, meetings: model.store, initialTab: stage == "brief" ? "Brief" : "整理稿").padding(24) }.frame(width: 1000, height: 1000).background(LeafTheme.mist).preferredColorScheme(.dark))
            view.frame = NSRect(x: 0, y: 0, width: 1000, height: 1000)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            if let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: image)
                let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/verification/meeting-workflow-\(stage).png")
                try image.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        XCTAssertTrue(model.store.index.meetings.count == 1)
    }
}
