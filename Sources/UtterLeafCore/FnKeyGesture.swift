/// Recognizes a standalone Fn press/release without firing for Fn shortcuts.
/// Keyboard text never enters this state machine.
public struct FnKeyGesture {
    public private(set) var isPressed = false
    private var usedInChord = false

    public init() {}

    /// Returns true once on release of a standalone Fn press.
    public mutating func fnChanged(isDown: Bool, hasOtherModifiers: Bool) -> Bool {
        if isDown {
            if !isPressed { isPressed = true; usedInChord = hasOtherModifiers }
            else if hasOtherModifiers { usedInChord = true }
            return false
        }
        let shouldToggle = isPressed && !usedInChord && !hasOtherModifiers
        reset()
        return shouldToggle
    }

    public mutating func otherKey() {
        if isPressed { usedInChord = true }
    }

    public mutating func otherModifiersChanged(hasOtherModifiers: Bool) {
        if isPressed && hasOtherModifiers { usedInChord = true }
    }

    public mutating func reset() { isPressed = false; usedInChord = false }
}
