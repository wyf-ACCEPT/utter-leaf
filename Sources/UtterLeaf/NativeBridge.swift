import AppKit
import AVFoundation
import Carbon
import UtterLeafCore

@MainActor final class Microphone {
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?
    var onChunk: ((Data, Float) -> Void)?
    var onDisconnect: (() -> Void)?
    func ensurePermission() async throws {
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        var granted = permission == .authorized
        if permission == .notDetermined { granted = await requestPermission() }
        guard granted else { throw AppFailure("麦克风未授权。请在系统设置 → 隐私与安全性 → 麦克风中允许 UtterLeaf。", code: "microphone_denied") }
    }
    func start() throws {
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw AppFailure("没有可用的麦克风输入设备。", code: "microphone_unavailable")
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / source.sampleRate) + 32)
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var consumed = false; var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if consumed { state.pointee = .noDataNow; return nil }
                consumed = true; state.pointee = .haveData; return buffer
            }
            guard status != .error, let samples = output.int16ChannelData?[0], output.frameLength > 0 else { return }
            let count = Int(output.frameLength)
            var sum: Double = 0
            for i in 0..<count { let sample = Double(samples[i]) / 32768; sum += sample * sample }
            let rms = Float(sqrt(sum / Double(count)))
            let data = Data(bytes: samples, count: count * 2)
            DispatchQueue.main.async { self?.onChunk?(data, rms) }
        }
        tapInstalled = true
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onDisconnect?() }
        }
        do { engine.prepare(); try engine.start() } catch { stop(); throw AppFailure("无法启动麦克风，请检查输入设备。", code: "audio_engine_start") }
    }
    private func requestPermission() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }
    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
    }
}

enum InsertionMethod: String { case accessibility, clipboardPaste, pasteDispatched }
@MainActor protocol DictationTarget: AnyObject {
    var displayName: String { get }
    var diagnosticID: String? { get }
    func insert(_ text: String, allowActivation: Bool) async throws -> InsertionMethod
}

extension DictationTarget { var diagnosticID: String? { nil } }

@MainActor final class InputTarget: DictationTarget {
    let app: NSRunningApplication
    let element: AXUIElement
    let selection: CFTypeRef?
    let selectionSupported: Bool
    var displayName: String { app.localizedName ?? "原应用" }
    var diagnosticID: String? { app.bundleIdentifier }
    init(app: NSRunningApplication, element: AXUIElement, selection: CFTypeRef) {
        self.app = app; self.element = element; self.selection = selection; selectionSupported = true
    }
    static func prepareCapture() -> TargetCapture {
        let app = NSWorkspace.shared.frontmostApplication
        let application = app.map { AXUIElementCreateApplication($0.processIdentifier) }
        func attribute(_ name: String) -> AXUIElement? {
            guard let application else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, name as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
        let window = attribute(kAXFocusedWindowAttribute)
        return TargetCapture(bundleID: app?.bundleIdentifier, sameContext: {
            guard let app, !app.isTerminated, let window,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  let current = attribute(kAXFocusedWindowAttribute) else { return false }
            return CFEqual(window, current)
        }, probe: {
            guard AXIsProcessTrusted() else { return .unavailable("capture_permission", retry: false) }
            guard let app, let application else { return .unavailable("capture_no_app", retry: false) }
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return .unavailable("capture_utterleaf_foreground", retry: false)
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                return .unavailable("capture_context_changed", retry: false)
            }
            var focused: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused)
            guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                return .unavailable("capture_focus_ax_\(result.rawValue)", retry: true)
            }
            let element = unsafeBitCast(focused, to: AXUIElement.self)
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            guard subrole as? String != kAXSecureTextFieldSubrole else { return .unavailable("capture_secure", retry: false) }
            var selection: CFTypeRef?
            let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection)
            guard rangeResult == .success, let selection, CFGetTypeID(selection) == AXValueGetTypeID() else {
                return .unavailable("capture_selection_ax_\(rangeResult.rawValue)", retry: true)
            }
            return .captured(InputTarget(app: app, element: element, selection: selection))
        })
    }
    private func validate() throws {
        guard AXIsProcessTrusted(), !app.isTerminated else { throw AppFailure("原应用不可用或辅助功能未授权。文字已保留，可复制后手动粘贴。", code: "target_unavailable") }
        guard selectionSupported else { throw AppFailure("无法验证原输入框的光标位置。文字已保留，可复制后手动粘贴。", code: "target_selection_unsupported") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw AppFailure("当前应用已变化，已停止自动输入。文字已保留。", code: "target_focus_changed")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var current: CFTypeRef?; var range: CFTypeRef?; var subrole: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &current)
        guard focusedResult == .success, let current else {
            throw AppFailure("暂时无法读取原输入框。文字已保留，可复制后粘贴。", code: "target_focus_ax_\(focusedResult.rawValue)")
        }
        guard CFEqual(current, element) else {
            throw AppFailure("原输入框已变化，已停止自动输入。文字已保留。", code: "target_element_changed")
        }
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range)
        guard rangeResult == .success, let range else {
            throw AppFailure("暂时无法读取原光标位置。文字已保留，可复制后粘贴。", code: "target_selection_ax_\(rangeResult.rawValue)")
        }
        guard let selection, CFEqual(range, selection) else {
            throw AppFailure("原光标位置已变化，已停止自动输入。文字已保留。", code: "target_cursor_changed")
        }
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != kAXSecureTextFieldSubrole else { throw AppFailure("无法输入到密码框。", code: "target_secure") }
    }
    private func readText() -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    private func readRange() -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private func confirms(_ text: String, before: String?, range: NSRange?) -> Bool {
        var substring: String?
        if let range {
            var inserted = CFRange(location: range.location, length: text.utf16.count)
            if let parameter = AXValueCreate(.cfRange, &inserted) {
                var value: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success { substring = value as? String }
            }
        }
        return InsertionVerification.confirms(before: before, originalRange: range, inserted: text,
            after: readText(), currentRange: readRange(), insertedSubstring: substring)
    }
    func insert(_ text: String, allowActivation: Bool) async throws -> InsertionMethod {
        try Task.checkCancellation()
        if allowActivation && NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            app.activate(); try await Task.sleep(for: .milliseconds(180))
        }
        try validate()
        let before = readText(), range = readRange()
        // Web/Electron composers require real paste/input events; an AX success can be a no-op.
        if !InsertionVerification.prefersKeyboardPaste(bundleID: app.bundleIdentifier) {
            var writable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success && writable.boolValue {
                let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
                if result == .success {
                    try await Task.sleep(for: .milliseconds(100))
                    if confirms(text, before: before, range: range) { return .accessibility }
                    // Fall back only when both the original content and selection are unchanged.
                    guard let before, readText() == before, readRange() == range else {
                        throw AppFailure("原应用没有确认输入结果。请先检查输入框，避免重复输入；正文已保留。", code: "target_write_uncertain")
                    }
                } else if result != .attributeUnsupported && result != .notImplemented {
                    throw AppFailure("原应用没有确认输入结果。请先检查输入框，避免重复输入；正文已保留。", code: "target_write_uncertain")
                }
            }
        }
        try validate()
        return try await paste(text, before: before, range: range)
    }
    private func paste(_ text: String, before: String?, range: NSRange?) async throws -> InsertionMethod {
        guard CGPreflightPostEventAccess(),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            throw AppFailure("无法向原应用粘贴，请检查辅助功能权限；文字已保留。", code: "paste_permission")
        }
        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        try validate()
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            pasteboard.clearContents(); if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
            throw AppFailure("无法写入剪贴板，文字已保留。", code: "pasteboard_write")
        }
        let ownedCount = pasteboard.changeCount
        defer {
            // Preserve a user's newer clipboard copy while this paste is in flight.
            if pasteboard.changeCount == ownedCount && pasteboard.string(forType: .string) == text {
                pasteboard.clearContents(); if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
            }
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        // Use the normal session keyboard route so Cocoa menus and web paste handlers run.
        // The foreground app/field/range were verified immediately before this synchronous pair.
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        for milliseconds in [40, 80, 140, 240, 400] {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            if confirms(text, before: before, range: range) { return .clipboardPaste }
        }
        if let before, readText() == before, readRange() == range {
            throw AppFailure("粘贴后原输入框没有变化，正文已保留。可复制后粘贴，或重试输入。", code: "paste_not_applied")
        }

        return .pasteDispatched
    }
}

