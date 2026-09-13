import Testing
import SwiftUI
@testable import RawiCore

/// WCAG relative luminance, so the contrast assertions below mean something
/// rather than being a vibe check.
func luminance(_ hex: String) -> Double {
    let v = Array(hex.dropFirst())
    func channel(_ i: Int) -> Double {
        let s = Double(UInt8(String(v[(i * 2)...(i * 2 + 1)]), radix: 16) ?? 0) / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(0) + 0.7152 * channel(1) + 0.0722 * channel(2)
}

func contrastRatio(_ a: String, _ b: String) -> Double {
    let (l1, l2) = (luminance(a), luminance(b))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}

@Suite("RawiColors") struct RawiColorsTests {
    @Test("every token resolves in both appearances") func complete() {
        for token in ColorToken.allCases {
            for appearance in ResolvedAppearance.allCases {
                let hex = RawiColors.hex(token, appearance)
                #expect(hex.hasPrefix("#"), "\(token) missing in \(appearance)")
                #expect(hex.count == 7, "\(token)/\(appearance) is not #rrggbb: \(hex)")
            }
        }
    }

    @Test("light and dark genuinely differ for every ground and text token") func differ() {
        for token in [ColorToken.ink, .surface, .raised, .bone, .muted, .faint] {
            #expect(RawiColors.hex(token, .dark) != RawiColors.hex(token, .light),
                    "\(token) is identical in both themes")
        }
    }

    @Test("grounds and text are inverted between themes") func inverted() {
        #expect(luminance(RawiColors.hex(.ink, .dark)) < 0.3)
        #expect(luminance(RawiColors.hex(.ink, .light)) > 0.7)
        #expect(luminance(RawiColors.hex(.bone, .dark)) > 0.7)
        #expect(luminance(RawiColors.hex(.bone, .light)) < 0.3)
    }

    @Test("body text clears 4.5:1 against its ground in both themes") func contrast() {
        for appearance in ResolvedAppearance.allCases {
            let ratio = contrastRatio(RawiColors.hex(.bone, appearance),
                                      RawiColors.hex(.surface, appearance))
            #expect(ratio >= 4.5, "bone on surface is \(ratio):1 in \(appearance)")
        }
    }

    @Test("secondary text clears 4.5:1 too — it is body copy, not decoration") func secondary() {
        for appearance in ResolvedAppearance.allCases {
            let ratio = contrastRatio(RawiColors.hex(.muted, appearance),
                                      RawiColors.hex(.surface, appearance))
            #expect(ratio >= 4.5, "muted on surface is \(ratio):1 in \(appearance)")
        }
    }

    @Test("faint text clears the 3:1 floor") func faint() {
        for appearance in ResolvedAppearance.allCases {
            let ratio = contrastRatio(RawiColors.hex(.faint, appearance),
                                      RawiColors.hex(.surface, appearance))
            #expect(ratio >= 3.0, "faint on surface is \(ratio):1 in \(appearance)")
        }
    }

    @Test("state colours stay legible on their ground") func stateContrast() {
        for appearance in ResolvedAppearance.allCases {
            for token in [ColorToken.saffron, .verdigris, .lapis, .clay] {
                let ratio = contrastRatio(RawiColors.hex(token, appearance),
                                          RawiColors.hex(.surface, appearance))
                #expect(ratio >= 3.0, "\(token) on surface is \(ratio):1 in \(appearance)")
            }
        }
    }

    @Test("state colours stay distinguishable from one another") func states() {
        for appearance in ResolvedAppearance.allCases {
            let states = [ColorToken.saffron, .verdigris, .lapis, .clay]
                .map { RawiColors.hex($0, appearance) }
            #expect(Set(states).count == states.count)
        }
    }

    @Test("the pill palette is dark regardless of appearance") func pillIsDark() {
        // It floats over arbitrary content; a light pill on a light document vanishes.
        #expect(RawiColors.pillHex(.ink) == RawiColors.hex(.ink, .dark))
        #expect(luminance(RawiColors.pillHex(.ink)) < 0.3)
        #expect(luminance(RawiColors.pillHex(.bone)) > 0.7)
    }
}

@Suite("Type scale") struct TypeScaleTests {
    static let uiSources: [URL] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/RawiCore/UI")
        return (try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "swift" } ?? []
    }()

    @Test("no view picks a font size by hand") func noLooseSizes() {
        // Fifteen sizes between 8 and 34 is what this replaced. Nobody sees the
        // difference between 10.5 and 11; everybody sees a screen measured
        // against itself.
        let pattern = try! Regex("size: [0-9]")
        for file in Self.uiSources where file.lastPathComponent != "DesignTokens.swift" {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for line in text.split(separator: "\n") where line.contains(pattern) {
                Issue.record(Comment(rawValue: "\(file.lastPathComponent): \(line)"))
            }
        }
    }

    @Test("the steps stay far enough apart to be worth having") func distinct() {
        let steps: [CGFloat] = [TypeScale.micro, TypeScale.small, TypeScale.body,
                                TypeScale.heading, TypeScale.title, TypeScale.figure,
                                TypeScale.hero]
        for (a, b) in zip(steps, steps.dropFirst()) {
            #expect(b > a)
            // A step you cannot see is a step that will be picked at random.
            #expect(b - a >= 1)
        }
    }
}
