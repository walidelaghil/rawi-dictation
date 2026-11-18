import AppKit
import SwiftUI

@MainActor
public final class DestinationsViewModel: ObservableObject {
    @Published public var rules: [DestinationRule] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false

    /// The rule being written in the form.
    @Published public var draftName = ""
    @Published public var draftApps = ""
    @Published public var draftURL = ""
    @Published public var draftField = ""
    @Published public var draftInstruction = ""
    /// The form stays folded away until it is wanted: open, it pushed the rules
    /// list down to two visible rows.
    @Published public var composing = false
    @Published public var detecting: Int?
    @Published public var detected: String?
    @Published public var fieldAware = FieldAwareness.current

    public enum FieldAwareness { case on, needsAccessibility
        static var current: FieldAwareness { AXIsProcessTrusted() ? .on : .needsAccessibility }
    }

    /// Reads where you are. Injectable so tests do not depend on the frontmost app.
    public var sense: () -> (bundleID: String?, url: String?, field: FieldContext?) = {
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return (bundle, BrowserContext.activeURL(bundleID: bundle), FieldContext.focused())
    }

    private let store: DestinationStore
    public init(store: DestinationStore) {
        self.store = store
        reload()
    }
    public func reload() { rules = store.rules; fieldAware = .current }

    public var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty
            && !draftInstruction.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func saveDraft() {
        guard canSave else { return }
        let apps = draftApps.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        func optional(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t
        }
        store.add(DestinationRule(name: draftName.trimmingCharacters(in: .whitespaces), bundleIDs: apps,
                                  urlPattern: optional(draftURL), fieldPattern: optional(draftField),
                                  instruction: draftInstruction.trimmingCharacters(in: .whitespaces)))
        draftName = ""; draftApps = ""; draftURL = ""; draftField = ""; draftInstruction = ""; detected = nil
        composing = false
        reload()
    }

    /// Gives you five seconds to click into the field you mean, then reads it.
    public func detect() {
        guard detecting == nil else { return }
        composing = true
        detected = nil
        Task { @MainActor in
            for remaining in stride(from: 5, to: 0, by: -1) {
                detecting = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            detecting = nil
            fill(from: sense())
        }
    }

    func fill(from sensed: (bundleID: String?, url: String?, field: FieldContext?)) {
        let own = Bundle.main.bundleIdentifier
        guard let bundle = sensed.bundleID, bundle != own else {
            detected = "Rawi was still in front. Click Detect, then switch to the field within five seconds."
            return
        }
        draftApps = bundle
        if let url = sensed.url, let host = URL(string: url)?.host {
            draftURL = "*\(host)*"
        }
        if let field = sensed.field, let name = field.name {
            draftField = name.lowercased()
            if draftName.isEmpty { draftName = name }
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName
                ?? bundle.components(separatedBy: ".").last ?? bundle
            detected = "Found “\(name)”\(field.multiline ? ", a multi-line field" : ""), in \(app)."
        } else {
            detected = fieldAware == .on
                ? "Found the app, but the field did not say what it is. You can type a word from its label."
                : "Found the app. Reading the field needs Accessibility."
        }
    }
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
                         info: "Rawi reads which app you are in, which page for a browser, and "
                             + "which field you are typing in. The most specific rule wins: a field "
                             + "beats a page, a page beats an app. Rules change structure and "
                             + "register only. They never add facts, and the guard still protects "
                             + "your words.")

            capability

