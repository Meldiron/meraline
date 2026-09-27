import Foundation

/// The language the models answer in, chats, agents, and games alike, from Settings › Prompt; English until it
/// is changed. It goes to the model as a line after whichever prompt a request sends
/// (`Preferences.instructions(for:)`), so a prompt you changed keeps it too.
nonisolated enum AnswerLanguage: String, CaseIterable, Identifiable, Sendable {
    case english, czech, slovak
    // The rest in the order of their English names.
    case croatian, danish, dutch, finnish, french, german, greek, hungarian, italian, japanese, korean, norwegian
    case polish, portuguese, romanian, russian, chinese, slovenian, spanish, swedish, turkish, ukrainian

    var id: Self { self }

    /// Its name in English, as the model is told it.
    var name: String {
        self == .chinese ? "Simplified Chinese" : rawValue.capitalized
    }

    /// Its name in itself.
    var endonym: String {
        switch self {
        case .english: "English"
        case .czech: "Čeština"
        case .slovak: "Slovenčina"
        case .chinese: "简体中文"
        case .croatian: "Hrvatski"
        case .danish: "Dansk"
        case .dutch: "Nederlands"
        case .finnish: "Suomi"
        case .french: "Français"
        case .german: "Deutsch"
        case .greek: "Ελληνικά"
        case .hungarian: "Magyar"
        case .italian: "Italiano"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .norwegian: "Norsk"
        case .polish: "Polski"
        case .portuguese: "Português"
        case .romanian: "Română"
        case .russian: "Русский"
        case .slovenian: "Slovenščina"
        case .spanish: "Español"
        case .swedish: "Svenska"
        case .turkish: "Türkçe"
        case .ukrainian: "Українська"
        }
    }

    /// How the picker shows it: “Czech (Čeština)”.
    var title: String {
        name == endonym ? name : "\(name) (\(endonym))"
    }

    /// The line that goes after `prompt`. The games and Why? are written in English, so they need none for it.
    func instruction(for prompt: SystemPrompt) -> String? {
        switch prompt {
        case .chat:
            "Write your answers in \(name), unless the user asks for another language, as for a translation."
        case .game:
            self == .english ? nil : """
            Play the game in \(name): every word, line, name, and reason you write is in \(name). \
            Keep the markers the rules ask for exactly as they are written, such as “OK: ”, “NO: ”, “PASS”, \
            “Score: ”, “NONE”, “ | ”, and “ → ”.
            """
        case .toolReason:
            self == .english ? nil : "Write the sentence in \(name)."
        }
    }
}
