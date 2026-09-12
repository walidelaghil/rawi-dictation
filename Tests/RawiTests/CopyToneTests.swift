import Testing
import Foundation
@testable import RawiCore

/// The copy rules that are mechanical enough to enforce.
///
/// Not taste-policing for its own sake: an em-dash in every other sentence and a
/// middle dot between every pair of words are the two most recognisable marks of
/// text a machine wrote, in a product whose whole claim is that the words are
/// yours.
@Suite("Copy") struct CopyToneTests {
    static let uiFiles: [URL] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RawiCore/UI")
        return (try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "swift" } ?? []
    }()

    /// Every string literal in a file, minus the comments around them.
    func strings(in file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .flatMap { line -> [String] in
                line.split(separator: "\"").enumerated()
                    .filter { $0.offset % 2 == 1 }
                    .map { String($0.element) }
            }
    }

    @Test("no em-dashes in anything the user reads") func noEmDash() {
        #expect(!Self.uiFiles.isEmpty)
        for file in Self.uiFiles {
            for text in strings(in: file) where text.contains("—") || text.contains("–") {
                Issue.record(Comment(rawValue: "\(file.lastPathComponent): \(text)"))
            }
        }
    }

    @Test("at most one middle dot in a line of copy") func middleDots() {
        for file in Self.uiFiles {
            for text in strings(in: file) where text.filter({ $0 == "·" }).count > 1 {
                Issue.record(Comment(rawValue: "\(file.lastPathComponent): \(text)"))
            }
        }
    }

    @Test("the pill's own labels stay short enough to read at a glance") func pillLabels() {
        for state: DictationState in [.idle, .transcribing, .cleaning, .inserting,
                                      .transforming,
                                      .recording(mode: .pushToTalk, startedAt: .now)] {
            let label = PillLabel.text(for: state)
            #expect(label.count <= 16, Comment(rawValue: label))
            #expect(!label.contains("—"))
        }
    }
}
