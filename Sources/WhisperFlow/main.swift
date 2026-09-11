import AppKit
import Foundation

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
