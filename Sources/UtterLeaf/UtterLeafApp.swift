import SwiftUI
import AppKit
import UtterLeafCore

@main struct UtterLeafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(store: (ProcessInfo.processInfo.arguments.contains("--provider-smoke") || ProcessInfo.processInfo.arguments.contains("--minutes-file-probe"))
        ? LocalStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("utterleaf-smoke-" + UUID().uuidString)) : nil)
    let hotkey = GlobalHotKey()
    let pill = PillPresentation()
    let meetingCaptions = MeetingCaptionPanel()
    var window: NSWindow!
    var panel: NSPanel!
    var item: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--minutes-file-probe") {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                do {
                    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UtterLeaf")
                    let manifest = try JSONDecoder().decode(MinutesAccountsManifest.self, from: Data(contentsOf: root.appendingPathComponent("minutes-accounts-v1.json")))
                    guard let profile = manifest.profiles.first(where: { $0.id == manifest.selected }) else { exit(2) }
                    let session = MinutesFileSession(profile: profile); try await session.load()
                    let key = UUID()
                    let quota = try await session.run("quota", key: key)
                    print("Minutes quota probe: remaining=\(quota["remaining"] ?? "unknown")")
                    if ProcessInfo.processInfo.arguments.contains("--resume-synthetic") {
                        let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/verification/minutes-file-probe-checkpoint.json")
                        let checkpoint = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String]
                        guard let object = checkpoint?["objectToken"], let keyString = checkpoint?["key"], let key = UUID(uuidString: keyString) else { exit(3) }
                        for _ in 0..<72 {
                            let status = try await session.run("status", key: key, arguments: ["objectToken": object])
                            let complete = MinutesFileResult.isComplete(status)
                            print("Minutes original task complete: \(complete)"); fflush(stdout)
                            if complete {
                                let result = try await session.run("result", key: key, arguments: ["objectToken": object])
                                let rows = try MinutesFileResult.segments(result)
                                print("Minutes original result: segments=\(rows.count), speakers=\(Set(rows.map(\.speaker)).count)")
                                exit(0)
                            }
                            try await Task.sleep(for: .seconds(5))
                        }
                        print("Minutes original task remains pending"); exit(4)
                    }
                    if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--synthetic-wav"), ProcessInfo.processInfo.arguments.count > flag + 1 {
                        let audio = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[flag + 1]).standardizedFileURL
                        guard audio.path.contains("/.local/verification/minutes-rea/audio/"), (try audio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 1_000_000 else { exit(3) }
                        let token = try await session.upload(audio: audio, seconds: 20, key: key, prepared: { object in
                            let checkpoint = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/verification/minutes-file-probe-checkpoint.json")
                            try JSONSerialization.data(withJSONObject: ["key": key.uuidString, "objectToken": object]).write(to: checkpoint, options: .atomic)
                            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: checkpoint.path)
                            print("Minutes prepare: checkpoint saved")
                        }, progress: { print("Minutes upload: \($0)%") })
                        for _ in 0..<36 {
                            let status = try await session.run("status", key: key, arguments: ["objectToken": token])
                            print("Minutes task complete: \(MinutesFileResult.isComplete(status))")
                            if MinutesFileResult.isComplete(status) {
                                let result = try await session.run("result", key: key, arguments: ["objectToken": token])
                                let rows = try MinutesFileResult.segments(result)
                                print("Minutes result: segments=\(rows.count), speakerIDs=\(Set(rows.map(\.speaker)).count)"); exit(0)
                            }
                            try await Task.sleep(for: .seconds(5))
                        }
                        print("Minutes synthetic task remains pending"); exit(4)
                    }
                    exit(0)
                } catch {
                    print("Minutes probe failed: \((error as? AppFailure)?.code ?? "web_bridge")")
                    let ns = error as NSError
                    print("Bridge error category: \(ns.domain) / \(ns.code)")
                    exit(1)
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--usage-sync-check") || ProcessInfo.processInfo.arguments.contains("--history-sync-check") || ProcessInfo.processInfo.arguments.contains("--vocabulary-sync-check") {
            NSApp.setActivationPolicy(.prohibited)
            let path = model.store.root.appendingPathComponent("ledger.json")
            if let data = try? Data(contentsOf: path), let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let calls = original["calls"] as? [[String: Any]] ?? []
                let jobs = original["jobs"] as? [[String: Any]] ?? []
                if calls.contains(where: { $0["status"] as? String == "pending" }) || jobs.contains(where: { ["recording", "processing", "inserting", "paused"].contains($0["status"] as? String ?? "") }) {
                    print("Cloud sync check skipped: an active recording or request is present.")
                    NSApp.terminate(nil); return
                }
            }
            model.store.captureCloudUsage()
            model.store.usageCloud.onRemoteBudget = nil
            Task {
                if ProcessInfo.processInfo.arguments.contains("--vocabulary-sync-check") {
                    await model.store.vocabularyCloud.sync()
                    if let data = try? JSONSerialization.data(withJSONObject: model.store.vocabularyCloud.diagnostic, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
                    NSApp.terminate(nil); return
                }
                if ProcessInfo.processInfo.arguments.contains("--history-sync-check") {
                    model.store.captureCloudHistory()
                    model.store.historyCloud.onRemoteChange = nil
                    await model.store.historyCloud.sync()
                    if let data = try? JSONSerialization.data(withJSONObject: model.store.historyCloud.diagnostic, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
                    NSApp.terminate(nil); return
                }
                await model.store.usageCloud.sync()
                var report = model.store.usageCloud.snapshot
                report.removeValue(forKey: "calls")
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        LeafTheme.apply(model.store.database.preferences.appearance)
        let root = RootView(model: model, store: model.store)
        window = UtterLeafWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "UtterLeaf · 言叶"; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 900, height: 680)
        window.contentView = NSHostingView(rootView: root); window.center()
        window.setFrameAutosaveName("UtterLeafMain")
        model.showWindow = { [weak self] in self?.showMain() }
        model.onPhase = { [weak self] in self?.updatePanel() }
        if !ProcessInfo.processInfo.arguments.contains("--provider-smoke") {
            hotkey.action = { [weak self] in self?.model.toggle() }
            hotkey.canCancel = { [weak self] in
                guard let model = self?.model else { return false }
                return model.busy && !model.inserting
            }
            hotkey.cancel = { [weak self] in self?.model.abort(preserveRecording: true) }
            hotkey.onAvailabilityChange = { [weak self] in self?.model.hotkeyRegistered = $0 }
            model.hotkeyRegistered = hotkey.register()
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        meetingCaptions.attach(model: model.meetings, store: model.store)
        model.meetings.onCaptureState = { [weak self] recording, seconds, paused in
            guard let self else { return }
            item.button?.title = recording ? String(format: " %02d:%02d", Int(seconds) / 60, Int(seconds) % 60) : ""
            item.button?.toolTip = recording ? (paused ? "会议已暂停" : "会议录音中") : "UtterLeaf"
            item.button?.image = NSImage(systemSymbolName: recording ? "waveform" : "leaf", accessibilityDescription: recording ? "会议录音" : "UtterLeaf")
        }
        item.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "UtterLeaf")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 UtterLeaf", action: #selector(openMain), keyEquivalent: "")
        menu.addItem(withTitle: "打开会议", action: #selector(openMeetings), keyEquivalent: "")
        menu.addItem(withTitle: "开始 / 结束录音    Fn", action: #selector(toggleRecording), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 UtterLeaf", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }; item.menu = menu
        panel = RecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = false
        panel.animationBehavior = .none; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = RecordingPillHost(rootView: RecordingPill(model: model, store: model.store, presentation: pill))
        pill.orderFront = { [weak self] in
            guard let self else { return }
            if let screen = NSScreen.main {
                let rect = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: rect.midX - 210, y: rect.minY + 20))
            }
            panel.ignoresMouseEvents = false; panel.orderFrontRegardless()
        }
        pill.orderOut = { [weak self] in self?.panel.orderOut(nil) }
        if ProcessInfo.processInfo.arguments.contains("--provider-smoke") {
            Task { await SmokeRunner.run(model: model); NSApp.terminate(nil) }
        } else {
            model.store.billingSync.isDictating = { [weak self] in (self?.model.busy ?? false) || (self?.model.meetings.blocksDictation ?? false) }
            model.store.billingSync.start()
            model.store.captureCloudUsage()
            model.store.usageCloud.canSync = { [weak self] in !(self?.model.busy ?? true) && !(self?.model.meetings.blocksDictation ?? true) }
            model.store.usageCloud.start()
            model.store.captureCloudHistory()
            model.store.historyCloud.canSync = model.store.usageCloud.canSync
            model.store.historyCloud.start()
            model.store.vocabularyCloud.canSync = model.store.usageCloud.canSync
            model.store.minutesAccounts.canRefresh = model.store.usageCloud.canSync
            model.store.vocabularyCloud.start()
            showMain()
        }
    }
    func showMain() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func openMeetings() { model.route = "会议"; showMain() }
    @objc func openMain() { showMain() }
    @objc func toggleRecording() { model.toggle() }
    @objc func quit() { model.abort(); NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.hasUnsavedRecording { model.showWindow?(); return .terminateCancel }
        pill.closeImmediately(); meetingCaptions.close(); model.meetings.shutdown(); model.store.billingSync.stop(); model.store.usageCloud.stop(); model.store.historyCloud.stop(); model.store.vocabularyCloud.stop(); hotkey.unregister(); model.abort(); return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func updatePanel() {
        guard panel != nil else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        switch model.phase {
        case .starting: pill.show(.preparing, detail: "Esc 取消", reduceMotion: reduced)
        case .recording: pill.show(.recording, detail: "Fn 结束 · Esc 取消", reduceMotion: reduced)
        case .transcribing: pill.show(.processing, detail: "正在转写 · Esc 取消", reduceMotion: reduced)
        case .cleaning: pill.show(.processing, detail: "整理文字 · Esc 取消", reduceMotion: reduced)
        case .inserting: pill.show(.processing, detail: "输入到原应用", reduceMotion: reduced)
        case .preview where model.showsPillRecovery:
            panel.ignoresMouseEvents = false
            pill.show(.recovery, detail: "文字已保留", reduceMotion: reduced)
        case .preview where pill.stage == .recovery:
            panel.ignoresMouseEvents = true; pill.closeImmediately()
        default:
            panel.ignoresMouseEvents = true
            pill.finish(model.pillOutcome, reduceMotion: reduced)
        }
        item?.button?.image = NSImage(systemSymbolName: model.phase == .recording ? "waveform" : "leaf", accessibilityDescription: "UtterLeaf")
    }
}
