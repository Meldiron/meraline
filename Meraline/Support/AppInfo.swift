import Foundation

extension Bundle {
    /// The GitHub repository, from MeralineRepositoryURL in Info.plist (MERALINE_REPOSITORY_URL in
    /// project.yml). Everything that links out derives from it, so a fork changes one setting.
    var repositoryURL: URL? {
        guard let value = (object(forInfoDictionaryKey: "MeralineRepositoryURL") as? String)?.trimmed,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    /// The Sparkle feed for the beta channel: a rolling `beta` pre-release that the release
    /// workflow keeps pointed at the newest build.
    var betaFeedURL: String? {
        repositoryURL.map { $0.absoluteString + "/releases/download/beta/appcast.xml" }
    }

    /// The tag `version` was released from, which names its GitHub release: 1.8.0-beta.1 is v1.8.0-beta.1.
    static func releaseTag(for version: String) -> String {
        "v\(version)"
    }

    /// The GitHub release of `version`, a pre-release for a beta.
    func releaseNotesURL(for version: String) -> URL? {
        repositoryURL?.appending(path: "releases/tag/\(Self.releaseTag(for: version))")
    }

    var newIssueURL: URL? {
        repositoryURL?
            .appending(path: "issues/new")
            .appending(queryItems: [URLQueryItem(name: "template", value: "bug_report.yml")])
    }
}
