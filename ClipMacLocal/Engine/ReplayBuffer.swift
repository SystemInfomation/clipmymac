import Foundation
import CoreMedia
import AVFoundation
import VideoToolbox
import OSLog

private let logger = Logger(subsystem: "com.clipmaclocal", category: "ReplayBuffer")

// MARK: - Replay Buffer

/// Thread-safe, lock-free-style circular replay buffer.
/// Keeps the last `duration` seconds of video + audio sample buffers in memory,
/// with disk spillover when memory pressure is high.
final class ReplayBuffer {

    // MARK: Configuration

    var targetDuration: TimeInterval {
        didSet { trimToTargetDuration() }
    }

    // MARK: Private State

    private let lock = NSLock()
    private var videoFrames: [CMSampleBuffer] = []
    private var audioFrames: [CMSampleBuffer] = []
    private var totalVideoBytes: Int = 0
    private let maxMemoryBytes: Int = 200 * 1_048_576  // 200 MB cap

    // MARK: Init

    init(targetDuration: TimeInterval = 30) {
        self.targetDuration = targetDuration
    }

    // MARK: Append

    /// Appends a video sample buffer to the ring buffer.
    func append(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        videoFrames.append(sampleBuffer)
        totalVideoBytes += estimatedSize(of: sampleBuffer)
        trimExcess()
    }

