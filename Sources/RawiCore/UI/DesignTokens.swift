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
    /// The height the rows actually need. Used as a ceiling, never as a demand.
    @State private var contentHeight: CGFloat = .greatestFiniteMagnitude

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
                // A ceiling, not a demand. `maxHeight` can only shrink the list
                // below the space it was offered, so a one-row list is a one-row
                // card and a long one still fills the window and scrolls inside.
                //
                // `fixedSize` here instead made the list insist on its content
                // height, which pushed the screen's own header off the top of the
                // window as soon as there were more rows than fitted.
                ScrollView { rows }
                    .frame(maxHeight: contentHeight)
            } else {
                rows
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 5) { content }
            .padding(.vertical, 8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: RowsHeightKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(RowsHeightKey.self) { height in
                // A LazyVStack only measures what it has built, so the ceiling
                // starts unbounded and comes down only when the rows genuinely
                // fit. It must never report *less* than what is on screen.
                if height > 0 { contentHeight = max(contentHeight == .greatestFiniteMagnitude
                                                    ? 0 : contentHeight, height) }
            }
    }
}

private struct RowsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One row inside a `RowGroup`. Lights on hover, which is the only separation a
/// list of this size needs.
public struct Row<Content: View>: View {
    let appearance: ResolvedAppearance
    var selected: Bool = false
    @ViewBuilder var content: Content
    @State private var hovered = false

    public init(appearance: ResolvedAppearance, selected: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.appearance = appearance
        self.selected = selected
        self.content = content()
    }

    private var fill: Color {
        if selected { return RawiColors.color(.saffron, appearance).opacity(0.16) }
        if hovered { return RawiColors.color(.surface, appearance).opacity(0.55) }
        return .clear
    }

    public var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.control).fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(selected
                            ? RawiColors.color(.saffron, appearance).opacity(0.55)
                            : .clear))
            )
            .padding(.horizontal, 8)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .animation(.easeOut(duration: 0.12), value: selected)
    }
}

/// The type scale, in one place because it is a scale.
///
/// Rawi had fifteen sizes between 8 and 34 point, most of them within half a
/// point of a neighbour. Nobody can see the difference between 10.5 and 11, but
/// everybody can see a page that was measured against itself rather than picked
/// a line at a time.
///
/// Seven steps, each with a job:
///
///   - `hero` the one number a screen is about. At most one per screen.
///   - `figure` the tile numbers beside it.
///   - `title` a screen's name.
///   - `heading` a row's subject, a section's name, the wordmark.
///   - `body` everything you read.
///   - `small` what supports it: evidence, timestamps, detail.
///   - `micro` labels and shortcuts, usually uppercase or monospaced.
///
/// Weights stop at three. Anything louder than semibold on a 13 point screen is
/// shouting.
/// The steps are pitched off the platform, not off a web page: 13 is the system
/// body size on macOS, and anything a window asks you to read sits there. A
/// screen full of 11 and 12 point text reads as cramped however well it is
/// spaced, which is exactly what happened here.
public enum TypeScale {
    public static let hero: CGFloat = 32
    public static let figure: CGFloat = 26
    public static let title: CGFloat = 22
    public static let heading: CGFloat = 15
    public static let body: CGFloat = 13
    public static let small: CGFloat = 11.5
    public static let micro: CGFloat = 10
}
