import CoreGraphics
import Foundation

public enum HotkeyError: Error, LocalizedError {
    case tapCreationFailed
    case carbonRegistrationFailed(OSStatus)
    case carbonNeedsCombination(String)

    public var errorDescription: String? {
        switch self {
        case .tapCreationFailed:
            "Could not create the keyboard event tap. Grant Input Monitoring in "
            + "System Settings → Privacy & Security → Input Monitoring."
        case .carbonRegistrationFailed(let status):
            "Could not register the global hotkey (OSStatus \(status)). Another app "
            + "is probably already using that combination — pick a different one."
        case .carbonNeedsCombination(let hotkey):
            "“\(hotkey)” cannot be used without Input Monitoring. The permission-free "
            + "hotkey backend needs a modifier combination such as ctrl+option+space."
        }
    }
}

/// Watches the keyboard for the dictation hotkey and for Esc.
///
/// The tap is created with `.listenOnly`, which is not an optimisation but a safety
/// property: this app never consumes a keystroke. Esc therefore still reaches the
/// focused app, and a hang here can never leave the keyboard unresponsive.
public final class HotkeyMonitor: HotkeyBackend {
    private let matcher: HotkeyMatcher
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onEscape: () -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierIsDown = false
    private var keyIsDown = false

    public init(matcher: HotkeyMatcher,
                onPress: @escaping () -> Void,
                onRelease: @escaping () -> Void,
                onEscape: @escaping () -> Void) {
        self.matcher = matcher
        self.onPress = onPress
        self.onRelease = onRelease
        self.onEscape = onEscape
    }

    public var isRunning: Bool { tap != nil }

    public var describeBackend: String { "event tap (listen-only, needs Input Monitoring)" }

    public func start() throws {
        guard tap == nil else { return }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        // The C callback cannot capture, so `self` travels through userInfo.
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: context) else {
            throw HotkeyError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        modifierIsDown = false
        keyIsDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables a tap that takes too long to respond. Without re-arming,
        // the hotkey silently dies after the first slow transcription.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyDown, keyCode == HotkeyConfig.escapeKeyCode {
            onEscape()
            // Deliberately no early return and no consumption: Esc continues to
            // the focused app.
        }

        switch matcher {
        case .modifierFlag(let flag):
            guard type == .flagsChanged else { return }
            let isDown = event.flags.contains(flag)
            guard isDown != modifierIsDown else { return }
            modifierIsDown = isDown
            isDown ? onPress() : onRelease()

        case .keyCode(let wanted, let modifiers):
            guard keyCode == wanted else { return }
            switch type {
            case .keyDown:
                guard event.flags.isSuperset(of: modifiers), !keyIsDown else { return }
                keyIsDown = true
                onPress()
            case .keyUp:
                guard keyIsDown else { return }
                keyIsDown = false
                onRelease()
            default:
                return
            }
        }
    }
}
