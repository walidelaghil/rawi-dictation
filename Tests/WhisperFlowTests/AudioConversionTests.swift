import Testing
import AVFoundation
@testable import WhisperFlowCore

@Suite("Audio conversion") struct AudioConversionTests {
    @Test("rms of silence is zero, of full-scale is one") func rms() {
        #expect(rmsLevel([Int16](repeating: 0, count: 512)) == 0.0)
        let full = [Int16](repeating: Int16.max, count: 512)
        #expect(abs(rmsLevel(full) - 1.0) < 0.01)
    }

    @Test("rms of a half-scale signal is one half") func halfScale() {
        let half = [Int16](repeating: Int16.max / 2, count: 512)
        #expect(abs(rmsLevel(half) - 0.5) < 0.02)
    }

    @Test("rms of an empty block is zero, not NaN") func emptyRms() {
        #expect(rmsLevel([]) == 0.0)
    }

    @Test("target format is 16kHz mono int16") func targetFormat() {
        let f = AudioRecorder.whisperFormat
        #expect(f.sampleRate == 16_000)
        #expect(f.channelCount == 1)
        #expect(f.commonFormat == .pcmFormatInt16)
    }

    @Test("level smoothing converges toward the input") func smoothing() {
        var l = 0.0
        for _ in 0..<100 { l = smoothLevel(previous: l, sample: 1.0) }
        #expect(l > 0.99)
    }

    @Test("level smoothing decays back toward silence") func decay() {
        var l = 1.0
        for _ in 0..<100 { l = smoothLevel(previous: l, sample: 0.0) }
        #expect(l < 0.01)
    }

    @Test("stopping when not recording throws rather than crashing") func stopIdle() {
        #expect(throws: AudioError.self) { _ = try AudioRecorder().stop() }
    }
}
