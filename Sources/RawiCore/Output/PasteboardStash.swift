import AppKit

/// Snapshot of a pasteboard's full contents, so a restore preserves images and
/// rich text rather than flattening everything to a plain string.
public struct PasteboardStash: Sendable {
    private let items: [[String: Data]]

    private init(items: [[String: Data]]) { self.items = items }

    public static func capture(_ pb: NSPasteboard) -> PasteboardStash {
        let captured: [[String: Data]] = (pb.pasteboardItems ?? []).map { item in
            var byType: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    byType[type.rawValue] = data
                }
            }
            return byType
        }
        return PasteboardStash(items: captured.filter { !$0.isEmpty })
    }

    public func restore(to pb: NSPasteboard) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { byType in
            let item = NSPasteboardItem()
            for (raw, data) in byType {
                item.setData(data, forType: NSPasteboard.PasteboardType(raw))
            }
            return item
        }
        pb.writeObjects(restored)
    }

    public var isEmpty: Bool { items.isEmpty }
}
