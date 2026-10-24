import Foundation

// Retry transient accessibility reads only before recording, in the original app/window.
@MainActor final class TargetCapture {
    enum Result {
        case captured(any DictationTarget)
        case unavailable(String, retry: Bool)
    }
    let bundleID: String?
    private let sameContext: () -> Bool
    private let probe: () -> Result
    private var result: Result
    private(set) var attempts = 1
    var errorCode: String? {
        if case let .unavailable(code, _) = result { return code }
        return nil
    }
    init(bundleID: String?, sameContext: @escaping () -> Bool, probe: @escaping () -> Result) {
        self.bundleID = bundleID; self.sameContext = sameContext; self.probe = probe
        result = probe()
    }
    func resolve(delays: [Duration] = [.milliseconds(60), .milliseconds(120), .milliseconds(180)]) async throws -> (any DictationTarget)? {
        for delay in delays {
            guard case .unavailable(_, retry: true) = result else { break }
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            guard sameContext() else {
                result = .unavailable("capture_context_changed", retry: false); break
            }
            attempts += 1; result = probe()
        }
        try Task.checkCancellation()
        if case let .captured(target) = result { return target }
        return nil
    }
}
