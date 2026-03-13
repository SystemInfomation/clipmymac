import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Metal
import OSLog

private let logger = Logger(subsystem: "com.clipmaclocal", category: "CaptureEngine")

// MARK: - Capture Configuration

struct CaptureConfiguration {
    var width: Int = 1920
    var height: Int = 1080
    var frameRate: Double = 60.0
    var bitRate: Int = 8_000_000         // 8 Mbps default
    var showsCursor: Bool = true
    var capturesAudio: Bool = true
    var captureMode: CaptureMode = .fullScreen
    var displayID: CGDirectDisplayID = CGMainDisplayID()
    var windowID: CGWindowID? = nil
    var applicationBundleID: String? = nil

    enum CaptureMode: String, CaseIterable, Identifiable, Codable {
        case fullScreen = "Full Screen"
        case specificApp = "Specific App"
        case specificWindow = "Specific Window"
        var id: String { rawValue }
    }
}

// MARK: - Capture Engine

/// Core capture engine using ScreenCaptureKit with Metal-accelerated frame delivery.
@MainActor
final class CaptureEngine: NSObject, ObservableObject {

    // MARK: Published State

    @Published var isCapturing: Bool = false
    @Published var isStarting: Bool = false
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var availableApps: [SCRunningApplication] = []
    @Published var framesPerSecond: Double = 0
    @Published var captureError: String? = nil

    // MARK: Internal

    var configuration: CaptureConfiguration = CaptureConfiguration()
    var replayBuffer: ReplayBuffer?
    var audioEngine: AudioCaptureEngine?

    // MARK: Private

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var frameCount: Int = 0
    private var lastFPSUpdate: Date = Date()

    // MARK: - Refresh Available Content

    func refreshAvailableContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            availableDisplays = content.displays
            availableWindows = content.windows.filter { $0.title != nil && !$0.title!.isEmpty }
            availableApps = content.applications
            logger.info("Refreshed: \(content.displays.count) displays, \(content.windows.count) windows")
        } catch {
            logger.error("Failed to refresh content: \(error.localizedDescription)")
            captureError = error.localizedDescription
        }
    }

    // MARK: - Start Capture

    func startCapture() async throws {
        guard !isCapturing else { return }
        isStarting = true
        captureError = nil
        defer { isStarting = false }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        availableDisplays = content.displays
        availableWindows = content.windows
        availableApps = content.applications

        let filter = try buildContentFilter(from: content)
        let streamConfig = buildStreamConfig()

        let output = StreamOutput()
        output.onFrame = { [weak self] sampleBuffer in
            self?.replayBuffer?.append(sampleBuffer)
            self?.updateFPS()
        }
        output.onAudioFrame = { [weak self] sampleBuffer in
            self?.replayBuffer?.appendAudio(sampleBuffer)
        }
        output.onStopWithError = { [weak self] error in
            Task { @MainActor in
                self?.captureError = error.localizedDescription
                self?.isCapturing = false
            }
        }
        self.streamOutput = output

        let captureStream = SCStream(filter: filter, configuration: streamConfig, delegate: output)
        try captureStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        if configuration.capturesAudio {
            try captureStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        }

        try await captureStream.startCapture()
        self.stream = captureStream
        isCapturing = true
        captureError = nil
        logger.info("Capture started")
    }

    // MARK: - Stop Capture

    func stopCapture() async {
        guard isCapturing, let stream = stream else {
            isStarting = false
            self.stream = nil
            self.streamOutput = nil
            return
        }
        do {
            try await stream.stopCapture()
            logger.info("Capture stopped")
        } catch {
            logger.error("Stop capture error: \(error.localizedDescription)")
        }
        self.stream = nil
        self.streamOutput = nil
        isCapturing = false
        isStarting = false
    }

    // MARK: - Build Content Filter

    private func buildContentFilter(from content: SCShareableContent) throws -> SCContentFilter {
        switch configuration.captureMode {
        case .fullScreen:
            let display = content.displays.first(where: { $0.displayID == configuration.displayID })
                ?? content.displays.first
            guard let display = display else {
                throw CaptureError.noDisplayAvailable
            }
            return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        case .specificApp:
            guard let bundleID = configuration.applicationBundleID,
                  let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }) else {
                throw CaptureError.appNotFound
            }
            let display = content.displays.first ?? content.displays[0]
            return SCContentFilter(display: display, including: [app], exceptingWindows: [])

        case .specificWindow:
            guard let windowID = configuration.windowID,
                  let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowNotFound
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    // MARK: - Build Stream Configuration

    private func buildStreamConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = configuration.width
        config.height = configuration.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
        config.queueDepth = 6
        config.showsCursor = configuration.showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        // Capture system audio via ScreenCaptureKit
        config.capturesAudio = configuration.capturesAudio
        config.excludesCurrentProcessAudio = true
        if configuration.capturesAudio {
            config.sampleRate = 48000
            config.channelCount = 2
        }
        return config
    }

    // MARK: - FPS Update

    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            Task { @MainActor in self.framesPerSecond = fps }
            frameCount = 0
            lastFPSUpdate = now
        }
    }

    // MARK: - Errors

    enum CaptureError: LocalizedError {
        case noDisplayAvailable
        case appNotFound
        case windowNotFound
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noDisplayAvailable: return "No display available for capture"
            case .appNotFound: return "The specified application was not found"
            case .windowNotFound: return "The specified window was not found"
            case .permissionDenied: return "Screen recording permission denied"
            }
        }
    }
}

// MARK: - Stream Output Handler

private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CMSampleBuffer) -> Void)?
    var onAudioFrame: ((CMSampleBuffer) -> Void)?
    var onStopWithError: ((Error) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            onFrame?(sampleBuffer)
        case .audio:
            onAudioFrame?(sampleBuffer)
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("SCStream stopped with error: \(error.localizedDescription)")
        onStopWithError?(error)
    }
}
