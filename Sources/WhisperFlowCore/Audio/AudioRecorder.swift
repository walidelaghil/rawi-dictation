import AVFoundation
import Foundation

public struct RecordingResult: Sendable {
    public let url: URL
    public let duration: Duration
    public init(url: URL, duration: Duration) { self.url = url; self.duration = duration }
}

public protocol AudioRecording: AnyObject, Sendable {
    func start(to url: URL) throws
    func stop() throws -> RecordingResult
    func cancel()
    var level: Double { get }
    var isRecording: Bool { get }
}

public enum AudioError: Error, LocalizedError {
    case microphonePermissionDenied
    case engineStartFailed(String)
    case converterUnavailable
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied: "Microphone access denied"
        case .engineStartFailed(let m): "Could not start audio engine: \(m)"
        case .converterUnavailable: "Could not build a 16 kHz audio converter"
        case .notRecording: "Not recording"
        }
    }
}

/// Computes RMS of a 16-bit PCM block, normalised to 0...1.
func rmsLevel(_ samples: [Int16]) -> Double {
    guard !samples.isEmpty else { return 0 }
    var sum = 0.0
    for s in samples {
        let v = Double(s) / Double(Int16.max)
        sum += v * v
    }
    return (sum / Double(samples.count)).squareRoot()
}

/// Exponential smoothing so the pill's meter moves smoothly rather than flickering.
func smoothLevel(previous: Double, sample: Double) -> Double {
    0.85 * previous + 0.15 * sample
}

public final class AudioRecorder: AudioRecording, @unchecked Sendable {
    /// The only format whisper.cpp accepts: 16 kHz, mono, signed 16-bit.
    static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000,
        channels: 1, interleaved: true)!

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var writer: WAVWriter?
    private var _level: Double = 0
    private var _isRecording = false

    public init() {}

    public var level: Double { lock.withLock { _level } }
    public var isRecording: Bool { lock.withLock { _isRecording } }

    public func start(to url: URL) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioError.microphonePermissionDenied
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Never assume 48 kHz — read what the hardware actually gives us.
        let hardwareFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: hardwareFormat, to: Self.whisperFormat) else {
            throw AudioError.converterUnavailable
        }
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue

        let writer = try WAVWriter(url: url)

        lock.withLock {
            self.engine = engine
            self.converter = converter
            self.writer = writer
            self._level = 0
            self._isRecording = true
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buf, _ in
            self?.handle(buf)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? writer.finalize()
            lock.withLock { self._isRecording = false }
            throw AudioError.engineStartFailed(error.localizedDescription)
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let samples = convert(buffer) else { return }
        lock.withLock {
            guard _isRecording, let writer else { return }
            try? writer.append(samples)
            _level = smoothLevel(previous: _level, sample: rmsLevel(samples))
        }
    }

    /// Resamples one hardware buffer to 16 kHz mono Int16. The ratio is not
    /// integral in general, so the output capacity is derived, never assumed.
    private func convert(_ buffer: AVAudioPCMBuffer) -> [Int16]? {
        let converter = lock.withLock { self.converter }
        guard let converter else { return nil }

        let ratio = Self.whisperFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.whisperFormat,
                                         frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, out.frameLength > 0,
              let channel = out.int16ChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
    }

    public func stop() throws -> RecordingResult {
        // Tear the engine down *before* finalizing, so no tap callback can append
        // after the header sizes have been patched.
        let (engine, writer) = lock.withLock { (self.engine, self.writer) }
        guard let engine, let writer else { throw AudioError.notRecording }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock { self._isRecording = false; self._level = 0 }

        try writer.finalize()
        lock.withLock { self.engine = nil; self.converter = nil; self.writer = nil }
        return RecordingResult(url: writer.url, duration: writer.duration)
    }

    public func cancel() {
        let (engine, writer) = lock.withLock { (self.engine, self.writer) }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        lock.withLock { self._isRecording = false; self._level = 0 }
        try? writer?.finalize()
        if let url = writer?.url { try? FileManager.default.removeItem(at: url) }
        lock.withLock { self.engine = nil; self.converter = nil; self.writer = nil }
    }
}
