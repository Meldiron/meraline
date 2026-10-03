import AVFoundation
import AppKit
import ScreenCaptureKit
@testable import Meraline

nonisolated extension Showcase {
    /// Where the clips go (`scripts/clips.sh`). Unset, as in every other test run, the clips are skipped.
    static let clips: URL? = environment["MERALINE_CLIPS"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    /// Whether to record the clip `name`: MERALINE_CLIPS_ONLY names the ones to record, or all when unset.
    static func wantsClip(_ name: String) -> Bool {
        guard let only = environment["MERALINE_CLIPS_ONLY"], !only.trimmed.isEmpty else { return true }
        return only.split(separator: " ").contains { $0 == name }
    }
}

/// Moments of a recording, marked by the scene as it drives the panel, on the clock the frames are stamped with,
/// so the promo's cut can refer to them by name (`card`, `enter`, `shown`, …) rather than by a stopwatch; and
/// counts the scene wants written beside them, such as how many times it asked a model. They go into `name`.json
/// next to the clip as the promo's `src/clips.json` has them: the clip's length, where the panel's window was, and
/// the markers in seconds from the first frame.
@MainActor
final class ClipMarks {
    private(set) var times: [String: CMTime] = [:]
    private(set) var counts: [String: Int] = [:]

    func mark(_ name: String) {
        times[name] = CMClockGetTime(CMClockGetHostTimeClock())
    }

    func count(_ name: String, _ value: Int) {
        counts[name] = value
    }
}

extension ShowcaseStage {
    /// Records the panel over the gradient for `seconds` while `action` drives it, at up to 60 frames a second, into
    /// `name`.mp4 (`name-light.mp4` in light) in `Showcase.clips`. The picture is the window's frame as the recording
    /// starts, with `room` more below and to the right for a window that grows while it runs, and never past the
    /// gradient. Only the stage's two windows are in it, the backdrop and the panel, so the panel may be hidden when
    /// it starts and open while it runs, and the Meraline you run, which shares the test host's bundle identifier,
    /// never is: a filter by application once recorded its Settings window over the panel. Nothing is clicked or
    /// typed; the window keeps the keyboard throughout when it has it.
    func recordPanel(
        _ panel: NSWindow, as name: String, seconds: Double, room: CGSize = .zero,
        action: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        try await recordPanel(panel, as: name, seconds: seconds, room: room, region: nil) { _ in await action() }
    }

    /// The same, with the scene marking moments (`ClipMarks`), and, for a clip meant for the promo's films, `region`
    /// of the screen recorded (in points from its top left, see `filmRegion`) instead of the window's frame; the
    /// markers and where the panel was go into `name`.json beside the clip.
    func recordPanel(
        _ panel: NSWindow, as name: String, seconds: Double, room: CGSize = .zero, region filmRegion: CGRect?,
        action: @escaping @MainActor @Sendable (ClipMarks) async -> Void
    ) async throws {
        guard let output = Showcase.clips else { return }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let file = output.appending(path: "\(name)\(appearance.suffix).mp4")
        try? FileManager.default.removeItem(at: file)
        await Showcase.waitForIdle()
        if panel.isVisible { panel.makeKey() }
        await Showcase.settle(0.4)

        var region: NSRect
        if let filmRegion {
            region = NSRect(
                x: screen.frame.minX + filmRegion.minX, y: screen.frame.maxY - filmRegion.maxY,
                width: filmRegion.width, height: filmRegion.height
            )
        } else {
            region = panel.frame
            region.origin.y -= room.height
            region.size.height += room.height
            region.size.width += room.width
            region = region.intersection(backdrop.frame)
        }
        let panelTopLeft = CGPoint(x: panel.frame.minX - screen.frame.minX, y: screen.frame.maxY - panel.frame.maxY)
        let scale = screen.backingScaleFactor
        // H.264 wants even sizes.
        let size = CGSize(width: CGFloat(Int(region.width * scale) & ~1), height: CGFloat(Int(region.height * scale) & ~1))

        let filter = SCContentFilter(display: try await display(), including: try await shareable([backdrop, panel]))
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        // ScreenCaptureKit counts from the display's top left.
        configuration.sourceRect = CGRect(
            x: region.minX - screen.frame.minX, y: screen.frame.maxY - region.maxY,
            width: size.width / scale, height: size.height / scale
        )
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureResolution = .best

        let sink = try ClipSink(file: file, size: size)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        await Showcase.settle(0.3)
        let marks = ClipMarks()
        let driving = Task { await action(marks) }
        try? await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        await sink.finish(holdingUntil: seconds)
        await driving.value
        if panel.isVisible { panel.resignKey() }
        FileHandle.standardError.write(Data("Clip: \(file.lastPathComponent) (\(sink.frames) frames)\n".utf8))

        // The markers in the clip's own time: the frames are stamped with the host clock, as the marks are.
        guard filmRegion != nil || !marks.times.isEmpty, let first = sink.firstFrameTime else { return }
        var markers: [String: Double] = [:]
        for (name, time) in marks.times {
            markers[name] = (CMTimeSubtract(time, first).seconds * 1_000).rounded() / 1_000
        }
        var info: [String: Any] = [
            "duration": (seconds * 1_000).rounded() / 1_000,
            "panel": ["x": panelTopLeft.x, "y": panelTopLeft.y],
            "markers": markers,
        ]
        if !marks.counts.isEmpty { info["counts"] = marks.counts }
        let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appending(path: "\(name)\(appearance.suffix).json"))
    }
}

/// Writes the frames a stream delivers into an H.264 movie, on its own queue.
private nonisolated final class ClipSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "meraline.clip")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var firstTime: CMTime?
    private var last: CMSampleBuffer?
    private(set) var frames = 0

    /// When the first frame was, on the host clock; read once the movie is finished.
    var firstFrameTime: CMTime? { firstTime }

    init(file: URL, size: CGSize) throws {
        writer = try AVAssetWriter(outputURL: file, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 16_000_000,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ShowcaseStage.ShowcaseError.notWritten }
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid, CMSampleBufferGetImageBuffer(buffer) != nil,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        if firstTime == nil {
            firstTime = time
            writer.startSession(atSourceTime: time)
        }
        guard input.isReadyForMoreMediaData, input.append(buffer) else { return }
        last = buffer
        frames += 1
    }

    /// Ends the movie once the capture has stopped. A still window sends no frames, so the last one is written
    /// again at `seconds` from the first, and the clip keeps its end state as long as the scene did.
    func finish(holdingUntil seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let first = self.firstTime, let last = self.last {
                    let end = CMTimeAdd(first, CMTime(seconds: seconds, preferredTimescale: 600))
                    if end > CMSampleBufferGetPresentationTimeStamp(last), self.input.isReadyForMoreMediaData {
                        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: end, decodeTimeStamp: .invalid)
                        var copy: CMSampleBuffer?
                        if CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: last, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy) == noErr, let copy {
                            self.input.append(copy)
                        }
                    }
                }
                self.input.markAsFinished()
                continuation.resume()
            }
        }
        await writer.finishWriting()
    }
}
