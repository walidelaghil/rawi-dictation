import AppKit

/// The Rawi mark: one continuous stroke that reads as a waveform and as a kashida,
/// the elongation Arabic uses to stretch a letter. راوي is a narrator, and the mark
/// is the line of a voice.
///
/// Drawn in code rather than shipped as an asset for three reasons: it stays sharp
/// at any menu-bar height and any Dock size, it is the same geometry in the app and
/// in the design canvas, and a template image drawn this way inverts correctly on a
/// dark menu bar without a second file to keep in step.
public enum RawiMark {
    /// The path from the design canvas, in a 24×24 box: `M2 12h4l2-5 3 10 3-8 2 3h6`.
    /// Points are y-down as SVG writes them; `path(in:)` flips them for AppKit.
    private static let points: [CGPoint] = [
        CGPoint(x: 2, y: 12), CGPoint(x: 6, y: 12), CGPoint(x: 8, y: 7),
        CGPoint(x: 11, y: 17), CGPoint(x: 14, y: 9), CGPoint(x: 16, y: 12),
        CGPoint(x: 22, y: 12),
    ]

    /// Stroke width in the 24-unit space. The canvas draws 1.7 at 22px; this is the
    /// same optical weight at 18px, the menu-bar size.
    private static let strokeWidth: CGFloat = 2.0

    /// The mark as a path filling `rect`, preserving the 24×24 aspect.
    ///
    /// `strokeScale` thickens the line for small renders. A stroke that scales
    /// purely with the box disappears at 16pt — the icon becomes a smudge — so the
    /// small sizes get a heavier line, which is what hinting does for type.
    public static func path(in rect: CGRect, strokeScale: CGFloat = 1) -> NSBezierPath {
        let scale = min(rect.width, rect.height) / 24
        let offsetX = rect.minX + (rect.width - 24 * scale) / 2
        let offsetY = rect.minY + (rect.height - 24 * scale) / 2
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            // 24 - y: SVG counts down from the top, AppKit up from the bottom.
            let mapped = CGPoint(x: offsetX + point.x * scale,
                                 y: offsetY + (24 - point.y) * scale)
            if index == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
        }
        path.lineWidth = strokeWidth * scale * strokeScale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    /// The mark as an image.
    ///
    /// `tint` nil means a template image: the menu bar paints it, so it follows the
    /// user's menu-bar appearance and their accent-colour highlight. A tint is for
    /// the states where colour *is* the message — recording, or a missing
    /// permission — and those deliberately stop being templates.
    public static func image(size: CGFloat = 18, tint: NSColor? = nil,
                             alpha: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size),
                            flipped: false) { rect in
            (tint ?? .black).withAlphaComponent(alpha).setStroke()
            path(in: rect).stroke()
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = "Rawi"
        return image
    }

    /// The menu-bar icon for a state. One glyph throughout, so the identity never
    /// changes shape; colour and weight carry what is happening.
    ///
    /// Colour is not decoration here. An app that shows its logo unchanged while it
    /// cannot hear you is worse than one with no icon at all.
    public static func statusImage(state: DictationState, enabled: Bool,
                                   microphoneGranted: Bool, size: CGFloat = 18) -> NSImage {
        guard enabled else { return image(size: size, alpha: 0.35) }
        guard microphoneGranted else {
            return image(size: size, tint: RawiColors.nsColor(.clay, .dark))
        }
        switch state {
        case .recording:
            return image(size: size, tint: RawiColors.nsColor(.saffron, .dark))
        case .transcribing, .cleaning, .inserting, .transforming:
            return image(size: size, tint: RawiColors.nsColor(.lapis, .dark))
        case .error:
            return image(size: size, tint: RawiColors.nsColor(.clay, .dark))
        case .idle, .notice:
            return image(size: size)
        }
    }

    /// The app icon: the mark in saffron on the ink ground, in the rounded square
    /// macOS expects. Rendered at each size the iconset needs rather than scaled
    /// from one bitmap, so the stroke stays even at 16pt.
    public static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // macOS icons sit in about 80% of their canvas, with the corner radius a
            // little under a quarter of the body.
            let inset = size * 0.098
            let body = rect.insetBy(dx: inset, dy: inset)
            RawiColors.nsColor(.ink, .dark).setFill()
            NSBezierPath(roundedRect: body,
                         xRadius: body.width * 0.223,
                         yRadius: body.width * 0.223).fill()
            RawiColors.nsColor(.saffron, .dark).setStroke()
            // Small icons carry the mark larger and heavier: at 16pt the detail is
            // what goes first, and a legible smaller mark beats a faithful blur.
            let small = size < 64
            let markInset = body.width * (small ? 0.11 : 0.17)
            path(in: body.insetBy(dx: markInset, dy: markInset),
                 strokeScale: small ? 1.45 : 1).stroke()
            return true
        }
    }

    /// Writes the PNGs `iconutil` expects into `directory`. Used by `make icon`;
    /// keeping it here means the icon and the menu bar cannot drift apart.
    public static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = CGFloat(base * scale)
                let icon = appIcon(size: pixels)
                guard let tiff = icon.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}
