import Testing
@testable import WhisperFlowCore

@Suite("Permissions") struct PermissionsTests {
    @Test("missing lists exactly what is not granted") func missing() {
        let s = PermissionStatus(accessibility: false, inputMonitoring: true, microphone: false)
        #expect(s.missing == ["Accessibility", "Microphone"])
        #expect(!s.allGranted)
    }

    @Test("all granted has an empty missing list") func granted() {
        let s = PermissionStatus(accessibility: true, inputMonitoring: true, microphone: true)
        #expect(s.missing.isEmpty)
        #expect(s.allGranted)
    }

    @Test("each pane maps to a distinct settings url") func urls() {
        var seen = Set<String>()
        for pane in Permissions.SettingsPane.allCases {
            let url = Permissions.settingsURL(for: pane)
            #expect(url.scheme == "x-apple.systempreferences")
            seen.insert(url.absoluteString)
        }
        #expect(seen.count == Permissions.SettingsPane.allCases.count)
    }

    @Test("every pane explains why it is needed") func rationales() {
        for pane in Permissions.SettingsPane.allCases {
            #expect(!pane.rationale.isEmpty)
            #expect(!pane.title.isEmpty)
        }
    }

    @Test("current() runs without crashing in a test process") func current() {
        _ = Permissions.current()
    }
}
