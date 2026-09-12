import SwiftUI

@MainActor
public final class DestinationsViewModel: ObservableObject {
    @Published public var rules: [DestinationRule] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false

    private let store: DestinationStore
    public init(store: DestinationStore) {
        self.store = store
        reload()
    }
    public func reload() { rules = store.rules }
    public func toggle(_ rule: DestinationRule) {
        store.setEnabled(rule.id, !rule.enabled); reload()
    }
    public func remove(_ rule: DestinationRule) { store.remove(rule.id); reload() }
}

public struct DestinationsView: View {
    @ObservedObject var model: DestinationsViewModel
    public init(model: DestinationsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "Destinations", appearance: model.appearance,
                         showInfo: $model.showInfo,
                         info: "Rawi reads which app you are in, and for a browser, which page. "
                             + "Rules change structure and register only. They never add facts, "
                             + "and the guard still protects your words. Page-level is as "
                             + "fine-grained as this can get: knowing which field you are in "
                             + "needs Accessibility, which this Mac cannot grant.")

            capability

            RowGroup(appearance: model.appearance) {
                ForEach(model.rules) { rule in
                  Row(appearance: model.appearance) {
                    HStack(alignment: .top, spacing: 12) {
                        Button { model.toggle(rule) } label: {
                            Image(systemName: rule.enabled ? "checkmark.square.fill" : "square")
                                .font(.system(size: 13))
                                .foregroundStyle(rule.enabled ? c(.saffron) : c(.faint))
                        }
                        .buttonStyle(.plain)
                        .help(rule.enabled ? "Disable" : "Enable")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.name).font(.system(size: 13))
                                .foregroundStyle(rule.enabled ? c(.bone) : c(.faint))
                            Text(rule.matchDescription)
                                .font(.system(size: 10.5).monospaced())
                                .foregroundStyle(c(.faint))
                        }
                        .frame(width: 210, alignment: .leading)

                        Text(rule.instruction)
                            .font(.system(size: 11.5))
                            .foregroundStyle(rule.enabled ? c(.muted) : c(.faint))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        if !rule.isBuiltIn {
                            Button { model.remove(rule) } label: {
                                Image(systemName: "xmark").font(.system(size: 9))
                                    .foregroundStyle(c(.faint))
                            }.buttonStyle(.plain)
                        }
                    }
                  }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.surface))
    }

    /// What the three signals can and cannot do — measured, not assumed.
    private var capability: some View {
        HStack(spacing: 12) {
            signal("Which app", "free", .verdigris,
                   "Read from the system. No permission at all.")
            signal("Which page", "one click", .saffron,
                   "The browser tab URL. You approve Brave once, with no administrator.")
            signal("Which field", "blocked", .clay,
                   "Needs Accessibility, which this Mac will not grant.")
        }
    }

    private func signal(_ title: String, _ badge: String,
                        _ token: ColorToken, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(c(.bone))
                Spacer()
                Text(badge.uppercased())
                    .font(.system(size: 8.5, weight: .medium).monospaced()).tracking(1.1)
                    .foregroundStyle(c(token))
            }
            Text(detail).font(.system(size: 11)).foregroundStyle(c(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(token).opacity(0.45))))
    }
}
