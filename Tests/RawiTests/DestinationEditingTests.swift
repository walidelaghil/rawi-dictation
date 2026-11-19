import Foundation
import Testing
@testable import RawiCore

@Suite struct DestinationEditingTests {
    private func store() -> DestinationStore {
        DestinationStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("dest-\(UUID().uuidString).json"))
    }

    @Test func editChangesAUserRule() {
        let s = store()
        let rule = DestinationRule(name: "Mine", bundleIDs: ["a.b"], instruction: "short")
        s.add(rule)
        s.update(rule.id, name: "Renamed", bundleIDs: ["c.d"], urlPattern: "*x*",
                 fieldPattern: nil, instruction: "longer")
        let got = s.rules.first { $0.id == rule.id }
        #expect(got?.name == "Renamed")
        #expect(got?.bundleIDs == ["c.d"])
        #expect(got?.urlPattern == "*x*")
        #expect(got?.instruction == "longer")
    }

    @Test func builtInRulesCannotBeEdited() {
        let s = store()
        guard let builtIn = s.rules.first(where: { $0.isBuiltIn }) else { return }
        s.update(builtIn.id, name: "Hacked", bundleIDs: [], urlPattern: nil,
                 fieldPattern: nil, instruction: "x")
        #expect(s.rules.first { $0.id == builtIn.id }?.name == builtIn.name)
    }
}
