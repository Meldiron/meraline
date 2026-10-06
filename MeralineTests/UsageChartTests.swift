import AppKit
import SwiftUI
import Testing
@testable import Meraline

/// The chart of Settings › Usage, drawn offscreen: a plain render has no glass, but the chart has none either.
@MainActor
struct UsageChartTests {
    /// 2027-01-15 23:44 UTC.
    private let now = Date(timeIntervalSince1970: 1_800_000_000 + 15 * 3_600 + 44 * 60)
    private static let chart = CGSize(width: 560, height: 150)
    private static let margin: CGFloat = 80

    /// A day's bars with tokens in the last one alone, so the others leave the plot empty over them.
    private var bars: [UsageBar] {
        let ledger = UsageLedger(file: nil)
        ledger.record(at: now.addingTimeInterval(-60)) { $0.count(answer: TokenUsage(input: 4_000, output: 900), reported: true, for: "anthropic/claude") }
        return UsageBar.bars(of: ledger.series(.day, now: now), in: .day)
    }

    /// How much of each pixel the chart drew on, 0 to 255, with `selected` under the pointer: the chart in the
    /// middle of an empty view, `margin` points from every edge. Rows run from the top.
    private func draw(_ bars: [UsageBar], selected: String?) async throws -> (alpha: [UInt8], width: Int, height: Int, scale: CGFloat) {
        let view = UsageChart(points: bars, selectedBar: .constant(selected))
            .frame(width: Self.chart.width, height: Self.chart.height)
            .padding(Self.margin)
        let host = NSHostingView(rootView: view)
        let size = NSSize(width: Self.chart.width + 2 * Self.margin, height: Self.chart.height + 2 * Self.margin)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = try #require(rep.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        return (alpha, image.width, image.height, CGFloat(image.width) / size.width)
    }

    /// The pixels drawn on at all outside the chart's own frame, and those drawn on solidly anywhere.
    private func ink(_ drawn: (alpha: [UInt8], width: Int, height: Int, scale: CGFloat)) -> (outside: Int, solid: Int) {
        // A point of slack around the chart, for edges drawn half on a pixel.
        let inside = CGRect(origin: CGPoint(x: Self.margin, y: Self.margin), size: Self.chart).insetBy(dx: -1, dy: -1)
        var outside = 0
        var solid = 0
        for y in 0..<drawn.height {
            for x in 0..<drawn.width {
                let alpha = drawn.alpha[y * drawn.width + x]
                if alpha > 127 { solid += 1 }
                if alpha > 12, !inside.contains(CGPoint(x: (CGFloat(x) + 0.5) / drawn.scale, y: (CGFloat(y) + 0.5) / drawn.scale)) { outside += 1 }
            }
        }
        return (outside, solid)
    }

    /// The numbers of the bar under the pointer once sat above the plot, where the card around the chart cut them
    /// off but for their bottom edge. They stay inside the chart, for the first and last bars too.
    @Test func theNumbersOfTheBarUnderThePointerStayInsideTheChart() async throws {
        let bars = bars
        let plain = ink(try await draw(bars, selected: nil))
        #expect(plain.outside == 0, "the chart alone keeps to its frame")
        #expect(plain.solid > 0, "and draws offscreen")
        for selected in [0, bars.count / 2, bars.count - 1] {
            let drawn = try await draw(bars, selected: bars[selected].label)
            let found = ink(drawn)
            #expect(found.solid > plain.solid + Int(200 * drawn.scale * drawn.scale), "bar \(selected) shows its numbers: \(found.solid) against \(plain.solid)")
            #expect(found.outside == 0, "bar \(selected) drew \(found.outside) pixels outside the chart")
        }
    }

    /// How many labels stand under the plot: the runs of columns with ink in the strip below the bars, left of the
    /// token scale's own labels, a few points of clear columns between one label and the next.
    private func labels(under drawn: (alpha: [UInt8], width: Int, height: Int, scale: CGFloat)) -> Int {
        let rows = Int((Self.margin + Self.chart.height - 12) * drawn.scale)..<Int((Self.margin + Self.chart.height) * drawn.scale)
        let columns = Int(Self.margin * drawn.scale)..<Int((Self.margin + Self.chart.width - 31) * drawn.scale)
        let gap = Int(4 * drawn.scale)
        var count = 0
        var clear = gap
        for x in columns {
            if rows.contains(where: { drawn.alpha[$0 * drawn.width + x] > 60 }) {
                if clear >= gap { count += 1 }
                clear = 0
            } else {
                clear += 1
            }
        }
        return count
    }

    /// A month's thirty days once all had their number under them, run together as "2324252627282930": the axis
    /// drew a label for every bar, whichever ones it was told to mark. The month's labels are counted, since they
    /// are numbers alone; an hour's and a day's read "11:44 PM" and "11 PM" where the clock has AM and PM, and
    /// the strip would count each of those twice.
    @Test func onlyTheTicksAreLabeled() async throws {
        // With tokens counted, so the token scale's labels are as wide as they get and the strip stops short of them.
        let ledger = UsageLedger(file: nil)
        ledger.record(at: now.addingTimeInterval(-60)) { $0.count(answer: TokenUsage(input: 4_000, output: 900), reported: true, for: "anthropic/claude") }
        let bars = UsageBar.bars(of: ledger.series(.month, now: now), in: .month)
        let ticks = bars.filter(\.isTick).count
        #expect(ticks == 7 && bars.count == 30)
        #expect(labels(under: try await draw(bars, selected: nil)) == ticks, "\(ticks) of \(bars.count) bars are ticks")
        for window in [UsageWindow.hour, .day] {
            let bars = UsageBar.bars(of: ledger.series(window, now: now), in: window)
            #expect(bars.filter(\.isTick).count < bars.count, "\(window) thins its labels too")
        }
    }
}
