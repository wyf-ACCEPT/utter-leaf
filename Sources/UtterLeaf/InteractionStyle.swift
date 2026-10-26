import SwiftUI
import AppKit

struct HandCursor: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @State private var inside = false
    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active:
                if enabled { inside = true; NSCursor.pointingHand.set() }
            case .ended:
                if inside { inside = false; NSCursor.arrow.set() }
            }
        }.onChange(of: enabled) { _, value in
            if !value && inside { inside = false; NSCursor.arrow.set() }
        }.onDisappear { if inside { NSCursor.arrow.set() } }
    }
}
extension View {
    func handCursor() -> some View { modifier(HandCursor()) }
}
struct SidebarItem: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                Text(title).font(.system(size: LeafType.scaled(14), weight: selected ? .semibold : .regular))
            }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 46)
                .foregroundStyle(selected || hovered ? LeafTheme.leaf : LeafTheme.muted)
                .background(LeafTheme.leaf.opacity(selected ? 0.14 : hovered ? 0.075 : 0), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(LeafTheme.line.opacity(hovered && !selected ? 0.65 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).handCursor().onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct PrimaryButtonFace: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        configuration.label.font(.system(size: LeafType.scaled(14), weight: .semibold)).padding(.horizontal, 24).frame(height: 46)
            .foregroundStyle(LeafTheme.actionInk)
            .background(LeafTheme.leaf.opacity(enabled ? (configuration.isPressed ? 0.72 : hovered ? 0.87 : 1) : 0.35), in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .handCursor().onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}

struct CallHistoryRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CallHistoryRowFace(configuration: configuration) }
}
private struct CallHistoryRowFace: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: 12).fill(LeafTheme.leaf.opacity(enabled && (hovered || configuration.isPressed) ? (configuration.isPressed ? 0.16 : 0.08) : 0)).allowsHitTesting(false))
            .opacity(enabled ? 1 : 0.5).handCursor().onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}
