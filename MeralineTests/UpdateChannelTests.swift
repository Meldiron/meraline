import Foundation
import Testing
@testable import Meraline

@MainActor
struct UpdateChannelTests {
    private let noSecrets = SecretStore(read: { _ in "" }, write: { _, _ in })

    private func makeDefaults() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aVersionIsABetaWhenItsTagIsAPreRelease() {
        // As scripts/release.sh decides: any suffix after the version goes out on the beta channel.
        #expect(UpdateChannel(version: "1.7.0") == .stable)
        #expect(UpdateChannel(version: "1.8.0-beta.1") == .beta)
        #expect(UpdateChannel(version: "2.0.0-rc.2") == .beta)
    }

    @Test func theChipNamesTheTagOfItsGitHubRelease() throws {
        #expect(Bundle.releaseTag(for: "1.7.0") == "v1.7.0")
        #expect(Bundle.releaseTag(for: "1.8.0-beta.1") == "v1.8.0-beta.1")
        let repository = try #require(Bundle.main.repositoryURL)
        #expect(Bundle.main.releaseNotesURL(for: "1.8.0-beta.1") == repository.appending(path: "releases/tag/v1.8.0-beta.1"))
    }

    @Test func theSwitchFollowsTheBetaFeedAndRemembersIt() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets)
        let updater = Updater(preferences: preferences, defaults: defaults, currentVersion: "1.7.0")
        #expect(updater.channel == .stable)
        #expect(updater.currentChannel == .stable)

        updater.channel = .beta
        #expect(preferences.updateChannel == .beta)
        #expect(Preferences(defaults: defaults, secrets: noSecrets).updateChannel == .beta)
        // Still the stable build that runs until the beta arrives.
        #expect(updater.currentChannel == .stable)
        #expect(!updater.isLeavingBeta)
    }

    @Test func aBetaOnTheStableChannelStaysUntilANewerStableRelease() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets)
        preferences.updateChannel = .beta
        let updater = Updater(preferences: preferences, defaults: defaults, currentVersion: "1.8.0-beta.1")
        #expect(updater.currentChannel == .beta)
        #expect(!updater.isLeavingBeta)

        updater.channel = .stable
        #expect(updater.isLeavingBeta)
    }
}
