import SwiftUI

/// Shared visual chrome; native fields retain selection, IME, accessibility and keyboard behavior.
private struct LeafInputChrome: ViewModifier {
    var focus: FocusState<Bool>.Binding?
    @FocusState private var localFocus: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var focused: Bool { focus?.wrappedValue ?? localFocus }
    private var binding: FocusState<Bool>.Binding { focus ?? $localFocus }
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).scrollContentBackground(.hidden)
            .focused(binding).focusEffectDisabled()
            .foregroundStyle(LeafTheme.ink)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 44, alignment: .leading)
            .background(LeafTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(focused && enabled ? LeafTheme.leaf.opacity(0.85) : LeafTheme.line.opacity(hovered && enabled ? 1 : 0.7), lineWidth: focused && enabled ? 1.5 : 1)
                .allowsHitTesting(false))
            .shadow(color: LeafTheme.leaf.opacity(focused && enabled ? 0.09 : 0), radius: 4)
            .opacity(enabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .simultaneousGesture(TapGesture().onEnded { if enabled { binding.wrappedValue = true } })
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: focused)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}
extension View {
    func leafInput(focus: FocusState<Bool>.Binding? = nil) -> some View { modifier(LeafInputChrome(focus: focus)) }
}
