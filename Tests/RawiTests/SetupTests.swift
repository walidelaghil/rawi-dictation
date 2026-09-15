import Foundation
import Testing
@testable import RawiCore

@Suite("First run") struct SetupLogicTests {
    func status(mic: Bool = true, whisper: Bool = true, model: Bool = true, detector: Bool = true,
                ollama: Bool = true, missing: [String] = []) -> SetupStatus {
        SetupStatus(microphone: mic, accessibility: false, inputMonitoring: false,
                    whisperInstalled: whisper, transcriptionModel: model, detectorModel: detector,
                    ollamaReachable: ollama, ollamaMissing: missing)
    }

    @Test("dictation needs the microphone, whisper.cpp and a model; nothing else") func canDictate() {
        #expect(status().canDictate)
        #expect(!status(mic: false).canDictate)
        #expect(!status(whisper: false).canDictate)
        #expect(!status(model: false).canDictate)
        #expect(status(detector: false).canDictate)
    }

    @Test("polish is ready when Ollama has every model, or when polish is off") func polish() {
        #expect(status().polishReady(provider: .ollama))
        #expect(!status(missing: ["qwen2.5:3b"]).polishReady(provider: .ollama))
        #expect(!status(ollama: false).polishReady(provider: .ollama))
        #expect(status(ollama: false).polishReady(provider: .off))
    }

    @Test("an existing config counts as set up; one without the key too") func existingConfig() throws {
        let json = #"{"hotkey":"option+space"}"#
        #expect(try JSONDecoder().decode(Config.self, from: Data(json.utf8)).setupCompleted)
        var fresh = Config.default
        fresh.setupCompleted = false
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(fresh))
        #expect(!back.setupCompleted)
    }

    @Test("the models to pull are listed once each, in the order they are needed") func required() {
        var config = Config.default
        config.cleanup.models = CleanupModels(latin: "qwen2.5:1.5b", arabic: "qwen2.5:3b")
        config.cleanup.transformModel = "qwen2.5:3b"
        #expect(OllamaModels.required(for: config).map(\.name) == ["qwen2.5:1.5b", "qwen2.5:3b"])
    }

    @Test("Ollama's pull stream reads as progress") func pullLines() {
        #expect(OllamaModels.progress(fromLine: #"{"status":"pulling manifest"}"#)?.fraction == nil)
        #expect(OllamaModels.progress(fromLine: #"{"status":"pulling abc","total":200,"completed":50}"#)?.fraction == 0.25)
        #expect(OllamaModels.progress(fromLine: #"{"status":"success"}"#)?.fraction == 1)
        #expect(OllamaModels.progress(fromLine: #"{"error":"model not found"}"#)?.status == "error: model not found")
        #expect(OllamaModels.progress(fromLine: "not json") == nil)
    }

    @Test("the detector is a known, downloadable model") func detector() {
        #expect(ModelStore.detector.filename == "ggml-base.bin")
        #expect(ModelStore.detector.multilingual)
    }
}

@MainActor
@Suite("The setup screen's model") struct SetupViewModelTests {
    func model() -> (SetupViewModel, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("setup-\(UUID().uuidString).json")
        var config = Config.default
        config.setupCompleted = false
        try? config.save(to: url)
        return (SetupViewModel(settings: SettingsViewModel(config: config, url: url)), url)
    }

    @Test("steps move forward and back, and the last one finishes") func steps() {
        let (m, url) = model()
        var finished = false
        m.onFinish = { finished = true }
        #expect(m.step == .welcome)
        m.back()
        #expect(m.step == .welcome)
        for _ in SetupStep.allCases.dropLast() { m.next() }
        #expect(m.step == .tryIt)
        m.next()
        #expect(finished)
        #expect((try? Config.load(from: url))?.setupCompleted == true)
    }

    @Test("skipping polish turns it off and moves on") func skipPolish() {
        let (m, url) = model()
        m.step = .polish
        m.skipPolish()
        #expect(m.step == .hotkey)
        #expect((try? Config.load(from: url))?.cleanup.provider == .off)
    }

