import Foundation

public enum TerminalReturnPolicy {
    public static func acceptsText(_ text: String) -> Bool {
        !text.isEmpty && text.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil
    }
    public static func allows(inputChanged: Bool, sameWindow: Bool, sameElement: Bool, foregroundMatches: Bool) -> Bool {
        !inputChanged && sameWindow && sameElement && foregroundMatches
    }
}
