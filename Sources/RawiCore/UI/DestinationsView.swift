import AppKit
import SwiftUI

@MainActor
public final class DestinationsViewModel: ObservableObject {
    @Published public var rules: [DestinationRule] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false
    public var undo: UndoCenter?

    /// The rule being written in the form.
    @Published public var draftName = ""
    @Published public var draftApps = ""
    @Published public var draftURL = ""
    @Published public var draftField = ""
    @Published public var draftInstruction = ""
    /// The form stays folded away until it is wanted: open, it pushed the rules
    /// list down to two visible rows.
    @Published public var composing = false
    @Published public var query = ""
    @Published public var editing: UUID?
    @Published public var editName = ""
    @Published public var editApps = ""
    @Published public var editURL = ""
    @Published public var editField = ""
    @Published public var editInstruction = ""
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
    public var filtered: [DestinationRule] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rules }
        return rules.filter {
            $0.name.lowercased().contains(q) || $0.instruction.lowercased().contains(q)
                || $0.matchDescription.lowercased().contains(q)
        }
    }

    public func beginEditing(_ rule: DestinationRule) {
        guard !rule.isBuiltIn else { return }
        editing = rule.id
        editName = rule.name
        editApps = rule.bundleIDs.joined(separator: ", ")
        editURL = rule.urlPattern ?? ""
        editField = rule.fieldPattern ?? ""
        editInstruction = rule.instruction
    }
    public func cancelEditing() { editing = nil }
    public var canSaveEdit: Bool {
        !editName.trimmingCharacters(in: .whitespaces).isEmpty
            && !editInstruction.trimmingCharacters(in: .whitespaces).isEmpty
    }
    public func saveEdit() {
        guard let id = editing, canSaveEdit else { return }
        func optional(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t
        }
        store.update(id, name: editName.trimmingCharacters(in: .whitespaces),
                     bundleIDs: editApps.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init),
                     urlPattern: optional(editURL), fieldPattern: optional(editField),
                     instruction: editInstruction.trimmingCharacters(in: .whitespaces))
        editing = nil
        reload()
    }

    public func toggle(_ rule: DestinationRule) {
        store.setEnabled(rule.id, !rule.enabled); reload()
    }
    public func remove(_ rule: DestinationRule) {
        let index = store.rules.firstIndex { $0.id == rule.id } ?? store.rules.count
        store.remove(rule.id); reload()
        undo?.offer("Deleted “\(rule.name)”") { [store, weak self] in
            store.restore(rule, at: index); self?.reload()
        }
    }
}

struct DestinationRow: View {
    let rule: DestinationRule
    @ObservedObject var model: DestinationsViewModel
    @State private var hovered = false
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }
    private var editing: Bool { model.editing == rule.id }

    var body: some View { if editing { editor } else { display } }

    private var display: some View {
        Row(appearance: model.appearance) {
            HStack(alignment: .top, spacing: 12) {
                Button { model.toggle(rule) } label: {
                    Image(systemName: rule.enabled ? "checkmark.square.fill" : "square")
                        .font(.system(size: TypeScale.heading))
                        // Not saffron: that colour means "recording right now".
                        .foregroundStyle(rule.enabled ? c(.verdigris) : c(.muted))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(rule.enabled ? "Turn off" : "Turn on")
                .accessibilityLabel(rule.enabled ? "Turn off \(rule.name)" : "Turn on \(rule.name)")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 9) {
                        Text(rule.name)
                            .font(.system(size: TypeScale.heading, weight: .medium))
                            .foregroundStyle(rule.enabled ? c(.bone) : c(.muted))
                        Text(rule.matchDescription)
                            .font(.system(size: TypeScale.small).monospaced())
                            .foregroundStyle(c(.muted))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Text(rule.instruction)
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(c(.muted))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !rule.isBuiltIn {
                    RemoveButton(visible: hovered, label: "Delete the \(rule.name) rule",
                                 appearance: model.appearance) { model.remove(rule) }
                }
            }
        }
        .onHover { hovered = $0 }
        .onTapGesture { model.beginEditing(rule) }
        .help(rule.isBuiltIn ? "Built in. You can turn it off." : "Click to edit")
    }

    private var editor: some View {
        FormCard(appearance: model.appearance) {
            GrowingField(placeholder: "Name", text: $model.editName, lines: 1...2,
                         weight: .medium, size: TypeScale.heading, appearance: model.appearance)
            Rectangle().fill(c(.edge)).frame(height: 1)
            GrowingField(placeholder: "App bundle IDs", text: $model.editApps, lines: 1...3,
                         appearance: model.appearance)
            GrowingField(placeholder: "Page, like *atlassian.net*", text: $model.editURL, lines: 1...2,
                         appearance: model.appearance)
            GrowingField(placeholder: "Field, like summary", text: $model.editField, lines: 1...2,
                         appearance: model.appearance)
            GrowingField(placeholder: "How to shape the text", text: $model.editInstruction,
                         lines: 1...6, appearance: model.appearance)
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: model.cancelEditing)
                    .buttonStyle(.plain).font(.system(size: TypeScale.body))
                    .foregroundStyle(c(.muted)).keyboardShortcut(.escape, modifiers: [])
                PrimaryButton(title: "Save", enabled: model.canSaveEdit,
                              appearance: model.appearance) { model.saveEdit() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 8)
    }
}

