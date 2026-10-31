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
        XCTAssertEqual(store.authentication, .unverified)
    }
    @MainActor func testNativeQuotaAndSidebarAtMinimumWindowSize() async throws {
        guard ProcessInfo.processInfo.environment["UTTERLEAF_NATIVE_PANEL_TEST"] == "1" else { throw XCTSkip("Requires an interactive macOS desktop") }
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(root: directory), file = directory.appendingPathComponent("minutes-quota-v1.json")
        try JSONEncoder().encode(sample()).write(to: file)
        store.minutesAccounts = MinutesAccountStore(root: directory, networkEnabled: false)
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
            VStack(spacing: 18) { UsageBudgetView(store: store); MinutesQuotaView(accounts: store.minutesAccounts) }.padding(24)
        }.frame(width: 920, height: 1300).background(LeafTheme.mist).preferredColorScheme(.dark))
        cards.frame = NSRect(x: 0, y: 0, width: 920, height: 1300); cards.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        try save(cards, name: "6x30-weekly-and-provider-quota")
        let states: [(String, MinutesQuotaStore.Authentication, Bool)] = [
            ("Signed out", .required, false), ("Checking session", .unverified, true),
            ("Signed in", .authenticated, false), ("Refreshing", .authenticated, true)]
        let board = NSHostingView(rootView: VStack(spacing: 18) {
            ForEach(states.indices, id: \.self) { index in
                HStack {
                    Text(states[index].0).font(.system(size: 14)).foregroundStyle(LeafTheme.muted)
                    Spacer()
                    MinutesQuotaActions(authentication: states[index].1, checking: states[index].2, profile: store.minutesAccounts.profile, profiles: store.minutesAccounts.profiles, refresh: {}, login: {}, select: { _ in }, add: {}, rename: {}, automatic: {})
                }
            }
            Divider()
            HStack { CardHeaderButton(title: "同步设置") {}; CardHeaderButton(title: "核对中…", busy: true) {}.disabled(true) }
        }.padding(24).frame(width: 540).background(LeafTheme.mist).preferredColorScheme(.dark))
        board.frame = NSRect(x: 0, y: 0, width: 540, height: 320); board.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        try save(board, name: "6x30-header-control-states")

        var frames: [String: CGRect] = [:]
        let measured = NSHostingView(rootView: HStack(spacing: 10) {
            measure("action") { CardHeaderButton(title: "立即查询", tint: LeafTheme.serviceBlue) {} }
            measure("status") { CardHeaderMenu(title: "默认账号 · 已登录", symbol: "checkmark.circle.fill", tint: LeafTheme.serviceBlue) { Button("默认账号") {} } }
            measure("busyAction") { CardHeaderButton(title: "查询中…", busy: true, tint: LeafTheme.serviceBlue) {}.disabled(true) }
            measure("busyStatus") { CardHeaderMenu(title: "默认账号 · 验证中…", busy: true, tint: LeafTheme.serviceBlue) { Button("默认账号") {} } }
        }.coordinateSpace(name: "controls").onPreferenceChange(HeaderFrames.self) { frames = $0 }
            .padding(20).frame(width: 720, height: 90))
        measured.frame = NSRect(x: 0, y: 0, width: 720, height: 90); measured.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(frames.count, 4)
        for (name, rect) in frames {
            XCTAssertEqual(rect.width, name == "status" || name == "busyStatus" ? 190 : 120, accuracy: 0.5)
            XCTAssertEqual(rect.height, 34, accuracy: 0.5)
            XCTAssertEqual(rect.midY, frames["action"]?.midY ?? -.infinity, accuracy: 0.5)
        }
    }
    @MainActor private func save(_ view: NSView, name: String) throws {
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/verification/\(name).png")
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: file)
    }
    private func measure<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        content().background(GeometryReader { geometry in
            Color.clear.preference(key: HeaderFrames.self, value: [name: geometry.frame(in: .named("controls"))])
        })
    }
}

private struct HeaderFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { _, new in new } }
}
