import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Global hotkeys via Carbon's `RegisterEventHotKey`.
///
/// This API predates TCC and requires **no permission** — verified on a managed Mac
/// where Accessibility and Input Monitoring could not be granted at all. That makes
/// it the fallback when the user is not a local admin.
///
/// Two costs relative to the event tap:
///   - it can only bind a modifier+key combination, never a bare `fn`
///   - the combination is **consumed**, so it must be one nothing else uses
///
/// Because a release event can be missed if the modifiers are lifted before the key,
/// a safety timeout stops a push-to-talk recording that never saw its release.
public final class CarbonHotkeyMonitor: HotkeyBackend {
    private let keyCode: UInt16?
    private let modifiers: CGEventFlags
    private let cancelKeyCode: UInt16?
    private let cancelModifiers: CGEventFlags
    private let transformKeyCode: UInt16?
    private let transformModifiers: CGEventFlags

    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onCancel: () -> Void
    private let onTransformPress: () -> Void
    private let onTransformRelease: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var cancelRef: EventHotKeyRef?
    private var transformRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let signature = OSType(0x57464C57)     // 'WFLW'

    /// Hotkey ids are unique per signature across the whole process, so two
    /// monitors — dictation on the event tap, transform on Carbon — would collide
    /// on a fixed id. Each instance takes its own block of three.
    private static let counter = Counter()
    private let idBase: UInt32
    private var dictateID: UInt32 { idBase + 1 }
    private var cancelID: UInt32 { idBase + 2 }
    private var transformID: UInt32 { idBase + 3 }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var next: UInt32 = 0
        func take() -> UInt32 { lock.withLock { next += 10; return next } }
    }

    public init(keyCode: UInt16?, modifiers: CGEventFlags,
                cancelKeyCode: UInt16? = nil, cancelModifiers: CGEventFlags = [],
                transformKeyCode: UInt16? = nil, transformModifiers: CGEventFlags = [],
                onPress: @escaping () -> Void = {},
                onRelease: @escaping () -> Void = {},
                onCancel: @escaping () -> Void = {},
                onTransformPress: @escaping () -> Void = {},
                onTransformRelease: @escaping () -> Void = {}) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.cancelKeyCode = cancelKeyCode
        self.cancelModifiers = cancelModifiers
        self.transformKeyCode = transformKeyCode
        self.transformModifiers = transformModifiers
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
        self.onTransformPress = onTransformPress
        self.onTransformRelease = onTransformRelease
        self.idBase = Self.counter.take()
    }

    public var isRunning: Bool { hotKeyRef != nil || transformRef != nil }

    public var describeBackend: String {
        "Carbon hotkey (no permissions required)"
    }

    public func start() throws {
        guard handlerRef == nil else { return }

        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userInfo in
            guard let event, let userInfo else { return OSStatus(eventNotHandledErr) }
            let monitor = Unmanaged<CarbonHotkeyMonitor>.fromOpaque(userInfo)
                .takeUnretainedValue()

            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }

            monitor.handle(id: id.id, kind: GetEventKind(event))
            return noErr
        }

        let installStatus = InstallEventHandler(GetApplicationEventTarget(), callback,
                                                types.count, &types, context, &handlerRef)
        guard installStatus == noErr else { throw HotkeyError.carbonRegistrationFailed(installStatus) }

        if let keyCode {
            let status = RegisterEventHotKey(
                UInt32(keyCode), Self.carbonModifiers(modifiers),
                EventHotKeyID(signature: Self.signature, id: dictateID),
                GetApplicationEventTarget(), 0, &hotKeyRef)
            guard status == noErr else { throw HotkeyError.carbonRegistrationFailed(status) }
        }

        if let cancelKeyCode {
            _ = RegisterEventHotKey(UInt32(cancelKeyCode), Self.carbonModifiers(cancelModifiers),
                                    EventHotKeyID(signature: Self.signature, id: cancelID),
                                    GetApplicationEventTarget(), 0, &cancelRef)
        }

        // Transform is deliberately allowed to fail quietly: a clash with another
        // app costs the transform key, and must not cost dictation too.
        if let transformKeyCode {
            _ = RegisterEventHotKey(UInt32(transformKeyCode),
                                    Self.carbonModifiers(transformModifiers),
                                    EventHotKeyID(signature: Self.signature, id: transformID),
                                    GetApplicationEventTarget(), 0, &transformRef)
        }
    }

    /// False when the transform combination could not be claimed — another app
    /// already owns it — so the caller can say so instead of leaving a dead key.
    public var transformRegistered: Bool { transformRef != nil }

    public func stop() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let cancelRef { UnregisterEventHotKey(cancelRef) }
        if let transformRef { UnregisterEventHotKey(transformRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        cancelRef = nil
        transformRef = nil
        handlerRef = nil
    }

    private func handle(id: UInt32, kind: UInt32) {
        switch (id, Int(kind)) {
        case (dictateID, kEventHotKeyPressed): onPress()
        case (dictateID, kEventHotKeyReleased): onRelease()
        case (cancelID, kEventHotKeyPressed): onCancel()
        case (transformID, kEventHotKeyPressed): onTransformPress()
        case (transformID, kEventHotKeyReleased): onTransformRelease()
        default: break
        }
    }

    static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var result: Int = 0
        if flags.contains(.maskCommand) { result |= cmdKey }
        if flags.contains(.maskShift) { result |= shiftKey }
        if flags.contains(.maskAlternate) { result |= optionKey }
        if flags.contains(.maskControl) { result |= controlKey }
        return UInt32(result)
    }
}