@MainActor final class GlobalHotKey {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var gesture = FnKeyGesture()
    private var available = false
    private var escapeConsumed = false
    var action: (() -> Void)?
    var canCancel: (() -> Bool)?
    var cancel: (() -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?

    func register() -> Bool {
        if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
                workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.gesture.reset() }
                })
            }
        }
        refresh()
        return available
    }

    private func refresh() {
        guard AXIsProcessTrusted() else {
            removeTap(); updateAvailability(false); return
        }
        if eventTap == nil { installTap() }
        if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
            gesture.reset(); CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        updateAvailability(eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false)
    }

    private func installTap() {
        // A session event tap covers both this app and external input fields.
        // Only standalone Fn modifier events are consumed; other keys pass through.
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                // The source is installed exclusively on the main run loop.
                return MainActor.assumeIsolated { owner.receive(type: type, event: event) }
            }, userInfo: context) else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); return
        }
        eventTap = tap; runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            gesture.reset()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        let hasOtherModifiers = !event.flags.intersection(otherModifiers).isEmpty
        if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) {
            if type == .keyDown && !hasOtherModifiers && (escapeConsumed || canCancel?() == true) {
                if !escapeConsumed {
                    escapeConsumed = true; gesture.otherKey()
                    Task { @MainActor [weak self] in self?.cancel?() }
                }
                return nil
            }
            if type == .keyUp && escapeConsumed { escapeConsumed = false; return nil }
        }
        if type == .flagsChanged && event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Function) {
            let down = event.flags.contains(.maskSecondaryFn)
            let consumed = down || gesture.isPressed
            if gesture.fnChanged(isDown: down, hasOtherModifiers: hasOtherModifiers) {
                // Return promptly to the OS; audio setup and AX reads run after the callback.
                Task { @MainActor [weak self] in self?.action?() }
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        if type == .keyDown || type == .keyUp { gesture.otherKey() }
        else if type == .flagsChanged { gesture.otherModifiersChanged(hasOtherModifiers: hasOtherModifiers) }
        return Unmanaged.passUnretained(event)
    }

    private func updateAvailability(_ value: Bool) {
        guard value != available else { return }
        available = value; onAvailabilityChange?(value)
    }
    private func removeTap() {
        gesture.reset(); escapeConsumed = false
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil; eventTap = nil
    }
    func unregister() {
        permissionTimer?.invalidate(); permissionTimer = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll(); removeTap(); updateAvailability(false)
    }
}