public struct DestinationsView: View {
    @ObservedObject var model: DestinationsViewModel
    public init(model: DestinationsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Destinations", appearance: model.appearance,
                         subtitle: "Different apps and pages, different writing style.")

                addCard

                if model.rules.count > 3 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(c(.muted))
                        TextField("Search rules", text: $model.query)
                            .textFieldStyle(.plain).font(.system(size: TypeScale.body))
                            .foregroundStyle(c(.bone))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
                }

                if model.filtered.isEmpty {
                    EmptyHint(title: model.rules.isEmpty ? "No rules yet."
                                  : "No rule matches “\(model.query)”.",
                              detail: "", appearance: model.appearance)
                } else {
                    RowGroup(appearance: model.appearance, scrolls: false) {
                        ForEach(model.filtered) { DestinationRow(rule: $0, model: model) }
                    }
                }

                capability
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(c(.surface))
        .onAppear { model.reload() }
    }

    /// Same shape as Snippets: the name on top, what it matches and does below.
    private var addCard: some View {
        FormCard(appearance: model.appearance) {
            GrowingField(placeholder: "Name this rule…  (like: Jira summary)", text: $model.draftName,
                         lines: 1...2, weight: .medium, size: TypeScale.heading,
                         appearance: model.appearance)
            Rectangle().fill(c(.edge)).frame(height: 1)
            HStack(spacing: 10) {
                Text("when I am in").font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
                Spacer()
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
            if let detected = model.detected {
                Text(detected).font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            GrowingField(placeholder: "App bundle IDs", text: $model.draftApps, lines: 1...3,
                         appearance: model.appearance)
            GrowingField(placeholder: "Page, like *atlassian.net*  (optional)", text: $model.draftURL,
                         lines: 1...2, appearance: model.appearance)
            GrowingField(placeholder: "Field, like summary  (optional)", text: $model.draftField,
                         lines: 1...2, appearance: model.appearance)
            Rectangle().fill(c(.edge)).frame(height: 1)
            GrowingField(placeholder: "…shape the text like this, like: one short line, no full stop",
                         text: $model.draftInstruction, lines: 1...6, appearance: model.appearance)
            HStack {
                Spacer()
                PrimaryButton(title: "Add rule", enabled: model.canSave,
                              appearance: model.appearance) { model.saveDraft() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Add (⌘Return)")
            }
        }
    }

    /// What the three signals can and cannot do, as one quiet stacked list.
    private var capability: some View {
        FormCard(appearance: model.appearance) {
            Text("What Rawi can read").font(.system(size: TypeScale.body, weight: .semibold))
                .foregroundStyle(c(.bone))
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: TypeScale.body, weight: .medium)).foregroundStyle(c(.bone))
                .frame(width: 100, alignment: .leading)
            Text(detail).font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(badge.uppercased())
                .font(.system(size: TypeScale.micro, weight: .medium).monospaced())
                .tracking(1.1).foregroundStyle(c(token)).fixedSize()
        }
    }
}