            RowGroup(appearance: model.appearance) {
                ForEach(model.rules) { rule in
                  Row(appearance: model.appearance) {
                    HStack(alignment: .top, spacing: 12) {
                        Button { model.toggle(rule) } label: {
                            Image(systemName: rule.enabled ? "checkmark.square.fill" : "square")
                                .font(.system(size: TypeScale.heading))
                                // Not saffron: that colour means "recording right
                                // now" everywhere else, and a checked box is not
                                // that.
                                .foregroundStyle(rule.enabled ? c(.verdigris) : c(.faint))
                        }
                        .buttonStyle(.plain)
                        .help(rule.enabled ? "Disable" : "Enable")

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 9) {
                                Text(rule.name)
                                    .font(.system(size: TypeScale.heading, weight: .medium))
                                    .foregroundStyle(rule.enabled ? c(.bone) : c(.faint))
                                Text(rule.matchDescription)
                                    .font(.system(size: TypeScale.small).monospaced())
                                    .foregroundStyle(c(.faint))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Text(rule.instruction)
                                .font(.system(size: TypeScale.body))
                                .foregroundStyle(rule.enabled ? c(.muted) : c(.faint))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if !rule.isBuiltIn {
                            Button { model.remove(rule) } label: {
                                Image(systemName: "xmark").font(.system(size: TypeScale.small))
                                    .foregroundStyle(c(.muted)).frame(width: 24, height: 24).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Delete this rule")
                            .accessibilityLabel("Delete the \(rule.name) rule")
                        }
                    }
                  }
                }
            }
            addRule
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.surface))
    }

    private var addRule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Add a rule").font(.system(size: TypeScale.body, weight: .semibold)).foregroundStyle(c(.bone))
                Spacer()
                if !model.composing {
                    Button("New rule") { model.composing = true }
                        .buttonStyle(.plain)
                        .font(.system(size: TypeScale.small, weight: .medium)).foregroundStyle(c(.saffron))
                }
                Button(action: model.detect) {
                    Label(model.detecting.map { "Click into the field… \($0)" } ?? "Detect field",
                          systemImage: "scope")
                        .font(.system(size: TypeScale.small, weight: .medium))
                        .foregroundStyle(model.detecting == nil ? c(.bone) : c(.saffron))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
                            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
                }
                .buttonStyle(.plain)
                .help("Click, then click into the text field this rule is for, within five seconds")
            }
            if model.composing {
            if let detected = model.detected {
                Text(detected).font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                field("Name", $model.draftName)
                field("App bundle IDs", $model.draftApps)
            }
            HStack(spacing: 8) {
                field("Page, like *atlassian.net*", $model.draftURL)
                field("Field, like summary", $model.draftField)
            }
            field("How to shape the text, like: one short line, no full stop", $model.draftInstruction)
            HStack {
                Spacer()
                Button("Add rule", action: model.saveDraft)
                    .buttonStyle(.plain)
                    .font(.system(size: TypeScale.body, weight: .semibold))
                    .foregroundStyle(model.canSave ? c(.saffron) : c(.faint))
                    .disabled(!model.canSave)
            }
            }
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: TypeScale.body))
            .foregroundStyle(c(.bone))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
    }

    /// What the three signals can and cannot do — measured, not assumed.
    private var capability: some View {
        HStack(alignment: .top, spacing: 12) {
            signal("Which app", "free", .verdigris,
                   "Read from the system. No permission at all.")
            signal("Which page", "one click", .saffron,
                   "The browser tab URL. You approve Brave once, with no administrator.")
            if model.fieldAware == .on {
                signal("Which field", "on", .verdigris,
                       "Its label, read through Accessibility. Tells a Summary box from a Description.")
            } else {
                signal("Which field", "needs access", .clay,
                       "Grant Accessibility in System Settings and field rules start working.")
            }
        }
    }

    private func signal(_ title: String, _ badge: String,
                        _ token: ColorToken, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: TypeScale.body, weight: .semibold)).foregroundStyle(c(.bone))
                Spacer()
                Text(badge.uppercased())
                    .font(.system(size: TypeScale.micro, weight: .medium).monospaced())
                    .tracking(1.1)
                    .foregroundStyle(c(token))
                    .fixedSize()
            }
            Text(detail).font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface)
                .strokeBorder(c(token).opacity(0.45))))
    }
}
