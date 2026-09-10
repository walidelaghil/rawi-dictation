import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("ConfigWatcher") struct ConfigWatcherTests {
    /// Small actor so the watcher's background callback can be observed safely.
    actor Signal {
        private var fired = 0
        func hit() { fired += 1 }
        func count() -> Int { fired }
    }

    @Test("a write to the watched file fires the callback", .timeLimit(.minutes(1)))
    func detectsWrite() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-watch-\(UUID().uuidString).json")
        try Config.default.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let signal = Signal()
        let watcher = ConfigWatcher(url: url, debounceMs: 50) {
            Task { await signal.hit() }
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(300))
        var edited = Config.default
        edited.maxSessionSeconds = 60
        try edited.save(to: url)

        // Poll rather than sleeping a fixed amount, so the test is not flaky.
        for _ in 0..<40 {
            if await signal.count() > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await signal.count() > 0)
    }

    @Test("several rapid writes are debounced into fewer callbacks",
          .timeLimit(.minutes(1)))
    func debounces() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-watch-\(UUID().uuidString).json")
        try Config.default.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let signal = Signal()
        let watcher = ConfigWatcher(url: url, debounceMs: 200) {
            Task { await signal.hit() }
        }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))

        for seconds in [61, 62, 63, 64, 65] {
            var edited = Config.default
            edited.maxSessionSeconds = seconds
            try edited.save(to: url)
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(600))
        let count = await signal.count()
        #expect(count >= 1)
        #expect(count < 5)          // debounced, not one per write
    }

    @Test("watching a file that does not exist yet does not crash") func missingFile() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-absent-\(UUID().uuidString).json")
        let watcher = ConfigWatcher(url: url, debounceMs: 50) {}
        watcher.start()
        try await Task.sleep(for: .milliseconds(200))
        watcher.stop()
    }
}
