import Foundation

/// Lets another process drive the dictation pipeline without synthesizing a
/// keystroke, by posting a distributed notification the running app observes.
///
/// This exists because the pipeline cannot otherwise be verified: synthesizing the
/// hotkey requires Accessibility in the *sending* process, and a bundled binary
/// spawned from a terminal is attributed by TCC to that terminal rather than to
/// itself. Posting a notification needs no permission, and the app that receives it
/// runs with its own identity and its own grants.
///
/// Only start/stop/cancel — it drives the same controller entry points the hotkey
/// does, so it cannot do anything the hotkey could not.
public enum RemoteTrigger {
    public enum Action: String, Sendable, CaseIterable {
        case start, stop, cancel, handsFree, window
    }

    private static let name = "com.welaghil.rawi.trigger"

    public static func post(_ action: Action) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(name), object: action.rawValue, userInfo: nil, deliverImmediately: true)
    }

    public static func observe(_ handler: @escaping @Sendable (Action) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(name), object: nil, queue: .main
        ) { notification in
            guard let raw = notification.object as? String,
                  let action = Action(rawValue: raw) else { return }
            handler(action)
        }
    }
}
