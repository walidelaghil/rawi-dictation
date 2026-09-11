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
    private let keyCode: UInt16
    private let modifiers: CGEventFlags
    private let cancelKeyCode: UInt16?
    private let cancelModifiers: CGEventFlags

    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onCancel: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var cancelRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let signature = OSType(0x57464C57)     // 'WFLW'
    private static let dictateID: UInt32 = 1
    private static let cancelID: UInt32 = 2

    public init(keyCode: UInt16, modifiers: CGEventFlags,
                cancelKeyCode: UInt16?, cancelModifiers: CGEventFlags,
                onPress: @escaping () -> Void,
                onRelease: @escaping () -> Void,
                onCancel: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.cancelKeyCode = cancelKeyCode
        self.cancelModifiers = cancelModifiers
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
    }

    public var isRunning: Bool { hotKeyRef != nil }

    public var describeBackend: String {
        "Carbon hotkey (no permissions required)"
    }

    public func start() throws {
        guard hotKeyRef == nil else { return }

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

        let status = RegisterEventHotKey(UInt32(keyCode), Self.carbonModifiers(modifiers),
                                         EventHotKeyID(signature: Self.signature, id: Self.dictateID),
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else { throw HotkeyError.carbonRegistrationFailed(status) }

        if let cancelKeyCode {
            _ = RegisterEventHotKey(UInt32(cancelKeyCode), Self.carbonModifiers(cancelModifiers),
                                    EventHotKeyID(signature: Self.signature, id: Self.cancelID),
                                    GetApplicationEventTarget(), 0, &cancelRef)
        }
    }

    public func stop() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let cancelRef { UnregisterEventHotKey(cancelRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        cancelRef = nil
        handlerRef = nil
    }

    private func handle(id: UInt32, kind: UInt32) {
        switch (id, Int(kind)) {
        case (Self.dictateID, kEventHotKeyPressed): onPress()
        case (Self.dictateID, kEventHotKeyReleased): onRelease()
        case (Self.cancelID, kEventHotKeyPressed): onCancel()
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