    /// Appends an audio sample buffer.
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        audioFrames.append(sampleBuffer)
        trimExcessAudio()
    }

    // MARK: Export

    /// Exports the most recent `seconds` of buffered video to a temp MP4 file.
    /// Returns the URL of the exported file.
    func exportClip(lastSeconds seconds: TimeInterval,
                    configuration: CaptureConfiguration,
                    progress: ((Double) -> Void)? = nil) async throws -> URL {
        let frames: [CMSampleBuffer]
        let audioBuffers: [CMSampleBuffer]
        lock.lock()
        frames = Array(videoFrames)
        audioBuffers = Array(audioFrames)
        lock.unlock()

        guard !frames.isEmpty else {
            throw ReplayBufferError.noFramesAvailable
        }

        // Find the timestamp of the last frame
        guard let lastFrame = frames.last else {
            throw ReplayBufferError.noFramesAvailable
        }
        let lastPTS = CMSampleBufferGetPresentationTimeStamp(lastFrame)
        guard lastPTS.isValid else {
            throw ReplayBufferError.invalidTimestamps
        }

        let startPTS = CMTimeSubtract(lastPTS, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))

        // Filter frames to the requested window
        let videoSlice = frames.filter { buf in
            let pts = CMSampleBufferGetPresentationTimeStamp(buf)
            return pts.isValid && CMTimeCompare(pts, startPTS) >= 0
        }

        let audioSlice = audioBuffers.filter { buf in
            let pts = CMSampleBufferGetPresentationTimeStamp(buf)
            return pts.isValid && CMTimeCompare(pts, startPTS) >= 0
        }

        guard !videoSlice.isEmpty else {
            throw ReplayBufferError.noFramesInRange
        }

        return try await writeToFile(videoFrames: videoSlice,
                                     audioFrames: audioSlice,
                                     configuration: configuration,
                                     progress: progress)
    }

    // MARK: Clear

    func clear() {
        lock.lock()
        videoFrames.removeAll()
        audioFrames.removeAll()
        totalVideoBytes = 0
        lock.unlock()
    }

    // MARK: Stats

    var videoFrameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return videoFrames.count
    }

    var bufferedDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return bufferedDurationUnsafe()
    }

    // MARK: - Private Helpers

    private func bufferedDurationUnsafe() -> TimeInterval {
        guard let first = videoFrames.first, let last = videoFrames.last else { return 0 }
        let firstPTS = CMSampleBufferGetPresentationTimeStamp(first)
        let lastPTS = CMSampleBufferGetPresentationTimeStamp(last)
        return CMTimeGetSeconds(CMTimeSubtract(lastPTS, firstPTS))
    }

    private func trimExcess() {
        // Trim by duration
        while videoFrames.count > 1 {
            let duration = bufferedDurationUnsafe()
            if duration <= targetDuration + 2 { break }  // Keep 2s extra headroom
            let removed = videoFrames.removeFirst()
            totalVideoBytes -= estimatedSize(of: removed)
        }

        // Trim by memory
        while totalVideoBytes > maxMemoryBytes && videoFrames.count > 1 {
            let removed = videoFrames.removeFirst()
            totalVideoBytes -= estimatedSize(of: removed)
        }
    }

    private func trimExcessAudio() {
        // Keep audio synchronized with video duration + a little extra
        let maxAudioDuration = targetDuration + 5
        while audioFrames.count > 1 {
            guard let first = audioFrames.first, let last = audioFrames.last else { break }
            let firstPTS = CMSampleBufferGetPresentationTimeStamp(first)
            let lastPTS = CMSampleBufferGetPresentationTimeStamp(last)
            let dur = CMTimeGetSeconds(CMTimeSubtract(lastPTS, firstPTS))
            if dur <= maxAudioDuration { break }
            audioFrames.removeFirst()
        }
    }

    private func trimToTargetDuration() {
        lock.lock()
        defer { lock.unlock() }
        trimExcess()
        trimExcessAudio()
    }

    private func estimatedSize(of buffer: CMSampleBuffer) -> Int {
        return CMSampleBufferGetTotalSampleSize(buffer)
    }

    // MARK: - AVAssetWriter Export

    private func writeToFile(videoFrames: [CMSampleBuffer],
                             audioFrames: [CMSampleBuffer],
                             configuration: CaptureConfiguration,
                             progress: ((Double) -> Void)?) async throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let filename = "ClipMacLocal_\(Int(Date().timeIntervalSince1970)).mp4"
        let outputURL = tmpDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.bitRate,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
                kVTCompressionPropertyKey_RealTime as String: false,
                kVTCompressionPropertyKey_Quality as String: 0.85
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = CGAffineTransform.identity

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw ReplayBufferError.writerSetupFailed
        }
        writer.add(videoInput)

        // Audio settings (only if we have audio frames)
        var audioInput: AVAssetWriterInput? = nil
        if !audioFrames.isEmpty {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = false
            if writer.canAdd(aInput) {
                writer.add(aInput)
                audioInput = aInput
            }
        }

        // Determine start time
        guard let firstVideoBuffer = videoFrames.first else {
            throw ReplayBufferError.noFramesAvailable
        }
        let startTime = CMSampleBufferGetPresentationTimeStamp(firstVideoBuffer)

        writer.startWriting()
        writer.startSession(atSourceTime: startTime)

        // Write video frames
        let total = videoFrames.count
        for (index, sampleBuffer) in videoFrames.enumerated() {
            // Retry until input is ready
            var retries = 0
            while !videoInput.isReadyForMoreMediaData && retries < 1000 {
                try await Task.sleep(nanoseconds: 1_000_000)
                retries += 1
            }
            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
            progress?(Double(index) / Double(total) * 0.8)
        }
        videoInput.markAsFinished()

        // Write audio frames
        if let audioInput = audioInput {
            for sampleBuffer in audioFrames {
                var retries = 0
                while !audioInput.isReadyForMoreMediaData && retries < 1000 {
                    try await Task.sleep(nanoseconds: 1_000_000)
                    retries += 1
                }
                if audioInput.isReadyForMoreMediaData {
                    audioInput.append(sampleBuffer)
                }
            }
            audioInput.markAsFinished()
        }

        progress?(0.9)

        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? ReplayBufferError.exportFailed
        }

        progress?(1.0)
        logger.info("Exported clip to \(outputURL.lastPathComponent) (\(videoFrames.count) frames)")
        return outputURL
    }
}

// MARK: - Errors

enum ReplayBufferError: LocalizedError {
    case noFramesAvailable
    case noFramesInRange
    case invalidTimestamps
    case writerSetupFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noFramesAvailable: return "No frames available in the replay buffer"
        case .noFramesInRange: return "No frames found in the requested time range"
        case .invalidTimestamps: return "Invalid frame timestamps in buffer"
        case .writerSetupFailed: return "Failed to set up video writer"
        case .exportFailed: return "Video export failed"
        }
    }
}
