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
