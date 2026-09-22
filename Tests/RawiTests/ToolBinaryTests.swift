import Testing
import Foundation
@testable import RawiCore

@Suite("ToolBinary") struct ToolBinaryTests {
    /// The PATH launchd actually hands a GUI app: no Homebrew directory in it.
    private static let launchdPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    @Test("finds a Homebrew tool on the PATH a Finder-launched app inherits")
    func homebrewWithoutPath() throws {
        // The bug: whisper-server was spawned through `/usr/bin/env`, which sees
        // only PATH, so an installed tool read as missing whenever Rawi was
        // launched from Finder rather than from a terminal — and the pill said
        // whisper.cpp was not installed to someone who had just installed it.
        let installed = "/opt/homebrew/bin/whisper-server"
        // Skipped rather than failed on a machine without whisper.cpp, or an
        // Intel one, where the claim has nothing to be true about.
        try #require(FileManager.default.isExecutableFile(atPath: installed))
        #expect(!Self.launchdPath.contains("/opt/homebrew"))
        #expect(ToolBinary.resolve("whisper-server", searchPath: Self.launchdPath)?.path
                == installed)
    }

    @Test("PATH still wins over the Homebrew fallback") func pathFirst() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toolbinary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shim = dir.appendingPathComponent("whisper-server")
        try "#!/bin/sh\n".write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)

        #expect(ToolBinary.resolve("whisper-server", searchPath: dir.path)?.path == shim.path)
    }

    @Test("a name that is nowhere resolves to nil") func missing() {
        #expect(ToolBinary.resolve("definitely-not-a-real-binary-xyz") == nil)
    }

    @Test("a path is taken literally, executable or not") func absolute() {
        #expect(ToolBinary.resolve("/bin/sh") != nil)
        #expect(ToolBinary.resolve("/nope/whisper-server") == nil)
    }
}
