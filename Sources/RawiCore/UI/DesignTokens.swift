import SwiftUI

/// The corner-radius system, in one place because it is a system.
///
/// Rawi had seven radii — 2, 3, 5, 7, 8, 10, 11 — each picked in the moment. The
/// eye reads that as carelessness even when every screen is individually fine.
/// Three values, one rule:
///
///   - `surface` for anything that holds content: cards, lists, overlays, panels
///   - `control` for anything you act on: buttons, fields, pickers, chips
///   - `Capsule` for badges and meters, where the shape is the label
public enum Radius {
    public static let surface: CGFloat = 12
    public static let control: CGFloat = 9
    /// Data marks: level bars, streak squares, the idle dot. Small enough that the
    /// radius reads as a soft edge rather than a shape.
    public static let mark: CGFloat = 3
}

/// A group of rows in one surface.
///
/// Rows are separated by space, not by a hairline under each one. A rule under
/// every row is the densest possible way to say "these are separate", and it
/// makes a list of six names look like a spec sheet for a machine tool.
public struct RowGroup<Content: View>: View {
    let appearance: ResolvedAppearance
    var scrolls: Bool = true
    @ViewBuilder var content: Content

    public init(appearance: ResolvedAppearance, scrolls: Bool = true,
                @ViewBuilder content: () -> Content) {
        self.appearance = appearance
        self.scrolls = scrolls
        self.content = content()
    }

    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    public var body: some View {
        Group {
            if scrolls {
                ScrollView { rows }
            } else {
                rows
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 2) { content }
            .padding(.vertical, 6)
    }
}

/// One row inside a `RowGroup`. Lights on hover, which is the only separation a
/// list of this size needs.
public struct Row<Content: View>: View {
    let appearance: ResolvedAppearance
    @ViewBuilder var content: Content
    @State private var hovered = false

    public init(appearance: ResolvedAppearance, @ViewBuilder content: () -> Content) {
        self.appearance = appearance
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.control)
                .fill(hovered ? RawiColors.color(.surface, appearance).opacity(0.55) : .clear))
            .padding(.horizontal, 6)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
