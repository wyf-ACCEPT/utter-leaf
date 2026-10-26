import Foundation

public enum KeyboardDelivery {
    public static func hasFreshResult(request: String, consumed: String?, text: String, updated: TimeInterval, now: TimeInterval) -> Bool {
        UUID(uuidString: request) != nil && request != consumed && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && updated.isFinite && now.isFinite && now >= updated && now - updated < 900
    }
    public static func matchesTarget(request: String, expectedRequest: String?, document: String, expectedDocument: String?,
                                     before: String, expectedBefore: String?, after: String, expectedAfter: String?) -> Bool {
        request == expectedRequest && document == expectedDocument
            && before == expectedBefore && after == expectedAfter
    }
}
