import XCTest
import AppKit
import SwiftUI
import UtterLeafCore
@testable import UtterLeaf

final class QuotaPresentationTests: XCTestCase {
    private func sample() throws -> MinutesQuotaSnapshot {
        try MinutesQuotaSnapshot.parse(JSONSerialization.data(withJSONObject: ["code": 0, "data": ["display_quota": [
            "remaining_asr_quota": 148, "remaining_ai_quota": 0,
            "display_quota_list": [["AuthKey": "vc_asr_function_prem", "IsVisible": true, "QuotaUnit": 0, "Amount": 150,
                "SourceList": [["IsVisible": true, "DisplayText": "每日体验额度", "Remaining": 28, "Amount": 30,
                    "RefreshTime": Date().addingTimeInterval(3600).timeIntervalSince1970]]]]]]]))
    }
    @MainActor func testQuotaCacheLoadsWithoutCreatingANetworkSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("quota.json"), snapshot = try sample()
        try JSONEncoder().encode(snapshot).write(to: file)
        let store = MinutesQuotaStore(file: file, networkEnabled: false)
        store.refresh(force: true)
        XCTAssertEqual(store.snapshot, snapshot); XCTAssertFalse(store.checking)
        XCTAssertNil(store.lastAttempt)
    }
    @MainActor func testNativeQuotaAndSidebarAtMinimumWindowSize() async throws {
        guard ProcessInfo.processInfo.environment["UTTERLEAF_NATIVE_PANEL_TEST"] == "1" else { throw XCTSkip("Requires an interactive macOS desktop") }
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(root: directory), file = directory.appendingPathComponent("quota.json")
        try JSONEncoder().encode(sample()).write(to: file)
        store.minutesQuota = MinutesQuotaStore(file: file, networkEnabled: false)
        var job = HistoryJob(pipeline: .final); job.finalCharacters = 1200
        var call = UsageCall(jobID: job.id, provider: "Doubao", model: "test", price: .init(version: "test", currency: "CNY", note: "test"))
        call.status = .succeeded; call.estimatedAmount = 2
        store.database.jobs = [job]; store.database.calls = [call]
        let model = AppModel(store: store); model.route = "用量与费用"
        let root = NSHostingView(rootView: RootView(model: model, store: store).preferredColorScheme(.dark))
        root.frame = NSRect(x: 0, y: 0, width: 900, height: 680)
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        try save(root, name: "6x30-sidebar-minimum")
        let cards = NSHostingView(rootView: ScrollView {
            VStack(spacing: 18) { UsageBudgetView(store: store); MinutesQuotaView(quota: store.minutesQuota) }.padding(24)
        }.frame(width: 920, height: 1300).background(LeafTheme.mist).preferredColorScheme(.dark))
        cards.frame = NSRect(x: 0, y: 0, width: 920, height: 1300); cards.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        try save(cards, name: "6x30-weekly-and-provider-quota")
    }
    @MainActor private func save(_ view: NSView, name: String) throws {
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/verification/\(name).png")
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: file)
    }
}
