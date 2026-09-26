import Foundation

/// The whimsical lines the panel murmurs while a model is still thinking, before the first word of the
/// answer arrives. Real activity (a web search, a page, a command) always wins over these.
nonisolated enum ThinkingStatus {
    /// How long each line stays before the next one fades in.
    static let rotationInterval: Duration = .seconds(3)

    static let lines: [String] = [
        "sharpening pencils…",
        "asking the void…",
        "consulting the sparkle council…",
        "warming up the neurons…",
        "rummaging through the archives…",
        "untangling the thoughts…",
        "polishing the sparkle…",
        "counting to infinity…",
        "herding electrons…",
        "brewing a small idea…",
        "reticulating splines…",
        "dusting off the dictionary…",
        "convincing the bits to line up…",
        "staring thoughtfully into the distance…",
        "checking under the couch…",
        "aligning the stars…",
        "squinting at the question…",
        "looking for the right words…",
        "rehearsing the answer…",
        "waking the hamsters…",
        "pondering, very seriously…",
        "rounding up stray commas…",
        "pretending to know already…",
        "asking a friend of a friend…",
        "shuffling the cards…",
        "mumbling to itself…",
        "consulting the tea leaves…",
        "tuning the antenna…",
        "clearing its throat…",
        "whispering to the cloud…",
        "flipping through the notes…",
        "taking a deep breath…",
        "polishing the punctuation…",
        "drawing a little diagram…",
        "stirring the thought soup…",
        "turning it over once more…",
        "measuring twice…",
        "finding the thread…",
        "feeding the sparkle…",
        "summoning a good answer…"
    ]

    /// A random line that differs from the one currently on screen, so a rotation is always visible.
    static func line(after previous: String? = nil) -> String {
        var generator = SystemRandomNumberGenerator()
        return line(after: previous, using: &generator)
    }

    static func line<Generator: RandomNumberGenerator>(after previous: String?, using generator: inout Generator) -> String {
        let candidates = lines.filter { $0 != previous }
        return candidates.randomElement(using: &generator) ?? lines[0]
    }
}
