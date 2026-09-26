import Testing
@testable import Meraline

struct ThinkingStatusTests {
    @Test func linesAreShortLowercaseMurmursThatTrailOff() {
        #expect(ThinkingStatus.lines.count >= 20)
        #expect(Set(ThinkingStatus.lines).count == ThinkingStatus.lines.count)
        for line in ThinkingStatus.lines {
            #expect(line.hasSuffix("…"), "\(line) should trail off")
            #expect(line.count <= 44, "\(line) is too long for one line in the panel")
            #expect(line.first?.isLowercase == true, "\(line) should read as a murmur")
        }
    }

    @Test func neverRepeatsTheLineJustShown() {
        var generator = SeededGenerator(state: 7)
        var previous = ThinkingStatus.line(after: nil, using: &generator)
        for _ in 0..<500 {
            let next = ThinkingStatus.line(after: previous, using: &generator)
            #expect(next != previous)
            #expect(ThinkingStatus.lines.contains(next))
            previous = next
        }
    }

    @Test func eventuallyShowsEveryLine() {
        var generator = SeededGenerator(state: 42)
        var seen: Set<String> = []
        var previous: String?
        for _ in 0..<2000 {
            previous = ThinkingStatus.line(after: previous, using: &generator)
            seen.insert(previous!)
        }
        #expect(seen == Set(ThinkingStatus.lines))
    }

    @Test func picksAreReproducibleForASeed() {
        var first = SeededGenerator(state: 1)
        var second = SeededGenerator(state: 1)
        let a = (0..<10).map { _ in ThinkingStatus.line(after: nil, using: &first) }
        let b = (0..<10).map { _ in ThinkingStatus.line(after: nil, using: &second) }
        #expect(a == b)
    }
}

/// SplitMix64, so the picker's tests are deterministic.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
