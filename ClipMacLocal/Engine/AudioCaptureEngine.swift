import Foundation
import AVFoundation
import CoreMedia
import OSLog

private let logger = Logger(subsystem: "com.clipmaclocal", category: "AudioCaptureEngine")

// MARK: - Audio Capture Engine

/// Captures microphone audio using AVAudioEngine and provides level metering.
final class AudioCaptureEngine: ObservableObject {

    // MARK: Published

    @Published var isMicrophoneActive: Bool = false
    @Published var microphoneLevel: Float = 0.0
    @Published var isMonitoring: Bool = false

    // MARK: Private

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let mixerNode = AVAudioMixerNode()
    private var tapBuffer: [CMSampleBuffer] = []
    private let bufferLock = NSLock()

    // MARK: - Start Microphone

    func startMicrophone() throws {
        guard !isMicrophoneActive else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Install a tap on the input node
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, time: time)
        }

        try engine.start()
        self.audioEngine = engine
        self.inputNode = input
        self.isMicrophoneActive = true
        logger.info("Microphone capture started (format: \(format))")
    }

    // MARK: - Stop Microphone

    func stopMicrophone() {
        guard isMicrophoneActive else { return }
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isMicrophoneActive = false
        microphoneLevel = 0
        logger.info("Microphone capture stopped")
    }

    // MARK: - Get Buffered Audio

    func consumeBufferedAudio() -> [CMSampleBuffer] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        let result = tapBuffer
        tapBuffer.removeAll()
        return result
    }

    // MARK: - Private Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Update level meter
        if let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            let frameLength = Int(buffer.frameLength)
            var peak: Float = 0.0
            for channel in 0..<channelCount {
                let data = channelData[channel]
                for frame in 0..<frameLength {
                    peak = max(peak, abs(data[frame]))
                }
            }
            let db = peak > 0 ? 20 * log10(peak) : -80
            let normalized = max(0, min(1, (db + 60) / 60))
            DispatchQueue.main.async { self.microphoneLevel = normalized }
        }

        // Convert to CMSampleBuffer and store
        if let sampleBuffer = buffer.toCMSampleBuffer(presentationTime: time) {
            bufferLock.lock()
            tapBuffer.append(sampleBuffer)
            // Keep last 130 seconds of audio
            if tapBuffer.count > 130 * 48 {
                tapBuffer.removeFirst(tapBuffer.count - 130 * 48)
            }
            bufferLock.unlock()
        }
    }
}

// MARK: - AVAudioPCMBuffer → CMSampleBuffer Conversion

private extension AVAudioPCMBuffer {
    func toCMSampleBuffer(presentationTime: AVAudioTime) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer? = nil

        let frameCount = Int(self.frameLength)
        let channelCount = Int(self.format.channelCount)
        let sampleRate = self.format.sampleRate

        var asbd = self.format.streamDescription.pointee

        var formatDesc: CMAudioFormatDescription? = nil
        let fmtStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard fmtStatus == noErr, let formatDesc = formatDesc else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTimeMakeWithSeconds(Double(presentationTime.sampleTime) / sampleRate, preferredTimescale: 48000),
            decodeTimeStamp: .invalid
        )

        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let buffer = sampleBuffer else { return nil }

        // Attach audio data
        if let floatData = self.floatChannelData {
            let dataSize = frameCount * channelCount * MemoryLayout<Float>.size
            if let blockBuffer = try? createBlockBuffer(floatData: floatData,
                                                        frameCount: frameCount,
                                                        channelCount: channelCount,
                                                        dataSize: dataSize) {
                CMSampleBufferSetDataBuffer(buffer, newValue: blockBuffer)
                CMSampleBufferSetDataReady(buffer)
            }
        }

        return buffer
    }

    private func createBlockBuffer(floatData: UnsafePointer<UnsafeMutablePointer<Float>>,
                                   frameCount: Int,
                                   channelCount: Int,
                                   dataSize: Int) throws -> CMBlockBuffer? {
        var blockBuffer: CMBlockBuffer? = nil
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let bb = blockBuffer else { return nil }
        CMBlockBufferAssureBlockMemory(bb)

        // Interleave channels
        var writeOffset = 0
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                var sample = floatData[channel][frame]
                let writeStatus = CMBlockBufferReplaceDataBytes(
                    with: &sample,
                    blockBuffer: bb,
                    offsetIntoDestination: writeOffset,
                    dataLength: MemoryLayout<Float>.size
                )
                if writeStatus != noErr { return nil }
                writeOffset += MemoryLayout<Float>.size
            }
        }
        return bb
    }
}
