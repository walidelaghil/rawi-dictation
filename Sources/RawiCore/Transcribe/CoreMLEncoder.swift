import Foundation

/// Whether the Neural Engine is doing the encoder pass, and where its model lives.
///
/// The encoder is the whole fixed cost of a dictation: whisper pads every
/// recording to a thirty-second window and encodes all of it, however little you
/// said. Measured on an M4 with large-v3-turbo: 1200ms on the GPU, 513ms on the
/// Neural Engine. Homebrew builds whisper.cpp with `COREML=0`, so on a stock
/// install the faster path is not merely unused, it is absent from the binary —
/// which is worth saying out loud rather than leaving as a silent default.
public enum CoreMLEncoder {
    /// Where whisper.cpp looks for the Core ML encoder, which is not quite
    /// "next to the model": it drops the extension, drops a `-qX_X`
    /// quantisation suffix if there is one, and appends `-encoder.mlmodelc`.
    /// So one encoder serves every quantisation of the same model — see
    /// `whisper_get_coreml_path_encoder`.
    public static func path(forModel model: String) -> String {
        var stem = model
        if let dot = stem.lastIndex(of: ".") { stem = String(stem[stem.startIndex..<dot]) }
        if let dash = stem.lastIndex(of: "-") {
            let suffix = stem[dash...]
            // "-q8_0", "-q5_1": five characters, q second, underscore fourth.
            if suffix.count == 5 {
                let c = Array(suffix)
                if c[1] == "q", c[3] == "_" { stem = String(stem[stem.startIndex..<dash]) }
            }
        }
        return stem + "-encoder.mlmodelc"
    }

    /// The encoder is a compiled model bundle — a directory, not a file.
    public static func isInstalled(forModel model: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: path(forModel: Config.expand(model)), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Whether this whisper build can use the Neural Engine at all.
    ///
    /// `-DWHISPER_COREML=1` produces one library a stock build does not have,
    /// `libwhisper.coreml.dylib`, and the presence of that file is the whole
    /// answer. The executable itself is no help: it links neither the framework
    /// nor the Core ML shim directly, both of which sit behind `libwhisper`.
    /// (An earlier version of this looked for "CoreML.framework" in the binary
    /// and always said no — the check that appeared to confirm it was matching
    /// the string "coreml" in this project's own install path.)
    public static func isSupported(by binary: URL) -> Bool {
        let bin = binary.deletingLastPathComponent()
        let candidates = [
            bin.appendingPathComponent("libwhisper.coreml.dylib"),
            bin.deletingLastPathComponent().appendingPathComponent("lib/libwhisper.coreml.dylib"),
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
    }
}
