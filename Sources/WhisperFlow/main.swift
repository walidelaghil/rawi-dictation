import AppKit
import Foundation

import WhisperFlowCore

// Drive the running app for verification: --trigger start|stop|cancel|handsFree
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
