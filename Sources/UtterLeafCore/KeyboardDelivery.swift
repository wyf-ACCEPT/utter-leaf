import Foundation

public enum KeyboardDelivery {
    public static func canPerformReturn(phase: String, launching: Bool, fullAccess: Bool) -> Bool {
        fullAccess && !launching && !["starting", "recording", "processing", "ready"].contains(phase)
    }
    public static func hasFreshResult(request: String, consumed: String?, text: String, updated: TimeInterval, now: TimeInterval) -> Bool {
        UUID(uuidString: request) != nil && request != consumed && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && updated.isFinite && now.isFinite && now >= updated && now - updated < 900
    }
    public static func matchesTarget(request: String, expectedRequest: String?, document: String, expectedDocument: String?,
                                     before: String, expectedBefore: String?, after: String, expectedAfter: String?) -> Bool {
        mismatch(request: request, expectedRequest: expectedRequest, document: document, expectedDocument: expectedDocument,
            before: before, expectedBefore: expectedBefore, after: after, expectedAfter: expectedAfter) == nil
    }
    /// Diagnostic categories only; callers must never log the document or surrounding text.
    public static func mismatch(request: String, expectedRequest: String?, document: String, expectedDocument: String?,
                                before: String, expectedBefore: String?, after: String, expectedAfter: String?) -> String? {
        if request != expectedRequest { return "request_changed" }
        if document != expectedDocument { return "document_changed" }
        if before != expectedBefore || after != expectedAfter { return "context_changed" }
        return nil
    }
}
