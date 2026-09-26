import Foundation
import Observation

/// Release notes as they arrive in an appcast item: Markdown with headings, bullets, inline styling,
/// and screenshots. The notes under the input render these blocks with the panel's inline Markdown
/// renderer, and load the screenshots from GitHub when they open.
nonisolated enum ReleaseNotes {
    enum Block: Equatable {
        case heading(String)
        case bullet(String)
        case paragraph(String)
        /// A screenshot on a line of its own, with the words that describe it. Only https pictures.
        case picture(URL, caption: String)
    }

    static func blocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmed
            if line.isEmpty {
                flush()
            } else if isPicture(line) {
                flush()
                if let picture = picture(in: line) { blocks.append(picture) }
            } else if line.hasPrefix("#") {
                flush()
                blocks.append(.heading(String(line.drop { $0 == "#" }).trimmed))
            } else if let marker = ["- ", "* ", "• "].first(where: line.hasPrefix) {
                flush()
                blocks.append(.bullet(String(line.dropFirst(marker.count)).trimmed))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// A line that only shows a picture: a Markdown image, or an HTML `img` or `picture` with its parts.
    private static func isPicture(_ line: String) -> Bool {
        line.hasPrefix("![") || ["<img", "<picture", "</picture", "<source"].contains { line.lowercased().hasPrefix($0) }
    }

    /// The picture a line shows: a Markdown image, or the `img` of an HTML line, which inside a `picture` is
    /// the one every browser shows. The other parts of a `picture` show nothing of their own.
    private static func picture(in line: String) -> Block? {
        let found: (source: Substring, caption: Substring)?
        if let match = line.firstMatch(of: #/^!\[(?<caption>[^\]]*)\]\(\s*<?(?<source>[^\s)>]+)>?(?:\s+"[^"]*")?\s*\)/#) {
            found = (match.source, match.caption)
        } else if let tag = line.firstMatch(of: #/(?i)<img\b[^>]*>/#) {
            found = attribute("src", in: tag.output).map { ($0, attribute("alt", in: tag.output) ?? "") }
        } else {
            found = nil
        }
        guard let found, let url = URL(string: String(found.source)), url.scheme?.lowercased() == "https", url.host() != nil else {
            return nil
        }
        return .picture(url, caption: String(found.caption).trimmed)
    }

    /// The `src` or `alt` of an HTML tag, quoted with double or single quotes.
    private static func attribute(_ name: String, in tag: Substring) -> Substring? {
        let attributes = tag.matches(of: #/(?i)\b(?<name>src|alt)\s*=\s*(?:"(?<double>[^"]*)"|'(?<single>[^']*)')/#)
        guard let match = attributes.first(where: { $0.name.lowercased() == name }) else { return nil }
        return match.double ?? match.single
    }

    /// Enough for an appcast that carries HTML notes: tags go, the common entities come back, and an `img`
    /// becomes a Markdown picture on a line of its own.
    static func strippingHTML(_ html: String) -> String {
        let html = html.replacing(#/(?i)<img\b[^>]*>/#) { tag in
            attribute("src", in: tag.output).map { "\n![\(attribute("alt", in: tag.output) ?? "")](\($0))\n" } ?? ""
        }
        var text = html.replacingOccurrences(of: "<br\\s*/?>|</p>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmed
    }
}

/// The update the panel announces. After Meraline updates, a What's New capsule sits under the card
/// until it is dismissed, and the next update brings it back. The version and the notes Sparkle
/// carried for it stay in UserDefaults, so the capsule outlasts a relaunch.
@Observable
final class WhatsNew {
    private static let versionKey = "whatsNew.announcedVersion"
    private static let notesKey = "whatsNew.announcedNotes"

    /// The update to announce, or nil when there is nothing new or it was dismissed.
    private(set) var update: Updater.Update?
    /// Whether the notes are open under the input.
    var isExpanded = false

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .meraline, currentVersion: String = Bundle.main.shortVersion) {
        self.defaults = defaults
        if defaults.string(forKey: Self.versionKey) == currentVersion {
            update = Updater.Update(version: currentVersion, notes: defaults.string(forKey: Self.notesKey))
        }
    }

    /// Announces the running version after an update, replacing whatever was announced before.
    func announce(_ update: Updater.Update) {
        defaults.set(update.version, forKey: Self.versionKey)
        defaults.set(update.notes, forKey: Self.notesKey)
        self.update = update
    }

    /// Hides the capsule and the notes until the next update.
    func dismiss() {
        defaults.removeObject(forKey: Self.versionKey)
        defaults.removeObject(forKey: Self.notesKey)
        update = nil
        isExpanded = false
    }
}
