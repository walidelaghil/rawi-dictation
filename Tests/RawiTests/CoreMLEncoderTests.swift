import Testing
import Foundation
@testable import RawiCore

@Suite("Where whisper looks for the Core ML encoder") struct CoreMLEncoderTests {
    @Test("a quantisation suffix is dropped, so one encoder serves them all")
    func quantised() {
        // whisper_get_coreml_path_encoder strips "-qX_X" deliberately: the Core
        // ML encoder is full precision and shared across quantisations of the
        // same model. Getting this wrong means silently never finding it.
        #expect(CoreMLEncoder.path(forModel: "/m/ggml-large-v3-turbo-q8_0.bin")
                == "/m/ggml-large-v3-turbo-encoder.mlmodelc")
        #expect(CoreMLEncoder.path(forModel: "/m/ggml-large-v3-turbo-q5_1.bin")
                == "/m/ggml-large-v3-turbo-encoder.mlmodelc")
    }

    @Test("an unquantised model keeps its whole name") func plain() {
        #expect(CoreMLEncoder.path(forModel: "/m/ggml-large-v3-turbo.bin")
                == "/m/ggml-large-v3-turbo-encoder.mlmodelc")
        #expect(CoreMLEncoder.path(forModel: "/m/ggml-base.bin")
                == "/m/ggml-base-encoder.mlmodelc")
    }

    @Test("a dash that is not a quantisation is left alone") func notQuantisation() {
        // "-v3" and "-small.en" are part of the name, not a suffix to strip, and
        // the published encoders are named to match: ggml-small.en-encoder.mlmodelc.
        #expect(CoreMLEncoder.path(forModel: "/m/ggml-small.en.bin")
                == "/m/ggml-small.en-encoder.mlmodelc")
        #expect(CoreMLEncoder.path(forModel: "/m/ggml-large-v3.bin")
                == "/m/ggml-large-v3-encoder.mlmodelc")
    }

    @Test("a missing encoder is reported missing") func missing() {
        #expect(!CoreMLEncoder.isInstalled(forModel: "/nowhere/ggml-large-v3-turbo-q8_0.bin"))
    }

    @Test("a build without Core ML is reported as such") func unsupported() {
        // /bin/sh links no Core ML, and a path that does not exist is not a build.
        #expect(!CoreMLEncoder.isSupported(by: URL(fileURLWithPath: "/bin/sh")))
        #expect(!CoreMLEncoder.isSupported(by: URL(fileURLWithPath: "/nope/whisper-cli")))
    }
}

@Suite("Telling a Core ML build from a stock one") struct CoreMLBuildTests {
    /// Builds a fake install tree so the check is tested on its own terms
    /// rather than on whatever happens to be on this machine.
    private func tree(withCoreML: Bool) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisper-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("bin"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("lib"),
                               withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("bin/whisper-server"))
        try Data().write(to: root.appendingPathComponent("lib/libwhisper.1.dylib"))
        if withCoreML {
            try Data().write(to: root.appendingPathComponent("lib/libwhisper.coreml.dylib"))
        }
        return root
    }

    @Test("a build with the Core ML shim beside it is recognised") func supported() throws {
        let root = try tree(withCoreML: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(CoreMLEncoder.isSupported(by: root.appendingPathComponent("bin/whisper-server")))
    }

    @Test("a stock build is not") func unsupportedTree() throws {
        // Homebrew's layout exactly: same binary, same libwhisper, no shim.
        let root = try tree(withCoreML: false)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!CoreMLEncoder.isSupported(by: root.appendingPathComponent("bin/whisper-server")))
    }
}