    @Test("the try-it step is done once something was typed") func tryIt() {
        let (m, _) = model()
        m.status = SetupStatus(microphone: true, accessibility: true, inputMonitoring: true,
                               whisperInstalled: true, transcriptionModel: true, detectorModel: true,
                               ollamaReachable: true, ollamaMissing: [])
        #expect(!m.isDone(.tryIt))
        m.tryText = "hello from the setup screen"
        #expect(m.isDone(.tryIt))
    }
}

@Suite("Downloading, against the network", .enabled(if: ProcessInfo.processInfo.environment["RAWI_LIVE_NET"] != nil))
struct DownloadLiveTests {
    @Test("a download lands on disk and reports progress up to the end") func small() async throws {
        final class Box: @unchecked Sendable { var values: [Double] = [] }
        let box = Box()
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/README.md")!
        let file = try await DownloadWithProgress.fetch(url, expected: 10_000) { box.values.append($0) }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
        #expect(size > 1_000)
        #expect((box.values.last ?? 0) > 0.9)
        try? FileManager.default.removeItem(at: file)
    }
}

import AppKit
import SwiftUI

@MainActor
@Suite("Setup proof") struct SetupProofTests {
    @Test("setup proof", .enabled(if: ProcessInfo.processInfo.environment["RAWI_PROOF_SETUP"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_PROOF_SETUP"]!)
        var images: [NSImage] = []
        let cases: [(SetupStep, ResolvedAppearance, (SetupViewModel) -> Void)] = [
            (.models, .dark, { m in
                m.status = SetupStatus(microphone: true, accessibility: true, inputMonitoring: false,
                                       whisperInstalled: true, transcriptionModel: false, detectorModel: false,
                                       ollamaReachable: true, ollamaMissing: [])
                m.progress = [ModelStore.recommended.id: 0.42]
            }),
            (.polish, .dark, { m in
                m.settings.config.cleanup.provider = .ollama
                m.status = SetupStatus(microphone: true, accessibility: true, inputMonitoring: false,
                                       whisperInstalled: true, transcriptionModel: true, detectorModel: true,
                                       ollamaReachable: true, ollamaMissing: ["qwen2.5:3b"])
            }),
            (.hotkey, .light, { m in
                m.settings.config.hotkey = "option"
                m.status = SetupStatus(microphone: true, accessibility: true, inputMonitoring: true,
                                       whisperInstalled: true, transcriptionModel: true, detectorModel: true,
                                       ollamaReachable: true, ollamaMissing: [])
            }),
            (.tryIt, .light, { m in
                m.status = SetupStatus(microphone: true, accessibility: true, inputMonitoring: true,
                                       whisperInstalled: true, transcriptionModel: true, detectorModel: true,
                                       ollamaReachable: true, ollamaMissing: [])
                m.tryText = "This is my first dictation with Rawi, and it typed exactly what I said."
            }),
        ]
        for (step, appearance, configure) in cases {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("proof-\(UUID().uuidString).json")
            try? Config.default.save(to: url)
            let model = SetupViewModel(settings: SettingsViewModel(config: .default, url: url))
            model.appearance = appearance
            model.step = step
            let host = NSHostingView(rootView: SetupView(model: model))
            host.frame = NSRect(x: 0, y: 0, width: 800, height: 580)
            host.layoutSubtreeIfNeeded()
            model.stopPolling()
            configure(model)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(rep)
            images.append(image)
        }
        let gap: CGFloat = 14
        let columns = 2
        let cell = images[0].size
        let width = CGFloat(columns) * (cell.width + gap) + gap
        let height = CGFloat((images.count + 1) / columns) * (cell.height + gap) + gap
        let sheet = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            NSColor(white: 0.45, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            for (i, image) in images.enumerated() {
                let x = gap + CGFloat(i % columns) * (cell.width + gap)
                let y = gap + CGFloat(i / columns) * (cell.height + gap)
                image.draw(in: NSRect(x: x, y: y, width: cell.width, height: cell.height),
                           from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: nil)
            }
            return true
        }
        try NSBitmapImageRep(data: sheet.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!.write(to: out)
    }
}
