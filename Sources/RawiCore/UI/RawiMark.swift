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
    static let svgPoints: [CGPoint] = [
        CGPoint(x: 2, y: 12), CGPoint(x: 6, y: 12), CGPoint(x: 8, y: 7),
        CGPoint(x: 11, y: 17), CGPoint(x: 14, y: 9), CGPoint(x: 16, y: 12),
        CGPoint(x: 22, y: 12),
    ]

    /// The mark with its two interior peaks driven by an audio level.
    ///
    /// The icon is a waveform, so while you are speaking it may as well be *your*
    /// waveform. This is the only always-visible surface Rawi has, and it answers
    /// the question you actually have while holding the key — is it hearing me —
    /// without opening anything.
    ///
    /// Only the two interior points move. The ends are pinned so the silhouette
    /// stays the same glyph rather than becoming an animation that happens to
    /// start from the logo.
    public static func svgPoints(level: Double, motion: MarkMotion = .rest) -> [CGPoint] {
        var points = svgPoints
        let amount = min(max(level, 0), 1)
        if amount > 0 {
            // Point 2 is the crest at y=7, point 3 the trough at y=17. A loud
            // frame pushes them apart; the travel is small on purpose, because a
            // menu bar icon that flails is noise.
            points[2].y = 7 - amount * 4
            points[3].y = 17 + amount * 4
        }

        guard motion != .rest else { return points }

        // The amplitude collapses toward the centre line, and the landing spring
        // swells it by 6% on the way back. Both act on the distance from centre,
        // so the ends — which are already on it — cannot move.
        let scale = 1 + motion.spring * 0.06
        for index in points.indices.dropFirst().dropLast() {
            points[index].y = midline + (points[index].y - midline) * (1 - motion.flatten) * scale
        }

        // One bump travels the flat line. Gaussian rather than a moving dot, so
        // the line bends around it instead of something sliding along it.
        if motion.flatten > 0.02 {
            let head = 2 + motion.bump * 20
            for index in points.indices.dropFirst().dropLast() {
                let distance = points[index].x - head
                points[index].y -= exp(-(distance * distance) / 7) * 3.2 * motion.flatten
            }
        }
        return points
    }

    /// The centre line the waveform collapses onto: both ends already sit on it.
    private static let midline: CGFloat = 12

    /// Stroke width in the 24-unit space. The canvas draws 1.7 at 22px; this is the
    /// same optical weight at 18px, the menu-bar size.
    static let strokeWidthUnits: CGFloat = 2.0

    /// The mark as a path filling `rect`, preserving the 24×24 aspect.
    ///
    /// `strokeScale` thickens the line for small renders. A stroke that scales
    /// purely with the box disappears at 16pt — the icon becomes a smudge — so the
    /// small sizes get a heavier line, which is what hinting does for type.
    public static func path(in rect: CGRect, strokeScale: CGFloat = 1,
                            level: Double = 0, motion: MarkMotion = .rest) -> NSBezierPath {
        let scale = min(rect.width, rect.height) / 24
        let offsetX = rect.minX + (rect.width - 24 * scale) / 2
        let offsetY = rect.minY + (rect.height - 24 * scale) / 2
        let path = NSBezierPath()
        for (index, point) in svgPoints(level: level, motion: motion).enumerated() {
            // 24 - y: SVG counts down from the top, AppKit up from the bottom.
            let mapped = CGPoint(x: offsetX + point.x * scale,
                                 y: offsetY + (24 - point.y) * scale)
            if index == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
        }
        path.lineWidth = strokeWidthUnits * scale * strokeScale
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
                             alpha: CGFloat = 1, level: Double = 0,
                             motion: MarkMotion = .rest) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size),
                            flipped: false) { rect in
            (tint ?? .black).withAlphaComponent(alpha).setStroke()
            path(in: rect, level: level, motion: motion).stroke()
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
                                   microphoneGranted: Bool, size: CGFloat = 18,
                                   level: Double = 0,
                                   motion: MarkMotion = .rest) -> NSImage {
        guard enabled else { return image(size: size, alpha: 0.35) }
        guard microphoneGranted else {
            return image(size: size, tint: RawiColors.nsColor(.clay, .dark))
        }
        switch state {
        case .recording:
            // The level only reaches the icon here. An idle mark twitching with
            // room noise would be a distraction rather than feedback.
            return image(size: size, tint: RawiColors.nsColor(.saffron, .dark), level: level)
        case .transcribing, .cleaning, .inserting, .transforming:
            return image(size: size, tint: RawiColors.nsColor(.lapis, .dark), motion: motion)
        case .error:
            return image(size: size, tint: RawiColors.nsColor(.clay, .dark))
        case .notice:
            return image(size: size, tint: RawiColors.nsColor(.verdigris, .dark),
                         motion: motion)
        case .idle:
            return image(size: size, motion: motion)
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

import SwiftUI

/// The same mark for SwiftUI. Stroke it rather than fill it:
/// `RawiMarkShape().stroke(color, style: RawiMarkShape.stroke(for: 22))`.
public struct RawiMarkShape: Shape {
    public var level: Double
    public var motion: MarkMotion

    public init(level: Double = 0, motion: MarkMotion = .rest) {
        self.level = level
        self.motion = motion
    }

    /// Lets SwiftUI interpolate the shape between frames rather than stepping it.
    public var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(level, AnimatablePair(motion.flatten, motion.bump)) }
        set {
            level = newValue.first
            motion.flatten = newValue.second.first
            motion.bump = newValue.second.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let offsetX = rect.minX + (rect.width - 24 * scale) / 2
        let offsetY = rect.minY + (rect.height - 24 * scale) / 2
        var path = Path()
        // SwiftUI counts y downward, exactly as the SVG does, so no flip here.
        for (index, point) in RawiMark.svgPoints(level: level, motion: motion).enumerated() {
            let mapped = CGPoint(x: offsetX + point.x * scale, y: offsetY + point.y * scale)
            if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        return path
    }

    public static func stroke(for size: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: RawiMark.strokeWidthUnits * size / 24,
                    lineCap: .round, lineJoin: .round)
    }
}
