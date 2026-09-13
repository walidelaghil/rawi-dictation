import AppKit
import SwiftUI

/// Semantic roles, never colour names. A view asks for `.muted` text on a
/// `.surface` ground; it never learns what either one looks like.
///
/// This indirection is the only thing that keeps two themes in step. A view that
/// hardcodes a colour works in the theme it was written for and is broken in the
/// other one, silently, until someone looks.
public enum ColorToken: String, Sendable, CaseIterable {
    // grounds and borders
    case ink, surface, raised, edge
    // text, three weights
    case bone, muted, faint
    // state
    case saffron      // live — recording
    case verdigris    // finished — inserted, accepted
    case lapis        // detected language, secondary state
    case clay         // guard rejection, error
}

public enum RawiColors {
    /// One table, both themes. Adding a token here forces a value for each — which
    /// is deliberate: a token defined in one theme only is the classic two-theme bug.
    ///
    /// Every text token clears 4.5:1 on every ground it is used on, in both
    /// themes, and `ContrastFloorTests` fails if that stops being true. A token is
    /// a contrast commitment: do not dim one with `.opacity()`, because that
    /// breaks the commitment silently and no test can see it in a screenshot.
    private static let table: [ColorToken: (dark: String, light: String)] = [
        .ink:       ("#12161C", "#F4F6F8"),
        .surface:   ("#1A1F27", "#FFFFFF"),
        .raised:    ("#232933", "#EDF0F4"),
        .edge:      ("#333B47", "#D5DBE3"),
        .bone:      ("#E7EBF0", "#171B21"),
        .muted:     ("#A3AEBD", "#4E5764"),
        // Lifted until every text token clears WCAG AA on every ground it is used
        // on. faint was 3.80:1 on `raised`, and it carries the raw transcript,
        // every tile's qualifier and every settings description.
        .faint:     ("#86909C", "#656E7B"),
        // Accents share chroma and lightness and vary only in hue, so none shouts
        // over the others. The light values are darkened to hold contrast on white.
        .saffron:   ("#E0A039", "#976101"),
        .verdigris: ("#4FB3A6", "#116B60"),
        .lapis:     ("#9084F0", "#4A3DAF"),
        .clay:      ("#E2726C", "#A93A34"),
    ]

    public static func hex(_ token: ColorToken, _ appearance: ResolvedAppearance) -> String {
        guard let pair = table[token] else { return "#FF00FF" }   // unmissable, never silent
        return appearance == .dark ? pair.dark : pair.light
    }

    public static func color(_ token: ColorToken, _ appearance: ResolvedAppearance) -> Color {
        Color(nsColor: nsColor(token, appearance))
    }

    public static func nsColor(_ token: ColorToken, _ appearance: ResolvedAppearance) -> NSColor {
        NSColor(hex: hex(token, appearance))
    }

    /// The pill is always dark, whatever the appearance.
    ///
    /// It floats over arbitrary application content — a light pill on a light
    /// document disappears, and the recording state is the one thing that must
    /// never be ambiguous. A deliberate exception, not an oversight.
    public static func pill(_ token: ColorToken) -> Color {
        color(token, .dark)
    }

    public static func pillHex(_ token: ColorToken) -> String {
        hex(token, .dark)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
