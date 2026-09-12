import Foundation

/// Watches the config file and reports changes, so edits take effect without a
/// restart. Editors usually replace rather than modify the file, so the watch is
/// re-established after a rename or delete.
public final class ConfigWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.welaghil.rawi.configwatch")
    private let debounce: DispatchTimeInterval

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?

    public init(url: URL = Config.configFile,
                debounceMs: Int = 250,
                onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
        self.debounce = .milliseconds(debounceMs)
    }

    public func start() {
        queue.async { [weak self] in self?.arm() }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            self.pending = nil
            self.cancelSource()
        }
    }

    private func arm() {
        // Only the source is torn down here. A pending debounced callback must
        // survive: an atomic save (rename-replace, which is what most editors and
        // `Config.save` do) invalidates the descriptor and triggers a re-arm, and
        // cancelling the pending work here would swallow that very save.
        cancelSource()
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Nothing to watch yet; look again shortly.
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.arm() }
            return
        }

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.scheduleChange()
            if flags.contains(.delete) || flags.contains(.rename) {
                self.queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in self?.arm() }
            }
        }
        source.setCancelHandler { [descriptor = self.descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    /// Editors can emit several events per save; only the last one matters.
    private func scheduleChange() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func cancelSource() {
        source?.cancel()          // the cancel handler closes the descriptor
        source = nil
        descriptor = -1
    }
}
