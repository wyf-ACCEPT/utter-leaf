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

/// Shared card-header geometry for actions and noninteractive status capsules.
private struct CardHeaderContent: View {
    let title: String
    var symbol: String?
    var busy = false
    var body: some View {
        HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.small).frame(width: 14, height: 14).accessibilityHidden(true) }
            else if let symbol { Image(systemName: symbol).font(.system(size: 13)).frame(width: 14, height: 14).accessibilityHidden(true) }
            Text(title)
        }
    }
}
private struct CardHeaderChrome: ViewModifier {
    let tint: Color
    var width: CGFloat = 120
    var enabled = true
    var hovered = false
    var pressed = false
    func body(content: Content) -> some View {
        content.font(.system(size: 14, weight: .medium)).lineLimit(1)
            .foregroundStyle(tint.opacity(enabled ? 1 : 0.5))
            .frame(width: width, height: 34)
            .background(tint.opacity(enabled ? (pressed ? 0.22 : hovered ? 0.16 : 0.10) : 0.05), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(enabled ? 0.18 : 0.08), lineWidth: 1))
            .contentShape(Capsule())
    }
}
private struct CardHeaderButtonStyle: ButtonStyle {
    let tint: Color
    var width: CGFloat = 120
    func makeBody(configuration: Configuration) -> some View { CardHeaderButtonFace(configuration: configuration, tint: tint, width: width) }
}
private struct CardHeaderButtonFace: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    var width: CGFloat = 120
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        configuration.label.modifier(CardHeaderChrome(tint: tint, width: width, enabled: enabled, hovered: hovered, pressed: configuration.isPressed))
            .onHover { hovered = $0 }.handCursor()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}
struct CardHeaderButton: View {
    let title: String
    var busy = false
    var tint: Color = LeafTheme.leaf
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) { CardHeaderContent(title: title, busy: busy) }
            .buttonStyle(CardHeaderButtonStyle(tint: tint)).focused($focused)
            .overlay(Capsule().stroke(focused ? tint : .clear, lineWidth: 2).padding(-3).allowsHitTesting(false))
            .accessibilityLabel(title)
    }
}
struct CardHeaderMenu<Content: View>: View {
    let title: String
    var symbol: String?
    var busy = false
    var tint: Color = LeafTheme.leaf
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: {
            HStack(spacing: 6) {
                CardHeaderContent(title: title, symbol: symbol, busy: busy).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).frame(width: 10).accessibilityHidden(true)
            }.padding(.horizontal, 12)
        }.menuStyle(.button).buttonStyle(CardHeaderButtonStyle(tint: tint, width: 190))
            .menuIndicator(.hidden).accessibilityElement(children: .combine).accessibilityLabel(title)
    }
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
