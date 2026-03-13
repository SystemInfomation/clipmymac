import XCTest
@testable import ClipMacLocal

// MARK: - ClipMacLocal Tests

final class ClipMacLocalTests: XCTestCase {

    // MARK: - Clip Model Tests

    func testClipFormattedDuration_seconds() {
        let clip = makeClip(duration: 45)
        XCTAssertEqual(clip.formattedDuration, "45s")
    }

    func testClipFormattedDuration_minutes() {
        let clip = makeClip(duration: 125)
        XCTAssertEqual(clip.formattedDuration, "2:05")
    }

    func testClipFormattedFileSize_kb() {
        let clip = makeClip(fileSize: 512_000)
        XCTAssertTrue(clip.formattedFileSize.contains("KB") || clip.formattedFileSize.contains("MB"))
    }

    func testClipFormattedFileSize_mb() {
        let clip = makeClip(fileSize: 10_485_760)  // 10 MB
        XCTAssertTrue(clip.formattedFileSize.contains("MB"))
    }

    // MARK: - Replay Buffer Tests

    func testReplayBufferInit() {
        let buffer = ReplayBuffer(targetDuration: 30)
        XCTAssertEqual(buffer.bufferedDuration, 0)
        XCTAssertEqual(buffer.videoFrameCount, 0)
    }

    func testReplayBufferTargetDuration() {
        let buffer = ReplayBuffer(targetDuration: 60)
        XCTAssertEqual(buffer.bufferedDuration, 0)
    }

    func testReplayBufferClear() {
        let buffer = ReplayBuffer(targetDuration: 30)
        buffer.clear()
        XCTAssertEqual(buffer.videoFrameCount, 0)
    }

    // MARK: - App Settings Tests

    func testAppSettingsDefaultBufferDuration() {
        // Buffer duration should be between 15 and 120
        let settings = AppSettings.shared
        XCTAssertGreaterThanOrEqual(settings.bufferDuration, 15)
        XCTAssertLessThanOrEqual(settings.bufferDuration, 120)
    }

    func testAppSettingsDefaultStorageDirectory() {
        let settings = AppSettings.shared
        XCTAssertFalse(settings.storageDirectory.path.isEmpty)
    }

    func testCaptureCaptureConfiguration() {
        let settings = AppSettings.shared
        let config = settings.captureConfiguration
        XCTAssertGreaterThan(config.width, 0)
        XCTAssertGreaterThan(config.height, 0)
        XCTAssertGreaterThan(config.frameRate, 0)
    }

    // MARK: - Resolution Preset Tests

    func testResolutionPreset1080p() {
        let (w, h) = ResolutionPreset.p1080.dimensions
        XCTAssertEqual(w, 1920)
        XCTAssertEqual(h, 1080)
    }

    func testResolutionPreset4K() {
        let (w, h) = ResolutionPreset.p4K.dimensions
        XCTAssertEqual(w, 3840)
        XCTAssertEqual(h, 2160)
    }

    // MARK: - Hotkey Config Tests

    func testDefaultHotkeyDisplayString() {
        let config = HotkeyConfig.defaultSaveClip
        // Should contain ⌘ and ⇧ modifiers
        XCTAssertTrue(config.displayString.contains("⌘"))
        XCTAssertTrue(config.displayString.contains("⇧"))
        XCTAssertTrue(config.displayString.contains("C"))
    }

    // MARK: - Color Extension Tests

    func testColorFromHex() {
        // Should not crash when creating colors from hex strings
        let red = Color(hex: "FF0000")
        let green = Color(hex: "00FF00")
        let blue = Color(hex: "0000FF")
        let _ = Color(hex: "#e94560")
        // If we get here without crashing, test passes
        XCTAssertNotNil(red)
        XCTAssertNotNil(green)
        XCTAssertNotNil(blue)
    }

    // MARK: - Helpers

    private func makeClip(duration: TimeInterval = 30,
                          fileSize: Int64 = 1_000_000) -> Clip {
        Clip(
            title: "Test Clip",
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: duration,
            fileSize: fileSize
        )
    }
}

// Make Color testable
import SwiftUI
