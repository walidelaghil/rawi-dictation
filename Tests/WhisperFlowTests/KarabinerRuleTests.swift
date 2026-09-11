import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("Karabiner rule") struct KarabinerRuleTests {
    func parsed(_ exe: String = "/Apps/WhisperFlow") -> [String: Any] {
        let data = Data(KarabinerRule.json(executable: exe).utf8)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test("produces valid Karabiner complex-modification JSON") func shape() {
        let root = parsed()
        #expect(root["title"] as? String == "WhisperFlow Dictation")
        let rules = root["rules"] as! [[String: Any]]
        #expect(rules.count == 3)
        for rule in rules {
            #expect(rule["description"] is String)
            let manipulators = rule["manipulators"] as! [[String: Any]]
            #expect(!manipulators.isEmpty)
            #expect(manipulators[0]["type"] as? String == "basic")
            #expect(manipulators[0]["from"] is [String: Any])
        }
    }

    @Test("fn rule starts on key down and stops on key up") func fnRule() {
        let rules = parsed()["rules"] as! [[String: Any]]
        let m = (rules[0]["manipulators"] as! [[String: Any]])[0]
        let from = m["from"] as! [String: Any]
        #expect(from["key_code"] as? String == "fn")

        let to = m["to"] as! [[String: Any]]
        #expect(to.contains { $0["shell_command"] as? String == "'/Apps/WhisperFlow' --trigger start" })
        let afterUp = m["to_after_key_up"] as! [[String: Any]]
        #expect(afterUp.contains { $0["shell_command"] as? String == "'/Apps/WhisperFlow' --trigger stop" })
    }

    @Test("fn is re-sent so it keeps working as a modifier") func fnPassthrough() {
        let rules = parsed()["rules"] as! [[String: Any]]
        let to = ((rules[0]["manipulators"] as! [[String: Any]])[0]["to"]) as! [[String: Any]]
        // fn must come first, or fn+arrow and the function row would break.
        #expect(to.first?["key_code"] as? String == "fn")
    }

    @Test("esc rule passes escape through to the focused app") func escPassthrough() {
        let rules = parsed()["rules"] as! [[String: Any]]
        let esc = rules.first { ($0["description"] as! String).contains("Esc") }!
        let to = ((esc["manipulators"] as! [[String: Any]])[0]["to"]) as! [[String: Any]]
        #expect(to.first?["key_code"] as? String == "escape")
        #expect(to.contains { ($0["shell_command"] as? String)?.contains("--trigger cancel") == true })
    }

    @Test("the executable path is quoted, so a path with spaces survives") func quoting() {
        let root = parsed("/Users/me/My Apps/WhisperFlow.app/Contents/MacOS/WhisperFlow")
        let rules = root["rules"] as! [[String: Any]]
        let to = ((rules[0]["manipulators"] as! [[String: Any]])[0]["to"]) as! [[String: Any]]
        let cmd = to.compactMap { $0["shell_command"] as? String }.first!
        #expect(cmd.hasPrefix("'/Users/me/My Apps/"))
        #expect(cmd.contains("' --trigger start"))
    }

    @Test("every trigger the rule emits is one the app understands") func triggersValid() {
        let json = KarabinerRule.json(executable: "/x")
        for action in ["start", "stop", "cancel"] {
            #expect(json.contains("--trigger \(action)"))
            #expect(RemoteTrigger.Action(rawValue: action) != nil)
        }
    }

    @Test("installs to Karabiner's assets folder without touching karabiner.json") func install() throws {
        // Writing here only makes the rule *available*; it is not enabled.
        #expect(KarabinerRule.ruleFile.path.hasSuffix(
            ".config/karabiner/assets/complex_modifications/whisperflow.json"))
    }
}
