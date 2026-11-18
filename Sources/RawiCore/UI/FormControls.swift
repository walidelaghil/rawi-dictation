import SwiftUI

/// The one input every add and edit form uses. Grows with what you type (up to
/// `lines.upperBound`, then scrolls), so a pasted paragraph is always readable.
struct GrowingField: View {
    let placeholder: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 1...8
    var weight: Font.Weight = .regular
    var size: CGFloat = TypeScale.body
    let appearance: ResolvedAppearance
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(lines)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(c(.bone))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The filled call-to-action. Greyed out until the form can be submitted.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let appearance: ResolvedAppearance
    let action: () -> Void
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: TypeScale.body, weight: .semibold))
                .foregroundStyle(enabled ? c(.ink) : c(.faint))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Radius.control)
                    .fill(enabled ? c(.saffron) : c(.raised)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A card that holds a form.
struct FormCard<Content: View>: View {
    let appearance: ResolvedAppearance
    @ViewBuilder var content: Content
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.ink))
                .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }
}

/// The × on a row: 24pt to hit, shown only while the row is hovered or focused.
struct RemoveButton: View {
    let visible: Bool
    let label: String
    let appearance: ResolvedAppearance
    let action: () -> Void
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: TypeScale.small, weight: .medium))
                .foregroundStyle(c(.muted))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// "Removed. Undo" — shown for a few seconds after a delete.
struct UndoToast: View {
    let message: String
    let appearance: ResolvedAppearance
    let undo: () -> Void
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    var body: some View {
        HStack(spacing: 12) {
            Text(message).font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
            Button("Undo", action: undo)
                .buttonStyle(.plain)
                .font(.system(size: TypeScale.body, weight: .semibold))
                .foregroundStyle(c(.saffron))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// One "Removed. Undo" for the whole window. Screens call `offer`; the window
/// shows the bar. A new offer replaces the old one, so Undo always means the last delete.
@MainActor
public final class UndoCenter: ObservableObject {
    @Published public var message: String?
    private var action: (() -> Void)?
    private var task: Task<Void, Never>?

    public init() {}

    public func offer(_ message: String, _ action: @escaping () -> Void) {
        self.message = message
        self.action = action
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self.message = nil; self.action = nil }
        }
    }

    public func undo() {
        action?()
        message = nil; action = nil; task?.cancel()
    }
}

struct UndoBar: View {
    @ObservedObject var center: UndoCenter
    let appearance: ResolvedAppearance
    let onUndone: () -> Void

    var body: some View {
        Group {
            if let message = center.message {
                UndoToast(message: message, appearance: appearance) {
                    center.undo(); onUndone()
                }
                .padding(.bottom, 18)
            }
        }
        .animation(.easeOut(duration: 0.15), value: center.message)
    }
}
