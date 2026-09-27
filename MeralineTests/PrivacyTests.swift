import Foundation
import Testing
@testable import Meraline

@MainActor
struct PrivacyTests {
    private typealias Support = GameTestSupport

    @Test func theSparkleShowsEachProvidersModel() {
        let preferences = Support.preferences()
        preferences[.ollama] = ProviderSettings(model: "llama3.2", baseURL: Provider.ollama.defaultBaseURL, apiKey: "", isEnabled: true)
        let session = ChatSession(preferences: preferences) { _ in AsyncThrowingStream { _ in } }
        let menu = PanelContext(session: session, preferences: preferences, layout: PanelLayout(), openSettings: { _ in }).providersMenu
        #expect(menu.actions.first { $0.id == "provider.ollama" }?.subtitle == "llama3.2")
    }

    // MARK: Screen sharing

    @Test func hidingFromScreenSharingIsOffUntilTurnedOnAndThenKept() {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let noSecrets = SecretStore(read: { _ in "" }, write: { _, _ in })
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(!preferences.hidesFromScreenSharing)
        preferences.hidesFromScreenSharing = true
        #expect(Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false).hidesFromScreenSharing)
    }

    @Test func theSparkleTurnsHidingFromScreenSharingOnAndOff() {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences) { _ in AsyncThrowingStream { _ in } }
        let context = PanelContext(session: session, preferences: preferences, layout: PanelLayout(), openSettings: { _ in })
        let hide = context.providersMenu.actions.first { $0.id == "hideFromScreenSharing" }
        #expect(hide?.isChecked == false)
        hide?.perform()
        #expect(preferences.hidesFromScreenSharing)
        #expect(context.providersMenu.actions.first { $0.id == "hideFromScreenSharing" }?.isChecked == true)
    }
}
