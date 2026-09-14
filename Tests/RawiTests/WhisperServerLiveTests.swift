import Foundation
import Testing
@testable import RawiCore

/// Against the real whisper-server, because the line breaks that made dictation
/// arrive as four short lines were not in any fixture: they were in what the
/// server actually sends. Point RAWI_LIVE_WAV at a recording of real speech
/// (anything in ~/Library/Application Support/Rawi/recordings) and run:
///
///     RAWI_LIVE_WAV=/path/to.wav swift test --filter WhisperServerLive
@Suite("The real server, end to end", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["RAWI_LIVE_WAV"] != nil))
struct WhisperServerLiveTests {
    static var wav: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_LIVE_WAV"]!)
    }
    static let port = Int(ProcessInfo.processInfo.environment["RAWI_LIVE_PORT"] ?? "") ?? 8711

    @Test("the server segments its answer, and we deliver one line") func oneLine() async throws {
        var body = Data()
        let boundary = WhisperServerEngine.boundary
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("""
            Content-Disposition: form-data; name="file"; filename="audio.wav"\r\n
            """.utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: Self.wav))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(Self.port)/inference")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        try #require(status == 200,
                     "no whisper-server on \(Self.port) — start Rawi first")

        // What the server said, and what the user gets.
        let served = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?
            .flatMap { $0["text"] as? String } ?? ""
        let delivered = WhisperServerEngine.parse(data)

        #expect(!delivered.isEmpty)
        #expect(!delivered.contains("\n"))
        #expect(!delivered.contains("  "))
        #expect(delivered == delivered.trimmingCharacters(in: .whitespacesAndNewlines))
        // The words survive the join: same text, only the breaks are gone.
        #expect(delivered == Transcript.clean(served))
    }
}
