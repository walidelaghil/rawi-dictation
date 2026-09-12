import Testing
import Foundation
@testable import RawiCore

/// Little-endian readers for asserting exact header bytes.
func le32(_ d: Data, _ o: Int) -> UInt32 {
    UInt32(d[o]) | UInt32(d[o+1]) << 8 | UInt32(d[o+2]) << 16 | UInt32(d[o+3]) << 24
}
func le16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[o]) | UInt16(d[o+1]) << 8 }

@Suite("WAVWriter") struct WAVWriterTests {
    func tmp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-\(UUID().uuidString).wav")
    }

    @Test("writes a valid 44-byte canonical header") func header() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.append([Int16](repeating: 0, count: 16_000))
        try w.finalize()

        let d = try Data(contentsOf: url)
        #expect(d.count == 44 + 32_000)
        #expect(d[0..<4].elementsEqual("RIFF".utf8))
        #expect(d[8..<12].elementsEqual("WAVE".utf8))
        #expect(d[12..<16].elementsEqual("fmt ".utf8))
        #expect(d[36..<40].elementsEqual("data".utf8))

        #expect(le32(d, 4)  == UInt32(36 + 32_000))   // RIFF size
        #expect(le32(d, 40) == UInt32(32_000))        // data size
        #expect(le32(d, 24) == 16_000)                // sample rate
        #expect(le32(d, 28) == 32_000)                // byte rate
        #expect(le16(d, 22) == 1)                     // mono
        #expect(le16(d, 34) == 16)                    // bits per sample
        #expect(le16(d, 20) == 1)                     // PCM format tag
    }

    @Test("frameCount and duration track appended samples") func counts() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.append([Int16](repeating: 1, count: 8_000))
        try w.append([Int16](repeating: 2, count: 8_000))
        try w.finalize()
        #expect(w.frameCount == 16_000)
        #expect(w.duration == .seconds(1))
    }

    @Test("an empty recording still produces a readable file") func empty() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.finalize()
        let d = try Data(contentsOf: url)
        #expect(d.count == 44)
        #expect(le32(d, 40) == 0)
        #expect(w.frameCount == 0)
    }

    @Test("samples round-trip as little-endian int16") func endianness() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.append([0x0102, -2])
        try w.finalize()
        let d = try Data(contentsOf: url)
        #expect(d[44] == 0x02); #expect(d[45] == 0x01)
        #expect(d[46] == 0xFE); #expect(d[47] == 0xFF)   // -2 as two's complement LE
    }

    @Test("finalize is idempotent") func doubleFinalize() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.append([Int16](repeating: 0, count: 10))
        try w.finalize()
        try w.finalize()
        #expect(try Data(contentsOf: url).count == 64)
    }
}
