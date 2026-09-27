import Foundation
import Testing
@testable import Meraline

@MainActor
struct PermissionsTests {
    @Test func thePaneOpensByName() {
        #expect(SettingsPane(named: "permissions") == .permissions)
        #expect(SettingsPane(named: "Permissions") == .permissions)
        #expect(AutomationRoute(url: URL(string: "meraline://settings?pane=permissions")!) == .settings(pane: "permissions"))
    }

    @Test func eachPermissionOpensItsListInPrivacyAndSecurity() {
        let anchors = Permission.allCases.map { $0.settingsURL.absoluteString }
        #expect(anchors == [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ])
    }

    @Test func statusFollowsWhatMacOSSays() {
        let permissions = Permissions.shared
        permissions.refresh()
        #expect(permissions.isAllowed(.accessibility) == SelectionAccess.shared.isGranted)
        #expect(permissions.isAllowed(.screenRecording) == ScreenCapture.hasAccess)
    }
}
