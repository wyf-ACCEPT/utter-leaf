import Foundation

public enum InsertionVerification {
    public static func prefersKeyboardPaste(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return id.hasPrefix("com.openai.") || id.contains("chrome") || id.contains("chromium")
            || id.hasPrefix("com.microsoft.edgemac") || id == "com.apple.safari"
            || id.hasPrefix("org.mozilla.firefox") || id.contains("thebrowser")
            || id == "com.tinyspeck.slackmacgap" || id == "com.microsoft.vscode"
    }
    public static func expectedText(before: String?, range: NSRange?, inserted: String) -> String? {
        guard let before, let range, range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= (before as NSString).length, range.length <= (before as NSString).length - range.location else { return nil }
        return (before as NSString).replacingCharacters(in: range, with: inserted)
    }
    public static func confirms(before: String?, originalRange: NSRange?, inserted: String,
                                after: String?, currentRange: NSRange?, insertedSubstring: String?) -> Bool {
        guard !inserted.isEmpty else { return false }
        if let originalRange, let currentRange {
            guard currentRange.location == originalRange.location + inserted.utf16.count,
                  currentRange.length == 0 else { return false }
        }
        if let expected = expectedText(before: before, range: originalRange, inserted: inserted), after == expected {
            return before != after || currentRange?.length == 0
        }
        return insertedSubstring == inserted && originalRange != nil && currentRange != nil
    }
}
