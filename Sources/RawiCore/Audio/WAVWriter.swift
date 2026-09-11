import Foundation

/// Incremental canonical RIFF/WAVE writer for 16-bit PCM.
///
/// whisper-cli accepts only 16 kHz mono PCM. A wrong header does not error — it
/// produces silent garbage transcripts — so the header is written exactly and the
/// size fields are patched on close.
public final class WAVWriter {
    private let handle: FileHandle
    private let sampleRate: Int
    private let channels: Int
    private var dataBytes: Int = 0
    private var finalized = false

    public let url: URL

    public init(url: URL, sampleRate: Int = 16_000, channels: Int = 1) throws {
        self.url = url
        self.sampleRate = sampleRate
        self.channels = channels

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Self.header(sampleRate: sampleRate,
                                                 channels: channels,
                                                 dataBytes: 0))
    }

    public func append(_ samples: [Int16]) throws {
        guard !finalized, !samples.isEmpty else { return }
        var bytes = [UInt8]()
        bytes.reserveCapacity(samples.count * 2)
        for s in samples {
            let u = UInt16(bitPattern: s)
            bytes.append(UInt8(u & 0xFF))
            bytes.append(UInt8(u >> 8))
        }
        try handle.write(contentsOf: bytes)
        dataBytes += bytes.count
    }

    /// Patches the RIFF and data chunk sizes, then closes the file.
    public func finalize() throws {
        guard !finalized else { return }
        finalized = true
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: Self.le32(UInt32(36 + dataBytes)))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: Self.le32(UInt32(dataBytes)))
        try handle.close()
    }

    public var frameCount: Int { dataBytes / (2 * channels) }

    public var duration: Duration {
        .nanoseconds(Int64(frameCount) * 1_000_000_000 / Int64(sampleRate))
    }

    // MARK: - Byte helpers

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }

    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    private static func header(sampleRate: Int, channels: Int, dataBytes: Int) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        var d = Data()
        d.append(contentsOf: Array("RIFF".utf8))
        d.append(contentsOf: le32(UInt32(36 + dataBytes)))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        d.append(contentsOf: le32(16))                       // fmt chunk size
        d.append(contentsOf: le16(1))                        // PCM
        d.append(contentsOf: le16(UInt16(channels)))
        d.append(contentsOf: le32(UInt32(sampleRate)))
        d.append(contentsOf: le32(UInt32(byteRate)))
        d.append(contentsOf: le16(UInt16(blockAlign)))
        d.append(contentsOf: le16(UInt16(bitsPerSample)))
        d.append(contentsOf: Array("data".utf8))
        d.append(contentsOf: le32(UInt32(dataBytes)))
        return d
    }
}
