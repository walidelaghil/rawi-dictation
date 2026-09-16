import Testing
import Foundation
@testable import RawiCore

@Suite("ModelStore") struct ModelStoreTests {
    @Test("the recommended model is multilingual") func recommended() {
        // English-only was the v1 bug: it did not degrade on Arabic, it failed.
        #expect(ModelStore.recommended.multilingual)
        #expect(ModelStore.recommended.id == "large-v3-turbo-q8_0")
    }

    @Test("every known model has a plausible download url") func urls() {
        for m in ModelStore.known {
            #expect(m.downloadURL.absoluteString.hasSuffix(m.filename))
            #expect(m.downloadURL.host == "huggingface.co")
            #expect(m.approxBytes > 1_000_000)
        }
    }

    @Test("ids and filenames are unique") func unique() {
        #expect(Set(ModelStore.known.map(\.id)).count == ModelStore.known.count)
        #expect(Set(ModelStore.known.map(\.filename)).count == ModelStore.known.count)
    }

    @Test("English-only models are flagged as such") func englishOnly() {
        #expect(ModelStore.model(id: "small.en")?.multilingual == false)
        #expect(ModelStore.model(id: "base.en")?.multilingual == false)
    }

    @Test("a model resolves from a configured path") func fromPath() {
        let p = "/Users/x/Library/Application Support/Rawi/models/ggml-small.en.bin"
        #expect(ModelStore.model(forPath: p)?.id == "small.en")
        #expect(ModelStore.model(forPath: "/tmp/mystery.bin") == nil)
    }

    @Test("an unknown id is nil rather than a crash") func unknown() {
        #expect(ModelStore.model(id: "not-a-model") == nil)
    }

    @Test("installed reflects what is actually on disk") func installed() {
        for m in ModelStore.known {
            let onDisk = FileManager.default.fileExists(atPath: ModelStore.url(for: m).path)
            #expect(ModelStore.isInstalled(m) == onDisk)
        }
        #expect(Set(ModelStore.installed().map(\.id))
                == Set(ModelStore.known.filter(ModelStore.isInstalled).map(\.id)))
    }

    @Test("the directory sits under Application Support") func dir() {
        #expect(ModelStore.directory.path.contains("Application Support/Rawi/models"))
    }

    @Test("sizes render for a picker") func sizes() {
        #expect(ModelStore.recommended.approxSize.hasSuffix("MB"))
    }

    @Test("the shipped default config points at an installed multilingual model") func defaultPath() {
        let m = ModelStore.model(forPath: Config.default.whispercpp.model)
        #expect(m?.multilingual == true)
        #expect(m?.id == ModelStore.recommended.id)
    }
}
