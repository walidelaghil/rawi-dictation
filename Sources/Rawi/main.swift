import AppKit
import Foundation

import RawiCore

// Drive the running app for verification:
// --trigger start|stop|cancel|handsFree|transform|window|menu|undo
if let i = CommandLine.arguments.firstIndex(of: "--trigger"),
   i + 1 < CommandLine.arguments.count {
    guard let action = RemoteTrigger.Action(rawValue: CommandLine.arguments[i + 1]) else {
        let valid = RemoteTrigger.Action.allCases.map(\.rawValue).joined(separator: ", ")
        FileHandle.standardError.write(Data("unknown trigger. valid: \(valid)\n".utf8))
        exit(2)
    }
    RemoteTrigger.post(action)
    // Give the distributed notification time to leave the process.
    Thread.sleep(forTimeInterval: 0.3)
    exit(0)
}

if CommandLine.arguments.contains("--install-karabiner-rule") {
    let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
    do {
        let path = try KarabinerRule.install(executable: executable)
        print("Wrote \(path.path)")
        print("")
        print("Nothing is enabled yet. Open Karabiner-Elements → Complex Modifications")
        print("→ Add rule → enable the Rawi rule you want.")
    } catch {
        FileHandle.standardError.write(Data("Failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)
}

// Renders the app icon from the same mark the menu bar draws, so the two cannot
// drift apart and no bitmap needs to live in the repository. Used by `make bundle`.
if let i = CommandLine.arguments.firstIndex(of: "--write-iconset"),
   i + 1 < CommandLine.arguments.count {
    let directory = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    do {
        try RawiMark.writeIconset(to: directory)
        print("Wrote \(directory.path)")
    } catch {
        FileHandle.standardError.write(Data("Failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)
}

if CommandLine.arguments.contains("--doctor") {
    let finished = DispatchSemaphore(value: 0)
    Task.detached {
        await Doctor.run()
        finished.signal()
    }
    finished.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
