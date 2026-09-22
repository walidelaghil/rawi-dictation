import Foundation

/// Finds a Homebrew-installed tool from inside an app bundle.
///
/// A GUI app launched from Finder, the Dock or a login item inherits launchd's
/// PATH — `/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` — which on Apple silicon
/// does not contain Homebrew's `/opt/homebrew/bin`. Spawning through
/// `/usr/bin/env` therefore fails with "No such file or directory" for a tool
/// that is plainly installed, and the app says whisper.cpp is not installed to a
/// user who has just installed it.
///
/// Launched from a terminal the same app works, which is why this survived: every
/// development run inherits the developer's own PATH.
public enum ToolBinary {
    /// Where Homebrew puts things, searched after PATH so an explicit PATH entry
    /// still wins. Apple silicon first, then Intel.
    static let extraDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// The executable `configured` names, or nil if there is none to run.
    /// A name containing a slash is a path and is taken literally.
    ///
    /// `searchPath` is the PATH to look along, and exists so the tests can pose
    /// as a Finder-launched app without mutating the environment out from under
    /// every other test running beside them.
    public static func resolve(_ configured: String, searchPath: String? = nil) -> URL? {
        let fm = FileManager.default
        if configured.contains("/") {
            let expanded = Config.expand(configured)
            return fm.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        let path = searchPath ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathDirs = path.split(separator: ":").map(String.init)
        for dir in pathDirs + extraDirectories {
            let candidate = dir + "/" + configured
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}
