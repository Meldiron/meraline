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

extension ShowcaseStage {
    /// Records the panel over the gradient for `seconds` while `action` drives it, at up to 60 frames a second, into
    /// `name`.mp4 (`name-light.mp4` in light) in `Showcase.clips`. The picture is the window's frame as the recording
    /// starts, with `room` more below and to the right for a window that grows while it runs, and never past the
    /// gradient. Only the test host's own windows are in it, so the window may be hidden when it starts and open
    /// while it runs. Nothing is clicked or typed; the window keeps the keyboard throughout when it has it.
    func recordPanel(
        _ panel: NSWindow, as name: String, seconds: Double, room: CGSize = .zero,
        action: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        guard let output = Showcase.clips else { return }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let file = output.appending(path: "\(name)\(appearance.suffix).mp4")
        try? FileManager.default.removeItem(at: file)
        await Showcase.waitForIdle()
        if panel.isVisible { panel.makeKey() }
        await Showcase.settle(0.4)

        var region = panel.frame
        region.origin.y -= room.height
        region.size.height += room.height
        region.size.width += room.width
        region = region.intersection(backdrop.frame)
        let scale = screen.backingScaleFactor
        // H.264 wants even sizes.
        let size = CGSize(width: CGFloat(Int(region.width * scale) & ~1), height: CGFloat(Int(region.height * scale) & ~1))

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let app = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw ShowcaseError.windowNotFound
        }
        let filter = SCContentFilter(display: try await display(), including: [app], exceptingWindows: [])
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
        let driving = Task { await action() }
        try? await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        await sink.finish(holdingUntil: seconds)
        await driving.value
        if panel.isVisible { panel.resignKey() }
        FileHandle.standardError.write(Data("Clip: \(file.lastPathComponent) (\(sink.frames) frames)\n".utf8))
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
